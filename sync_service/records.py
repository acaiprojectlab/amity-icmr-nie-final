"""
Patient records uploaded from the mobile app, written to MongoDB in exactly
the shape the web app's DataHandler.save_prediction writes (data_handler.py),
so they appear on the web Dashboard, View Records and CSV exports like any
other record. Keep this module in step with data_handler.py;
tests/test_web_compat.py compares the two.

Patient and study IDs come from the same `counters` documents the web app
uses, so numbering is shared and never collides. The phone's own record UUID
(`mobile_record_id`, unique index) makes uploads safe to retry.
"""
from datetime import datetime, timezone
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field
from pymongo import ReturnDocument
from pymongo.collection import Collection
from pymongo.database import Database
from pymongo.errors import DuplicateKeyError

COLLECTION = "virus_predictions"

# Same (stored_key, label) pairs as data_handler.SYMPTOM_LABELS.
SYMPTOM_LABELS = [
    ("HEADACHE", "Headache"),
    ("IRRITABLITY", "Irritability"),
    ("ALTEREDSENSORIUM", "Altered Sensorium"),
    ("SOMNOLENCE", "Somnolence"),
    ("NECKRIGIDITY", "Neck Rigidity"),
    ("SEIZURES", "Seizures"),
    ("DIARRHEA", "Diarrhea"),
    ("DYSENTERY", "Dysentery"),
    ("NAUSEA", "Nausea"),
    ("VOMITING", "Vomiting"),
    ("ABDOMINALPAIN", "Abdominal Pain"),
    ("MALAISE", "Malaise"),
    ("MYALGIA", "Myalgia"),
    ("ARTHRALGIA", "Arthralgia"),
    ("CHILLS", "Chills"),
    ("RIGORS", "Rigors"),
    ("FEVER", "Fever"),
    ("BREATHLESSNESS", "Breathlessness"),
    ("COUGH", "Cough"),
    ("RHINORRHEA", "Rhinorrhea"),
    ("SORETHROAT", "Sore Throat"),
    ("BULLAE", "Bullae"),
    ("PAPULARRASH", "Papular Rash"),
    ("PUSTULARRASH", "Pustular Rash"),
    ("MUSCULARRASH", "Muscular Rash"),
    ("MACULOPAPULARRASH", "Maculopapular Rash"),
    ("ESCHAR", "Eschar"),
    ("DARKURINE", "Dark Urine"),
    ("HEPATOMEGALY", "Hepatomegaly"),
    ("JAUNDICE", "Jaundice"),
    ("REDEYE", "Red Eye"),
    ("DISCHARGEEYES", "Discharge Eyes"),
    ("CRUSHINGEYES", "Crushing Eyes"),
    ("SWELLINGEYES", "Swelling Eyes"),
    ("RETROORBITALPAIN", "Retro Orbital Pain"),
]

_MONTHS = ["", "January", "February", "March", "April", "May", "June",
           "July", "August", "September", "October", "November", "December"]
_SEX = {0: "Female", 1: "Male", 2: "Other"}
_HOSPITAL_PREFIXES = {"MMC": "M", "TMC": "T"}


# ---------------------------------------------------------------------------
# Upload payload (what the phone sends)
# ---------------------------------------------------------------------------

class _Strict(BaseModel):
    model_config = ConfigDict(extra="ignore", str_max_length=2000)


class PatientIn(_Strict):
    date_of_collection: str = ""
    patient_name: str = ""
    patient_mrd_id: str = ""
    hospital: str = ""
    department: str = ""
    department_specification: str = ""
    date_of_admission: str = ""
    mobile_no: str = ""
    address_line: str = ""
    age: Optional[int] = None
    sex: Optional[int] = None            # 0 Female, 1 Male, 2 Other
    patient_type: Optional[int] = None   # 0 Outpatient, 1 Inpatient
    onset_of_illness: str = ""           # dd-mm-yyyy
    duration_of_illness_days: Optional[int] = None
    state_name: str = ""
    district_name: str = ""
    subdistrict: str = ""
    pin_code: str = ""
    syndrome_name: str = ""


class TopPrediction(_Strict):
    virus: str = ""
    confidence: float = 0.0              # percent, as on the web


class PredictionIn(_Strict):
    predicted_virus_name: str = ""
    prediction_confidence_percent: float = 0.0
    top: list[TopPrediction] = Field(default_factory=list, max_length=5)


class DoctorIn(_Strict):
    lab_id: str = ""
    confirmed_pathogen: str = ""         # comma-separated, as on the web
    submitted_at: Optional[datetime] = None


class RecordIn(_Strict):
    enrolled_at: datetime                # when the phone enrolled the patient
    enrolled_by: str = ""                # informational; the token says who uploads
    patient: PatientIn
    symptoms: dict[str, int] = Field(default_factory=dict)
    prediction: PredictionIn
    doctor: DoctorIn = Field(default_factory=DoctorIn)
    deleted: bool = False


# ---------------------------------------------------------------------------
# Web-format helpers (mirror data_handler.py)
# ---------------------------------------------------------------------------

def symptom_column_name(label: str) -> str:
    return f"symptom_{label.lower().replace(' ', '_')}"


def hospital_prefix(hospital: str) -> str:
    if not hospital or hospital == "Select...":
        return ""
    if hospital in _HOSPITAL_PREFIXES:
        return _HOSPITAL_PREFIXES[hospital]
    for ch in hospital:
        if ch.isalpha():
            return ch.upper()
    return ""


def _month_name(onset: str) -> str:
    """Month of the dd-mm-yyyy onset date, like the web's month_name."""
    try:
        month = int(onset.split("-")[1])
    except (IndexError, ValueError):
        month = 1  # the web defaults patient_data['month'] to 1
    return _MONTHS[month] if 1 <= month <= 12 else "Unknown"


def _utc_naive(value: datetime) -> datetime:
    """pymongo stores naive datetimes as UTC; the web writes utcnow()."""
    if value.tzinfo is not None:
        value = value.astimezone(timezone.utc).replace(tzinfo=None)
    return value


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _next_sequence(counters: Collection, counter_id: str) -> int:
    doc = counters.find_one_and_update(
        {"_id": counter_id},
        {"$inc": {"sequence_value": 1}},
        upsert=True,
        return_document=ReturnDocument.AFTER,
    )
    return int(doc.get("sequence_value", 1))


def allocate_ids(db: Database, hospital: str) -> tuple[str, str]:
    """Next official Patient ID (P001...) and Study ID (M01, T01...), from
    the web app's own counters."""
    patient_id = f"P{_next_sequence(db['counters'], 'patient_id'):03d}"
    prefix = hospital_prefix(hospital)
    study_id = ""
    if prefix:
        study_id = f"{prefix}{_next_sequence(db['counters'], f'study_id_{prefix}'):02d}"
    return patient_id, study_id


def _doctor_fields(doctor: DoctorIn) -> dict:
    """Same fields the web's save_doctor_lab_data sets for a DR update."""
    submitted = _utc_naive(doctor.submitted_at) if doctor.submitted_at else utcnow()
    now = utcnow()
    return {
        "doctor_recommended_viruses": [],
        "doctor_recommended_count": 0,
        "lab_id": doctor.lab_id,
        "test_performed": "",
        "date_of_sample_collection": "",
        "sample_type": "",
        "diagnostic_method": "",
        "laboratory_results": "",
        "confirmed_pathogen": doctor.confirmed_pathogen,
        "date_of_report": "",
        "doctor_lab_submitted_at": min(submitted, now),
        "last_updated": now,
    }


def build_document(rec: RecordIn, record_id: str, patient_id: str,
                   study_id: str, uploaded_by: str, is_admin: bool) -> dict:
    p = rec.patient
    pr = rec.prediction
    doc = {
        # Patient information (same keys and order as save_prediction)
        "patient_id": patient_id,
        "patient_name": p.patient_name,
        "date_of_collection": p.date_of_collection,
        "patient_study_id": study_id,
        "patient_mrd_id": p.patient_mrd_id,
        "hospital": p.hospital,
        "department": p.department,
        "department_specification": p.department_specification,
        "date_of_admission": p.date_of_admission,
        "patient_id_no": "",
        "address_line": p.address_line,
        "mobile_no": p.mobile_no,
        "age": p.age,
        "sex": _SEX.get(p.sex, "Unknown"),
        "patient_type": "Inpatient" if p.patient_type == 1 else "Outpatient",
        "onset_of_illness": p.onset_of_illness,
        "duration_of_illness_days": p.duration_of_illness_days,
        "state_name": p.state_name or "Unknown",
        "district_name": p.district_name or "Unknown",
        "subdistrict": p.subdistrict,
        "pin_code": p.pin_code,
        "syndrome_name": p.syndrome_name,
        "syndrome_specification": "",
        "month_name": _month_name(p.onset_of_illness),
        "year": 2015,  # the web stores this constant model feature too
    }
    for key, label in SYMPTOM_LABELS:
        doc[symptom_column_name(label)] = "Yes" if rec.symptoms.get(key, 0) == 1 else "No"
    doc.update({
        "predicted_virus_name": pr.predicted_virus_name,
        "prediction_confidence_percent": pr.prediction_confidence_percent,
    })
    for i in range(5):
        # Missing ranks are '' and the integer 0, exactly as the web writes them.
        t = pr.top[i] if i < len(pr.top) else None
        doc[f"top_{i + 1}_virus"] = t.virus if t else ""
        doc[f"top_{i + 1}_confidence"] = t.confidence if t else 0
    doc.update({
        "doctor_recommended_viruses": [],
        "doctor_recommended_count": 0,
        "lab_id": "",
        "test_performed": "",
        "date_of_sample_collection": "",
        "sample_type": "",
        "diagnostic_method": "",
        "laboratory_results": "",
        "confirmed_pathogen": "",
        "date_of_report": "",
        "doctor_lab_submitted_at": None,
        "prediction_timestamp": min(_utc_naive(rec.enrolled_at), utcnow()),
        "model_primary": "CustomMajor",
        "model_secondary": "CustomOther",
        "app_version": "2.0",
        # Mobile-only bookkeeping (extra columns at the end of web CSVs)
        "source": "mobile_app",
        "mobile_record_id": record_id,
        "enrolled_by": rec.enrolled_by,
        "uploaded_by": uploaded_by,
        "uploaded_at": utcnow(),
    })
    # Doctor recommendation and deletion are admin actions, as on the web.
    if is_admin and rec.doctor.lab_id:
        doctor = _doctor_fields(rec.doctor)
        doctor.pop("last_updated")  # not set on a new record, as on the web
        doc.update(doctor)
    if is_admin and rec.deleted:
        doc.update({"is_deleted": True, "deleted_at": utcnow()})
    return doc


# ---------------------------------------------------------------------------
# Upsert
# ---------------------------------------------------------------------------

def ensure_indexes(db: Database) -> None:
    # Partial: web-created records have no mobile_record_id and are untouched.
    db[COLLECTION].create_index(
        "mobile_record_id",
        unique=True,
        partialFilterExpression={"mobile_record_id": {"$exists": True}},
        name="mobile_record_id_unique",
    )


def upsert_record(db: Database, record_id: str, rec: RecordIn,
                  uploaded_by: str, is_admin: bool) -> dict:
    """Create the record on first upload; afterwards apply only the admin
    changes (doctor recommendation, deletion) -- never overwrite enrolment
    fields, which web admins may have edited since. Returns the official
    IDs. Safe to repeat."""
    col = db[COLLECTION]
    existing = col.find_one({"mobile_record_id": record_id})
    if existing is None:
        patient_id, study_id = allocate_ids(db, rec.patient.hospital)
        doc = build_document(rec, record_id, patient_id, study_id,
                             uploaded_by, is_admin)
        try:
            col.insert_one(doc)
            return {"patient_id": patient_id, "patient_study_id": study_id,
                    "created": True}
        except DuplicateKeyError:
            # The same record arrived twice at once; the other one won.
            # (The IDs allocated here are skipped, as on any failed web save.)
            existing = col.find_one({"mobile_record_id": record_id})

    if is_admin:
        changes = {}
        if rec.doctor.lab_id:
            changes.update(_doctor_fields(rec.doctor))
        if rec.deleted and not existing.get("is_deleted"):
            changes.update({"is_deleted": True, "deleted_at": utcnow()})
        if changes:
            changes.setdefault("last_updated", utcnow())
            col.update_one({"_id": existing["_id"]}, {"$set": changes})
    return {"patient_id": existing.get("patient_id", ""),
            "patient_study_id": existing.get("patient_study_id", ""),
            "created": False}
