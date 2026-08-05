"""
Shared Input Validation & Export Safety
=======================================
One place for the field rules that ICMR requires, so the *intake* form
(app.py -> Prediction page) and the *edit* form (dashboard.py -> View Records
-> Edit) can never drift apart and accept different data for the same field.

Rules implemented here
----------------------
* **Patient Name**  - mandatory, letters/spaces/.'- only (no digits, no
  symbols that would let a name become a CSV formula).
* **Patient MRD ID** - mandatory, alphanumeric with - / _ separators.
* **Mobile No.**    - optional, but when present must be EXACTLY 10 digits
  with no alphabets and no symbols.
* **Pin Code**      - optional, but when present must be exactly 6 digits.
* **Dates**         - DD-MM-YYYY, real calendar dates, not in the future.

Export safety
-------------
``csv_safe`` neutralises spreadsheet formula injection. A patient-supplied
value such as ``=cmd|'/c calc'!A1`` stored in a free-text field would be
executed by Excel/LibreOffice when the exported CSV is opened. Every text
cell written to a downloaded CSV must go through it.
"""
import re
import unicodedata
from datetime import date, datetime

# --- Field limits ----------------------------------------------------------
MOBILE_DIGITS = 10
PIN_DIGITS = 6
MAX_NAME_LEN = 100
MAX_MRD_LEN = 50
MAX_TEXT_LEN = 200

# Punctuation that genuinely occurs in personal names, alongside letters.
_NAME_PUNCT = set(" .'-’")  # includes the typographic apostrophe
# Zero-width joiner / non-joiner: required to render many Indic conjuncts.
_NAME_JOINERS = {"‌", "‍"}


def _is_name_char(ch: str) -> bool:
    """True for characters legitimately found in a personal name.

    Accepts Unicode *letters* (L*) and *combining marks* (M*) so Indic scripts
    work -- Tamil, Devanagari etc. attach vowel signs and viramas as separate
    combining codepoints, and a letters-only rule would reject perfectly valid
    names such as "ராஜ்". Everything else (digits, =, @, |, control chars) is
    rejected, which is also what stops a "name" from acting as a spreadsheet
    formula once exported.
    """
    if ch in _NAME_PUNCT or ch in _NAME_JOINERS:
        return True
    return unicodedata.category(ch)[0] in ("L", "M")
# MRD IDs are hospital record numbers: letters, digits, and - / _ separators.
_MRD_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9\-/_]*$")
_DIGITS_ONLY_RE = re.compile(r"^\d+$")

# Characters that make a spreadsheet treat a cell as a formula.
_FORMULA_TRIGGERS = ("=", "+", "-", "@")
_CONTROL_TRIGGERS = ("\t", "\r", "\n")


# ---------------------------------------------------------------------------
# Normalisers -- run these on raw widget input before storing
# ---------------------------------------------------------------------------
def clean_text(value, max_len: int = MAX_TEXT_LEN) -> str:
    """Trim, collapse internal whitespace, and cap the length of free text."""
    if value is None:
        return ""
    return re.sub(r"\s+", " ", str(value)).strip()[:max_len]


def digits_only(value) -> str:
    """Every digit in ``value``, in order, with everything else dropped.

    Used to *report* what the user actually typed (e.g. "98765a4321" ->
    "987654321", 9 digits) so the error message can be specific. It is
    deliberately NOT used to silently repair input: a mobile number the user
    mistyped must be corrected by the user, not guessed by the app.
    """
    if value is None:
        return ""
    return "".join(ch for ch in str(value) if ch.isdigit())


# ---------------------------------------------------------------------------
# Validators -- each returns None when valid, or a human-readable error
# ---------------------------------------------------------------------------
def validate_patient_name(value) -> str | None:
    """Mandatory. Letters and name punctuation only."""
    name = clean_text(value, MAX_NAME_LEN)
    if not name:
        return "Patient Name is required."
    if len(name) < 2:
        return "Patient Name must be at least 2 characters."
    if any(ch.isdigit() for ch in name):
        return "Patient Name cannot contain numbers."
    if not all(_is_name_char(ch) for ch in name):
        return ("Patient Name may only contain letters, spaces, apostrophes, "
                "hyphens and full stops.")
    if not any(unicodedata.category(ch)[0] == "L" for ch in name):
        return "Patient Name must contain at least one letter."
    return None


def validate_mrd_id(value) -> str | None:
    """Mandatory. Hospital record number: letters/digits with - / _ allowed."""
    mrd = clean_text(value, MAX_MRD_LEN).replace(" ", "")
    if not mrd:
        return "Patient MRD ID is required."
    if len(mrd) < 2:
        return "Patient MRD ID must be at least 2 characters."
    if not _MRD_RE.match(mrd):
        return ("Patient MRD ID may only contain letters, digits and the "
                "separators - / _ (e.g. A123456).")
    return None


def validate_mobile(value, required: bool = False) -> str | None:
    """Exactly 10 digits, digits only. Blank is allowed unless ``required``.

    Anything non-numeric is rejected outright rather than stripped, so a
    transposed or truncated number can never be silently "repaired" into a
    different, valid-looking number and saved against a patient.
    """
    raw = str(value or "").strip()
    if not raw:
        return "Mobile No is required." if required else None
    if not _DIGITS_ONLY_RE.match(raw):
        if any(ch.isalpha() for ch in raw):
            return "Mobile No cannot contain alphabets — enter 10 digits only."
        return "Mobile No must contain digits only (no spaces, +, - or other symbols)."
    if len(raw) != MOBILE_DIGITS:
        return f"Mobile No must be exactly {MOBILE_DIGITS} digits (you entered {len(raw)})."
    return None


def validate_pin_code(value, required: bool = False) -> str | None:
    """Exactly 6 digits when present."""
    raw = str(value or "").strip()
    if not raw:
        return "Pin Code is required." if required else None
    if not _DIGITS_ONLY_RE.match(raw):
        return "Pin Code must contain digits only."
    if len(raw) != PIN_DIGITS:
        return f"Pin Code must be exactly {PIN_DIGITS} digits (you entered {len(raw)})."
    return None


def parse_ddmmyyyy(value):
    """DD-MM-YYYY string -> ``date``; None when unparseable."""
    try:
        return datetime.strptime(str(value).strip(), "%d-%m-%Y").date()
    except (TypeError, ValueError):
        return None


def validate_ddmmyyyy(value, label: str, required: bool = True,
                      allow_future: bool = False) -> str | None:
    """A real DD-MM-YYYY calendar date, by default not in the future."""
    raw = str(value or "").strip()
    if not raw:
        return f"{label} is required." if required else None
    parsed = parse_ddmmyyyy(raw)
    if parsed is None:
        return f"{label} must be a valid date in DD-MM-YYYY format."
    if not allow_future and parsed > date.today():
        return f"{label} cannot be in the future."
    return None


def validate_patient_identity(name, mrd_id, mobile, pin_code=None,
                              mobile_required: bool = False):
    """Run the whole ICMR identity block at once.

    Returns a list of error strings (empty when everything is valid), in the
    order the fields appear on the form so the messages read top-to-bottom.
    """
    checks = [
        validate_patient_name(name),
        validate_mrd_id(mrd_id),
        validate_mobile(mobile, required=mobile_required),
    ]
    if pin_code is not None:
        checks.append(validate_pin_code(pin_code))
    return [err for err in checks if err]


# ---------------------------------------------------------------------------
# CSV export safety
# ---------------------------------------------------------------------------
def csv_safe(value):
    """Make a single cell safe to open in Excel / LibreOffice / Sheets.

    Cells beginning with ``=``, ``+``, ``-``, ``@``, tab or carriage return are
    interpreted as formulas by spreadsheet software. Free-text clinical fields
    (name, address, MRD ID, Lab ID) reach the CSV unfiltered, so without this a
    stored value like ``=HYPERLINK("http://evil","click")`` becomes a live
    formula on the reviewer's machine.

    Genuine numeric values (age, probabilities, counts) are passed through
    untouched so the CSV stays numerically usable — only *text* that starts
    with a trigger character is prefixed with an apostrophe, which spreadsheets
    render as plain text.
    """
    if value is None:
        return ""
    if isinstance(value, bool):
        return "Yes" if value else "No"
    if isinstance(value, (int, float)):
        return value
    text = str(value)
    if not text:
        return ""
    if text.startswith(_FORMULA_TRIGGERS) or text.startswith(_CONTROL_TRIGGERS):
        return "'" + text
    return text
