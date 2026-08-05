# Security & Production-Readiness Review

**Scope:** full review of `app.py`, `auth.py`, `dashboard.py`, `data_handler.py`,
`database.py`, `model_handler.py`, `pathogen_list.py` (~4,900 lines), the git
history, and the deployment configuration, ahead of the ICMR validation phase.

**Two sections:**

* **Part 1 — Fixed in this branch.** Code changes, all verified.
* **Part 2 — Needs your decision.** Findings I deliberately did *not* change,
  because the right fix depends on an ICMR policy call or on the ML team.
  **Read C1 and C2 first — they affect model inputs.**

---

## Part 1 — Fixed in this branch

### Requested changes

| # | Change | Where |
|---|--------|-------|
| R1 | **Patient Name is now mandatory.** Labelled `Patient Name *`, blocks both Predict and Enrol. Letters only — digits and symbols rejected. Unicode-aware, so Tamil/Devanagari/Bengali names are accepted (verified: `ராஜ்`, `राजेश कुमार` pass). | `validation.py`, `app.py` |
| R2 | **Patient MRD ID is now mandatory.** Labelled `Patient MRD ID *`, blocks Predict and Enrol. Letters/digits with `- / _` separators. | `validation.py`, `app.py` |
| R3 | **Mobile number restricted to 10 digits, no alphabets.** Widget capped at 10 characters; anything non-numeric is **rejected, never silently stripped** — a mistyped number must be corrected by the user, not guessed by the app. Error shown live as you type and re-checked on submit. Stays optional (your choice), but invalid input can no longer be saved. | `validation.py`, `app.py`, `dashboard.py` |
| R4 | **CSV export rebuilt** — see below. | `dashboard.py` |

**The same rules now apply to the View Records → Edit form.** It previously had
**no validation at all**: an already-saved record could be edited to blank out
the name and MRD ID, or to store a mobile number containing letters. Dates in
that form were free text and could be saved in any format, which silently broke
the "Date of Collection range" filter for that record.

#### R4 — CSV export

**82 columns in a fixed, grouped order**, identical between header and rows
(both generated from one list, so they cannot drift apart):

| Group | Columns |
|-------|---------|
| 1. Case identifiers | S. No., Patient ID, Patient Study ID, Patient MRD ID |
| 2. Admission & site | Date of Collection, Hospital, Department, Department (if Other), Date of Admission |
| 3. Patient | Patient Name, Age, Sex, Patient Type, Mobile No |
| 4. Address | Address, Subdistrict, District, State, Pin Code |
| 5. Clinical | Syndrome, Onset of Illness, Duration (days), Month of Illness, Selected Symptoms, **+ 35 individual `Symptom: X` Yes/No columns** in canonical ICMR order |
| 6. Prediction | Predicted Virus, Confidence (%), Top 1–5 Virus + Probability (%) |
| 7. **Doctor recommendation** | **Status, Lab ID, Count, Doctor Recommended Pathogen 1…5, Completed On** |
| 8. Metadata | Enrolled On, Last Updated (both IST) |

* **Recommended pathogens now land in five separate numbered columns, in the
  order the doctor selected them.** Empty while the case is Pending, filled the
  moment Update DR flips it to Completed — which is exactly the behaviour you
  asked for. Records saved before this change (which only stored the joined
  string) are split back out correctly, so **old records export properly too**.
* Empty cells are now **blank instead of `—`**. The em-dash is a screen
  placeholder; writing it into a data file turns every empty cell into a
  non-numeric string that breaks sorting, averaging, and import into SPSS/R/Stata.
* Probabilities are real numbers rounded to 2 dp, not strings.
* The 35 per-symptom columns are additive and easy to remove if ICMR wants a
  narrower file — say the word.

### Critical bugs fixed

**F1 — Saving a Doctor Recommendation destroyed existing lab data.**
`save_doctor_lab_data()` wrote *every* lab field using `.get(key, '')`
defaults, but the Update DR form only sends `lab_id` and `confirmed_pathogen`.
So every DR save silently overwrote `test_performed`, `sample_type`,
`diagnostic_method`, `laboratory_results`, `date_of_sample_collection` and
`date_of_report` with empty strings, and reset `doctor_recommended_viruses`
to `[]`. It is now a true partial update — verified that a DR save touches
none of those six fields.

**F2 — CSV export silently capped at 500 records.**
`get_records()` defaulted to `limit=500`. The Dashboard KPI counted *all*
enrolled cases, but View Records and "Download All" only ever saw the newest
500. Past 500 patients the export would have looked complete and quietly
omitted the rest — the worst possible failure mode for a validation data set.
Cap raised to 100,000, and if it is ever reached the page now shows a warning
instead of under-reporting silently.

**F3 — One database hiccup disabled the app until redeploy.**
In `database.py`, a failed ping left `self.client` assigned, so the
`if not self.client` guard short-circuited every later call and `connect()`
fell off the end returning `None` — permanently. Combined with `DataHandler`
being constructed at import time, a brief Atlas timeout during container start
left the deployment running with no database, every save returning "Failed to
enrol patient", forever. Now: the half-open client is discarded on failure and
the handler reconnects on demand (rate-limited to one attempt per 5s).
Verified recovery across a down→up transition.

**F4 — Spreadsheet formula injection in the CSV export.**
Free-text fields (name, address, MRD ID, Lab ID) reached the CSV unfiltered. A
stored value like `=cmd|'/c calc'!A1` or `=HYPERLINK("http://evil","Click")`
executes as a live formula when the file is opened in Excel or LibreOffice —
on the reviewer's machine, not the server. Every text cell now passes through
`csv_safe()`. Numeric cells are untouched, so the file stays numerically usable.

**F5 — Stored XSS in the sidebar identity block.**
`render_sign_out_control()` injected the user-supplied display name and email
straight into raw HTML with `unsafe_allow_html=True`. A sign-up first name of
`"><img src=x onerror=...>` became live markup. Now escaped with
`html.escape(..., quote=True)`.

**F6 — Account-enumeration oracle in "Forgot password?".**
The first response was correctly generic, but the 60-second resend cooldown was
only armed when the account actually existed — so a *second* request within a
minute answered "please wait 60s" for a registered email and repeated the
generic success for an unregistered one. That difference reliably reveals which
ICMR staff emails are registered. The cooldown is now armed unconditionally,
and submitting a code against a non-existent account consumes an attempt and
returns the same "incorrect code" message.

**F7 — Stack traces rendered into the page.**
`app.py` and `model_handler.py` printed `traceback.format_exc()` and raw
exception text to end users, exposing file paths, library versions, feature
names and internal state. All now log server-side and show a safe message.

### Data-integrity bugs fixed

| # | Bug | Effect |
|---|-----|--------|
| F8 | Dashboard day boundaries used UTC | India is UTC+5:30, so every case enrolled between 00:00 and 05:30 IST was counted on the *previous* day. Daily/weekly/monthly KPIs were wrong every single morning. Now IST-aware; timestamps display in IST. |
| F9 | `patient_id_no` read a key the form never sets (`patient_id_input`) | Always saved empty — and it is the identifier the View Records grid and CSV lead with. Now falls back to the auto-assigned `P001`-style ID. |
| F10 | `'IRRITABILITY'` display key didn't match the stored `'IRRITABLITY'` | Clinicians saw the misspelling "Irritablity" on the symptom checkbox. |
| F11 | Admission date earlier than onset was clamped to 0 silently | A reversed date pair recorded a wrong duration with no warning. Now flagged inline and blocked at Predict. |
| F12 | `export_to_csv()` crashed on `.dt.strftime` | Any missing timestamp makes the column `object` dtype and `.dt` raises. Now coerced first. |
| F13 | No indexes on `virus_predictions` | Every dashboard count and record listing was a full collection scan. Added indexes on `prediction_timestamp`, `is_deleted`, `patient_id`, `patient_mrd_id`, `doctor_lab_submitted_at`. |
| F14 | No audit trail on clinical data | Edits, deletes and DR saves now record `updated_by` / `deleted_by` (signed-in user's email) alongside the timestamp. |
| F15 | "No patient records yet" shown when the DB was simply unreachable | Actively misleading during an outage. Now distinguishes the two. |
| F16 | DR form accepted a completed case with zero pathogens | Now requires at least one, since "Completed" is what drives the CSV's pathogen columns. |

### Verification performed

* All 7 modules compile; `pyflakes` clean for everything introduced here.
* **8 end-to-end cases driven through the real app** (real Streamlit runtime,
  real `.pth` models loaded) via `streamlit.testing.v1.AppTest`: blank name →
  blocked; blank MRD → blocked; mobile with alphabets → blocked; 9-digit mobile
  → blocked; name with digits → blocked; valid + blank mobile → allowed; valid
  + 10-digit mobile → allowed; Tamil name → allowed.
* CSV export tested with Completed, Pending, legacy (pre-list-field) and
  formula-injection records; header/row order asserted identical.
* MongoDB reconnect verified across a down→up transition.
* DR partial update verified to touch none of the six previously-clobbered fields.
* All five pages render without exception; the RBAC clamp correctly bounces a
  `user` role off View Records.

---

## Part 2 — Needs your decision (not changed)

### C1 — Infants are fed to the model as 18–45-year-old adults ⚠️

`model_handler.py`, `preprocess_features`:

```python
age_group = pd.cut(df['age'], bins=[0, 5, 18, 45, 65, 150], labels=[0,1,2,3,4]).cat.codes
df['age_group'] = age_group.replace(-1, 2)
```

The bins are half-open on the left — `(0,5]`, `(5,18]`, … — so **age 0 falls
outside every bin**, yields code `-1`, and `.replace(-1, 2)` maps it to
group 2 = **18–45 years**.

The intake form explicitly instructs *"if age is less than 1, enter 0"*. So
**every infant enrolled is described to the model as a young adult.** For a
paediatric-heavy syndrome (rotavirus, RSV, measles) this is material.

Measured: `age=0 → group 2`, `age=1 → group 0`, `age=30 → group 2`.

**Why I did not fix it:** if the *training* pipeline used the same `pd.cut`
call, then training and inference are consistently wrong together, and
"fixing" only the inference side would introduce a train/serve mismatch that
could make accuracy *worse*. This needs the ML team to check the training code.

* If training used the same expression → leave inference alone, retrain with
  `include_lowest=True`, revalidate.
* If training handled age 0 correctly → this is a live inference bug and should
  be fixed and revalidated before the ICMR validation runs.

### C2 — Four of five symptom-group features are under-counted ⚠️

Same function. The group lists use **spaced** names while `ALL_SYMPTOMS` uses
**no-space** keys, so the missing ones are never counted:

| Feature | Counts | Never counted |
|---|---|---|
| `respiratory_symptoms` | 3 of 4 | `SORE THROAT` |
| `gi_symptoms` | 4 of 5 | `ABDOMINAL PAIN` |
| `neuro_symptoms` | **3 of 6** | `ALTERED SENSORIUM`, `NECK RIGIDITY`, `IRRITABILITY` |
| `skin_symptoms` | **1 of 4** | `PAPULAR RASH`, `PUSTULAR RASH`, `MACULOPAPULAR RASH` |
| `systemic_symptoms` | 5 of 5 | — |

`neuro_symptoms` misses half its inputs — including the two most specific AES
signs — and `skin_symptoms` is effectively just "bullae".

**Same caveat as C1**, and it applies with more force here: correcting these
names changes the numeric value of four model input features. Do **not** hot-fix
this during validation. Confirm against the training code first; if training
had the same bug, the fix is a retrain, not a patch.

*(Note: the checkboxes themselves are recorded correctly — the stored record and
the CSV show the right symptoms. Only the derived group-count features are
affected.)*

### C3 — Open self-registration (you chose to leave as-is)

Anyone on the internet can open the app, click "Create account", and
immediately enrol patients into the production database. New accounts get
`role: user`, which grants the Prediction page — enough to write real records.
Documented per your decision. If you change your mind, the cheapest control is
an email-domain allowlist in Streamlit secrets (~15 lines in `_validate_signup`).

Related, lower priority: sign-in throttling (`_MAX_FAILURES`) is **per Streamlit
session**, so an attacker resets it by reconnecting. Clerk applies its own
server-side limits, so this is a secondary brake, not the primary one — worth
knowing rather than worth fixing.

### C4 — Patient PII stored and exported in the clear

`patient_name`, `mobile_no`, `address_line`, `pin_code` and `patient_mrd_id`
are stored unencrypted in MongoDB and exported in full by any admin, with no
record of who exported what. Fine if MongoDB Atlas encryption-at-rest and IP
allowlisting are enabled and ICMR's DPDP position covers it — worth confirming
explicitly before validation, since this is the kind of thing an ethics
committee asks about. Options if you want to go further: Atlas field-level
encryption for the four identifying fields, an export audit log, and a
de-identified export mode for analysis.

### C5 — Excel may strip leading zeros on open

An MRD ID like `0012345` or a Lab ID like `007` is stored correctly in the CSV
file, but Excel's auto-typing displays it as `12345` / `7`. **The file is
correct; the display is not.** Ask ICMR to open exports via *Data → From Text/CSV*
and set those columns to "Text". I did not force text formatting because the
usual trick (`="0012345"`) is itself a formula and would defeat the injection
fix in F4.

### C6 — Model checkpoints load with `weights_only=False` fallback

`_safe_torch_load` tries `weights_only=True`, then falls back to
`weights_only=False`, which executes arbitrary pickle code. The `.pth` files
are committed to this repo so the current risk is low, but anyone who can
write to `models/` gets code execution. Worth pinning to a checksum if the
models ever move to external storage.

### C7 — The DR form collects 2 of the 10 lab fields in the schema

`test_performed`, `sample_type`, `diagnostic_method`, `laboratory_results`,
`date_of_sample_collection` and `date_of_report` exist in the database schema
and were being written on enrolment, but **no screen ever collects them**. They
are excluded from the CSV so it doesn't carry six permanently-empty columns.
If ICMR wants these captured, they need adding to the Update DR form — tell me
and I'll add them plus their CSV columns.

### C8 — Other smaller items

* **No duplicate-MRD detection.** The same patient can be enrolled twice with
  no warning. Now that MRD ID is mandatory this is easy to add (a lookup and a
  non-blocking warning at Enrol) — say the word.
* **Study ID counters burn a number on failed saves.** `_get_next_study_id`
  increments before the insert, so a failed enrolment leaves a gap in the
  `M01, M02, …` sequence. Cosmetic, but ICMR may query gaps in study IDs.
* **`patient_id` fallback can collide.** If the counter lookup fails,
  `_get_next_patient_id` falls back to `P<unix-timestamp>`, which is a
  different format and could collide with a real `P…` ID.
* **Session lost on browser refresh.** Auth lives in `st.session_state`, so a
  reload signs the user out. Secure, but clinicians will find it irritating
  mid-form; worth knowing before validation feedback comes in.
* **No secrets found in git history** — I checked all 53 commits. Clean.
* `requirements.txt` pins `torch==2.12.1`; the `.pth` bundles were pickled with
  scikit-learn 1.5.2 while `requirements.txt` allows `scikit-learn>=1.7`, which
  emits `InconsistentVersionWarning` on load. It works today, but pinning
  `scikit-learn==1.5.2` would remove the risk of a silent behaviour change.
