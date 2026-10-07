import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_models.dart';
import '../widgets/auth_widgets.dart';

/// Change password for the signed-in person; requires the current password
/// (same rules as the web app's sidebar form).
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_current, _newPassword, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    String? invalid;
    if (_current.text.isEmpty) {
      invalid = 'Please enter your current password.';
    } else {
      invalid = AuthController.validatePasswordPair(
          _newPassword.text, _confirm.text);
      if (invalid == null && _current.text == _newPassword.text) {
        invalid = 'The new password must be different from the current one.';
      }
    }
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
      await context.read<AuthController>().changePassword(
            currentPassword: _current.text,
            newPassword: _newPassword.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated.')),
      );
      Navigator.pop(context);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PasswordField(
                          controller: _current,
                          label: 'Current password',
                        ),
                        const SizedBox(height: 12),
                        PasswordField(
                          controller: _newPassword,
                          label: 'New password',
                          hint: 'At least ${AuthController.minPasswordLength} '
                              'characters, with a letter and a number',
                          isNewPassword: true,
                        ),
                        const SizedBox(height: 12),
                        PasswordField(
                          controller: _confirm,
                          label: 'Confirm new password',
                          isNewPassword: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Changing your password signs you out on your '
                          'other devices. An internet connection is required.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          AuthMessage(_error!),
                        ],
                        const SizedBox(height: 16),
                        BusyButton(
                          label: 'Update password',
                          busy: _busy,
                          onPressed: _submit,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
