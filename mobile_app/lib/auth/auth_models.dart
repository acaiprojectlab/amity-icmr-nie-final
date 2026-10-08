// Role / page-access model for the mobile app, mirroring the web app's
// auth.py (ROLE_PAGES). The single source of truth for a person's role is the
// Clerk user record's `public_metadata["role"]` -- the same record the web app
// reads -- so one account has the same access on the web and on the phone.
// Admins are promoted manually in the Clerk dashboard (Users -> select user ->
// Metadata -> public -> {"role": "admin"}). No role, or an unknown role, means
// standard "user" access (fail closed).

enum AppRole {
  user,
  admin;

  /// Role from Clerk `public_metadata`; anything other than "admin" is "user".
  static AppRole fromMetadata(Map<String, dynamic>? publicMetadata) {
    final raw = publicMetadata?['role']?.toString().trim().toLowerCase();
    return raw == 'admin' ? AppRole.admin : AppRole.user;
  }

  String get label => this == AppRole.admin ? 'Admin' : 'User';
}

/// The app's top-level sections.
enum AppPage { home, dashboard, prediction, records, about }

/// Page-access matrix -- same split as the web app:
///   user  -> Home, Prediction, About
///   admin -> Dashboard, Prediction, View Records, About
/// On the phone, the admin "Dashboard" is the Home tab with the case-status
/// KPIs shown; standard users get the same Home tab without them.
const Map<AppRole, List<AppPage>> rolePages = {
  AppRole.user: [AppPage.home, AppPage.prediction, AppPage.about],
  AppRole.admin: [
    AppPage.dashboard,
    AppPage.prediction,
    AppPage.records,
    AppPage.about,
  ],
};

bool roleCanOpen(AppRole role, AppPage page) =>
    rolePages[role]!.contains(page);

/// The signed-in person.
class AuthSession {
  const AuthSession({
    required this.userId,
    required this.email,
    required this.name,
    required this.role,
  });

  final String userId;
  final String email;
  final String name;
  final AppRole role;

  bool get isAdmin => role == AppRole.admin;

  @override
  bool operator ==(Object other) =>
      other is AuthSession &&
      other.userId == userId &&
      other.email == email &&
      other.name == name &&
      other.role == role;

  @override
  int get hashCode => Object.hash(userId, email, name, role);
}

/// What an auth action needs next.
sealed class AuthStep {
  const AuthStep();
}

/// Signed in -- nothing more to do.
class AuthComplete extends AuthStep {
  const AuthComplete();
}

/// A one-time code is required to finish (email verification on sign-up, or
/// a second step on sign-in such as Clerk's new-device check).
class CodeRequired extends AuthStep {
  const CodeRequired({required this.sentTo, this.fromAuthenticatorApp = false});

  /// Masked destination the code was sent to, e.g. "j***@example.com".
  final String sentTo;

  /// True when the code comes from an authenticator app, not a message.
  final bool fromAuthenticatorApp;
}

enum AuthErrorKind {
  notConfigured,
  network,
  invalidCredentials,
  rateLimited,
  accountExists,
  weakPassword,
  invalidCode,
  unsupported,
  sessionExpired,
  unknown,
}

/// An auth failure carrying a message that is safe to show to the person.
class AuthException implements Exception {
  const AuthException(this.kind, this.message);

  final AuthErrorKind kind;
  final String message;

  @override
  String toString() => message;
}
