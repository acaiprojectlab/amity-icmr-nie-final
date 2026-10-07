import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_models.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/logo_header.dart';
import 'forgot_password_screen.dart';

/// Sign-in / create-account screen, mirroring the web app's login page:
/// co-branded logos, "Sign in" and "Create account" tabs, forgot-password,
/// and the "Authorized ICMR/NIE personnel only" notice.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setupError = context.watch<AuthController>().setupError;
    const primaryBlue = Color(0xFF1565C0);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 3,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The three logos together are ~6.4x as wide as
                        // they are tall: scale them to fit narrow phones.
                        LayoutBuilder(
                          builder: (context, constraints) => LogoHeader(
                            height: ((constraints.maxWidth - 48) / 6.6)
                                .clamp(28.0, 52.0),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
                          child: Column(
                            children: [
                              Text(
                                '🦠 Personalized Laboratory Test '
                                'Recommendation System',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: primaryBlue,
                                  height: 1.25,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Sign in to continue to the diagnostic '
                                'workspace',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 13, color: Color(0xFF5F6B7A)),
                              ),
                            ],
                          ),
                        ),
                        if (setupError != null)
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: AuthMessage(setupError),
                          )
                        else ...[
                          TabBar(
                            controller: _tabs,
                            labelColor: primaryBlue,
                            indicatorColor: primaryBlue,
                            tabs: const [
                              Tab(
                                icon: Icon(Icons.lock_outline, size: 20),
                                text: 'Sign in',
                              ),
                              Tab(
                                icon: Icon(Icons.person_add_alt_1_outlined,
                                    size: 20),
                                text: 'Create account',
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                            // Both forms stay alive so switching tabs keeps
                            // what was typed.
                            child: Column(
                              children: [
                                Visibility(
                                  visible: _tabs.index == 0,
                                  maintainState: true,
                                  child: const _SignInForm(),
                                ),
                                Visibility(
                                  visible: _tabs.index == 1,
                                  maintainState: true,
                                  child: const _SignUpForm(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Authorized ICMR/NIE personnel only. '
                    'All access is monitored.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF8A93A1)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignInForm extends StatefulWidget {
  const _SignInForm();

  @override
  State<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<_SignInForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  CodeRequired? _codeStep;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = AuthController.normalizeEmail(_email.text);
    if (!AuthController.emailPattern.hasMatch(email) || _password.text.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final step =
          await context.read<AuthController>().signIn(email, _password.text);
      if (mounted && step is CodeRequired) setState(() => _codeStep = step);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _codeStep;
    if (step != null) {
      return CodeEntryForm(
        step: step,
        purpose: 'One more step to confirm it’s you.',
        onVerify: context.read<AuthController>().verifySignInCode,
        onBack: () => setState(() => _codeStep = null),
      );
    }

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email address',
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.mail_outline, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          PasswordField(
            controller: _password,
            label: 'Password',
            hint: 'Your password',
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            AuthMessage(_error!),
          ],
          const SizedBox(height: 16),
          BusyButton(label: 'Sign in', busy: _busy, onPressed: _submit),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ForgotPasswordScreen(initialEmail: _email.text),
                        ),
                      ),
              child: const Text('Forgot password?'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignUpForm extends StatefulWidget {
  const _SignUpForm();

  @override
  State<_SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends State<_SignUpForm> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  CodeRequired? _codeStep;

  @override
  void dispose() {
    for (final c in [_firstName, _lastName, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final invalid = AuthController.validateSignUp(
      firstName: _firstName.text,
      email: _email.text,
      password: _password.text,
      confirm: _confirm.text,
    );
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final step = await context.read<AuthController>().signUp(
            firstName: _firstName.text,
            lastName: _lastName.text,
            email: _email.text,
            password: _password.text,
          );
      if (mounted && step is CodeRequired) setState(() => _codeStep = step);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _codeStep;
    if (step != null) {
      return CodeEntryForm(
        step: step,
        purpose: 'Confirm your email address to finish creating your account.',
        onVerify: context.read<AuthController>().verifySignUpCode,
        onBack: () => setState(() => _codeStep = null),
      );
    }

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _firstName,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.givenName],
                  decoration: const InputDecoration(labelText: 'First name'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _lastName,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.familyName],
                  decoration: const InputDecoration(
                    labelText: 'Last name',
                    hintText: 'Optional',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email address',
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.mail_outline, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          PasswordField(
            controller: _password,
            label: 'Password',
            hint: 'At least ${AuthController.minPasswordLength} characters, '
                'with a letter and a number',
            isNewPassword: true,
          ),
          const SizedBox(height: 12),
          PasswordField(
            controller: _confirm,
            label: 'Confirm password',
            hint: 'Re-enter your password',
            isNewPassword: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          const Text(
            'New accounts start with standard (user) access. '
            'Administrator access is granted separately.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            AuthMessage(_error!),
          ],
          const SizedBox(height: 16),
          BusyButton(label: 'Create account', busy: _busy, onPressed: _submit),
        ],
      ),
    );
  }
}
