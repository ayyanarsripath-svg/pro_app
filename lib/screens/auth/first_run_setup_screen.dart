import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../app.dart';
/// Shown exactly once, the very first time the app is opened on a device -
/// creates the Admin account that owns the Admin PIN gate (spec section 28).
class FirstRunSetupScreen extends StatefulWidget {
  const FirstRunSetupScreen({super.key});

  @override
  State<FirstRunSetupScreen> createState() => _FirstRunSetupScreenState();
}

class _FirstRunSetupScreenState extends State<FirstRunSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _pinConfirmCtrl = TextEditingController();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              child: Container(
                padding: const EdgeInsets.all(24),
                constraints: const BoxConstraints(maxWidth: 420),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Image.asset('assets/images/logo_color.png', height: 90),
                      const SizedBox(height: 8),
                      const Text('PROFESSIONAL MOBILES',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: 0.5)),
                      const Text('& Laptop Service',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 22),
                      const Text('Set up your Admin account', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 4),
                      const Text('This PIN protects profit, cost & business reports.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(labelText: 'Owner / Admin Name'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone (optional)'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _pinCtrl,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(labelText: 'Admin PIN (4-6 digits)'),
                        validator: (v) => (v == null || v.length < 4) ? 'Min 4 digits' : null,
                      ),
                      TextFormField(
                        controller: _pinConfirmCtrl,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(labelText: 'Confirm PIN'),
                        validator: (v) => v != _pinCtrl.text ? 'PIN does not match' : null,
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton(
                        onPressed: _saving ? null : _submit,
                        child: _saving
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Create Admin Account'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
     if (!_formKey.currentState!.validate()) return;
     setState(() => _saving = true);
     await context.read<AuthService>().setupFirstAdmin(
           name: _nameCtrl.text.trim(),
           pin: _pinCtrl.text.trim(),
           phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
         );
     if (mounted) {
       Navigator.of(context).pushAndRemoveUntil(
         MaterialPageRoute(builder: (_) => const ProfessionalMobilesApp()),
         (route) => false,
       );
     }
   }
