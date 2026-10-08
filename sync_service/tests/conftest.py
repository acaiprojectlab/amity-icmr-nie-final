import os
import sys
import time
import types
from datetime import datetime, timezone

import jwt
import mongomock
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import main  # noqa: E402
from clerk_auth import ClerkVerifier  # noqa: E402

ISSUER = "https://divine-cod-42.clerk.accounts.dev"
USERS = {
    "user_admin": {"public_metadata": {"role": "admin"},
                   "primary_email_address_id": "e1",
                   "email_addresses": [{"id": "e1", "email_address": "admin@example.com"}]},
    "user_plain": {"public_metadata": {},
                   "primary_email_address_id": "e2",
                   "email_addresses": [{"id": "e2", "email_address": "user@example.com"}]},
}


@pytest.fixture(scope="session")
def rsa_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


class _StaticJwks:
    def __init__(self, public_key):
        self._key = types.SimpleNamespace(key=public_key)

    def get_signing_key_from_jwt(self, token):
        return self._key


@pytest.fixture
def make_token(rsa_key):
    def _make(sub="user_plain", issuer=ISSUER, expires_in=60, key=None):
        now = int(time.time())
        claims = {"sub": sub, "iss": issuer, "iat": now, "nbf": now,
                  "exp": now + expires_in, "sid": "sess_1"}
        return jwt.encode(claims, key or rsa_key, algorithm="RS256",
                          headers={"kid": "ins_test"})
    return _make


@pytest.fixture
def db():
    database = mongomock.MongoClient()["virus_prediction"]
    main.ensure_indexes(database)
    return database


@pytest.fixture
def client(db, rsa_key, monkeypatch):
    verifier = ClerkVerifier(issuer=ISSUER, secret_key="sk_test_x",
                             jwks_client=_StaticJwks(rsa_key.public_key()),
                             fetch_user=lambda uid: USERS[uid])
    monkeypatch.setattr(main, "get_db", lambda: db)
    monkeypatch.setattr(main, "get_verifier", lambda: verifier)
    return TestClient(main.app)


def sample_record(**overrides):
    rec = {
        "enrolled_at": datetime(2026, 10, 7, 12, 0, tzinfo=timezone.utc).isoformat(),
        "enrolled_by": "user@example.com",
        "patient": {
            "date_of_collection": "07-10-2026", "patient_name": "Test Patient",
            "patient_mrd_id": "MRD-9", "hospital": "MMC", "department": "Medicine",
            "department_specification": "", "date_of_admission": "07-10-2026",
            "mobile_no": "9999999999", "address_line": "1 Main Road", "age": 34,
            "sex": 1, "patient_type": 0, "onset_of_illness": "04-10-2026",
            "duration_of_illness_days": 3, "state_name": "Tamil Nadu",
            "district_name": "Chennai", "subdistrict": "", "pin_code": "600001",
            "syndrome_name": "ARI/Influenza Like Illness (ILI)",
        },
        "symptoms": {"FEVER": 1, "COUGH": 1, "HEADACHE": 0},
        "prediction": {
            "predicted_virus_name": "Influenza A H1N1",
            "prediction_confidence_percent": 61.5,
            "top": [{"virus": "Influenza A H1N1", "confidence": 61.5},
                    {"virus": "Dengue Virus", "confidence": 20.1}],
        },
        "doctor": {"lab_id": "", "confirmed_pathogen": "", "submitted_at": None},
        "deleted": False,
    }
    rec.update(overrides)
    return rec
