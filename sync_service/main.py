"""
Sync service for the mobile app: receives patients enrolled on phones and
saves them into the web app's MongoDB, so they show up on the web Dashboard
and View Records. See README.md for deployment (Render).

    PUT /v1/records/{record_id}   upload / update one record (signed-in users)
    GET /health                   liveness (also used by the app to wake the
                                  service from Render's free-plan sleep)

Environment:
    MONGODB_URI            same connection string as the web app (secret)
    MONGODB_DATABASE       database name (default: virus_prediction, as web)
    CLERK_SECRET_KEY       same Clerk app as the web (secret)
    CLERK_PUBLISHABLE_KEY  that app's publishable key (identifies the issuer)
"""
import logging
import os
from functools import lru_cache

from fastapi import Depends, FastAPI, Header, HTTPException, Path
from pymongo import MongoClient

from clerk_auth import AuthError, Caller, ClerkVerifier, frontend_api_from_publishable_key
from records import RecordIn, ensure_indexes, upsert_record

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("sync_service")

app = FastAPI(title="Amity ICMR mobile sync", docs_url=None, redoc_url=None)

_RECORD_ID = r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"


@lru_cache(maxsize=1)
def get_db():
    client = MongoClient(os.environ["MONGODB_URI"], serverSelectionTimeoutMS=10000,
                         retryWrites=True)
    db = client[os.environ.get("MONGODB_DATABASE", "virus_prediction")]
    ensure_indexes(db)
    return db


@lru_cache(maxsize=1)
def get_verifier() -> ClerkVerifier:
    issuer = frontend_api_from_publishable_key(os.environ["CLERK_PUBLISHABLE_KEY"])
    return ClerkVerifier(issuer=issuer, secret_key=os.environ["CLERK_SECRET_KEY"])


def current_caller(authorization: str | None = Header(default=None)) -> Caller:
    try:
        return get_verifier().verify(authorization)
    except AuthError as exc:
        raise HTTPException(status_code=401, detail="Please sign in again.") from exc


@app.get("/health")
def health():
    return {"ok": True}


@app.put("/v1/records/{record_id}")
def put_record(
    rec: RecordIn,
    record_id: str = Path(pattern=_RECORD_ID),
    caller: Caller = Depends(current_caller),
):
    try:
        result = upsert_record(get_db(), record_id, rec,
                               uploaded_by=caller.email or caller.user_id,
                               is_admin=caller.is_admin)
    except Exception:
        log.exception("Saving record %s failed", record_id)
        raise HTTPException(status_code=503, detail="Database unavailable; try again later.")
    log.info("record %s -> %s (%s) by %s", record_id, result["patient_id"],
             "new" if result["created"] else "existing", caller.user_id)
    return result
