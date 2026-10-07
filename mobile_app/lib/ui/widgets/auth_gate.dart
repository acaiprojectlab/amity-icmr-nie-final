import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../screens/login_screen.dart';
import 'navigation_shell.dart';

/// Shows the sign-in screen until someone is signed in, then the app with
/// the sections their role allows.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _shownAccess;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final session = auth.session;
    // Who is signed in and with which role; any change rebuilds the app
    // shell from scratch.
    final access = session == null
        ? auth.status.name
        : '${session.userId}:${session.role.name}';
    if (_shownAccess != null && access != _shownAccess) {
      // Signed in/out or role changed: close anything pushed on top (a
      // record being edited, the password-reset page, the account sheet) so
      // nothing from the previous access level stays on screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });
    }
    _shownAccess = access;

    return switch (auth.status) {
      AuthStatus.starting => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      AuthStatus.signedOut => const LoginScreen(),
      AuthStatus.signedIn => NavigationShell(key: ValueKey(access)),
    };
  }
}
