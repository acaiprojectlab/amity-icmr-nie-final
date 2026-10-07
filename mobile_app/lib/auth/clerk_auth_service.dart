import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clerk_auth/clerk_auth.dart' as clerk;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'auth_models.dart';
import 'auth_service.dart';

/// [AuthService] backed by the same Clerk application as the web app, so the
/// same accounts work on both and roles come from the same
/// `public_metadata["role"]`.
///
/// Why not copy the web app's approach: the web app checks passwords
/// server-side with Clerk's *secret* key. That key must never be put inside
/// an APK -- anyone can unpack it, and it grants full control of every
/// account, including making themselves admin. The app instead talks to
/// Clerk's Frontend API with the *publishable* key, which is designed to be
/// public, through Clerk's official Dart SDK (`clerk_auth`). Clerk enforces
/// passwords, lockouts and roles on its side; nothing the phone sends can
/// grant admin access.
///
/// Setup (see mobile_app/README.md): the Clerk dashboard must have the
/// Native API enabled (Native applications). The publishable key is built in
/// below; build with --dart-define=CLERK_PUBLISHABLE_KEY=... to point the app
/// at a different Clerk instance (e.g. production).
///
/// Offline use: the signed-in session is saved on the device, so the app
/// keeps working without a connection after the first sign-in. When online,
/// the session is refreshed every minute, which picks up role changes and
/// remote sign-outs.
class ClerkAuthService implements AuthService {
  ClerkAuthService({
    String? publishableKey,
    Future<Directory> Function()? storageDirectory,
  })  : _publishableKey = (publishableKey ?? _keyFromBuild).trim(),
        _storageDirectory = storageDirectory ?? getApplicationSupportDirectory;

  // Publishable key of the Clerk application shared with the web app. It only
  // identifies the application and is designed to be public, so it can live
  // in source (unlike the web app's secret key, which must never ship here).
  static const _keyFromBuild = String.fromEnvironment(
    'CLERK_PUBLISHABLE_KEY',
    defaultValue: 'pk_test_ZGl2aW5lLWNvZC00Mi5jbGVyay5hY2NvdW50cy5kZXYk',
  );
  static const _requestTimeout = Duration(seconds: 30);
  static const _signOutTimeout = Duration(seconds: 10);
  static const _clientRefreshPeriod = Duration(minutes: 1);

  static const _notConfigured = AuthException(
    AuthErrorKind.notConfigured,
    'Sign-in is not configured in this build of the app: the Clerk '
    'publishable key is missing or invalid (see mobile_app/README.md).',
  );
  static const _network = AuthException(
    AuthErrorKind.network,
    "Can't reach the sign-in service. Check your internet connection and "
    'try again.',
  );
  static const _rateLimited = AuthException(
    AuthErrorKind.rateLimited,
    'Too many attempts. Please wait a few minutes and try again.',
  );
  static const _nativeApiDisabled = AuthException(
    AuthErrorKind.notConfigured,
    'Sign-in from the mobile app is not enabled yet. An administrator must '
    'turn on the Native API in the Clerk dashboard.',
  );
  // One generic message for every credential problem (unknown email, wrong
  // password, locked account) so the form doesn't reveal which accounts exist.
  static const _invalidCredentials = AuthException(
    AuthErrorKind.invalidCredentials,
    'Invalid email or password.',
  );
  static const _weakPassword = AuthException(
    AuthErrorKind.weakPassword,
    "This password can't be used (it may be too weak or found in a known "
    'data breach). Please choose a longer, unique password.',
  );
  static const _invalidCode = AuthException(
    AuthErrorKind.invalidCode,
    'Invalid or expired code. Please request a new one.',
  );
  static const _webOnlySignUp = AuthException(
    AuthErrorKind.unsupported,
    "Accounts can't be created from the app on this deployment. Please "
    'create your account on the website, then sign in here.',
  );

  final String _publishableKey;

  /// Where the signed-in session is saved (app-private storage).
  final Future<Directory> Function() _storageDirectory;
  final _changes = StreamController<AuthSession?>.broadcast();
  _ClerkAuth? _auth;
  AuthSession? _last;

  _Pending _pending = _Pending.none;
  clerk.Strategy? _codeStrategy;

  @override
  AuthSession? get currentSession => _last;

  @override
  Stream<AuthSession?> get sessionChanges => _changes.stream;

  @override
  Future<void> initialize() async {
    if (!_publishableKey.startsWith('pk_')) throw _notConfigured;
    final storageDir = await _storageDirectory();
    final auth = _ClerkAuth(
      config: clerk.AuthConfig(
        publishableKey: _publishableKey,
        persistor: _FilePersistor(storageDir),
        // No backend of ours consumes session JWTs, so don't poll for them.
        sessionTokenPolling: false,
        telemetryPeriod: Duration.zero,
        clientRefreshPeriod: _clientRefreshPeriod,
        // No automatic retries: the SDK would otherwise back off when
        // offline and, when Clerk rate-limits, sleep for the whole
        // Retry-After period (minutes). Failing at once lets the screen say
        // what happened; the person can simply try again.
        retryOptions: const clerk.RetryOptions(maxAttempts: 1),
      ),
      onUpdate: _publish,
    );
    try {
      // Falls back to the session saved on the device when offline.
      await auth.initialize();
    } on FormatException {
      throw _notConfigured; // malformed publishable key
    }
    _auth = auth;
    _last = _toSession(auth.user);
  }

  // ---------------------------------------------------------------------
  // Sign in
  // ---------------------------------------------------------------------

  @override
  Future<AuthStep> signIn({
    required String email,
    required String password,
  }) async {
    _clearPending();
    await _call(
      (auth) async {
        await _prepareClient(auth, fresh: true);
        await auth.attemptSignIn(
          strategy: clerk.Strategy.password,
          identifier: email,
          password: password,
        );
      },
      (codes) => codes.contains('form_password_pwned')
          ? const AuthException(
              AuthErrorKind.weakPassword,
              'This password was found in a known data breach and can no '
              'longer be used. Please use "Forgot password?" to set a new one.',
            )
          : _invalidCredentials,
    );
    return _afterSignInAttempt(failure: _invalidCredentials);
  }

  @override
  Future<AuthStep> verifySignInCode(String code) async {
    final strategy = _codeStrategy;
    if (_pending != _Pending.signInCode || strategy == null) throw _invalidCode;
    await _call(
      (auth) => auth.attemptSignIn(strategy: strategy, code: code.trim()),
      _codeRejected,
    );
    return _afterSignInAttempt(failure: _invalidCode);
  }

  Future<AuthStep> _afterSignInAttempt({
    required AuthException failure,
  }) async {
    final auth = _auth!;
    if (auth.isSignedIn) {
      _clearPending();
      _publish();
      return const AuthComplete();
    }
    final signIn = auth.signIn;
    if (signIn != null && (signIn.needsSecondFactor || signIn.needsClientTrust)) {
      return _startSecondStep(signIn);
    }
    throw failure;
  }

  /// Password accepted, but Clerk wants a one-time code too: either the
  /// account has two-step verification, or this is a new device (Clerk's
  /// "client trust" check emails a code).
  Future<AuthStep> _startSecondStep(clerk.SignIn signIn) async {
    clerk.Factor? factor;
    for (final strategy in const [
      clerk.Strategy.emailCode,
      clerk.Strategy.totp,
      clerk.Strategy.phoneCode,
    ]) {
      factor = signIn.factorFor(strategy, stage: clerk.Stage.second);
      if (factor != null) break;
    }
    if (factor == null) {
      throw const AuthException(
        AuthErrorKind.unsupported,
        "This account needs a sign-in step the app doesn't support yet. "
        'Please sign in on the website.',
      );
    }
    final strategy = factor.strategy;
    if (strategy.requiresPreparation) {
      // Asks Clerk to send the code (no-op if it was already sent).
      await _call(
        (auth) => auth.attemptSignIn(strategy: strategy),
        (_) => const AuthException(
          AuthErrorKind.unknown,
          "Couldn't send the verification code. Please try again.",
        ),
      );
    }
    _pending = _Pending.signInCode;
    _codeStrategy = strategy;
    return CodeRequired(
      sentTo: factor.safeIdentifier ?? 'your email',
      fromAuthenticatorApp: strategy == clerk.Strategy.totp,
    );
  }

  // ---------------------------------------------------------------------
  // Sign up
  // ---------------------------------------------------------------------

  @override
  Future<AuthStep> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    _clearPending();
    // Clients can't write public_metadata, so a new account has no role and
    // therefore standard "user" access -- admins are only ever made in the
    // Clerk dashboard, exactly as on the web.
    await _call(
      (auth) async {
        await _prepareClient(auth, fresh: true);
        await auth.attemptSignUp(
          strategy: clerk.Strategy.password,
          firstName: firstName,
          lastName: lastName.isEmpty ? null : lastName,
          emailAddress: email,
          password: password,
          passwordConfirmation: password,
        );
      },
      _signUpRejected,
    );

    final auth = _auth!;
    if (auth.isSignedIn) {
      _publish();
      return const AuthComplete();
    }
    final signUp = auth.signUp;
    if (signUp != null &&
        signUp.missingFields.isEmpty &&
        signUp.unverified(clerk.Field.emailAddress) &&
        auth.env.supportsEmailCode) {
      // Clerk requires proof of email ownership: send a 6-digit code.
      await _call(
        (auth) => auth.attemptSignUp(strategy: clerk.Strategy.emailCode),
        _signUpRejected,
      );
      _pending = _Pending.signUpCode;
      _codeStrategy = clerk.Strategy.emailCode;
      return CodeRequired(sentTo: email);
    }
    // e.g. the Clerk instance also requires a username or phone number.
    throw _webOnlySignUp;
  }

  @override
  Future<AuthStep> verifySignUpCode(String code) async {
    if (_pending != _Pending.signUpCode) throw _invalidCode;
    await _call(
      (auth) => auth.attemptSignUp(
        strategy: clerk.Strategy.emailCode,
        code: code.trim(),
      ),
      _codeRejected,
    );
    if (_auth!.isSignedIn) {
      _clearPending();
      _publish();
      return const AuthComplete();
    }
    throw _invalidCode;
  }

  AuthException _signUpRejected(Set<String> codes) {
    if (codes.contains('form_identifier_exists') ||
        codes.contains('email_address_exists')) {
      return const AuthException(
        AuthErrorKind.accountExists,
        'An account with this email already exists. Please sign in instead.',
      );
    }
    if (codes.any((c) => c.startsWith('form_password'))) return _weakPassword;
    if (codes.any((c) => c.contains('captcha'))) return _webOnlySignUp;
    if (codes.contains('form_param_format_invalid')) {
      return const AuthException(
        AuthErrorKind.unknown,
        'Please enter a valid email address.',
      );
    }
    return const AuthException(
      AuthErrorKind.unknown,
      'Sign-up failed. Please check your details and try again.',
    );
  }

  // ---------------------------------------------------------------------
  // Codes
  // ---------------------------------------------------------------------

  @override
  Future<void> resendCode() async {
    final auth = _auth;
    if (auth == null) throw _notConfigured;
    final strategy = switch (_pending) {
      _Pending.signInCode || _Pending.signUpCode => _codeStrategy,
      _Pending.passwordReset => clerk.Strategy.resetPasswordEmailCode,
      _Pending.none => null,
    };
    if (strategy == null || strategy == clerk.Strategy.totp) return;
    // Password reset for an email with no account: nothing to resend, but
    // behave exactly as if a code was sent (no account probing).
    if (_pending == _Pending.passwordReset && auth.signIn == null) return;
    await _call(
      (auth) => auth.resendCode(strategy),
      (_) => const AuthException(
        AuthErrorKind.unknown,
        "Couldn't send a new code. Please try again shortly.",
      ),
    );
  }

  AuthException _codeRejected(Set<String> codes) {
    if (codes.contains('form_code_incorrect')) {
      return const AuthException(
        AuthErrorKind.invalidCode,
        'Incorrect code. Please check it and try again.',
      );
    }
    if (codes.contains('verification_failed')) {
      return const AuthException(
        AuthErrorKind.invalidCode,
        'Too many incorrect codes. Please request a new one.',
      );
    }
    return _invalidCode;
  }

  // ---------------------------------------------------------------------
  // Forgot password (Clerk emails the code itself -- no SMTP needed)
  // ---------------------------------------------------------------------

  @override
  Future<void> startPasswordReset(String email) async {
    _clearPending();
    try {
      await _call(
        (auth) async {
          await _prepareClient(auth, fresh: true);
          await auth.initiatePasswordReset(
            identifier: email,
            strategy: clerk.Strategy.resetPasswordEmailCode,
          );
        },
        (_) => _invalidCode,
      );
    } on AuthException catch (e) {
      // "No such account" etc. are swallowed so the visitor sees the same
      // outcome either way; only problems they can act on surface.
      if (e.kind == AuthErrorKind.network ||
          e.kind == AuthErrorKind.rateLimited ||
          e.kind == AuthErrorKind.notConfigured) {
        rethrow;
      }
    }
    _pending = _Pending.passwordReset;
  }

  @override
  Future<AuthStep> completePasswordReset({
    required String code,
    required String newPassword,
  }) async {
    if (_pending != _Pending.passwordReset || _auth?.signIn == null) {
      throw _invalidCode;
    }
    await _call(
      (auth) => auth.attemptSignIn(
        strategy: clerk.Strategy.resetPasswordEmailCode,
        code: code.trim(),
        password: newPassword,
      ),
      (codes) => codes.any((c) => c.startsWith('form_password'))
          ? _weakPassword
          : _codeRejected(codes),
    );
    return _afterSignInAttempt(failure: _invalidCode);
  }

  // ---------------------------------------------------------------------
  // Signed-in account management
  // ---------------------------------------------------------------------

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _call(
      (auth) => auth.updateUserPassword(currentPassword, newPassword),
      (codes) {
        if (codes.contains('form_password_incorrect') ||
            codes.contains('form_password_validation_failed')) {
          return const AuthException(
            AuthErrorKind.invalidCredentials,
            'Current password is incorrect.',
          );
        }
        if (codes.any((c) => c.startsWith('form_password'))) {
          return _weakPassword;
        }
        if (codes.any((c) => c.contains('reverification'))) {
          return const AuthException(
            AuthErrorKind.unknown,
            'For security, please sign out and sign in again, then change '
            'your password.',
          );
        }
        return const AuthException(
          AuthErrorKind.unknown,
          'Password could not be changed. Please try again.',
        );
      },
    );
  }

  @override
  Future<void> signOut() async {
    _clearPending();
    final auth = _auth;
    if (auth == null) return;
    // End the session on Clerk's side when online...
    final session = auth.session;
    if (session != null) {
      try {
        await auth.signOutOf(session).timeout(_signOutTimeout);
      } catch (_) {
        // Offline: the device still forgets the session below.
      }
    }
    // ...and always forget it on the device (the SDK clears the stored
    // client token before it even tries the network).
    try {
      await auth.signOut().timeout(_signOutTimeout);
    } catch (_) {
      auth.client = clerk.Client.empty;
    }
    _publish();
  }

  @override
  void dispose() {
    _auth?.terminate();
    _changes.close();
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  /// Make sure there's a Clerk client and environment to work with (both are
  /// missing after a first launch without network, or after sign-out). With
  /// [fresh], discard a half-finished sign-up, or a sign-in that already got
  /// past its password step, so the new attempt must start from the email +
  /// password just entered. (A sign-in still waiting for its password, e.g.
  /// after a typo, is simply retried: starting a new client every time would
  /// run into Clerk's rate limits.)
  Future<void> _prepareClient(clerk.Auth auth, {bool fresh = false}) async {
    if (auth.isNotAvailable) await auth.refreshEnvironment();
    final staleSignIn = auth.signIn;
    final stale = auth.isSigningUp ||
        (staleSignIn != null && !staleSignIn.needsFirstFactor);
    if (auth.client.isEmpty || (fresh && !auth.isSignedIn && stale)) {
      await auth.resetClient();
    }
  }

  /// Run [action] and translate any failure into an [AuthException]. Errors
  /// Clerk reports about the request itself go through [rejected], which
  /// picks the message for this particular flow.
  Future<void> _call(
    Future<void> Function(clerk.Auth auth) action,
    AuthException Function(Set<String> codes) rejected,
  ) async {
    final auth = _auth;
    if (auth == null) throw _notConfigured;
    try {
      await action(auth).timeout(_requestTimeout);
    } on AuthException {
      rethrow;
    } on clerk.ClerkError catch (e) {
      final codes = <String>{
        for (final err in e.errors?.errors ?? const [])
          if (err.code case final String code) code,
      };
      if (kDebugMode) debugPrint('Clerk error ${e.code.name} $codes: $e');
      if (codes.contains('socket_exception') ||
          codes.contains('unknown_exception')) {
        throw _network;
      }
      if (e.code == clerk.ClerkErrorCode.tooManyRetries ||
          codes.any((c) => c.contains('too_many') || c.contains('rate_limit'))) {
        throw _rateLimited;
      }
      if (codes.any((c) => c.contains('native'))) throw _nativeApiDisabled;
      if (e.code == clerk.ClerkErrorCode.legalAcceptanceRequired) {
        throw _webOnlySignUp;
      }
      throw rejected(codes);
    } on TimeoutException {
      throw _network;
    } catch (e) {
      // Socket/HTTP/parse failures surface as plain exceptions.
      if (kDebugMode) debugPrint('Auth request failed: $e');
      throw _network;
    }
  }

  void _clearPending() {
    _pending = _Pending.none;
    _codeStrategy = null;
  }

  /// Called on every SDK state change (including the background refresh):
  /// emit only when the person or their role actually changed.
  void _publish() {
    final session = _toSession(_auth?.user);
    if (session == _last) return;
    _last = session;
    if (!_changes.isClosed) _changes.add(session);
  }

  static AuthSession? _toSession(clerk.User? user) {
    if (user == null) return null;
    final email = (user.email ?? '').trim().toLowerCase();
    final name = [user.firstName, user.lastName]
        .whereType<String>()
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .join(' ');
    return AuthSession(
      userId: user.id,
      email: email,
      name: name.isNotEmpty ? name : email,
      role: AppRole.fromMetadata(user.publicMetadata),
    );
  }
}

enum _Pending { none, signInCode, signUpCode, passwordReset }

/// Saves the SDK's state (the signed-in session) in app-private storage.
/// Unlike the SDK's DefaultPersistor, which delays each save by 0.6 s and
/// drops it if the app shuts down meanwhile, this writes straight away, via a
/// temporary file so a crash mid-write can't corrupt the saved session.
class _FilePersistor implements clerk.Persistor {
  _FilePersistor(Directory directory)
      : _file = File('${directory.path}${Platform.pathSeparator}'
            'clerk_session.json');

  final File _file;
  final _cache = <String, dynamic>{};
  Future<void> _lastSave = Future.value();

  @override
  Future<void> initialize() async {
    try {
      if (_file.existsSync()) {
        _cache.addAll(
            jsonDecode(await _file.readAsString()) as Map<String, dynamic>);
      }
    } on FormatException {
      // Unreadable: start signed out.
    }
  }

  @override
  void terminate() {}

  @override
  FutureOr<T?> read<T>(String key) => _cache[key] as T?;

  @override
  FutureOr<void> write<T>(String key, T value) {
    _cache[key] = value;
    _save();
  }

  @override
  FutureOr<void> delete(String key) {
    if (_cache.containsKey(key)) {
      _cache.remove(key);
      _save();
    }
  }

  void _save() {
    final data = jsonEncode(_cache);
    // Chained so saves land in order: an older snapshot never overwrites a
    // newer one.
    _lastSave = _lastSave.then((_) async {
      try {
        final tmp = File('${_file.path}.tmp');
        await tmp.writeAsString(data, flush: true);
        await tmp.rename(_file.path);
      } catch (e) {
        if (kDebugMode) debugPrint('Could not save sign-in state: $e');
      }
    });
  }
}

/// Hooks the SDK's state-change callback.
class _ClerkAuth extends clerk.Auth {
  _ClerkAuth({required super.config, required this.onUpdate});

  final void Function() onUpdate;

  @override
  void update() {
    super.update();
    onUpdate();
  }
}
