# ICMR-NIE & ACAI Diagnostic System — mobile app

Flutter app for patient intake and on-device (offline) virus test
recommendation, the mobile counterpart of the Streamlit web app in the repo
root.

## Sign-in and roles

The app uses the **same Clerk accounts as the web app**: anyone who can sign in
on the website signs in here with the same email and password, and gets the
same access.

| Role  | What they see in the app                                                     |
|-------|------------------------------------------------------------------------------|
| User  | Home, Intake (prediction / test recommendation), About                      |
| Admin | Dashboard (case-status KPIs), Intake, Records (view, update DR, export, delete), About |

- The role comes from the Clerk user's public metadata, exactly as on the web.
  To make someone an admin: Clerk dashboard → Users → select the user →
  Metadata → Public → `{"role": "admin"}`. Anything else means standard user.
- Accounts created in the app always start as standard users.
- Sign in, Create account (with email verification code), Forgot password
  (Clerk emails the reset code), Change password and Sign out are supported.
  "Continue with Google" is web-only for now.
- After the first sign-in the session is kept on the phone, so the app keeps
  working **offline**. When the phone is online, role changes and remote
  sign-outs made in the Clerk dashboard take effect within about a minute.
- 5 wrong passwords in a row lock sign-in for 60 seconds, as on the web.

### Clerk setup

The app is connected to the Clerk application `divine-cod-42` (a Clerk
**development** instance), the same one the web app uses. Its publishable key
is built into `lib/auth/clerk_auth_service.dart`; publishable keys are meant
to be public, so that is safe.

Checked live on 2026-10-06 against that instance (with a Clerk test-mode
account, deleted afterwards):
- **Native applications → Native API** is on (required for phone sign-in).
- Create account works despite sign-up bot protection being on; new
  accounts start as User and need no email code on this instance.
- Sign in, wrong-password message, sign out, change password, forgot
  password (emailed code) all work.
- On a phone's first sign-in Clerk may email a 6-digit "confirm it's you"
  code; the app asks for it.
- After signing in, the app stays signed in when restarted with no internet.
- Clerk rate-limits rapid repeated attempts (several minutes); the app then
  shows "Too many attempts. Please wait a few minutes and try again."
- Not testable without a secret key: an admin account seeing Dashboard and
  Records (the role logic itself is covered by `test/auth_test.dart`).

Never put the Clerk **secret** key (`sk_…`) into the app. Anyone can unpack an
APK, and that key controls every account.

**Going to production:** when the web app moves to a Clerk production
instance (`sk_live_…`), build the app with the matching production key and
check that instance also has the Native API turned on:

```bash
flutter build apk --release --dart-define=CLERK_PUBLISHABLE_KEY=pk_live_xxxxxxxx
```

## Building the APK

```bash
flutter pub get
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

To try it on a connected phone: `flutter run --release`

Use `--release` (or `--profile`) when testing: in a plain debug build the
Intake tab shows a red error box. That is a pre-existing issue (several
entries in the syndrome list share the same value, which only debug builds
check), not a sign-in problem.

Patient records are stored on each phone (local database), so an admin sees
the patients enrolled on that phone, not the web app's central records.

## Tests

```bash
flutter analyze lib test
flutter test
```

`test/auth_test.dart` covers the role rules, sign-in throttling, and which
screens a user vs. an admin can reach, using a fake sign-in service.

## Code map (sign-in)

- `lib/auth/auth_models.dart`: roles and the page-access matrix (`rolePages`)
- `lib/auth/clerk_auth_service.dart`: talks to Clerk
- `lib/auth/auth_controller.dart`: signed-in state, password rules, lockout
- `lib/ui/widgets/auth_gate.dart`: sign-in screen vs. the app
- `lib/ui/screens/login_screen.dart`, `forgot_password_screen.dart`,
  `change_password_screen.dart`
- `AppProvider.applyAccess`: records and KPIs are only loaded for admins
