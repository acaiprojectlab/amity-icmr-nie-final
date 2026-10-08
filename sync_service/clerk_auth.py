"""
Who is uploading: verifies the Clerk session token the phone sends and looks
up the person's role, the same source of truth as the web app (auth.py): the
Clerk user's public_metadata["role"]; anything but "admin" means "user".

Session tokens are short-lived RS256 JWTs signed by the Clerk instance; they
are checked against its public keys (JWKS), so no secret is needed for that.
The role lookup uses the Clerk Backend API with the secret key, which stays on
this server only.
"""
import base64
import threading
import time
from dataclasses import dataclass
from typing import Callable, Optional

import httpx
import jwt
from jwt import PyJWKClient


class AuthError(Exception):
    """The request isn't from a signed-in Clerk user."""


@dataclass(frozen=True)
class Caller:
    user_id: str
    email: str
    is_admin: bool


def frontend_api_from_publishable_key(key: str) -> str:
    """pk_test_<base64 'host$'> -> https://host (the token issuer)."""
    try:
        encoded = key.split("_", 2)[2]
        encoded += "=" * (-len(encoded) % 4)
        host = base64.b64decode(encoded).decode().rstrip("$")
    except Exception as exc:
        raise ValueError("CLERK_PUBLISHABLE_KEY is not a valid publishable key") from exc
    if not host:
        raise ValueError("CLERK_PUBLISHABLE_KEY is not a valid publishable key")
    return f"https://{host}"


class ClerkVerifier:
    ROLE_CACHE_SECONDS = 60

    def __init__(self, issuer: str, secret_key: str,
                 jwks_client: Optional[PyJWKClient] = None,
                 fetch_user: Optional[Callable[[str], dict]] = None):
        self.issuer = issuer.rstrip("/")
        self._secret_key = secret_key
        self._jwks = jwks_client or PyJWKClient(
            f"{self.issuer}/.well-known/jwks.json", cache_keys=True, lifespan=3600)
        self._fetch_user = fetch_user or self._fetch_user_from_clerk
        self._cache: dict[str, tuple[float, dict]] = {}
        self._lock = threading.Lock()

    def verify(self, authorization: Optional[str]) -> Caller:
        if not authorization or not authorization.lower().startswith("bearer "):
            raise AuthError("Missing sign-in token")
        token = authorization[7:].strip()
        try:
            signing_key = self._jwks.get_signing_key_from_jwt(token)
            claims = jwt.decode(
                token,
                signing_key.key,
                algorithms=["RS256"],
                issuer=self.issuer,
                leeway=30,
                options={"require": ["exp", "iat", "sub", "iss"]},
            )
        except jwt.PyJWTError as exc:
            raise AuthError(f"Invalid sign-in token: {exc}") from exc
        user_id = claims["sub"]
        user = self._user(user_id)
        role = str((user.get("public_metadata") or {}).get("role", "user")).strip().lower()
        return Caller(user_id=user_id, email=_primary_email(user),
                      is_admin=role == "admin")

    def _user(self, user_id: str) -> dict:
        now = time.monotonic()
        with self._lock:
            hit = self._cache.get(user_id)
            if hit and now - hit[0] < self.ROLE_CACHE_SECONDS:
                return hit[1]
        try:
            user = self._fetch_user(user_id)
        except Exception:
            # Fail closed: without the role, treat the caller as a standard
            # user (they can still upload new enrolments, nothing more).
            return {}
        with self._lock:
            self._cache[user_id] = (now, user)
        return user

    def _fetch_user_from_clerk(self, user_id: str) -> dict:
        resp = httpx.get(
            f"https://api.clerk.com/v1/users/{user_id}",
            headers={"Authorization": f"Bearer {self._secret_key}"},
            timeout=10,
        )
        resp.raise_for_status()
        return resp.json()


def _primary_email(user: dict) -> str:
    primary = user.get("primary_email_address_id")
    for item in user.get("email_addresses") or []:
        if item.get("id") == primary:
            return item.get("email_address", "")
    return ""
