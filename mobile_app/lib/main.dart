import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'auth/auth_controller.dart';
import 'auth/auth_service.dart';
import 'auth/clerk_auth_service.dart';
import 'providers/app_provider.dart';
import 'ui/widgets/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientation (portrait for medical tablets/phones)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const AmityIcmrApp());
}

class AmityIcmrApp extends StatefulWidget {
  const AmityIcmrApp({super.key, this.authService, this.appProvider});

  /// Defaults to Clerk (same accounts as the web app); tests pass a fake.
  final AuthService? authService;

  @visibleForTesting
  final AppProvider? appProvider;

  @override
  State<AmityIcmrApp> createState() => _AmityIcmrAppState();
}

class _AmityIcmrAppState extends State<AmityIcmrApp> {
  late final AuthController _auth =
      AuthController(widget.authService ?? ClerkAuthService());
  // Created up front so the ML models load while the person signs in.
  late final AppProvider _app = widget.appProvider ?? AppProvider();

  @override
  void initState() {
    super.initState();
    _auth.addListener(_syncAccess);
    _auth.initialize();
  }

  // Role changes (sign-in, sign-out, admin promotion/demotion picked up in
  // the background) immediately change what data the app will load.
  void _syncAccess() => _app.applyAccess(_auth.session);

  @override
  void dispose() {
    _auth.removeListener(_syncAccess);
    _auth.dispose();
    _app.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF1565C0);
    const secondaryTeal = Color(0xFF00897B);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _auth),
        ChangeNotifierProvider.value(value: _app),
      ],
      child: MaterialApp(
        title: 'ICMR-NIE & ACAI Virus Diagnostic System',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: primaryBlue,
            primary: primaryBlue,
            secondary: secondaryTeal,
            surface: Colors.white,
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF8FAFC),
          appBarTheme: const AppBarTheme(
            backgroundColor: primaryBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: false,
            titleTextStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: -0.2,
            ),
            iconTheme: IconThemeData(color: Colors.white),
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: primaryBlue, width: 1.5),
            ),
            labelStyle: const TextStyle(fontSize: 13, color: Colors.black87),
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBlue,
              foregroundColor: Colors.white,
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        home: const AuthGate(),
      ),
    );
  }
}
