import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/services/auth_service.dart';
import 'core/services/theme_service.dart';
import 'screens/auth/app_access_gate_screen.dart';
import 'screens/auth/first_run_setup_screen.dart';
import 'screens/auth/pin_login_screen.dart';
import 'screens/shell/app_shell.dart';

class ProfessionalMobilesApp extends StatelessWidget {
  const ProfessionalMobilesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeService>().mode;
    return MaterialApp(
      title: 'Professional Mobiles & Laptop Service',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const _RootGate(),
      );
  }
}

/// Decides which screen owns the app right now:
/// 0. Shop access password not entered yet on this device -> AppAccessGateScreen.
/// 1. First launch ever -> create the Admin account.
/// 2. Not logged in for this session -> PIN screen.
/// 3. Logged in -> the main app shell.
class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  late Future<bool> _appUnlockedFuture;

  @override
  void initState() {
    super.initState();
    _appUnlockedFuture = context.read<AuthService>().loadAppUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _appUnlockedFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: AppColors.primaryBlue)),
            );
        }
        return Consumer<AuthService>(
          builder: (context, auth, _) {
            if (!auth.appUnlocked) return const AppAccessGateScreen();
            return const _AccountGate();
          },
          );
      },
      );
  }
}

class _AccountGate extends StatefulWidget {
  const _AccountGate();

  @override
  State<_AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<_AccountGate> {
  late Future<bool> _hasAccountFuture;

  @override
  void initState() {
    super.initState();
    _hasAccountFuture = context.read<AuthService>().hasAnyAccount();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasAccountFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: AppColors.primaryBlue)),
            );
        }
        if (!snapshot.data!) {
          return const FirstRunSetupScreen();
        }
        return Consumer<AuthService>(
          builder: (context, auth, _) {
            if (!auth.isLoggedIn) return const PinLoginScreen();
            return const AppShell();
          },
          );
      },
      );
  }
}
