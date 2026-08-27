import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/repositories/settings_repository.dart';
import '../../core/repositories/staff_repository.dart';
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

  // This app's own Google Cloud project (see README.md's Google Drive
  // Backup section) - both links below jump straight into it instead of
  // Console's generic project picker, so there's no "which project?" step
  // for the shop owner to get stuck on.
  static const _gcpProjectId = 'pro-app-drive-backup';
  static const _androidPackageName = 'com.example.pro_app';
  static const _credentialsUrl = 'https://console.cloud.google.com/apis/credentials?project=$_gcpProjectId';
  // "Audience" is Google Cloud Console's current name for the OAuth
  // consent screen's Test users list (older Console UIs call this page
  // "OAuth consent screen") - this is where a specific Google account
  // (mail id) has to be added before Google will let that account sign in
  // at all while this project stays in "Testing" publishing status.
  static const _testUsersUrl = 'https://console.cloud.google.com/auth/audience?project=$_gcpProjectId';

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

  // Re-asks for a staff/admin PIN right before revealing the signing
  // fingerprint below - being an admin login already gates the menu entry
  // itself, but this is sensitive enough (it's effectively a security
  // credential for the Google Drive OAuth client) that the spec asked for
  // an extra "master password" re-check immediately before showing it,
  // same idea as re-entering a password before revealing something
  // sensitive elsewhere. Any active staff/admin PIN is accepted, same as
  // every other PIN check in the app.
  Future<bool> _confirmMasterPin() async {
    final pinCtrl = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Enter Master PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('For your protection, re-enter your admin/staff PIN to view the signing info.'),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(labelText: 'PIN', errorText: error),
                onSubmitted: (_) => Navigator.pop(context, true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final staff = await StaffRepository().verifyPin(pinCtrl.text.trim());
                if (staff == null) {
                  setLocalState(() => error = 'Wrong PIN');
                  return;
                }
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    return ok ?? false;
  }

  /// Opens a URL in the phone's own browser (Chrome on almost every
  /// Android device) - always externally, never inside this app, since
  /// signing in to Google Cloud Console needs the full browser (cookies,
  /// account switcher) that an in-app webview can't reliably offer.
  Future<void> _openInChrome(String url) async {
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open $url')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open the link: $e')));
      }
    }
  }

  /// One tappable row: an icon + a link-styled label that opens [url] in
  /// Chrome (spec: "atha touch panna direct ah chrome open aagi sha
  /// change panra website kattanum" - the SHA-1/test-user setup steps
  /// below used to only ever be plain, un-clickable instructions text;
  /// now each step that needs a Console page opens it directly).
  Widget _consoleLinkRow({required IconData icon, required String label, required String url}) {
    return InkWell(
      onTap: () => _openInChrome(url),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.primaryBlue),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12.5, color: AppColors.primaryBlue, decoration: TextDecoration.underline, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.open_in_new_rounded, size: 14, color: AppColors.primaryBlue.withOpacity(0.7)),
          ],
        ),
      ),
    );
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
  //
  // Also walks through the OTHER half of getting a Google account working
  // with Drive backup (spec: "sha finger print entha mail id ku work
  // aaganumnu setup pannuvomla antha instruction kattanum") - registering
  // the SHA-1 alone is not enough while this project's OAuth consent
  // screen stays in "Testing" status; the specific Google account (mail
  // id) that will sign in from this phone also has to be added as a Test
  // user, or Google refuses that account outright before this app ever
  // sees it. Both steps now have their own direct Console link (tap ->
  // Chrome opens straight to that page - see _consoleLinkRow), instead of
  // this dialog just describing the steps in plain text and leaving the
  // shop owner to find Console's menus themselves.
  Future<void> _showSigningInfo() async {
    final confirmed = await _confirmMasterPin();
    if (!confirmed || !mounted) return;
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
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This is this install\'s signing certificate SHA-1 - Google needs it, '
                'together with the package name below, to let this app sign in for '
                'Google Drive backup.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: 14),
              if (sha1 != null) ...[
                Text('SHA-1 fingerprint', style: TextStyle(fontSize: 11, color: AppColors.textSecondaryOf(context))),
                SelectableText(
                  sha1,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13),
                ),
                const SizedBox(height: 10),
                Text('Package name', style: TextStyle(fontSize: 11, color: AppColors.textSecondaryOf(context))),
                const SelectableText(
                  _androidPackageName,
                  style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13),
                ),
                const Divider(height: 26),
                const Text('How to set this up', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                const SizedBox(height: 6),
                Text(
                  '1. Open Credentials below - sign in with the Google account that owns this app\'s '
                  'project, if asked. Open the "Pro App Android" Android OAuth client, paste in the '
                  'SHA-1 and package name above (use Copy), then Save.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 6),
                _consoleLinkRow(icon: Icons.vpn_key_rounded, label: 'Open Credentials (add SHA-1)', url: _credentialsUrl),
                const SizedBox(height: 10),
                Text(
                  '2. Open Test users below and Add the Google mail id that will actually sign in on '
                  'this phone. Skip this only if that account already appears in the list, or if '
                  '"Publishing status" has already been moved to "In production".',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 6),
                _consoleLinkRow(icon: Icons.person_add_alt_1_rounded, label: 'Open Test Users (add mail id)', url: _testUsersUrl),
              ] else
                Text(
                  'Could not read the signing certificate${error != null ? ' ($error)' : ''}.',
                  style: const TextStyle(color: Colors.red),
                ),
            ],
          ),
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
