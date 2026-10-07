import 'auth_models.dart';

/// Backend-agnostic authentication operations. The app uses
/// [ClerkAuthService]; tests substitute a fake.
///
/// Every method that talks to the server throws [AuthException] with a
/// message that is safe to show to the person.
abstract class AuthService {
  /// Prepare the service and restore any saved session. Must not throw for
  /// lack of network: a previously signed-in person stays signed in offline.
  /// Throws [AuthException] (kind [AuthErrorKind.notConfigured]) when the app
  /// was built without valid credentials.
  Future<void> initialize();

  /// The signed-in person, or null.
  AuthSession? get currentSession;

  /// Emits whenever the signed-in person (or their role) changes, including
  /// remote sign-outs and admin promotions picked up by a background refresh.
  Stream<AuthSession?> get sessionChanges;

  Future<AuthStep> signIn({required String email, required String password});

  /// Finish a sign-in that returned [CodeRequired].
  Future<AuthStep> verifySignInCode(String code);

  Future<AuthStep> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  });

  /// Finish a sign-up that returned [CodeRequired].
  Future<AuthStep> verifySignUpCode(String code);

  /// Re-send the code for whichever step is pending.
  Future<void> resendCode();

  /// Email a password-reset code. Completes normally whether or not the
  /// account exists, so the form can't be used to probe registered emails.
  Future<void> startPasswordReset(String email);

  /// Verify the emailed code and set the new password (signs the person in).
  Future<AuthStep> completePasswordReset({
    required String code,
    required String newPassword,
  });

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Always clears the local session, even when offline.
  Future<void> signOut();

  void dispose();
}
