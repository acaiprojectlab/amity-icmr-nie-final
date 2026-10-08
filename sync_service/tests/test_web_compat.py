"""
The documents this service writes must look exactly like the web app's own,
or the web Dashboard / View Records / CSV exports would mis-handle them.
This runs the web app's real DataHandler.save_prediction (data_handler.py, in
the repository root) next to records.build_document and compares the results.
Needs pandas installed (the web module imports it); skipped otherwise.
"""
import os
import sys
import types
import uuid
from datetime import datetime

import mongomock
import pytest
from pymongo.errors import DuplicateKeyError

import records
from conftest import sample_record

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MOBILE_ONLY = {"source", "mobile_record_id", "enrolled_by", "uploaded_by", "uploaded_at"}


@pytest.fixture(scope="module")
def web_handler():
    pytest.importorskip("pandas")
    # Stand-ins for the web modules that need Streamlit / a live database.
    sys.modules.setdefault("streamlit", types.ModuleType("streamlit"))
    fake_database = types.ModuleType("database")
    fake_database.get_db = lambda: None
    fake_database.test_db_connection = lambda: {"status": "error"}
    sys.modules["database"] = fake_database
    sys.path.insert(0, REPO_ROOT)
    try:
        import data_handler
    finally:
        sys.path.remove(REPO_ROOT)
    handler = data_handler.DataHandler()
    handler.db = mongomock.MongoClient()["web"]
    return data_handler, handler


def _web_inputs(rec):
    p = rec["patient"]
    patient_data = {
        "patient_name": p["patient_name"], "date_of_collection": p["date_of_collection"],
        "patient_mrd_id": p["patient_mrd_id"], "hospital": p["hospital"],
        "department": p["department"],
        "department_other_specification": p["department_specification"],
        "date_of_admission": p["date_of_admission"], "address_line": p["address_line"],
        "mobile_no": p["mobile_no"], "age": p["age"], "SEX": p["sex"],
        "PATIENTTYPE": p["patient_type"], "onset_of_illness": p["onset_of_illness"],
        "durationofillness": p["duration_of_illness_days"],
        "subdistrict": p["subdistrict"], "pin_code": p["pin_code"],
        "syndrome_name": p["syndrome_name"],
        "month": int(p["onset_of_illness"].split("-")[1]), "year": 2015,
        **rec["symptoms"],
    }
    pr = rec["prediction"]
    prediction = {
        "predicted_virus": pr["predicted_virus_name"],
        "confidence": pr["prediction_confidence_percent"],
        "top_5_predictions": [{"virus": t["virus"], "confidence": t["confidence"]}
                              for t in pr["top"]],
    }
    return patient_data, prediction, p["state_name"], p["district_name"]


def test_document_matches_web_save_prediction(web_handler):
    _, handler = web_handler
    rec = sample_record()
    patient_data, prediction, state, district = _web_inputs(rec)
    handler.save_prediction(patient_data, prediction,
                            {"model1": "CustomMajor", "model2": "CustomOther"},
                            None, state, district)
    web_doc = handler.db["virus_predictions"].find_one({}, {"_id": 0})

    mobile_db = mongomock.MongoClient()["mobile"]
    pid, sid = records.allocate_ids(mobile_db, rec["patient"]["hospital"])
    ours = records.build_document(records.RecordIn(**rec), str(uuid.uuid4()),
                                  pid, sid, "user@example.com", is_admin=False)

    assert set(ours) - MOBILE_ONLY == set(web_doc)
    for key, web_value in web_doc.items():
        if key == "prediction_timestamp":
            assert isinstance(ours[key], datetime) and ours[key].tzinfo is None
            continue
        assert ours[key] == web_value, key
        assert type(ours[key]) is type(web_value), key


def test_symptom_labels_and_prefixes_match_web(web_handler):
    data_handler, handler = web_handler
    assert records.SYMPTOM_LABELS == data_handler.SYMPTOM_LABELS
    for hospital in ["MMC", "TMC", "AIIMS", "", "Select...", "123"]:
        assert records.hospital_prefix(hospital) == handler._hospital_prefix(hospital)


def test_admin_doctor_fields_match_web_save_doctor_lab_data(web_handler):
    _, handler = web_handler
    col = handler.db["virus_predictions"]
    oid = col.insert_one({"patient_id": "P900"}).inserted_id
    handler.save_doctor_lab_data({"prediction_id": str(oid), "lab_id": "LAB-1",
                                  "confirmed_pathogen": "Dengue Virus"})
    web = col.find_one({"_id": oid}, {"_id": 0, "patient_id": 0})

    ours = records._doctor_fields(records.DoctorIn(lab_id="LAB-1",
                                                   confirmed_pathogen="Dengue Virus"))
    assert set(ours) == set(web)
    for key in ours:
        if key in ("doctor_lab_submitted_at", "last_updated"):
            assert isinstance(ours[key], datetime) and isinstance(web[key], datetime)
        else:
            assert ours[key] == web[key], key


def test_unique_index_only_applies_to_mobile_records():
    db = mongomock.MongoClient()["idx"]
    records.ensure_indexes(db)
    col = db[records.COLLECTION]
    col.insert_one({"patient_id": "P001"})  # web records: no mobile_record_id
    col.insert_one({"patient_id": "P002"})
    col.insert_one({"mobile_record_id": "a"})
    with pytest.raises(DuplicateKeyError):
        col.insert_one({"mobile_record_id": "a"})


def test_race_loser_returns_winner_ids():
    """Two uploads of one record: the second insert hits the unique index and
    must answer with the first one's IDs."""
    db = mongomock.MongoClient()["race"]
    records.ensure_indexes(db)
    rid = str(uuid.uuid4())
    rec = records.RecordIn(**sample_record())
    winner = records.upsert_record(db, rid, rec, "a@example.com", is_admin=False)

    real_find_one = db[records.COLLECTION].find_one
    calls = {"n": 0}

    def find_one_missing_first(*args, **kwargs):
        calls["n"] += 1
        return None if calls["n"] == 1 else real_find_one(*args, **kwargs)

    class RacingDb:
        def __getitem__(self, name):
            coll = db[name]
            if name == records.COLLECTION:
                coll.find_one = find_one_missing_first
            return coll

    loser = records.upsert_record(RacingDb(), rid, rec, "b@example.com", is_admin=False)
    assert loser["patient_id"] == winner["patient_id"]
    assert loser["created"] is False
    assert db[records.COLLECTION].count_documents({"mobile_record_id": rid}) == 1


def test_phone_symptom_keys_match_web():
    """The phone sends its model's symptom keys; each must be one the web
    knows, or that symptom would silently be recorded as 'No'."""
    import json
    path = os.path.join(REPO_ROOT, "mobile_app", "assets", "data", "model_config.json")
    if not os.path.exists(path):
        pytest.skip("mobile app not in this checkout")
    with open(path) as f:
        phone = json.load(f)["symptoms"]
    assert sorted(phone) == sorted(k for k, _ in records.SYMPTOM_LABELS)
