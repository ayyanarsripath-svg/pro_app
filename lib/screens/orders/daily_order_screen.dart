import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
// Voice entry for Add/Edit Item (spec item 6 - see _DialogMicButton below).
// Same two-library split as quick_transaction_screen.dart's mic feature:
// SpeechRecognitionResult isn't re-exported by speech_to_text.dart itself.
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart' as stt;

import '../../core/repositories/daily_order_repository.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/repositories/supplier_repository.dart';
import '../../core/services/background_tasks.dart';
import '../../core/services/daily_order_auto_send_signal.dart';
import '../../core/services/daily_order_widget_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/whatsapp_sms_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/daily_order_item.dart';
import '../../models/supplier.dart';
import '../../widgets/section_card.dart';

/// Daily supplier order note - the shop notes down parts/accessories to
/// order through the day, then sends the whole list to one chosen
/// supplier over WhatsApp as a PDF, with a reminder so it never gets
/// forgotten. An item that doesn't get sent on its own day is simply
/// carried forward automatically (see DailyOrderRepository.unsentItems) -
/// it keeps showing here, still labelled with its original date, until it
/// actually goes out.
class DailyOrderScreen extends StatefulWidget {
  const DailyOrderScreen({super.key});

  @override
  State<DailyOrderScreen> createState() => _DailyOrderScreenState();
}

class _DailyOrderScreenState extends State<DailyOrderScreen> with WidgetsBindingObserver {
  final _repo = DailyOrderRepository();
  final _settingsRepo = SettingsRepository();
  final _supplierRepo = SupplierRepository();
  final _pdfService = PdfService();
  final _waService = WhatsAppSmsService();
  final _widgetService = DailyOrderWidgetService();

  bool _loading = true;
  bool _sending = false;
  List<DailyOrderItem> _allItems = [];
  String _supplierName = '';
  String _supplierPhone = '';
  String _sendTime = '12:30';
  bool _reminderEnabled = true;
  bool _widgetEnabled = true;

  // True until proven otherwise (hasExactAlarmPermission() defaults to true
  // on any check failure/non-Android platform - see its own doc comment) so
  // this never flashes a false warning while the very first check is still
  // in flight.
  bool _exactAlarmOk = true;

  // Tracks the last DailyOrderAutoSendSignal.tick value already acted on -
  // see _maybeAutoSend.
  int _lastHandledAutoSendTick = 0;

  @override
  void initState() {
    super.initState();
    _load();
    DailyOrderAutoSendSignal.tick.addListener(_maybeAutoSend);
    // Granting the exact-alarm permission (see _recheckExactAlarm and the
    // "Fix now" banner below) sends the owner out to the phone's own
    // Settings app and back - there's no callback for "they came back",
    // only this app-resumed lifecycle event, so that's when the warning
    // banner re-checks itself and clears automatically once fixed.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    DailyOrderAutoSendSignal.tick.removeListener(_maybeAutoSend);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _recheckExactAlarm();
  }

  Future<void> _recheckExactAlarm() async {
    final ok = await hasExactAlarmPermission();
    if (mounted) setState(() => _exactAlarmOk = ok);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _repo.all();
    final settings = await _settingsRepo.getAll();
    // Widget on/off lives outside SQLite/backup - see
    // DailyOrderWidgetService.isEnabled for why.
    final widgetEnabled = await _widgetService.isEnabled();
    setState(() {
      _allItems = items;
      _supplierName = settings[SettingsRepository.dailyOrderSupplierName] ?? '';
      _supplierPhone = settings[SettingsRepository.dailyOrderSupplierPhone] ?? '';
      _sendTime = settings[SettingsRepository.dailyOrderSendTime] ?? '12:30';
      _reminderEnabled = settings[SettingsRepository.dailyOrderReminderEnabled] != 'false';
      _widgetEnabled = widgetEnabled;
      _loading = false;
    });
    // See _recheckExactAlarm's doc comment - re-checked on every load (pull-
    // to-refresh, first open, settings save) as well as on app-resume, so
    // the warning banner below is never stale.
    unawaited(_recheckExactAlarm());
    // Keeps the home-screen widget in sync with whatever just changed
    // (item added/deleted/sent, or a settings save) - see
    // DailyOrderWidgetService's doc comment for why _load() is the natural
    // place for this rather than threading a refresh call through every
    // individual mutation.
    await _widgetService.refresh();
    // Re-checked here (not just via the listener registered in initState)
    // so a signal that already fired BEFORE this screen was even built -
    // e.g. AppShell jumped straight to this tab because of the same tap -
    // still gets picked up, now that _supplierPhone/_allItems have their
    // real loaded values to decide with.
    _maybeAutoSend();
  }

  /// Auto-runs the same PDF-build + open-WhatsApp-with-attachment flow the
  /// "Send Order via WhatsApp" button triggers, the moment a Daily Order
  /// reminder (either the native exact-alarm notification, or the
  /// WorkManager-polled one - see DailyOrderAutoSendSignal's doc comment)
  /// is tapped (spec: "antha time vantha piragu auto matically pdf file ahh
  /// whatsapp ku send aaganum pdf na just send button mattum press
  /// pannuvan" - the shop just wants WhatsApp already open with Send
  /// ready, one tap left for them). Guards against double-firing on the
  /// same tap (e.g. both this screen's own initState/_load and AppShell's
  /// tab-jump settling around the same signal) and against starting a send
  /// that's already in progress, has no supplier phone configured yet, or
  /// has nothing pending.
  void _maybeAutoSend() {
    if (!mounted) return;
    final tick = DailyOrderAutoSendSignal.tick.value;
    if (tick == _lastHandledAutoSendTick) return;
    _lastHandledAutoSendTick = tick;
    if (_sending || _supplierPhone.trim().isEmpty || _pending.isEmpty) return;
    _sendOrder();
  }

  List<DailyOrderItem> get _pending => _allItems.where((i) => !i.sent).toList();

  /// Groups items by date for display. A sent item that has been ticked
  /// Received is done - it's left out here entirely ("erase") rather than
  /// deleted from the database, so order history stays intact while the
  /// list the shop owner looks at only shows what's still outstanding.
  Map<String, List<DailyOrderItem>> get _groupedByDate {
    final map = <String, List<DailyOrderItem>>{};
    for (final item in _allItems) {
      if (item.sent && item.received) continue;
      map.putIfAbsent(item.orderDate, () => []).add(item);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final grouped = _groupedByDate;
    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    final pending = _pending;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _supplierCard(),
            if (_reminderEnabled && !_exactAlarmOk) ...[
              const SizedBox(height: 4),
              _exactAlarmWarningBanner(),
              const SizedBox(height: 4),
            ],
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 4),
              _pendingBanner(pending),
              const SizedBox(height: 4),
            ],
            const SizedBox(height: 6),
            if (_allItems.isEmpty)
              const EmptyState(icon: Icons.assignment_rounded, message: 'No order items yet - tap + to add one')
            else
              for (final date in dates) _dateSection(date, grouped[date]!),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Item'),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Top summary card (supplier / send time / reminder) + settings dialog
  // ---------------------------------------------------------------------

  Widget _supplierCard() {
    return SectionCard(
      title: "Today's Supplier",
      icon: Icons.local_shipping_rounded,
      trailing: IconButton(
        icon: const Icon(Icons.settings_rounded),
        tooltip: 'Daily Order Settings',
        onPressed: _openSettings,
      ),
      children: [
        if (_supplierName.isEmpty && _supplierPhone.isEmpty)
          Text(
            'No supplier set yet - tap the gear icon to choose a supplier, order send time, and reminder.',
            style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12.5),
          )
        else ...[
          Text(_supplierName.isEmpty ? '(no name set)' : _supplierName, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (_supplierPhone.isNotEmpty)
            Text(_supplierPhone, style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12.5)),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.access_time_rounded, size: 14, color: AppColors.textSecondaryOf(context)),
            const SizedBox(width: 4),
            // _sendTime is stored as 24-hour "HH:mm" (e.g. "20:09") - shown
            // here via TimeOfDay.format so it reads as a normal 12-hour
            // AM/PM time ("8:09 PM"), matching what was actually picked in
            // the settings dialog instead of the raw stored value.
            Text('Send time: ${_parseTime(_sendTime).format(context)}', style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12.5)),
            const SizedBox(width: 14),
            Icon(
              _reminderEnabled ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
              size: 14,
              color: AppColors.textSecondaryOf(context),
            ),
            const SizedBox(width: 4),
            Text(_reminderEnabled ? 'Reminder on' : 'Reminder off', style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12.5)),
          ],
        ),
      ],
    );
  }

  TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 12;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 30) : 30;
    return TimeOfDay(hour: h, minute: m);
  }

  // Starting point shown in the WhatsApp caption field when the shop hasn't
  // customized it yet - richer than the plain 'Professional Mobiles Daily
  // Order' fallback WhatsAppSmsService.dailyOrderMessage uses when the field
  // is truly empty, so the shop can see the available tokens right away
  // (spec: "more ... whatspp app message customize panra option need and
  // preview kattanum").
  static const _dailyOrderMessageDefault =
      '{shopName}\nDaily Order - {itemCount} item(s)\nDates: {dates}\nTo: {supplierName}';

  String _dailyOrderMessagePreview(String template, String supplierName) {
    var preview = template;
    preview = preview.replaceAll('{supplierName}', supplierName.isEmpty ? 'Supplier' : supplierName);
    preview = preview.replaceAll('{itemCount}', '3');
    preview = preview.replaceAll('{dates}', formatDate(DateTime.now()));
    preview = preview.replaceAll('{shopName}', 'PROFESSIONAL MOBILES');
    return preview;
  }

  /// Shown from the "Reminder not showing up?" button inside the Daily
  /// Order Settings dialog below (spec: "daily order widget problem not
  /// solved / the problem is order not send automatically to fixed time" -
  /// traced to Android/MIUI-style background restrictions silently killing
  /// the reminder trigger, not an app bug - see background_tasks.dart's
  /// checkAndNotifyIfDue wiring, which is already correct). Explains what's
  /// actually happening and gives the owner two concrete fixes: one this
  /// button can do for them directly (the standard Android battery-
  /// optimization exemption), and one that only they can do by hand (the
  /// OEM-only "Autostart" toggle Xiaomi/Vivo/Oppo/Realme phones hide
  /// outside any app's reach).
  Future<void> _showReminderTroubleshootDialog(BuildContext parentContext) async {
    await showDialog<void>(
      context: parentContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reminder Not Showing Up?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'On many phones (Xiaomi/Redmi/Poco, Vivo, Oppo, Realme especially), Android itself kills this '
                'app\'s background reminder to save battery - unless the phone is told not to. This is a phone '
                'setting, not something broken in the app. Two steps fix it:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              const Text('1. Allow background running', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 4),
              const Text(
                'Tap the button below and choose "Allow" on the popup - this tells Android not to restrict this app.',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: requestIgnoreBatteryOptimizations,
                icon: const Icon(Icons.battery_charging_full_rounded, size: 18),
                label: const Text('Allow Background Running'),
              ),
              const SizedBox(height: 16),
              const Text('1b. Allow exact-time alarms (Android 12+)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 4),
              const Text(
                'On newer phones, tap below and choose "Allow" - this lets the reminder fire at the exact minute '
                'you set instead of Android silently delaying it. Does nothing (safe to tap) on older phones that '
                "don't need this.",
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: requestExactAlarmPermission,
                icon: const Icon(Icons.alarm_rounded, size: 18),
                label: const Text('Allow Exact Alarm Timing'),
              ),
              const SizedBox(height: 16),
              const Text('2. Turn on Autostart (Xiaomi/Redmi/Poco - MIUI)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 4),
              const Text(
                'This one can only be turned on by hand - no app can switch it on for you:\n\n'
                'Settings → Apps → Manage apps → Professional Mobiles → Autostart → turn ON\n\n'
                '(or: Security app → Permissions → Autostart → find Professional Mobiles → turn ON)\n\n'
                'Also check: Settings → Battery & performance → App battery saver → Professional Mobiles → '
                'choose "No restrictions".',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              const Text('Vivo / Oppo / Realme phones', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 4),
              const Text(
                'Similar idea, different name: Settings → Battery → App background power consumption / '
                'High background power usage apps → Professional Mobiles → allow it. Also check the same '
                'Autostart-style toggle under Settings → Apps → Autostart (Vivo) or Manage → Startup manager (Oppo).',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: openAppSettings,
                  icon: const Icon(Icons.settings_applications_rounded, size: 18),
                  label: const Text("Open this app's phone settings"),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _openSettings() async {
    final nameCtrl = TextEditingController(text: _supplierName);
    final phoneCtrl = TextEditingController(text: _supplierPhone);
    final savedMessageTemplate = await _settingsRepo.getDailyOrderMessageTemplate();
    final messageCtrl = TextEditingController(
      text: (savedMessageTemplate == null || savedMessageTemplate.trim().isEmpty) ? _dailyOrderMessageDefault : savedMessageTemplate,
    );
    final pdfNoteCtrl = TextEditingController(text: await _settingsRepo.getDailyOrderPdfNote() ?? '');
    // Enter/Done on the keyboard moves focus to the next field instead of
    // just closing the keyboard (spec: field full pannittu enter azhuthina
    // aditha tabku poganum) - see the matching pattern in _addItem/_editItem.
    final nameFocus = FocusNode();
    final phoneFocus = FocusNode();
    var pickedTime = _parseTime(_sendTime);
    var reminderOn = _reminderEnabled;
    var widgetOn = _widgetEnabled;

    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Daily Order Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  focusNode: nameFocus,
                  decoration: const InputDecoration(labelText: 'Supplier Name'),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(dialogContext).requestFocus(phoneFocus),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  focusNode: phoneFocus,
                  decoration: const InputDecoration(labelText: 'Supplier Phone'),
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => FocusScope.of(dialogContext).unfocus(),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final picked = await _pickSupplier();
                        if (picked != null) {
                          nameCtrl.text = picked.name;
                          phoneCtrl.text = picked.phone ?? '';
                        }
                      },
                      icon: const Icon(Icons.local_shipping_rounded, size: 18),
                      label: const Text('Pick from Suppliers list'),
                    ),
                    // Lets the shop pick the supplier's number straight
                    // from the phone's own saved Contacts, instead of
                    // retyping it (spec: "phone number kekkutho anga
                    // contact app la erunthu choose panramathiri panni
                    // kudu ... saving contact la erunthu choose
                    // pannippan"). Uses the system contact picker
                    // (openExternalPick), which needs no extra runtime
                    // permission prompt - Android grants this app
                    // temporary access to only the one contact picked.
                    TextButton.icon(
                      onPressed: () async {
                        final picked = await _pickFromContacts(dialogContext);
                        if (picked != null) {
                          if (picked.name.isNotEmpty) nameCtrl.text = picked.name;
                          if (picked.phone.isNotEmpty) phoneCtrl.text = picked.phone;
                        }
                      },
                      icon: const Icon(Icons.contacts_rounded, size: 18),
                      label: const Text('Pick from Contacts'),
                    ),
                  ],
                ),
                const Divider(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.access_time_rounded),
                  title: const Text('Order Send Time'),
                  subtitle: Text(pickedTime.format(dialogContext)),
                  onTap: () async {
                    final t = await showTimePicker(context: dialogContext, initialTime: pickedTime);
                    if (t != null) setDialogState(() => pickedTime = t);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Daily Reminder'),
                  subtitle: const Text(
                    'Notify me at send time if an order is still pending. Note: WhatsApp cannot be sent silently by any app - '
                    'this only shows a phone notification; tapping "Send Order" still opens WhatsApp for you to tap Send.',
                  ),
                  value: reminderOn,
                  onChanged: (v) => setDialogState(() => reminderOn = v),
                ),
                if (reminderOn)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _showReminderTroubleshootDialog(dialogContext),
                        icon: const Icon(Icons.battery_alert_rounded, size: 16, color: AppColors.warning),
                        label: const Text('Reminder not showing up? Tap here', style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Home Screen Widget'),
                  subtitle: const Text("Show pending items on your phone's home screen"),
                  value: widgetOn,
                  onChanged: (v) => setDialogState(() => widgetOn = v),
                ),
                const Divider(height: 20),
                const Text('WhatsApp Message & PDF', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  'Customize the WhatsApp caption sent with the order PDF, and an optional note printed on the PDF itself. '
                  'Tokens: {supplierName} {itemCount} {dates} {shopName}',
                  style: TextStyle(color: AppColors.textSecondaryOf(dialogContext), fontSize: 11.5),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: messageCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'WhatsApp Message', border: OutlineInputBorder()),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pdfNoteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'PDF Note (optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: Text('Preview', style: TextStyle(color: AppColors.textSecondaryOf(dialogContext), fontSize: 11.5, fontWeight: FontWeight.w700))),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.bgOf(dialogContext),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderOf(dialogContext)),
                  ),
                  child: Text(
                    _dailyOrderMessagePreview(messageCtrl.text, nameCtrl.text),
                    style: TextStyle(color: AppColors.textPrimaryOf(dialogContext), fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved == true) {
      final timeStr = '${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}';
      await _settingsRepo.set(SettingsRepository.dailyOrderSupplierName, nameCtrl.text.trim());
      await _settingsRepo.set(SettingsRepository.dailyOrderSupplierPhone, phoneCtrl.text.trim());
      await _settingsRepo.set(SettingsRepository.dailyOrderSendTime, timeStr);
      await _settingsRepo.set(SettingsRepository.dailyOrderReminderEnabled, reminderOn ? 'true' : 'false');
      await _settingsRepo.saveDailyOrderMessageTemplate(messageCtrl.text.trim());
      await _settingsRepo.saveDailyOrderPdfNote(pdfNoteCtrl.text.trim());
      // Deliberately not via _settingsRepo - see DailyOrderWidgetService.setEnabled.
      await _widgetService.setEnabled(widgetOn);

      if (reminderOn) {
        // forceReset: true - this is the one place the WorkManager catch-up
        // poll genuinely needs to restart (the owner just changed the send
        // time/turned the reminder back on). See background_tasks.dart's
        // BUG FIX note on scheduleDailyOrderReminder for why every OTHER
        // caller (main.dart, on every app open) must NOT force a reset.
        await scheduleDailyOrderReminder(hour: pickedTime.hour, minute: pickedTime.minute, forceReset: true);
      } else {
        await cancelDailyOrderReminder();
      }

      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Daily order settings saved')));
      }
    }
  }

  Future<Supplier?> _pickSupplier() async {
    final suppliers = await _supplierRepo.all();
    if (!mounted) return null;
    return showDialog<Supplier>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Pick Supplier'),
        children: [
          if (suppliers.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No suppliers added yet')),
          for (final s in suppliers)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, s),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.name),
                subtitle: Text(s.phone ?? '-'),
              ),
            ),
        ],
      ),
    );
  }

  /// Opens Android's own Contacts picker UI and returns the picked
  /// contact's display name + first phone number (sanitised at send time
  /// by WhatsAppSmsService, so any formatting - spaces, dashes, +91, etc -
  /// picked straight from Contacts is fine as-is). Returns null if the
  /// shop backs out of the picker, or if the chosen contact has no phone
  /// number saved at all.
  Future<({String name, String phone})?> _pickFromContacts(BuildContext dialogContext) async {
    try {
      final contact = await FlutterContacts.openExternalPick();
      if (contact == null) return null;
      final phone = contact.phones.isNotEmpty ? contact.phones.first.number : '';
      if (phone.isEmpty) {
        if (dialogContext.mounted) {
          ScaffoldMessenger.of(dialogContext).showSnackBar(
            SnackBar(content: Text('${contact.displayName} has no phone number saved')),
          );
        }
        return null;
      }
      return (name: contact.displayName, phone: phone);
    } catch (e) {
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(content: Text('Could not open Contacts: $e')),
        );
      }
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // Pending banner + Send Order flow
  // ---------------------------------------------------------------------

  /// Always-visible warning shown right on the Daily Order screen itself
  /// (not buried inside a settings dialog) whenever the reminder is turned
  /// on but Android's exact-alarm permission is missing - the single most
  /// likely reason the reminder can silently never fire even though the
  /// send time shown in Settings looks correct and every other permission
  /// was allowed (spec: "daily order la eppo notification time ku kattuthu
  /// but alarm or reminder varala ella settings um allow kuduthuttan" -
  /// settings show the right time but the alarm never actually comes even
  /// though the owner believes everything is already allowed). One tap on
  /// "Fix now" opens the exact Settings screen for this; the banner clears
  /// itself automatically the moment the owner returns to the app with it
  /// granted - see _recheckExactAlarm/didChangeAppLifecycleState above.
  Widget _exactAlarmWarningBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Reminder may not ring on time",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'One phone permission ("Alarms & reminders") is still off, so this reminder can be delayed by Android '
            'or may not ring at all - even though the send time above is set correctly. Tap below to allow it '
            '(one screen, one tap).',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
              onPressed: requestExactAlarmPermission,
              icon: const Icon(Icons.alarm_rounded),
              label: const Text('Fix Now - Allow Exact Alarm Timing'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingBanner(List<DailyOrderItem> pending) {
    final today = isoDateFormat.format(DateTime.now());
    final carriedOver = pending.any((i) => i.orderDate != today);
    final label = carriedOver
        ? '${pending.length} item(s) not yet sent (includes items carried forward from an earlier day)'
        : '${pending.length} item(s) ready to send';

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pending_actions_rounded, color: AppColors.primaryBlue),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _sendOrder,
              icon: _sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
              label: Text(_sending ? 'Preparing...' : 'Send Order via WhatsApp'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendOrder() async {
    if (_supplierPhone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Set the supplier's phone number in Settings first (tap the gear icon above).")),
      );
      return;
    }

    final pending = _pending;
    if (pending.isEmpty) return;

    setState(() => _sending = true);
    try {
      final pdfNote = await _settingsRepo.getDailyOrderPdfNote();
      final bytes = await _pdfService.buildDailyOrderPdf(
        supplierName: _supplierName.isEmpty ? 'Supplier' : _supplierName,
        items: pending,
        note: pdfNote,
      );

      final dir = await getTemporaryDirectory();
      final fileName = 'daily_order_${isoDateFormat.format(DateTime.now())}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      final dateLabels = pending.map((i) => formatDate(DateTime.parse(i.orderDate))).toSet().toList();
      final message = await _waService.dailyOrderMessage(
        supplierName: _supplierName.isEmpty ? 'Supplier' : _supplierName,
        orderDateLabels: dateLabels,
        itemCount: pending.length,
      );

      // One-click direct-to-WhatsApp send: opens WhatsApp itself with the
      // PDF and the short caption attached together in a single share,
      // skipping Android's "choose an app" chooser (see MainActivity.kt /
      // WhatsAppSmsService.shareFileToWhatsApp). Passing the supplier's
      // phone also skips WhatsApp's OWN contact/chat picker - it opens
      // straight into their chat, ready to tap Send. Falls back to the
      // older two-step hand-off (a wa.me chat message, then a separate
      // generic file-share sheet) only if the direct share isn't
      // available - e.g. WhatsApp isn't installed.
      final sharedDirect = await _waService.shareFileToWhatsApp(filePath: file.path, text: message, phone: _supplierPhone);
      if (!sharedDirect) {
        await _waService.sendWhatsApp(phone: _supplierPhone, message: message);
        await Future.delayed(const Duration(milliseconds: 600));
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Order Sent?'),
          content: const Text(
            "WhatsApp was opened with today's order PDF. Once you've actually tapped Send inside WhatsApp, mark this order as sent so it stops showing as pending.",
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Not Yet')),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Yes, Sent')),
          ],
        ),
      );

      if (confirmed == true) {
        await _repo.markSent(pending.map((i) => i.id).toList());
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Today's order marked as sent.")));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send order: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------------------------------------------------------------------
  // Add / delete items, date-grouped list
  // ---------------------------------------------------------------------

  Future<void> _addItem() async {
    final partCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    // Pre-filled with "1" - by far the most common quantity, so the shop
    // doesn't have to type it every single time (spec: "quantity la fixed
    // number 1 nu pottu kudu, adikkadi 1 podrathu kaduppa erukku"). Tapping
    // the field selects the "1" so typing a different number just replaces
    // it instead of requiring a manual delete first - see qtyFocus listener
    // below.
    final qtyCtrl = TextEditingController(text: '1');
    final phoneCtrl = TextEditingController();
    // Enter/Done moves focus to the next field instead of just closing the
    // keyboard (spec: field full pannittu enter azhuthina aditha tabku
    // poganum). Field order is Type/Model -> Part/Accessory -> Quantity ->
    // Phone (spec: "type model mela potru kizhe parts and accessories
    // potru").
    final typeFocus = FocusNode();
    final partFocus = FocusNode();
    final qtyFocus = FocusNode();
    final phoneFocus = FocusNode();
    qtyFocus.addListener(() {
      if (qtyFocus.hasFocus) {
        qtyCtrl.selection = TextSelection(baseOffset: 0, extentOffset: qtyCtrl.text.length);
      }
    });

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Order Item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: typeCtrl,
                focusNode: typeFocus,
                decoration: InputDecoration(
                  labelText: 'Type / Model',
                  // Mic 1 of 2 (spec item 6): speak the mobile brand/model
                  // (e.g. "Samsung A14") and it fills THIS field only - see
                  // _DialogMicButton's doc comment for why two independent
                  // mic buttons instead of one that tries to split a
                  // sentence across both fields.
                  suffixIcon: _DialogMicButton(controller: typeCtrl),
                ),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(dialogContext).requestFocus(partFocus),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: partCtrl,
                focusNode: partFocus,
                decoration: InputDecoration(
                  labelText: 'Part / Accessory Name *',
                  // Mic 2 of 2: speak the part/accessory (e.g. "back cover",
                  // "temper glass") and it fills THIS field only.
                  suffixIcon: _DialogMicButton(controller: partCtrl),
                ),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(dialogContext).requestFocus(qtyFocus),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: qtyCtrl,
                focusNode: qtyFocus,
                decoration: const InputDecoration(labelText: 'Quantity *'),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(dialogContext).requestFocus(phoneFocus),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                focusNode: phoneFocus,
                decoration: InputDecoration(
                  labelText: 'Phone (optional - for your own reference, tap to call)',
                  // Lets the shop call the supplier/customer about this
                  // item right away, straight from this dialog, instead of
                  // having to save first and find it in the list below to
                  // reach the same call button there (spec: "add order
                  // item la once phone number note pannathukku aprom call
                  // panra option ella"). Only meaningful once a number has
                  // actually been typed.
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.call_rounded),
                    tooltip: 'Call this number',
                    onPressed: () {
                      final phone = phoneCtrl.text.trim();
                      if (phone.isNotEmpty) _callPhone(phone);
                    },
                  ),
                ),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => FocusScope.of(dialogContext).unfocus(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Add')),
        ],
      ),
    );

    if (ok == true && partCtrl.text.trim().isNotEmpty && qtyCtrl.text.trim().isNotEmpty) {
      final today = isoDateFormat.format(DateTime.now());
      await _repo.create(
        orderDate: today,
        partName: partCtrl.text.trim(),
        typeModel: typeCtrl.text.trim().isEmpty ? null : typeCtrl.text.trim(),
        quantity: qtyCtrl.text.trim(),
        phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
      );
      await _load();
    }
  }

  Future<void> _editItem(DailyOrderItem item) async {
    final partCtrl = TextEditingController(text: item.partName);
    final typeCtrl = TextEditingController(text: item.typeModel ?? '');
    final qtyCtrl = TextEditingController(text: item.quantity);
    final phoneCtrl = TextEditingController(text: item.phone ?? '');
    // Enter/Done moves focus to the next field instead of just closing the
    // keyboard (spec: field full pannittu enter azhuthina aditha tabku
    // poganum). Field order matches _addItem: Type/Model -> Part/Accessory
    // -> Quantity -> Phone.
    final typeFocus = FocusNode();
    final partFocus = FocusNode();
    final qtyFocus = FocusNode();
    final phoneFocus = FocusNode();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Order Item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: typeCtrl,
                focusNode: typeFocus,
                decoration: InputDecoration(
                  labelText: 'Type / Model',
                  // Mic 1 of 2 (spec item 6): speak the mobile brand/model
                  // (e.g. "Samsung A14") and it fills THIS field only - see
                  // _DialogMicButton's doc comment for why two independent
                  // mic buttons instead of one that tries to split a
                  // sentence across both fields.
                  suffixIcon: _DialogMicButton(controller: typeCtrl),
                ),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(dialogContext).requestFocus(partFocus),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: partCtrl,
                focusNode: partFocus,
                decoration: InputDecoration(
                  labelText: 'Part / Accessory Name *',
                  // Mic 2 of 2: speak the part/accessory (e.g. "back cover",
                  // "temper glass") and it fills THIS field only.
                  suffixIcon: _DialogMicButton(controller: partCtrl),
                ),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(dialogContext).requestFocus(qtyFocus),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: qtyCtrl,
                focusNode: qtyFocus,
                decoration: const InputDecoration(labelText: 'Quantity *'),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(dialogContext).requestFocus(phoneFocus),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                focusNode: phoneFocus,
                decoration: InputDecoration(
                  labelText: 'Phone (optional - for your own reference, tap to call)',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.call_rounded),
                    tooltip: 'Call this number',
                    onPressed: () {
                      final phone = phoneCtrl.text.trim();
                      if (phone.isNotEmpty) _callPhone(phone);
                    },
                  ),
                ),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => FocusScope.of(dialogContext).unfocus(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok == true && partCtrl.text.trim().isNotEmpty && qtyCtrl.text.trim().isNotEmpty) {
      final updated = DailyOrderItem(
        id: item.id,
        orderDate: item.orderDate,
        sNo: item.sNo,
        partName: partCtrl.text.trim(),
        typeModel: typeCtrl.text.trim().isEmpty ? null : typeCtrl.text.trim(),
        quantity: qtyCtrl.text.trim(),
        phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
        sent: item.sent,
        sentAt: item.sentAt,
        createdAt: item.createdAt,
      );
      await _repo.update(updated);
      await _load();
    }
  }

  Future<void> _deleteItem(DailyOrderItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Item?'),
        content: Text('Remove "${item.partName}" from the order note?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await _repo.delete(item.id);
      await _load();
    }
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  Widget _dateSection(String date, List<DailyOrderItem> items) {
    final allSent = items.every((i) => i.sent);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(Icons.event_note_rounded, size: 16, color: AppColors.primaryBlue),
                const SizedBox(width: 6),
                Text(formatDate(DateTime.parse(date)), style: const TextStyle(fontWeight: FontWeight.w800)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: allSent ? AppColors.success.withOpacity(0.15) : AppColors.warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    allSent ? 'Sent' : 'Pending',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: allSent ? AppColors.success : AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final item in items) _itemRow(item),
        ],
      ),
    );
  }

  Widget _itemRow(DailyOrderItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 24, child: Text('${item.sNo}', style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.partName, style: const TextStyle(fontWeight: FontWeight.w600)),
                if ((item.typeModel ?? '').isNotEmpty)
                  Text(item.typeModel!, style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context))),
                Text('Qty: ${item.quantity}', style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context))),
              ],
            ),
          ),
          if ((item.phone ?? '').isNotEmpty)
            IconButton(
              icon: const Icon(Icons.call_rounded, size: 20, color: AppColors.primaryBlue),
              tooltip: item.phone,
              onPressed: () => _callPhone(item.phone!),
            ),
          if (!item.sent)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.primaryBlue),
              onPressed: () => _editItem(item),
            ),
          if (!item.sent)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.danger),
              onPressed: () => _deleteItem(item),
            ),
          // Sent items still need a receipt-status decision from the shop
          // owner: some ordered parts arrive, some don't. Received hides
          // the row (handled in _groupedByDate); Not Received is just an
          // acknowledgement and deliberately leaves the row exactly as-is
          // so the order keeps showing as outstanding.
          if (item.sent && !item.received) ...[
            IconButton(
              icon: const Icon(Icons.check_circle_outline_rounded, size: 20, color: AppColors.success),
              tooltip: 'Received',
              onPressed: () => _markReceived(item),
            ),
            IconButton(
              icon: const Icon(Icons.cancel_outlined, size: 20, color: AppColors.warning),
              tooltip: 'Not Received',
              onPressed: () => _markNotReceived(item),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _markReceived(DailyOrderItem item) async {
    await _repo.markReceived(item.id);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.partName} marked received')),
    );
  }

  /// Not Received (spec: "yellow x round touch panna thirumba order note ku
  /// antha particular order poganum" - tapping the yellow icon must actually
  /// send that item back to the order note). Used to just show a toast and
  /// leave the row exactly as-is; now it really resets the item back to
  /// "not yet sent" (DailyOrderRepository.resetToPending), so it reappears
  /// as a normal pending order-note row and gets swept into the next Send
  /// Order batch automatically, instead of sitting there sent-but-unreceived
  /// forever.
  Future<void> _markNotReceived(DailyOrderItem item) async {
    await _repo.resetToPending(item.id);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.partName} sent back to order note')),
    );
  }
}

/// One mic button wired to exactly one text field (spec item 6: "daily
/// order la mic add pannu atha thottu mobile brand name sonna type / model
/// la enter aaganum parts ... sonna part / accessories name la enter
/// aaganum ... etha optimization panni konjam theliva pannu" - add voice
/// entry to the Add Item screen, and figure out the clearest way to split
/// it across the Type/Model and Part/Accessories fields).
///
/// DESIGN CHOICE: two of these (one per field) instead of one mic button
/// that tries to guess where a single spoken sentence splits between brand
/// and part. Quick Income/Expense's mic (quick_transaction_screen.dart) can
/// get away with one button because it only ever has to pull one number out
/// of the sentence; here there is no reliable marker separating "Samsung
/// A14" from "back cover" in free speech ("samsung a14 back cover" could
/// just as easily be "samsung a14 back" + "cover"). A dedicated mic per
/// field means whatever was heard becomes that field's value, in full - no
/// guessing, so it's always right, at the small cost of one extra tap when
/// both fields need to be spoken. Quantity (already pre-filled "1") and
/// Phone (meant to stay blank) are deliberately left without a mic - spec
/// explicitly says leave them at their defaults.
///
/// A real StatefulWidget (not just a plain IconButton built inline) so it
/// gets its own mic-icon/listening state without having to thread a second
/// setState through the AlertDialog's builder - showDialog's content is a
/// normal mounted widget subtree, so this manages itself exactly like any
/// other stateful widget would.
class _DialogMicButton extends StatefulWidget {
  final TextEditingController controller;
  const _DialogMicButton({required this.controller});

  @override
  State<_DialogMicButton> createState() => _DialogMicButtonState();
}

class _DialogMicButtonState extends State<_DialogMicButton> {
  final _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _listening = false;

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    if (!_speechAvailable) {
      final ok = await _speech.initialize(
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
      );
      if (!mounted) return;
      setState(() => _speechAvailable = ok);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Mic not available - check microphone permission in phone Settings'),
        ));
        return;
      }
    }

    setState(() => _listening = true);
    await _speech.listen(onResult: (result) {
      final heard = result.recognizedWords.trim();
      if (heard.isEmpty) return;
      // Whatever's heard becomes this field's whole value - no parsing, see
      // this class's doc comment for why.
      widget.controller.text = heard;
      if (result.finalResult && mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
        color: _listening ? AppColors.primaryBlue : null,
      ),
      tooltip: _listening ? 'Listening... tap to stop' : 'Speak instead of typing',
      onPressed: _toggle,
    );
  }
}
