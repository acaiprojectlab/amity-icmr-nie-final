import threading
import uuid
from datetime import datetime

from cryptography.hazmat.primitives.asymmetric import rsa

from conftest import sample_record


def put(client, token, record_id, body):
    return client.put(f"/v1/records/{record_id}", json=body,
                      headers={"Authorization": f"Bearer {token}"})


def test_health(client):
    assert client.get("/health").json() == {"ok": True}


def test_new_record_gets_official_ids_from_web_counters(client, db, make_token):
    db["counters"].insert_one({"_id": "patient_id", "sequence_value": 41})
    db["counters"].insert_one({"_id": "study_id_M", "sequence_value": 7})
    rid = str(uuid.uuid4())

    r = put(client, make_token(), rid, sample_record())

    assert r.status_code == 200
    assert r.json() == {"patient_id": "P042", "patient_study_id": "M08", "created": True}
    doc = db["virus_predictions"].find_one({"mobile_record_id": rid})
    assert doc["patient_id"] == "P042"
    assert doc["source"] == "mobile_app"
    assert doc["uploaded_by"] == "user@example.com"
    assert doc["symptom_fever"] == "Yes" and doc["symptom_headache"] == "No"
    assert doc["sex"] == "Male" and doc["patient_type"] == "Outpatient"
    assert doc["month_name"] == "October" and doc["year"] == 2015
    assert doc["prediction_timestamp"] == datetime(2026, 10, 7, 12, 0)
    assert doc["doctor_lab_submitted_at"] is None
    assert "is_deleted" not in doc


def test_retry_returns_same_ids_without_duplicate(client, db, make_token):
    rid = str(uuid.uuid4())
    first = put(client, make_token(), rid, sample_record()).json()
    second = put(client, make_token(), rid, sample_record()).json()

    assert second == {**first, "created": False}
    assert db["virus_predictions"].count_documents({"mobile_record_id": rid}) == 1


def test_simultaneous_uploads_make_one_document(client, db, make_token):
    rid = str(uuid.uuid4())
    token = make_token()
    results = []
    barrier = threading.Barrier(4)

    def go():
        barrier.wait()
        results.append(put(client, token, rid, sample_record()).json())

    threads = [threading.Thread(target=go) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert db["virus_predictions"].count_documents({"mobile_record_id": rid}) == 1
    assert len({r["patient_id"] for r in results}) == 1


def test_standard_user_cannot_set_doctor_recommendation_or_delete(client, db, make_token):
    rid = str(uuid.uuid4())
    put(client, make_token(), rid, sample_record())
    change = sample_record(
        doctor={"lab_id": "LAB-1", "confirmed_pathogen": "Dengue Virus",
                "submitted_at": "2026-10-07T13:00:00Z"},
        deleted=True)

    r = put(client, make_token(sub="user_plain"), rid, change)

    assert r.status_code == 200
    doc = db["virus_predictions"].find_one({"mobile_record_id": rid})
    assert doc["lab_id"] == "" and doc["doctor_lab_submitted_at"] is None
    assert "is_deleted" not in doc


def test_admin_doctor_recommendation_and_delete_match_web_fields(client, db, make_token):
    rid = str(uuid.uuid4())
    put(client, make_token(), rid, sample_record())
    change = sample_record(
        doctor={"lab_id": "LAB-1", "confirmed_pathogen": "Dengue Virus, Chikungunya Virus",
                "submitted_at": "2026-10-07T13:00:00Z"})

    put(client, make_token(sub="user_admin"), rid, change)
    doc = db["virus_predictions"].find_one({"mobile_record_id": rid})
    assert doc["lab_id"] == "LAB-1"
    assert doc["confirmed_pathogen"] == "Dengue Virus, Chikungunya Virus"
    assert doc["doctor_lab_submitted_at"] == datetime(2026, 10, 7, 13, 0)
    assert doc["doctor_recommended_viruses"] == [] and doc["doctor_recommended_count"] == 0

    put(client, make_token(sub="user_admin"), rid, sample_record(deleted=True))
    doc = db["virus_predictions"].find_one({"mobile_record_id": rid})
    assert doc["is_deleted"] is True and isinstance(doc["deleted_at"], datetime)


def test_existing_enrolment_fields_are_never_overwritten(client, db, make_token):
    rid = str(uuid.uuid4())
    put(client, make_token(), rid, sample_record())
    # A web admin corrects the name; a later phone upload must not undo it.
    db["virus_predictions"].update_one({"mobile_record_id": rid},
                                       {"$set": {"patient_name": "Corrected Name"}})
    put(client, make_token(sub="user_admin"), rid, sample_record())
    assert db["virus_predictions"].find_one({"mobile_record_id": rid})["patient_name"] == "Corrected Name"


def test_rejects_missing_expired_foreign_or_wrong_issuer_tokens(client, make_token):
    rid = str(uuid.uuid4())
    other_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    assert client.put(f"/v1/records/{rid}", json=sample_record()).status_code == 401
    assert put(client, make_token(expires_in=-120), rid, sample_record()).status_code == 401
    assert put(client, make_token(issuer="https://evil.example"), rid, sample_record()).status_code == 401
    assert put(client, make_token(key=other_key), rid, sample_record()).status_code == 401


def test_rejects_bad_record_id(client, make_token):
    assert put(client, make_token(), "not-a-uuid", sample_record()).status_code == 422


def test_role_lookup_failure_means_standard_user(db, rsa_key, make_token, monkeypatch):
    import main
    from fastapi.testclient import TestClient
    from clerk_auth import ClerkVerifier
    from conftest import ISSUER, _StaticJwks

    def broken(uid):
        raise RuntimeError("Clerk down")

    verifier = ClerkVerifier(issuer=ISSUER, secret_key="x",
                             jwks_client=_StaticJwks(rsa_key.public_key()),
                             fetch_user=broken)
    monkeypatch.setattr(main, "get_db", lambda: db)
    monkeypatch.setattr(main, "get_verifier", lambda: verifier)
    c = TestClient(main.app)
    rid = str(uuid.uuid4())
    put(c, make_token(sub="user_admin"), rid,
        sample_record(doctor={"lab_id": "LAB-1", "confirmed_pathogen": "X",
                              "submitted_at": None}))
    assert db["virus_predictions"].find_one({"mobile_record_id": rid})["lab_id"] == ""
