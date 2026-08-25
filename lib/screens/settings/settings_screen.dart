import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/repositories/settings_repository.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/logo_service.dart';
import '../../core/services/theme_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'backup_screen.dart';
import 'menu_order_screen.dart';
import 'staff_screen.dart';
import 'whatsapp_template_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Same native channel MainActivity.kt already exposes for the WhatsApp
  // direct-share feature - reused here to ask the running app for its own
  // signing certificate's SHA-1 (see MainActivity.kt's getSigningSha1()).
  static const _nativeChannel = MethodChannel('pro_app/whatsapp_share');

  final _settingsRepo = SettingsRepository();
  final _nameCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _loading = true;
  String _whatsappSendApp = 'auto';

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
    _whatsappSendApp = await _settingsRepo.getWhatsAppSendApp();
    setState(() => _loading = false);
  }

  Future<void> _saveWhatsAppSendApp(String value) async {
    setState(() => _whatsappSendApp = value);
    await _settingsRepo.saveWhatsAppSendApp(value);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WhatsApp sending preference saved')));
  }

  Future<void> _saveShopInfo() async {
    await _settingsRepo.set(SettingsRepository.shopName, _nameCtrl.text.trim());
    await _settingsRepo.set(SettingsRepository.shopTagline, _taglineCtrl.text.trim());
    await _settingsRepo.set(SettingsRepository.shopAddress, _addressCtrl.text.trim());
    await _settingsRepo.set(SettingsRepository.shopPhone, _phoneCtrl.text.trim());
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shop details saved - will appear on printed bills.')));
  }

  Future<void> _changeLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    await context.read<LogoService>().setLogo(File(picked.path));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logo updated - it now shows in the menu and on printed bills.')),
      );
    }
  }

  Future<void> _resetLogo() async {
    await context.read<LogoService>().clearLogo();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logo reset to default')));
  }

  // Admin-only "App Signing Info" - reads this exact install's signing
  // certificate SHA-1 fingerprint natively (MainActivity.kt) and shows it
  // with a one-tap copy button, formatted exactly the way Google Cloud
  // Console's OAuth client "SHA-1 certificate fingerprint" field expects.
  // This is the value that must match the "Pro App Android" OAuth client
  // in Google Cloud Console (project pro-app-drive-backup) for Google
  // Drive backup sign-in to work - if Drive sign-in ever starts looping
  // with "[16] Account reauth failed" again, re-check this against that
  // Console page.
  Future<void> _showSigningInfo() async {
    String? sha1;
    String? error;
    try {
      final result = await _nativeChannel.invokeMethod<String>('getSigningSha1');
      sha1 = result;
    } catch (e) {
      error = e.toString();
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('App Signing Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This is this install\'s signing certificate SHA-1. Paste it into '
              'Google Cloud Console -> APIs & Services -> Credentials -> '
              '"Pro App Android" OAuth client -> SHA-1 certificate fingerprint '
              'if Google Drive backup ever gets stuck re-asking for account '
              'sign-in.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondaryOf(context)),
            ),
            const SizedBox(height: 14),
            if (sha1 != null)
              SelectableText(
                sha1,
                style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13),
              )
            else
              Text(
                'Could not read the signing certificate${error != null ? ' ($error)' : ''}.',
                style: const TextStyle(color: Colors.red),
              ),
          ],
        ),
        actions: [
          if (sha1 != null)
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: sha1!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('SHA-1 copied - paste it into Google Cloud Console')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final theme = context.watch<ThemeService>();
    final logo = context.watch<LogoService>();
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        SectionCard(title: 'Appearance', icon: Icons.dark_mode_rounded, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dark Mode'),
            subtitle: Text(theme.isDark ? 'Dark theme (easier on the eyes at night)' : 'Light theme (default, bright/sunlight friendly)'),
            secondary: Icon(theme.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, color: AppColors.primaryBlue),
            value: theme.isDark,
            onChanged: (v) => theme.setDark(v),
          ),
        ]),
        SectionCard(title: 'App Logo', icon: Icons.image_rounded, children: [
          Text(
            'Shown in the menu and on printed bills.',
            style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // A generous, rectangular (not squared-off) preview box so a
              // wide or tall shop photo is never squeezed into a tiny
              // square - BoxFit.contain always shows the full image, this
              // box just gives it room to actually be seen at a decent
              // size. Rounded corners + soft shadow for a richer look.
              Container(
                width: 130,
                height: 84,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.bgOf(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderOf(context)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 3)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: logo.hasCustomLogo
                      ? Image.file(logo.logoFile!, fit: BoxFit.contain)
                      : Image.asset('assets/images/logo_color.png', fit: BoxFit.contain),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _changeLogo,
                      icon: const Icon(Icons.upload_rounded),
                      label: const Text('Change Logo'),
                    ),
                    if (logo.hasCustomLogo)
                      OutlinedButton(onPressed: _resetLogo, child: const Text('Reset to Default')),
                  ],
                ),
              ),
            ],
          ),
        ]),
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
        SectionCard(title: 'WhatsApp Sending', icon: Icons.chat_bubble_rounded, children: [
          Text(
            'If this phone has both WhatsApp and WhatsApp Business installed, choose which one customer intimations (Received/Ready/Delivered/Warranty) should open in - a mismatch is the usual reason a message quietly "never goes" even though it opened somewhere.',
            style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Ask automatically (default)'),
                selected: _whatsappSendApp == 'auto',
                onSelected: (_) => _saveWhatsAppSendApp('auto'),
              ),
              ChoiceChip(
                label: const Text('Always use WhatsApp Business'),
                selected: _whatsappSendApp == 'business',
                onSelected: (_) => _saveWhatsAppSendApp('business'),
              ),
              ChoiceChip(
                label: const Text('Always use regular WhatsApp'),
                selected: _whatsappSendApp == 'regular',
                onSelected: (_) => _saveWhatsAppSendApp('regular'),
              ),
            ],
          ),
        ]),
        Card(
          child: ListTile(
            leading: const Icon(Icons.reorder_rounded, color: AppColors.primaryBlue),
            title: const Text('Customize Menu'),
            subtitle: const Text('Reorder the drawer menu - move what you use most to the top'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MenuOrderScreen())),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.chat_rounded, color: AppColors.primaryBlue),
            title: const Text('WhatsApp Message Templates'),
            subtitle: const Text('Customize the Received, Ready, and Delivery intimation texts sent to customers'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WhatsAppTemplateScreen())),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.backup_rounded, color: AppColors.primaryBlue),
            title: const Text('Backup & Restore'),
            subtitle: const Text('Manual backup, weekly auto-backup, Google Drive, restore'),
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
        if (auth.isAdmin)
          Card(
            child: ListTile(
              leading: const Icon(Icons.fingerprint_rounded, color: AppColors.primaryBlue),
              title: const Text('App Signing Info'),
              subtitle: const Text('SHA-1 fingerprint for Google Cloud Console (Drive backup sign-in)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showSigningInfo,
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
