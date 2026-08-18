import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';

class PinLoginScreen extends StatefulWidget {
  const PinLoginScreen({super.key});

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  final _pinCtrl = TextEditingController();
  String? _error;
  bool _checking = false;

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
                    const Text('Enter PIN to continue', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pinCtrl,
                      obscureText: true,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      style: const TextStyle(fontSize: 22, letterSpacing: 8),
                      decoration: InputDecoration(
                        counterText: '',
                        errorText: _error,
                        hintText: '••••',
                        ),
                      onSubmitted: (_) => _submit(),
                      onChanged: (v) => _submit(auto: true),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _checking ? null : _submit,
                        child: _checking
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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

  Future<void> _submit({bool auto = false}) async {
    final value = _pinCtrl.text.trim();
    if (auto && value.length < 4) return;
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok = await context.read<AuthService>().loginWithPin(value);
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (!ok) {
        if (!auto || value.length >= 6) {
          _error = 'Incorrect PIN';
          _pinCtrl.clear();
        }
      }
    });
  }
}
