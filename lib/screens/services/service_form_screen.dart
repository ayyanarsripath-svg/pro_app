import 'package:flutter/material.dart';

import '../../core/repositories/customer_repository.dart';
import '../../core/repositories/service_repository.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/services/whatsapp_sms_service.dart';
import '../../core/utils/formatters.dart';
import '../../models/customer.dart';
import '../../widgets/section_card.dart';

/// Intake screen for a new repair job - creates the customer (or reuses an
/// existing one by phone) and the service job card in one flow.
class ServiceFormScreen extends StatefulWidget {
    const ServiceFormScreen({super.key});

    @override
    State<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends State<ServiceFormScreen> {
    final _formKey = GlobalKey<FormState>();
    final _customerRepo = CustomerRepository();
    final _serviceRepo = ServiceRepository();
    final _settingsRepo = SettingsRepository();
    final _waService = WhatsAppSmsService();

    final _customerNameCtrl = TextEditingController();
    final _customerPhoneCtrl = TextEditingController();
    final _mobileNameCtrl = TextEditingController();
    final _modelCtrl = TextEditingController();
    final _imeiCtrl = TextEditingController();
    final _complaintCtrl = TextEditingController();
    final _conditionCtrl = TextEditingController();
    final _damageCtrl = TextEditingController();
    final _accOtherCtrl = TextEditingController();
    final _technicianCtrl = TextEditingController();
    final _estimatedCtrl = TextEditingController();
    final _advanceCtrl = TextEditingController(text: '0');
    final _discountCtrl = TextEditingController();
    final _warrantyPeriodCtrl = TextEditingController();
    final Map<String, TextEditingController> _faultAmountCtrls = {};

    bool _charger = false, _cable = false, _sim = false, _memoryCard = false;
    bool _warranty = false;
    // IMEI (mobile, numeric keypad) vs Serial No (laptop/other devices,
    // mixes letters e.g. "WES/1234" -> normal keyboard).
    bool _imeiIsSerial = false;
    DateTime? _expectedDate;
    Customer? _existingCustomer;
    bool _saving = false;

    List<String> _presets = [];
    final Set<String> _selectedPresets = {};

    List<String> _conditionPresets = [];
    final Set<String> _selectedConditions = {};
    List<String> _damagePresets = [];
    final Set<String> _selectedDamages = {};

    @override
    void initState() {
        super.initState();
        _loadPresets();
    }

    Future<void> _loadPresets() async {
        final presets = await _settingsRepo.getComplaintPresets();
        final conditions = await _settingsRepo.getConditionPresets();
        final damages = await _settingsRepo.getDamagePresets();
        if (mounted) {
            setState(() {
                _presets = presets;
                _conditionPresets = conditions;
                _damagePresets = damages;
            });
        }
    }

    /// Quick-pic chip toggle for Device Condition - single state at a time
    /// (a device is "Dead" OR "Hang on Logo" OR ..., not several at once),
    /// so picking a new one replaces whatever was selected before, and keeps
    /// the free-text field in sync so the shop can still type instead.
    void _toggleCondition(String preset) {
        setState(() {
            if (_selectedConditions.contains(preset)) {
                _selectedConditions.clear();
            } else {
                _selectedConditions
                    ..clear()
                    ..add(preset);
            }
            _conditionCtrl.text = _selectedConditions.join(' + ');
        });
    }

    /// Quick-pic chip toggle for Existing Damage - multi-select (a device
    /// can have more than one kind of physical damage at once), joined into
    /// the free-text field the same way complaint presets are.
    void _toggleDamage(String preset) {
        setState(() {
            if (_selectedDamages.contains(preset)) {
                _selectedDamages.remove(preset);
            } else {
                _selectedDamages.add(preset);
            }
            _damageCtrl.text = _selectedDamages.join(' + ');
        });
    }

    Future<void> _addCustomConditionPreset() async {
        final ctrl = TextEditingController();
        final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                title: const Text('Add Condition Preset'),
                content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Preset text (e.g. Dead)')),
                actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
                    ],
                ),
            );
        if (ok == true && ctrl.text.trim().isNotEmpty) {
            final text = ctrl.text.trim();
            if (!_conditionPresets.contains(text)) {
                setState(() => _conditionPresets = [..._conditionPresets, text]);
                await _settingsRepo.saveConditionPresets(_conditionPresets);
            }
            _toggleCondition(text);
        }
    }

    Future<void> _addCustomDamagePreset() async {
        final ctrl = TextEditingController();
        final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                title: const Text('Add Damage Preset'),
                content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Preset text (e.g. Dent)')),
                actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
                    ],
                ),
            );
        if (ok == true && ctrl.text.trim().isNotEmpty) {
            final text = ctrl.text.trim();
            if (!_damagePresets.contains(text)) {
                setState(() => _damagePresets = [..._damagePresets, text]);
                await _settingsRepo.saveDamagePresets(_damagePresets);
            }
            _toggleDamage(text);
        }
    }

    /// Toggles a quick-pick complaint chip on/off and keeps the free-text
    /// Fault / Complaint field in sync as "Preset1 + Preset2" (spec: "+" to
    /// add more) so the shop can either tap chips or type freely. Also
    /// manages a per-preset amount controller so the shop can key in what
    /// each fault costs when 2+ faults are picked (spec: breakdown like
    /// "Display 1200 + Battery 850 + Button 200" on the printed bill).
    void _togglePreset(String preset) {
        setState(() {
            if (_selectedPresets.contains(preset)) {
                _selectedPresets.remove(preset);
                _faultAmountCtrls.remove(preset)?.dispose();
            } else {
                _selectedPresets.add(preset);
                _faultAmountCtrls[preset] = TextEditingController();
            }
            _complaintCtrl.text = _selectedPresets.join(' + ');
            _recalcEstimatedFromFaults();
        });
    }

    /// Sums the per-fault amounts entered below (shown once 2+ complaint
    /// presets are selected) into the Estimated Amount field, so the shop
    /// doesn't have to add them up by hand - e.g. Display 1200 + Battery 850
    /// auto-fills Estimated Amount as 2050.
    void _recalcEstimatedFromFaults() {
        if (_selectedPresets.length < 2) return;
        double sum = 0;
        for (final preset in _selectedPresets) {
            sum += double.tryParse(_faultAmountCtrls[preset]?.text.trim() ?? '') ?? 0;
        }
        _estimatedCtrl.text = sum == sum.roundToDouble() ? sum.toStringAsFixed(0) : sum.toStringAsFixed(2);
    }

    /// Lets the shop add their own complaint preset to the quick-pick list -
    /// saved to settings so it's available on every future job card, not
    /// just this one.
    Future<void> _addCustomPreset() async {
        final ctrl = TextEditingController();
        final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                title: const Text('Add Complaint Preset'),
                content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Preset text (e.g. Display)')),
                actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
                    ],
                ),
            );
        if (ok == true && ctrl.text.trim().isNotEmpty) {
            final text = ctrl.text.trim();
            if (!_presets.contains(text)) {
                setState(() => _presets = [..._presets, text]);
                await _settingsRepo.saveComplaintPresets(_presets);
            }
            _togglePreset(text);
        }
    }

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            appBar: AppBar(title: const Text('New Service Job')),
            body: Form(
                key: _formKey,
                child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                        SectionCard(title: 'Customer', icon: Icons.person_rounded, children: [
                            TextFormField(
                                controller: _customerPhoneCtrl,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(labelText: 'Phone Number'),
                                onChanged: (v) async {
                                    if (v.trim().length >= 10) {
                                        final results = await _customerRepo.search(v.trim());
                                        final exact = results.where((c) => c.phone == v.trim()).toList();
                                        if (exact.isNotEmpty) {
                                            setState(() {
                                                _existingCustomer = exact.first;
                                                _customerNameCtrl.text = exact.first.name;
                                            });
                                        }
                                    }
                                },
                                ),
                            const SizedBox(height: 10),
                            TextFormField(
                                controller: _customerNameCtrl,
                                decoration: const InputDecoration(labelText: 'Customer Name'),
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                                ),
                            if (_existingCustomer != null)
                            const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text('Existing customer found - will link to their history.',
                                            style: TextStyle(fontSize: 11.5, color: Colors.green)),
                                ),
                            ]),
                        SectionCard(title: 'Device', icon: Icons.smartphone_rounded, children: [
                            TextFormField(controller: _mobileNameCtrl, decoration: const InputDecoration(labelText: 'Mobile Name (e.g. Samsung A15)')),
                            const SizedBox(height: 10),
                            TextFormField(controller: _modelCtrl, decoration: const InputDecoration(labelText: 'Model')),
                            const SizedBox(height: 10),
                            SegmentedButton<bool>(
                                segments: const [
                                    ButtonSegment(value: false, label: Text('IMEI')),
                                    ButtonSegment(value: true, label: Text('Serial No')),
                                    ],
                                selected: {_imeiIsSerial},
                                onSelectionChanged: (s) => setState(() => _imeiIsSerial = s.first),
                                ),
                            const SizedBox(height: 10),
                            TextFormField(
                                controller: _imeiCtrl,
                                keyboardType: _imeiIsSerial ? TextInputType.text : TextInputType.number,
                                decoration: InputDecoration(labelText: _imeiIsSerial ? 'Serial No' : 'IMEI'),
                                ),
                            ]),
                        SectionCard(title: 'Complaint', icon: Icons.report_problem_rounded, children: [
                            Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                    for (final preset in _presets)
                                    FilterChip(
                                        label: Text(preset),
                                        selected: _selectedPresets.contains(preset),
                                        onSelected: (_) => _togglePreset(preset),
                                        ),
                                    ActionChip(
                                        avatar: const Icon(Icons.add, size: 16),
                                        label: const Text('Add'),
                                        onPressed: _addCustomPreset,
                                        ),
                                    ],
                                ),
                            const SizedBox(height: 10),
                            TextFormField(controller: _complaintCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Fault / Complaint')),
                            if (_selectedPresets.length >= 2) ...[
                                const SizedBox(height: 12),
                                const Text('Amount per fault', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                for (final preset in _selectedPresets)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: TextFormField(
                                        controller: _faultAmountCtrls[preset],
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(labelText: '$preset Amount (₹)'),
                                        onChanged: (_) => setState(_recalcEstimatedFromFaults),
                                        ),
                                    ),
                                ],
                            ]),
                        SectionCard(title: 'Condition', icon: Icons.fact_check_rounded, children: [
                            Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                    for (final preset in _conditionPresets)
                                    FilterChip(
                                        label: Text(preset),
                                        selected: _selectedConditions.contains(preset),
                                        onSelected: (_) => _toggleCondition(preset),
                                        ),
                                    ActionChip(
                                        avatar: const Icon(Icons.add, size: 16),
                                        label: const Text('Add More'),
                                        onPressed: _addCustomConditionPreset,
                                        ),
                                    ],
                                ),
                            const SizedBox(height: 10),
                            TextFormField(controller: _conditionCtrl, decoration: const InputDecoration(labelText: 'Device Condition')),
                            const SizedBox(height: 14),
                            Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                    for (final preset in _damagePresets)
                                    FilterChip(
                                        label: Text(preset),
                                        selected: _selectedDamages.contains(preset),
                                        onSelected: (_) => _toggleDamage(preset),
                                        ),
                                    ActionChip(
                                        avatar: const Icon(Icons.add, size: 16),
                                        label: const Text('Add More'),
                                        onPressed: _addCustomDamagePreset,
                                        ),
                                    ],
                                ),
                            const SizedBox(height: 10),
                            TextFormField(controller: _damageCtrl, decoration: const InputDecoration(labelText: 'Existing Damage')),
                            ]),
                        SectionCard(title: 'Accessories Received', icon: Icons.cable_rounded, children: [
                            Wrap(
                                spacing: 4,
                                children: [
                                    FilterChip(label: const Text('Charger'), selected: _charger, onSelected: (v) => setState(() => _charger = v)),
                                    FilterChip(label: const Text('Cable'), selected: _cable, onSelected: (v) => setState(() => _cable = v)),
                                    FilterChip(label: const Text('SIM'), selected: _sim, onSelected: (v) => setState(() => _sim = v)),
                                    FilterChip(label: const Text('Memory Card'), selected: _memoryCard, onSelected: (v) => setState(() => _memoryCard = v)),
                                    ],
                                ),
                            const SizedBox(height: 10),
                            TextFormField(controller: _accOtherCtrl, decoration: const InputDecoration(labelText: 'Other')),
                            ]),
                        SectionCard(title: 'Repair', icon: Icons.handyman_rounded, children: [
                            TextFormField(controller: _technicianCtrl, decoration: const InputDecoration(labelText: 'Technician')),
                            ]),
                        SectionCard(title: 'Warranty', icon: Icons.verified_user_rounded, children: [
                            SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Warranty'),
                                value: _warranty,
                                onChanged: (v) => setState(() => _warranty = v),
                                ),
                            if (_warranty)
                            TextFormField(
                                controller: _warrantyPeriodCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Warranty Period (in days)'),
                                ),
                            ]),
                        SectionCard(title: 'Payment', icon: Icons.payments_rounded, children: [
                            TextFormField(
                                controller: _estimatedCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Estimated Amount (₹)'),
                                ),
                            const SizedBox(height: 10),
                            TextFormField(
                                controller: _advanceCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Advance Paid (₹)'),
                                ),
                            const SizedBox(height: 10),
                            // Bargained-off amount - only printed on the bill when
                            // non-zero (see PdfService._serviceAmountSummary).
                            TextFormField(
                                controller: _discountCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Discount (₹) - leave blank if none'),
                                ),
                            ]),
                        SectionCard(title: 'Delivery', icon: Icons.local_shipping_rounded, children: [
                            ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(_expectedDate == null ? 'Expected Delivery Date' : formatDate(_expectedDate!)),
                                trailing: const Icon(Icons.calendar_month_rounded),
                                onTap: () async {
                                    final picked = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now().add(const Duration(days: 2)),
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime.now().add(const Duration(days: 365)),
                                        );
                                    if (picked != null) setState(() => _expectedDate = picked);
                                },
                                ),
                            ]),
                        const SizedBox(height: 10),
                        ElevatedButton(
                            onPressed: _saving ? null : _submit,
                            child: _saving
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Create Service Job Card'),
                            ),
                        const SizedBox(height: 30),
                        ],
                    ),
                ),
            );
    }

    Future<void> _submit() async {
        if (!_formKey.currentState!.validate()) return;
        setState(() => _saving = true);

        final customer = await _customerRepo.findOrCreateByPhone(
            name: _customerNameCtrl.text.trim(),
            phone: _customerPhoneCtrl.text.trim(),
            );

        String? faultAmounts;
        if (_selectedPresets.length >= 2) {
            final parts = <String>[];
            for (final preset in _selectedPresets) {
                final amt = double.tryParse(_faultAmountCtrls[preset]?.text.trim() ?? '') ?? 0;
                parts.add('$preset:$amt');
            }
            faultAmounts = parts.join('|');
        }

        final service = await _serviceRepo.create(
            customerId: customer.id,
            mobileName: _mobileNameCtrl.text.trim(),
            model: _modelCtrl.text.trim(),
            imei: _imeiCtrl.text.trim(),
            complaint: _complaintCtrl.text.trim(),
            deviceCondition: _conditionCtrl.text.trim(),
            existingDamage: _damageCtrl.text.trim(),
            accCharger: _charger,
            accCable: _cable,
            accSim: _sim,
            accMemoryCard: _memoryCard,
            accOther: _accOtherCtrl.text.trim(),
            technician: _technicianCtrl.text.trim(),
            warranty: _warranty,
            warrantyPeriod: _warrantyPeriodCtrl.text.trim(),
            estimatedAmount: double.tryParse(_estimatedCtrl.text.trim()) ?? 0,
            advance: double.tryParse(_advanceCtrl.text.trim()) ?? 0,
            discount: double.tryParse(_discountCtrl.text.trim()) ?? 0,
            expectedDate: _expectedDate,
            faultAmounts: faultAmounts,
            );

        // Auto-send the job-card intimation the moment the job is created, via
        // both WhatsApp (wa.me link) and SMS (sms: URI) - both just open the
        // phone's own app with the message pre-filled and need one tap to send,
        // so no API key or Android SMS permission is ever needed. Failures here
        // should never block saving the job card.
        if (customer.phone != null && customer.phone!.trim().isNotEmpty) {
            final message = await _waService.serviceIntimationMessage(
                customerName: customer.name,
                customerPhone: customer.phone!,
                mobileModel: _modelCtrl.text.trim().isNotEmpty ? _modelCtrl.text.trim() : _mobileNameCtrl.text.trim(),
                imei: _imeiCtrl.text.trim(),
                complaint: _complaintCtrl.text.trim(),
                serviceCharge: double.tryParse(_estimatedCtrl.text.trim()) ?? 0,
                status: service.status,
                receivedDate: service.createdAt,
                expectedDelivery: _expectedDate,
                );
            try {
                await _waService.sendWhatsApp(phone: customer.phone!, message: message);
            } catch (_) {
                // Ignore - WhatsApp app may be unavailable; the job card is still saved.
            }
            try {
                await _waService.sendSms(phone: customer.phone!, message: message);
            } catch (_) {
                // Ignore - SMS app may be unavailable; the job card is still saved.
            }
        }

        if (mounted) Navigator.pop(context, true);
    }
}
