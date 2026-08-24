import 'package:flutter/material.dart';

import '../../core/repositories/reorder_repository.dart';
import '../../core/repositories/supplier_repository.dart';
import '../../core/services/reorder_scheduler_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/supplier.dart';
import '../../widgets/section_card.dart';

/// The "widget" step of the daily-order flow: quick-note what to order,
/// pick/enter the supplier, set the time it should go out. Saving here both
/// writes the order and arms its reminder in one step.
class QuickOrderScreen extends StatefulWidget {
  const QuickOrderScreen({super.key});

  @override
  State<QuickOrderScreen> createState() => _QuickOrderScreenState();
}

class _QuickOrderScreenState extends State<QuickOrderScreen> {
  final _supplierRepo = SupplierRepository();
  final _reorderRepo = ReorderRepository();
  final _scheduler = ReorderSchedulerService();

  final _noteCtrl = TextEditingController();
  final _supplierNameCtrl = TextEditingController();
  final _supplierPhoneCtrl = TextEditingController();

  List<Supplier> _suppliers = [];
  Supplier? _selectedSupplier;
  TimeOfDay _time = TimeOfDay.now();
  bool _repeatDaily = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    final list = await _supplierRepo.all();
    if (mounted) setState(() => _suppliers = list);
  }

  /// Rolls forward to tomorrow if the picked time already passed today, so
  /// the value we save always matches the instant ReorderSchedulerService
  /// actually arms - otherwise a task created for an earlier time-of-day
  /// would show as "already due" the moment the list screen's catch-up
  /// check runs, even though its real alarm correctly fires tomorrow.
  DateTime get _scheduledAt {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, _time.hour, _time.minute);
    if (target.isBefore(now)) target = target.add(const Duration(days: 1));
    return target;
  }

  bool get _willSendTomorrow {
    final now = DateTime.now();
    final todayAtPickedTime = DateTime(now.year, now.month, now.day, _time.hour, _time.minute);
    return todayAtPickedTime.isBefore(now);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quick Order')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          SectionCard(title: 'What to order', icon: Icons.edit_note_rounded, children: [
            TextField(
              controller: _noteCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'e.g. 5x display Redmi Note 10, 10x charging port pin, 20x tempered glass',
              ),
            ),
          ]),
          SectionCard(title: 'Supplier', icon: Icons.store_rounded, children: [
            if (_suppliers.isNotEmpty) ...[
              DropdownButtonFormField<Supplier>(
                value: _selectedSupplier,
                isExpanded: true,
                hint: const Text('Pick a saved supplier (optional)'),
                items: _suppliers
                    .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                    .toList(),
                onChanged: (s) {
                  setState(() {
                    _selectedSupplier = s;
                    if (s != null) {
                      _supplierNameCtrl.text = s.name;
                      _supplierPhoneCtrl.text = s.phone ?? '';
                    }
                  });
                },
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _supplierNameCtrl,
              decoration: const InputDecoration(labelText: 'Supplier Name'),
              onChanged: (_) => setState(() => _selectedSupplier = null),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _supplierPhoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Supplier WhatsApp Number'),
              onChanged: (_) => setState(() => _selectedSupplier = null),
            ),
          ]),
          SectionCard(title: 'Send Time', icon: Icons.alarm_rounded, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time_rounded, color: AppColors.primaryBlue),
              title: Text(_time.format(context), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              subtitle: Text(
                _willSendTomorrow ? 'Will send tomorrow at this time' : 'Will send today at this time',
              ),
              trailing: OutlinedButton(onPressed: _pickTime, child: const Text('Change')),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _repeatDaily,
              onChanged: (v) => setState(() => _repeatDaily = v),
              title: const Text('Repeat every day at this time'),
              subtitle: const Text('Off = sends once, on this date only'),
            ),
          ]),
          const SizedBox(height: 8),
          const Text(
            'At the set time you\'ll get a reminder notification. Tap it and the order PDF + WhatsApp will be ready - you just tap Send.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.alarm_add_rounded),
            label: Text(_saving ? 'Saving...' : 'Save & Set Reminder'),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (_noteCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter what to order')));
      return;
    }
    if (_supplierNameCtrl.text.trim().isEmpty || _supplierPhoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter supplier name and phone number')));
      return;
    }

    setState(() => _saving = true);

    final granted = await _scheduler.ensurePermissions();

    final task = await _reorderRepo.create(
      note: _noteCtrl.text.trim(),
      supplierId: _selectedSupplier?.id,
      supplierName: _supplierNameCtrl.text.trim(),
      supplierPhone: _supplierPhoneCtrl.text.trim(),
      scheduledAt: _scheduledAt,
      repeatDaily: _repeatDaily,
    );
    await _scheduler.schedule(task);

    if (!mounted) return;
    setState(() => _saving = false);

    if (!granted) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reminder permission needed'),
          content: const Text(
            'To fire at the exact time even when the app is closed, please allow "Alarms & reminders" and "Notifications" for this app in Android Settings, then reopen the app. The order has been saved and will still send once permission is granted.',
          ),
          actions: [ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    }

    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order set for ${formatDateTime(task.scheduledAt)}')),
      );
    }
  }
}
