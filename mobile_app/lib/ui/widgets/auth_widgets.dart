import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_models.dart';
import '../../sync/record_syncer.dart';
import '../screens/change_password_screen.dart';

/// "Admin" / "User" pill, same colours as the web app's sidebar badge.
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == AppRole.admin;
    final fg = isAdmin ? const Color(0xFF1A63C9) : const Color(0xFF4A5563);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isAdmin ? const Color(0xFFE8F1FD) : const Color(0xFFEEF2F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isAdmin ? Icons.shield_outlined : Icons.person_outline,
              size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            role.label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
  }
}

/// Error / info banner used by the sign-in forms.
class AuthMessage extends StatelessWidget {
  const AuthMessage(this.text, {super.key, this.isError = true});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFC62828) : const Color(0xFF2E7D32);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12.5, color: color, height: 1.3)),
          ),
        ],
      ),
    );
  }
}

/// Password input with a show/hide toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.isNewPassword = false,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool isNewPassword;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscured,
      enableSuggestions: false,
      autocorrect: false,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      autofillHints: [
        widget.isNewPassword ? AutofillHints.newPassword : AutofillHints.password
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.lock_outline, size: 20),
        suffixIcon: IconButton(
          icon: Icon(_obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 20),
          tooltip: _obscured ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
      ),
    );
  }
}

/// Full-width primary button with a busy spinner.
class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// "Enter the 6-digit code" step shared by sign-in (new-device / two-step
/// checks), sign-up (email verification) and password reset.
class CodeEntryForm extends StatefulWidget {
  const CodeEntryForm({
    super.key,
    required this.step,
    required this.purpose,
    required this.onVerify,
    required this.onBack,
  });

  final CodeRequired step;

  /// Sentence explaining why the code is needed.
  final String purpose;
  final Future<AuthStep> Function(String code) onVerify;
  final VoidCallback onBack;

  @override
  State<CodeEntryForm> createState() => _CodeEntryFormState();
}

class _CodeEntryFormState extends State<CodeEntryForm> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final invalid = AuthController.validateCode(_code.text);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = _info = null;
    });
    try {
      await widget.onVerify(_code.text.trim());
      // On success the auth gate swaps to the app.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = _info = null;
    });
    try {
      await context.read<AuthController>().resendCode();
      if (mounted) setState(() => _info = 'A new code has been sent.');
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fromApp = widget.step.fromAuthenticatorApp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          fromApp
              ? '${widget.purpose} Enter the 6-digit code from your '
                  'authenticator app.'
              : '${widget.purpose} We sent a 6-digit code to '
                  '${widget.step.sentTo}.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          maxLength: 6,
          autofillHints: const [AutofillHints.oneTimeCode],
          onSubmitted: (_) => _verify(),
          decoration: const InputDecoration(
            labelText: '6-digit code',
            hintText: '123456',
            prefixIcon: Icon(Icons.pin_outlined, size: 20),
            counterText: '',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          AuthMessage(_error!),
        ],
        if (_info != null) ...[
          const SizedBox(height: 10),
          AuthMessage(_info!, isError: false),
        ],
        const SizedBox(height: 14),
        BusyButton(label: 'Verify', busy: _busy, onPressed: _verify),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back'),
              onPressed: _busy ? null : widget.onBack,
            ),
            if (!fromApp)
              TextButton(
                onPressed: _busy ? null : _resend,
                child: const Text('Resend code'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Shown in place of a restricted screen (defense in depth behind the
/// navigation, like the web app's require_page_access).
class AccessDeniedView extends StatelessWidget {
  const AccessDeniedView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Access denied')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 48, color: Color(0xFFC62828)),
              SizedBox(height: 14),
              Text(
                'Access denied — this section is restricted to '
                'administrators.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'If you believe you need access, contact your system '
                'administrator.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// App-bar button that opens the account sheet (identity, role, change
/// password, sign out) -- the mobile counterpart of the web sidebar block.
class AccountButton extends StatelessWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.account_circle_outlined),
      tooltip: 'Account',
      onPressed: () => showAccountSheet(context),
    );
  }
}

Future<void> showAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => const _AccountSheet(),
  );
}

class _AccountSheet extends StatelessWidget {
  const _AccountSheet();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final session = auth.session;
    if (session == null) return const SizedBox.shrink();
    final initial = session.name.isNotEmpty ? session.name[0].toUpperCase() : '?';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(initial)),
              title: Text(session.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(session.email,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: RoleBadge(role: session.role),
            ),
            Text(
              session.isAdmin
                  ? 'Administrator access: dashboard, patient intake & '
                      'prediction, and patient records.'
                  : 'Standard access: patient intake & prediction. '
                      'Administrator access is granted separately.',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.key_outlined),
              title: const Text('Change password'),
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute(
                      builder: (_) => const ChangePasswordScreen()),
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout, color: Color(0xFFC62828)),
              title: const Text('Sign out',
                  style: TextStyle(color: Color(0xFFC62828))),
              onTap: () async {
                final navigator = Navigator.of(context);
                final pending = context.read<RecordSyncer>().pending;
                navigator.pop();
                if (pending > 0 && !await _confirmSignOut(navigator.context, pending)) {
                  return;
                }
                auth.signOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Patients enrolled here stay on the phone until uploaded; make sure
/// signing out is deliberate when some haven't gone up yet.
Future<bool> _confirmSignOut(BuildContext context, int pending) async {
  final plural = pending == 1 ? 'patient has' : 'patients have';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Not uploaded yet'),
      content: Text(
        '$pending $plural not been uploaded to the shared database yet. '
        'They stay safely on this phone and upload the next time anyone '
        'signs in here with an internet connection.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  return ok == true;
}
