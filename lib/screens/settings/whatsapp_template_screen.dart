import 'package:flutter/material.dart';

import '../../core/repositories/settings_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/section_card.dart';

/// Lets the shop customize the WhatsApp text sent automatically at each of
/// the three service-job stages - Received (job-card intake), Ready (status
/// changed to Ready for Delivery), and Delivery (final handover) - each one
/// independently editable with its own tokens and live preview (spec:
/// "received kum ready kum aprom delivery kum thani thaniya customise
/// need"). Supports simple {token} placeholders so the shop can rearrange/
/// reword freely while the actual customer/bill/amount values still get
/// filled in correctly at send time - see WhatsAppSmsService's
/// serviceIntimationMessage / readyForDeliveryMessage / deliveryMessage.
class WhatsAppTemplateScreen extends StatefulWidget {
  const WhatsAppTemplateScreen({super.key});

  @override
  State<WhatsAppTemplateScreen> createState() => _WhatsAppTemplateScreenState();
}

class _TemplateSpec {
  final String title;
  final String subtitle;
  final String defaultTemplate;
  final List<(String, String)> tokens;
  final Map<String, String> previewSample;
  final Future<String?> Function(SettingsRepository) load;
  final Future<void> Function(SettingsRepository, String) save;

  const _TemplateSpec({
    required this.title,
    required this.subtitle,
    required this.defaultTemplate,
    required this.tokens,
    required this.previewSample,
    required this.load,
    required this.save,
  });
}

final List<_TemplateSpec> _specs = [
  _TemplateSpec(
    title: 'Received Message',
    subtitle: 'Sent automatically via WhatsApp the moment a new service job card is created.',
    defaultTemplate: '📱 Mobile Service Received\n'
        'Dear Customer, உங்கள் mobile service-க்கு கொடுக்கப்பட்டுள்ளது.\n'
        '🔧 Model: {mobileName}\n'
        '📝 Problem: {complaint}\n'
        '💰 spare + service charge Amount: {amount}\n'
        '📞 Service முடிந்ததும் உங்களுக்கு WhatsApp மூலம் தகவல் தெரிவிக்கப்படும். நன்றி! 🙏\n'
        '{shopName}',
    tokens: const [
      ('{customerName}', 'Customer name'),
      ('{mobileName}', 'Mobile/model name'),
      ('{complaint}', 'Problem/complaint'),
      ('{amount}', 'Service + spare charge'),
      ('{shopName}', 'Shop name'),
      ('{billNo}', 'Bill number'),
      ('{imei}', 'IMEI / Serial No'),
      ('{technician}', 'Technician name'),
      ('{status}', 'Job status'),
      ('{receivedDate}', 'Date received'),
      ('{expectedDelivery}', 'Expected delivery date'),
    ],
    previewSample: const {
      '{customerName}': 'Ramesh',
      '{mobileName}': 'Samsung A15',
      '{complaint}': 'Display damage',
      '{amount}': '₹1,200',
      '{shopName}': 'PROFESSIONAL MOBILES',
      '{billNo}': 'A045',
      '{imei}': '351234567891234',
      '{technician}': 'Kumar',
      '{status}': 'Received',
      '{receivedDate}': '21/08/2026',
      '{expectedDelivery}': '23/08/2026',
    },
    load: (repo) => repo.getReceivedIntimationTemplate(),
    save: (repo, text) => repo.saveReceivedIntimationTemplate(text),
  ),
  _TemplateSpec(
    title: 'Ready for Delivery Message',
    subtitle: 'Sent automatically via WhatsApp when a service job\'s status is changed to Ready for Delivery.',
    defaultTemplate: '📱 PROFESSIONAL MOBILES\n'
        'வணக்கம் {customerName} அவர்களே! 👋\n'
        'உங்களுடைய {mobileName} மொபைல் service செய்து முடிக்கப்பட்டுவிட்டது. ✅\n'
        '📦 Mobile Delivery-ku Ready!\n'
        '💰 Service Amount: {amount}\n'
        '🧾 Bill No: {billNo}\n'
        'தயவுசெய்து கடைக்கு வந்து உங்கள் mobile-ஐ பெற்றுக்கொள்ளவும்.\n'
        '🙏 நன்றி\n'
        '{shopName}',
    tokens: const [
      ('{customerName}', 'Customer name'),
      ('{mobileName}', 'Mobile/model name'),
      ('{amount}', 'Service amount'),
      ('{billNo}', 'Bill number'),
      ('{shopName}', 'Shop name'),
      ('{complaint}', 'Problem/complaint'),
      ('{imei}', 'IMEI / Serial No'),
      ('{technician}', 'Technician name'),
      ('{balance}', 'Balance still due'),
    ],
    previewSample: const {
      '{customerName}': 'Ramesh',
      '{mobileName}': 'Samsung A15',
      '{amount}': '₹1,200',
      '{billNo}': 'A045',
      '{shopName}': 'PROFESSIONAL MOBILES',
      '{complaint}': 'Display damage',
      '{imei}': '351234567891234',
      '{technician}': 'Kumar',
      '{balance}': '₹0',
    },
    load: (repo) => repo.getReadyIntimationTemplate(),
    save: (repo, text) => repo.saveReadyIntimationTemplate(text),
  ),
  _TemplateSpec(
    title: 'Delivery Message',
    subtitle: 'Sent automatically via WhatsApp the moment a job is marked Delivered.',
    defaultTemplate: '📱 Mobile Service Delivered\n'
        'Dear Customer, உங்கள் mobile service முடிந்து ஒப்படைக்கப்பட்டுள்ளது.\n'
        '🔧 Model: {mobileName}\n'
        '💰 Total Amount: {amount}\n'
        '✅ Paid: {paidAmount}\n'
        '🙏 நன்றி! Thank you for choosing {shopName}.\n'
        '{shopName}',
    tokens: const [
      ('{customerName}', 'Customer name'),
      ('{mobileName}', 'Mobile/model name'),
      ('{amount}', 'Total amount'),
      ('{paidAmount}', 'Amount paid'),
      ('{billNo}', 'Bill number'),
      ('{shopName}', 'Shop name'),
      ('{complaint}', 'Problem/complaint'),
      ('{imei}', 'IMEI / Serial No'),
      ('{technician}', 'Technician name'),
      ('{deliveryPerson}', 'Delivered by'),
      ('{balance}', 'Balance still due'),
    ],
    previewSample: const {
      '{customerName}': 'Ramesh',
      '{mobileName}': 'Samsung A15',
      '{amount}': '₹1,200',
      '{paidAmount}': '₹1,200',
      '{billNo}': 'A045',
      '{shopName}': 'PROFESSIONAL MOBILES',
      '{complaint}': 'Display damage',
      '{imei}': '351234567891234',
      '{technician}': 'Kumar',
      '{deliveryPerson}': 'Suresh',
      '{balance}': '₹0',
    },
    load: (repo) => repo.getDeliveryIntimationTemplate(),
    save: (repo, text) => repo.saveDeliveryIntimationTemplate(text),
  ),
];

class _WhatsAppTemplateScreenState extends State<WhatsAppTemplateScreen> {
  final _settingsRepo = SettingsRepository();
  bool _loading = true;
  final List<TextEditingController> _ctrls = List.generate(_specs.length, (_) => TextEditingController());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (var i = 0; i < _specs.length; i++) {
      final saved = await _specs[i].load(_settingsRepo);
      _ctrls[i].text = (saved == null || saved.trim().isEmpty) ? _specs[i].defaultTemplate : saved;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(int i) async {
    await _specs[i].save(_settingsRepo, _ctrls[i].text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved - this text will be used for the next ${_specs[i].title.toLowerCase()}.')),
      );
    }
  }

  void _resetToDefault(int i) {
    setState(() => _ctrls[i].text = _specs[i].defaultTemplate);
  }

  void _insertToken(int i, String token) {
    final ctrl = _ctrls[i];
    final sel = ctrl.selection;
    final text = ctrl.text;
    final insertAt = sel.start >= 0 ? sel.start : text.length;
    final newText = text.replaceRange(insertAt, sel.end >= 0 ? sel.end : insertAt, token);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: insertAt + token.length),
    );
  }

  String _previewText(int i) {
    var preview = _ctrls[i].text;
    for (final entry in _specs[i].previewSample.entries) {
      preview = preview.replaceAll(entry.key, entry.value);
    }
    return preview;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _specs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('WhatsApp Message Templates'),
          bottom: TabBar(tabs: _specs.map((s) => Tab(text: s.title.replaceAll(' Message', ''))).toList()),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: List.generate(_specs.length, (i) => _buildTab(context, i)),
              ),
      ),
    );
  }

  Widget _buildTab(BuildContext context, int i) {
    final spec = _specs[i];
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        SectionCard(title: spec.title, icon: Icons.chat_rounded, children: [
          Text(
            '${spec.subtitle} Tap a token below to insert it - it gets replaced with the real value when the message is sent.',
            style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: spec.tokens
                .map((t) => ActionChip(
                      label: Text(t.$1),
                      tooltip: t.$2,
                      onPressed: () => _insertToken(i, t.$1),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrls[i],
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
              Expanded(child: ElevatedButton(onPressed: () => _save(i), child: const Text('Save'))),
              const SizedBox(width: 10),
              OutlinedButton(onPressed: () => _resetToDefault(i), child: const Text('Reset to Default')),
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
            child: Text(_previewText(i), style: TextStyle(color: AppColors.textPrimaryOf(context), fontSize: 13)),
          ),
        ]),
      ],
    );
  }
}
