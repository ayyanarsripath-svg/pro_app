import 'package:flutter/material.dart';

import '../../core/repositories/settings_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/section_card.dart';

/// Lets the shop customize the WhatsApp text sent automatically when a
/// service job's status is changed to "Ready for Delivery" (spec: an
/// editable, user-friendly template instead of the fixed built-in wording).
/// Supports simple {token} placeholders so the shop can rearrange/reword
/// freely while the actual customer/bill/amount values still get filled in
/// correctly at send time - see WhatsAppSmsService.readyForDeliveryMessage.
class WhatsAppTemplateScreen extends StatefulWidget {
  const WhatsAppTemplateScreen({super.key});

  @override
  State<WhatsAppTemplateScreen> createState() => _WhatsAppTemplateScreenState();
}

class _WhatsAppTemplateScreenState extends State<WhatsAppTemplateScreen> {
  final _settingsRepo = SettingsRepository();
  final _templateCtrl = TextEditingController();
  bool _loading = true;

  static const _defaultTemplate =
      '📱 PROFESSIONAL MOBILES\n'
      'வணக்கம் {customerName} அவர்களே! 👋\n'
      'உங்களுடைய {mobileName} மொபைல் service செய்து முடிக்கப்பட்டுவிட்டது. ✅\n'
      '📦 Mobile Delivery-ku Ready!\n'
      '💰 Service Amount: {amount}\n'
      '🧾 Bill No: {billNo}\n'
      'தயவுசெய்து கடைக்கு வந்து உங்கள் mobile-ஐ பெற்றுக்கொள்ளவும்.\n'
      '🙏 நன்றி\n'
      '{shopName}';

  static const _tokens = [
    ('{customerName}', 'Customer name'),
    ('{mobileName}', 'Mobile/model name'),
    ('{amount}', 'Service amount'),
    ('{billNo}', 'Bill number'),
    ('{shopName}', 'Shop name'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await _settingsRepo.getReadyIntimationTemplate();
    _templateCtrl.text = (saved == null || saved.trim().isEmpty) ? _defaultTemplate : saved;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    await _settingsRepo.saveReadyIntimationTemplate(_templateCtrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved - this text will be used the next time a job is marked Ready for Delivery.')),
      );
    }
  }

  void _resetToDefault() {
    setState(() => _templateCtrl.text = _defaultTemplate);
  }

  void _insertToken(String token) {
    final sel = _templateCtrl.selection;
    final text = _templateCtrl.text;
    final insertAt = sel.start >= 0 ? sel.start : text.length;
    final newText = text.replaceRange(insertAt, sel.end >= 0 ? sel.end : insertAt, token);
    _templateCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: insertAt + token.length),
    );
  }

  String _previewText() {
    var preview = _templateCtrl.text;
    const sample = {
      '{customerName}': 'Ramesh',
      '{mobileName}': 'Samsung A15',
      '{amount}': '₹1,200',
      '{billNo}': 'A045',
      '{shopName}': 'PROFESSIONAL MOBILES',
    };
    for (final entry in sample.entries) {
      preview = preview.replaceAll(entry.key, entry.value);
    }
    return preview;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WhatsApp Message Template')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                SectionCard(title: 'Ready for Delivery Message', icon: Icons.chat_rounded, children: [
                  Text(
                    'Sent automatically via WhatsApp when a service job\'s status is changed to Ready for Delivery. '
                    'Tap a token below to insert it - it gets replaced with the real value when the message is sent.',
                    style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12.5),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _tokens
                        .map((t) => ActionChip(
                              label: Text(t.$1),
                              tooltip: t.$2,
                              onPressed: () => _insertToken(t.$1),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _templateCtrl,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: 'Message text',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: ElevatedButton(onPressed: _save, child: const Text('Save'))),
                      const SizedBox(width: 10),
                      OutlinedButton(onPressed: _resetToDefault, child: const Text('Reset to Default')),
                    ],
                  ),
                ]),
                SectionCard(title: 'Preview', icon: Icons.visibility_rounded, children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bgOf(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderOf(context)),
                    ),
                    child: Text(_previewText(), style: TextStyle(color: AppColors.textPrimaryOf(context), fontSize: 13)),
                  ),
                ]),
              ],
            ),
    );
  }
}
