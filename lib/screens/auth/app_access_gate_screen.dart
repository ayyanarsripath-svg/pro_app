import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';

/// The very first screen anyone sees when they open the app. This is not
/// the staff/admin PIN login (that comes after) - it is a single shared
/// shop access password that must be entered once per device before the
/// app will even let someone create the first Admin account. Without
/// this, anyone who obtained a copy of the APK file could install it and
/// set themselves up as Admin.
class AppAccessGateScreen extends StatefulWidget {
  const AppAccessGateScreen({super.key});

  @override
  State<AppAccessGateScreen> createState() => _AppAccessGateScreenState();
}

class _AppAccessGateScreenState extends State<AppAccessGateScreen> {
  final _passwordCtrl = TextEditingController();
  String? _error;
  bool _checking = false;
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Container(
                padding: const EdgeInsets.all(24),
                constraints: const BoxConstraints(maxWidth: 380),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/images/logo_color.png', height: 84),
                    const SizedBox(height: 10),
                    const Text(
                      'Enter access password to continue',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                        errorText: _error,
                        hintText: 'Password',
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                      onSubmitted: (_) => _submit(),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _checking ? null : _submit,
                        child: _checking
                        ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Unlock'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
  }

  Future<void> _submit() async {
    final value = _passwordCtrl.text;
    if (value.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok = await context.read<AuthService>().unlockApp(value);
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (!ok) {
        _error = 'Incorrect password';
        _passwordCtrl.clear();
      }
    });
  }
}
