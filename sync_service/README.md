# Mobile sync service

A small web service that receives patients enrolled in the mobile app and
saves them into the **same MongoDB database as the web app**, in exactly the
web app's format. Uploaded patients then appear on the web Dashboard, View
Records and CSV exports like any other patient.

```
phone (saves offline first) --HTTPS + Clerk sign-in token--> this service --> MongoDB
```

- The phone never holds the database password; only this service does.
- Only people signed in with the web app's Clerk accounts can upload.
- New patients get their official Patient ID / Study ID here, from the same
  counters the web app uses, so phones and the web never hand out the same
  number. Until a patient is uploaded the phone shows a temporary `TMP-` ID.
- Doctor-recommendation updates and deletions made on a phone are applied only
  for admins (Clerk `public_metadata.role = "admin"`), as on the web. Fields a
  web admin has edited are never overwritten by a later phone upload.
- Uploads are safe to repeat: each phone record carries a unique ID, so a
  retry after a dropped connection never creates a duplicate.

## Deploy on Render (free plan)

You need: a Render account (free; sign up with GitHub), and from the web app's
Streamlit secrets the MongoDB connection string (`[mongodb]
connection_string`) and the Clerk secret key (`[clerk] secret_key`).

1. **MongoDB Atlas → Network Access**: make sure access is allowed from
   anywhere (`0.0.0.0/0`). Render's free plan has no fixed address. If the web
   app on Streamlit Cloud already works, this is very likely set already. The
   database password still protects the data.
2. **Render dashboard → New → Blueprint** → connect the GitHub repository
   `acaiprojectlab/amity-icmr-nie-final` and choose the branch
   `contains-mobile-app`. Render reads `render.yaml` from the repository root.
3. When asked, fill in:
   - `MONGODB_URI`: the MongoDB connection string
   - `CLERK_SECRET_KEY`: the Clerk secret key (`sk_test_…`)
   These are stored by Render only; they are never in the code.
4. **Database name**: the service uses `virus_prediction`, the web app's
   default. If the web app's Streamlit secrets set `MONGODB_DATABASE` to
   something else, change `MONGODB_DATABASE` in Render to match.
5. Click **Apply**. After the first deploy, open
   `https://<your-service>.onrender.com/health`; it should show `{"ok":true}`.
6. The app expects `https://amity-icmr-sync.onrender.com`. If Render gave the
   service a different address, rebuild the app with
   `--dart-define=SYNC_URL=https://<your-service>.onrender.com`.

**Free plan behaviour:** the service sleeps after 15 minutes without traffic
and takes about a minute to wake up. The app waits for it, so the first upload
after a quiet period is just slower. Free plan: 750 hours a month, more than
one always-on service needs.

## What it changes in the database

- New documents in `virus_predictions` (one per uploaded patient), with the
  same fields as web records plus `source: "mobile_app"`, `mobile_record_id`,
  `enrolled_by`, `uploaded_by` and `uploaded_at`. In the web app's bulk CSV
  export these extra fields appear as extra columns at the end.
- One index, `mobile_record_id_unique`, on `virus_predictions`. It only applies
  to phone records; existing web records are untouched.
- The shared `counters` documents advance as phone patients get their IDs.

## API

| | |
|---|---|
| `GET /health` | `{"ok": true}`; also used by the app to wake the service |
| `PUT /v1/records/{uuid}` | create/update one phone record; header `Authorization: Bearer <Clerk session token>`; returns `{"patient_id", "patient_study_id", "created"}` |

## Tests

```bash
pip install -r requirements-dev.txt
pytest -q tests
```

`tests/test_web_compat.py` runs the web app's own `DataHandler.save_prediction`
side by side with this service and checks the documents match field for field.
Run it after changing either side.
