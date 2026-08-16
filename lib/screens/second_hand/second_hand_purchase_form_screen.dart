import 'package:flutter/material.dart';

import '../../core/repositories/second_hand_repository.dart';
import '../../widgets/section_card.dart';

/// Full purchase-entry form covering every field in spec section 6.
class SecondHandPurchaseFormScreen extends StatefulWidget {
  const SecondHandPurchaseFormScreen({super.key});

  @override
  State<SecondHandPurchaseFormScreen> createState() => _SecondHandPurchaseFormScreenState();
}

class _SecondHandPurchaseFormScreenState extends State<SecondHandPurchaseFormScreen> {
  final _repo = SecondHandRepository();
  final _formKey = GlobalKey<FormState>();

  final _sellerNameCtrl = TextEditingController();
  final _sellerPhoneCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _imei1Ctrl = TextEditingController();
  final _imei2Ctrl = TextEditingController();
  final _ramCtrl = TextEditingController();
  final _storageCtrl = TextEditingController();
  final _colourCtrl = TextEditingController();
  final _batteryCtrl = TextEditingController();
  final _displayConditionCtrl = TextEditingController();
  final _bodyConditionCtrl = TextEditingController();
  final _accessoriesCtrl = TextEditingController();
  final _purchasePriceCtrl = TextEditingController();
  final _otherCostCtrl = TextEditingController(text: '0');
  final _expectedPriceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _warrantyPeriodCtrl = TextEditingController();

  String _condition = 'Good';
  bool _warranty = false;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Purchase 2nd Hand Phone')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            SectionCard(title: 'Seller', icon: Icons.person_rounded, children: [
              TextFormField(controller: _sellerNameCtrl, decoration: const InputDecoration(labelText: 'Seller Name')),
              const SizedBox(height: 10),
              TextFormField(controller: _sellerPhoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Seller Phone')),
            ]),
            SectionCard(title: 'Device Details', icon: Icons.phone_iphone_rounded, children: [
              TextFormField(controller: _brandCtrl, decoration: const InputDecoration(labelText: 'Mobile Brand')),
              const SizedBox(height: 10),
              TextFormField(controller: _modelCtrl, decoration: const InputDecoration(labelText: 'Model')),
              const SizedBox(height: 10),
              TextFormField(controller: _imei1Ctrl, decoration: const InputDecoration(labelText: 'IMEI 1')),
              const SizedBox(height: 10),
              TextFormField(controller: _imei2Ctrl, decoration: const InputDecoration(labelText: 'IMEI 2')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextFormField(controller: _ramCtrl, decoration: const InputDecoration(labelText: 'RAM'))),
                const SizedBox(width: 10),
                Expanded(child: TextFormField(controller: _storageCtrl, decoration: const InputDecoration(labelText: 'Storage'))),
              ]),
              const SizedBox(height: 10),
              TextFormField(controller: _colourCtrl, decoration: const InputDecoration(labelText: 'Colour')),
            ]),
            SectionCard(title: 'Condition', icon: Icons.fact_check_rounded, children: [
              DropdownButtonFormField<String>(
                value: _condition,
                items: ['Excellent', 'Good', 'Fair', 'Poor'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _condition = v ?? 'Good'),
                decoration: const InputDecoration(labelText: 'Overall Condition'),
              ),
              const SizedBox(height: 10),
              TextFormField(controller: _batteryCtrl, decoration: const InputDecoration(labelText: 'Battery Health (e.g. 88%)')),
              const SizedBox(height: 10),
              TextFormField(controller: _displayConditionCtrl, decoration: const InputDecoration(labelText: 'Display Condition')),
              const SizedBox(height: 10),
              TextFormField(controller: _bodyConditionCtrl, decoration: const InputDecoration(labelText: 'Body Condition')),
              const SizedBox(height: 10),
              TextFormField(controller: _accessoriesCtrl, decoration: const InputDecoration(labelText: 'Accessories Received')),
            ]),
            SectionCard(title: 'Purchase & Pricing', icon: Icons.currency_rupee_rounded, children: [
              TextFormField(
                controller: _purchasePriceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Purchase Price (₹)'),
                validator: (v) => (double.tryParse(v ?? '') == null) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(controller: _otherCostCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Other Cost at Purchase (₹)')),
              const SizedBox(height: 10),
              TextFormField(controller: _expectedPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Expected Selling Price (₹)')),
            ]),
            SectionCard(title: 'Warranty', icon: Icons.verified_user_rounded, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Offer Warranty'),
                value: _warranty,
                onChanged: (v) => setState(() => _warranty = v),
              ),
              if (_warranty) TextFormField(controller: _warrantyPeriodCtrl, decoration: const InputDecoration(labelText: 'Warranty Period')),
            ]),
            SectionCard(title: 'Notes', icon: Icons.notes_rounded, children: [
              TextFormField(controller: _notesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
            ]),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Record Purchase'),
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

    await _repo.recordPurchase(
      purchaseDate: DateTime.now(),
      sellerName: _sellerNameCtrl.text.trim(),
      sellerPhone: _sellerPhoneCtrl.text.trim(),
      brand: _brandCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      imei1: _imei1Ctrl.text.trim(),
      imei2: _imei2Ctrl.text.trim(),
      ram: _ramCtrl.text.trim(),
      storage: _storageCtrl.text.trim(),
      colour: _colourCtrl.text.trim(),
      conditionGrade: _condition,
      batteryHealth: _batteryCtrl.text.trim(),
      displayCondition: _displayConditionCtrl.text.trim(),
      bodyCondition: _bodyConditionCtrl.text.trim(),
      accessoriesReceived: _accessoriesCtrl.text.trim(),
      purchasePrice: double.tryParse(_purchasePriceCtrl.text.trim()) ?? 0,
      otherCost: double.tryParse(_otherCostCtrl.text.trim()) ?? 0,
      expectedSellingPrice: double.tryParse(_expectedPriceCtrl.text.trim()) ?? 0,
      warranty: _warranty,
      warrantyPeriod: _warrantyPeriodCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
    );

    if (mounted) Navigator.pop(context, true);
  }
}
