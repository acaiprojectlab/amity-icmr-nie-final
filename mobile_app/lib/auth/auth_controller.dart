import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_models.dart';
import 'auth_service.dart';

enum AuthStatus { starting, signedOut, signedIn }

/// App-wide authentication state and rules: the signed-in person and their
/// role, the page-access matrix, and the same form rules as the web app
/// (password policy, sign-in lockout after repeated failures, a cooldown
/// between emailed codes).
class AuthController extends ChangeNotifier {
  AuthController(this._service, {DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  // Same limits as the web app (auth.py).
  static const minPasswordLength = 8;
  static const maxFailures = 5;
  static const lockout = Duration(seconds: 60);
  static const resendCooldown = Duration(seconds: 60);
  static final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final AuthService _service;
  final DateTime Function() _now;
  StreamSubscription<AuthSession?>? _sub;

  AuthStatus _status = AuthStatus.starting;
  AuthSession? _session;
  AuthException? _setupError;
  int _failures = 0;
  DateTime? _lockedUntil;
  DateTime? _lastCodeSentAt;
  bool _disposed = false;

  AuthStatus get status => _status;
  AuthSession? get session => _session;
  AppRole get role => _session?.role ?? AppRole.user;
  bool get isAdmin => _session?.isAdmin ?? false;

  /// Non-null when sign-in can't work at all in this build/deployment.
  String? get setupError => _setupError?.message;

  /// Pages the signed-in person may open (empty when signed out).
  List<AppPage> get allowedPages =>
      _session == null ? const [] : rolePages[role]!;

  bool canOpen(AppPage page) =>
      _session != null && roleCanOpen(_session!.role, page);

  Future<void> initialize() async {
    try {
      await _service.initialize();
    } on AuthException catch (e) {
      _setupError = e;
    } catch (e) {
      _setupError = AuthException(
        AuthErrorKind.unknown,
        'Sign-in could not start ($e). Please restart the app.',
      );
    }
    if (_disposed) return;
    _sub = _service.sessionChanges.listen(_apply);
    _apply(_service.currentSession);
  }

  void _apply(AuthSession? session) {
    final status = session == null ? AuthStatus.signedOut : AuthStatus.signedIn;
    if (session == _session && status == _status) return;
    _session = session;
    _status = status;
    if (session != null) {
      _failures = 0;
      _lockedUntil = null;
    }
    notifyListeners();
  }

  /// Re-read the service's session after an action that may have signed the
  /// person in or out (the change stream also delivers it, asynchronously).
  AuthStep _settle(AuthStep step) {
    _apply(_service.currentSession);
    return step;
  }

  // -------------------------------------------------------------------
  // Validation (mirrors auth.py)
  // -------------------------------------------------------------------

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  static String? validatePasswordPair(String password, String confirm) {
    if (password.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters long.';
    }
    if (!RegExp('[A-Za-z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password)) {
      return 'Password must contain at least one letter and one number.';
    }
    if (password != confirm) return 'Passwords do not match.';
    return null;
  }

  static String? validateSignUp({
    required String firstName,
    required String email,
    required String password,
    required String confirm,
  }) {
    if (firstName.trim().isEmpty) return 'Please enter your first name.';
    if (!emailPattern.hasMatch(normalizeEmail(email))) {
      return 'Please enter a valid email address.';
    }
    return validatePasswordPair(password, confirm);
  }

  static String? validateCode(String code) =>
      RegExp(r'^\d{6}$').hasMatch(code.trim())
          ? null
          : 'Please enter the 6-digit code.';

  // -------------------------------------------------------------------
  // Throttling (per app run, like the web's per-session throttle)
  // -------------------------------------------------------------------

  int get lockoutSecondsLeft {
    final until = _lockedUntil;
    if (until == null) return 0;
    final left = until.difference(_now()).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  void _checkLockout() {
    final wait = lockoutSecondsLeft;
    if (wait > 0) {
      throw AuthException(
        AuthErrorKind.rateLimited,
        'Too many failed attempts. Please wait $wait seconds and try again.',
      );
    }
  }

  void _recordFailure() {
    _failures += 1;
    if (_failures >= maxFailures) {
      _lockedUntil = _now().add(lockout);
      _failures = 0;
    }
  }

  Future<T> _throttled<T>(Future<T> Function() action) async {
    _checkLockout();
    try {
      return await action();
    } on AuthException catch (e) {
      if (e.kind == AuthErrorKind.invalidCredentials) _recordFailure();
      rethrow;
    }
  }

  void _checkResendCooldown() {
    final last = _lastCodeSentAt;
    if (last == null) return;
    final wait = resendCooldown - _now().difference(last);
    if (wait > Duration.zero) {
      throw AuthException(
        AuthErrorKind.rateLimited,
        'A code was sent recently. Please wait ${wait.inSeconds + 1}s '
        'before requesting another.',
      );
    }
  }

  AuthStep _noteCodeSent(AuthStep step) {
    if (step is CodeRequired && !step.fromAuthenticatorApp) {
      _lastCodeSentAt = _now();
    }
    return step;
  }

  // -------------------------------------------------------------------
  // Actions -- each throws AuthException with a message for the person
  // -------------------------------------------------------------------

  Future<AuthStep> signIn(String email, String password) => _throttled(
        () async => _settle(_noteCodeSent(await _service.signIn(
          email: normalizeEmail(email),
          password: password,
        ))),
      );

  Future<AuthStep> verifySignInCode(String code) async =>
      _settle(await _service.verifySignInCode(code));

  Future<AuthStep> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async =>
      _settle(_noteCodeSent(await _service.signUp(
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        email: normalizeEmail(email),
        password: password,
      )));

  Future<AuthStep> verifySignUpCode(String code) async =>
      _settle(await _service.verifySignUpCode(code));

  Future<void> resendCode() async {
    _checkResendCooldown();
    await _service.resendCode();
    _lastCodeSentAt = _now();
  }

  /// Returns the message to show; identical whether or not the account
  /// exists.
  Future<String> startPasswordReset(String email) async {
    _checkResendCooldown();
    await _service.startPasswordReset(normalizeEmail(email));
    _lastCodeSentAt = _now();
    return 'If an account exists for that email, a 6-digit code has been '
        'sent to it. Check your inbox (and spam folder).';
  }

  Future<AuthStep> completePasswordReset({
    required String code,
    required String newPassword,
  }) async =>
      _settle(await _service.completePasswordReset(
        code: code,
        newPassword: newPassword,
      ));

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_session == null) {
      throw const AuthException(
        AuthErrorKind.unknown,
        'Please sign in again to change your password.',
      );
    }
    await _throttled(() => _service.changePassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
        ));
  }

  Future<void> signOut() async {
    await _service.signOut();
    _apply(null);
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _service.dispose();
    super.dispose();
  }
}
