import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/repositories/daily_order_repository.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/repositories/supplier_repository.dart';
import '../../core/services/background_tasks.dart';
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

class _DailyOrderScreenState extends State<DailyOrderScreen> {
  final _repo = DailyOrderRepository();
  final _settingsRepo = SettingsRepository();
  final _supplierRepo = SupplierRepository();
  final _pdfService = PdfService();
  final _waService = WhatsAppSmsService();

  bool _loading = true;
  bool _sending = false;
  List<DailyOrderItem> _allItems = [];
  String _supplierName = '';
  String _supplierPhone = '';
  String _sendTime = '12:30';
  bool _reminderEnabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _repo.all();
    final settings = await _settingsRepo.getAll();
    setState(() {
      _allItems = items;
      _supplierName = settings[SettingsRepository.dailyOrderSupplierName] ?? '';
      _supplierPhone = settings[SettingsRepository.dailyOrderSupplierPhone] ?? '';
      _sendTime = settings[SettingsRepository.dailyOrderSendTime] ?? '12:30';
      _reminderEnabled = settings[SettingsRepository.dailyOrderReminderEnabled] != 'false';
      _loading = false;
    });
  }

  List<DailyOrderItem> get _pending => _allItems.where((i) => !i.sent).toList();

  Map<String, List<DailyOrderItem>> get _groupedByDate {
    final map = <String, List<DailyOrderItem>>{};
    for (final item in _allItems) {
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
            Text('Send time: $_sendTime', style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12.5)),
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

  Future<void> _openSettings() async {
    final nameCtrl = TextEditingController(text: _supplierName);
    final phoneCtrl = TextEditingController(text: _supplierPhone);
    var pickedTime = _parseTime(_sendTime);
    var reminderOn = _reminderEnabled;

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
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Supplier Name')),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Supplier Phone'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
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
                  subtitle: const Text('Notify me at send time if an order is still pending'),
                  value: reminderOn,
                  onChanged: (v) => setDialogState(() => reminderOn = v),
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

      if (reminderOn) {
        await scheduleDailyOrderReminder(hour: pickedTime.hour, minute: pickedTime.minute);
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

  // ---------------------------------------------------------------------
  // Pending banner + Send Order flow
  // ---------------------------------------------------------------------

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
      final bytes = await _pdfService.buildDailyOrderPdf(
        supplierName: _supplierName.isEmpty ? 'Supplier' : _supplierName,
        items: pending,
      );

      final dir = await getTemporaryDirectory();
      final fileName = 'daily_order_${isoDateFormat.format(DateTime.now())}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      final dateLabels = pending.map((i) => formatDate(DateTime.parse(i.orderDate))).toSet().toList();
      final message = _waService.dailyOrderMessage(
        supplierName: _supplierName.isEmpty ? 'Supplier' : _supplierName,
        orderDateLabels: dateLabels,
        itemCount: pending.length,
      );

      // Two separate hand-offs to Android, one right after the other - a
      // wa.me link can pre-fill chat text but can't carry a file
      // attachment, so the itemised PDF has to go out as a second share
      // step (see whatsapp_sms_service.dart's dailyOrderMessage comment).
      await _waService.sendWhatsApp(phone: _supplierPhone, message: message);
      await Future.delayed(const Duration(milliseconds: 600));
      await Printing.sharePdf(bytes: bytes, filename: fileName);

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Order Sent?'),
          content: const Text(
            "WhatsApp was opened with today's order message, and the PDF share sheet was shown. Once you've actually tapped Send inside WhatsApp, mark this order as sent so it stops showing as pending.",
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
    final qtyCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Order Item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: partCtrl, decoration: const InputDecoration(labelText: 'Part / Accessory Name *')),
              const SizedBox(height: 10),
              TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: 'Type / Model')),
              const SizedBox(height: 10),
              TextField(controller: qtyCtrl, decoration: const InputDecoration(labelText: 'Quantity *')),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone (optional - for your own reference, tap to call)'),
                keyboardType: TextInputType.phone,
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
                    color: allSent ? Colors.green.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    allSent ? 'Sent' : 'Pending',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: allSent ? Colors.green[800] : Colors.orange[800],
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
              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.danger),
              onPressed: () => _deleteItem(item),
            ),
        ],
      ),
    );
  }
}
