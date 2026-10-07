import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_models.dart';
import '../widgets/auth_widgets.dart';

/// Two-step "Forgot password?" flow, as on the web: request an emailed
/// 6-digit code, then enter it with a new password. Clerk sends the email
/// itself. On success the person is signed in and the auth gate closes this
/// page.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.initialEmail.trim());
  final _code = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _info;
  CodeRequired? _secondStep;

  @override
  void dispose() {
    for (final c in [_email, _code, _newPassword, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function(AuthController auth) action) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = _info = null;
    });
    try {
      await action(context.read<AuthController>());
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final email = AuthController.normalizeEmail(_email.text);
    if (!AuthController.emailPattern.hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    await _run((auth) async {
      final message = await auth.startPasswordReset(email);
      if (mounted) {
        setState(() {
          _codeSent = true;
          _info = message;
        });
      }
    });
  }

  Future<void> _resetPassword() async {
    final invalid = AuthController.validateCode(_code.text) ??
        AuthController.validatePasswordPair(_newPassword.text, _confirm.text);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    await _run((auth) async {
      final step = await auth.completePasswordReset(
        code: _code.text,
        newPassword: _newPassword.text,
      );
      if (mounted && step is CodeRequired) setState(() => _secondStep = step);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _secondStep != null
                      ? CodeEntryForm(
                          step: _secondStep!,
                          purpose: 'Your password has been reset. One more '
                              'step to confirm it’s you.',
                          onVerify:
                              context.read<AuthController>().verifySignInCode,
                          onBack: () => Navigator.pop(context),
                        )
                      : _buildResetForm(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResetForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _codeSent
              ? 'Enter the 6-digit code from the email, then choose a new '
                  'password.'
              : 'Enter your account email and we’ll send you a 6-digit code '
                  'to reset your password.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          enabled: !_codeSent,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _codeSent ? null : _sendCode(),
          decoration: const InputDecoration(
            labelText: 'Account email',
            hintText: 'you@example.com',
            prefixIcon: Icon(Icons.mail_outline, size: 20),
          ),
        ),
        if (_codeSent) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: const InputDecoration(
              labelText: '6-digit code',
              hintText: '123456',
              prefixIcon: Icon(Icons.pin_outlined, size: 20),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          PasswordField(
            controller: _newPassword,
            label: 'New password',
            hint: 'At least ${AuthController.minPasswordLength} characters, '
                'with a letter and a number',
            isNewPassword: true,
          ),
          const SizedBox(height: 12),
          PasswordField(
            controller: _confirm,
            label: 'Confirm new password',
            isNewPassword: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _resetPassword(),
          ),
        ],
        if (_info != null) ...[
          const SizedBox(height: 12),
          AuthMessage(_info!, isError: false),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          AuthMessage(_error!),
        ],
        const SizedBox(height: 16),
        BusyButton(
          label: _codeSent ? 'Reset password' : 'Email me a code',
          busy: _busy,
          onPressed: _codeSent ? _resetPassword : _sendCode,
        ),
        if (_codeSent) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _codeSent = false;
                          _error = _info = null;
                        }),
                child: const Text('Use a different email'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run((auth) async {
                          await auth.resendCode();
                          if (mounted) {
                            setState(() => _info = 'A new code has been sent '
                                'if an account exists for that email.');
                          }
                        }),
                child: const Text('Resend code'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
