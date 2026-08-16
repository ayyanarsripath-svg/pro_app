import 'package:flutter/material.dart';

import '../../core/repositories/customer_repository.dart';
import '../../core/repositories/service_repository.dart';
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
  final _warrantyPeriodCtrl = TextEditingController();

  bool _charger = false, _cable = false, _sim = false, _memoryCard = false;
  bool _warranty = false;
  DateTime? _expectedDate;
  Customer? _existingCustomer;
  bool _saving = false;

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
              TextFormField(controller: _imeiCtrl, decoration: const InputDecoration(labelText: 'IMEI')),
            ]),
            SectionCard(title: 'Complaint', icon: Icons.report_problem_rounded, children: [
              TextFormField(controller: _complaintCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Fault / Complaint')),
            ]),
            SectionCard(title: 'Condition', icon: Icons.fact_check_rounded, children: [
              TextFormField(controller: _conditionCtrl, decoration: const InputDecoration(labelText: 'Device Condition')),
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
                TextFormField(controller: _warrantyPeriodCtrl, decoration: const InputDecoration(labelText: 'Warranty Period (e.g. 30 days)')),
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

    await _serviceRepo.create(
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
      expectedDate: _expectedDate,
    );

    if (mounted) Navigator.pop(context, true);
  }
}
