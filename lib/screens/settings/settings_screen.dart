import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/repositories/settings_repository.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'backup_screen.dart';
import 'staff_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settingsRepo = SettingsRepository();
  final _nameCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _settingsRepo.getAll();
    _nameCtrl.text = all[SettingsRepository.shopName] ?? 'PROFESSIONAL MOBILES';
    _taglineCtrl.text = all[SettingsRepository.shopTagline] ?? 'SERVICE & 2ND HAND SALES';
    _addressCtrl.text = all[SettingsRepository.shopAddress] ?? 'Mainroad, Ma.Kunnathur';
    _phoneCtrl.text = all[SettingsRepository.shopPhone] ?? '7806938306';
    setState(() => _loading = false);
  }

  Future<void> _saveShopInfo() async {
    await _settingsRepo.set(SettingsRepository.shopName, _nameCtrl.text.trim());
    await _settingsRepo.set(SettingsRepository.shopTagline, _taglineCtrl.text.trim());
    await _settingsRepo.set(SettingsRepository.shopAddress, _addressCtrl.text.trim());
    await _settingsRepo.set(SettingsRepository.shopPhone, _phoneCtrl.text.trim());
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shop details saved - will appear on printed bills.')));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        SectionCard(title: 'Shop Details (shown on printed bills)', icon: Icons.storefront_rounded, children: [
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Shop Name')),
          const SizedBox(height: 10),
          TextField(controller: _taglineCtrl, decoration: const InputDecoration(labelText: 'Tagline')),
          const SizedBox(height: 10),
          TextField(controller: _addressCtrl, decoration: const InputDecoration(labelText: 'Address')),
          const SizedBox(height: 10),
          TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone')),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _saveShopInfo, child: const Text('Save Shop Details')),
        ]),
        Card(
          child: ListTile(
            leading: const Icon(Icons.backup_rounded, color: AppColors.primaryBlue),
            title: const Text('Backup & Restore'),
            subtitle: const Text('Manual backup, daily/weekly auto-backup, Google Drive, restore'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen())),
          ),
        ),
        if (auth.isAdmin)
          Card(
            child: ListTile(
              leading: const Icon(Icons.badge_rounded, color: AppColors.primaryBlue),
              title: const Text('Staff & Permissions'),
              subtitle: const Text('Add staff accounts, set what they can see/do'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffScreen())),
            ),
          ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline_rounded, color: AppColors.primaryBlue),
            title: const Text('About'),
            subtitle: const Text('Professional Mobiles & Laptop Service - Offline Business Manager v1.0'),
          ),
        ),
      ],
    );
  }
}
