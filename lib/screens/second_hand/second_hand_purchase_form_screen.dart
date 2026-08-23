import 'package:flutter/material.dart';

import '../../core/repositories/second_hand_repository.dart';
import '../../models/second_hand_phone.dart';
import '../../widgets/section_card.dart';

/// Full purchase-entry form covering every field in spec section 6.
class SecondHandPurchaseFormScreen extends StatefulWidget {
  /// Which device-type segment is pre-selected when opened - "Mobile Sales"
  /// opens this pre-set to mobile, "Laptop Sales" pre-sets it to laptop.
  /// The Device Type toggle stays editable either way.
  final String initialDeviceType;
  const SecondHandPurchaseFormScreen({super.key, this.initialDeviceType = DeviceType.mobile});

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
  String _deviceType = DeviceType.mobile;

  bool get _isLaptop => _deviceType == DeviceType.laptop;

  @override
  void initState() {
    super.initState();
    _deviceType = widget.initialDeviceType;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isLaptop ? 'Purchase Laptop' : 'Purchase 2nd Hand Phone')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            SectionCard(title: 'Device Type', icon: Icons.devices_rounded, children: [
              // Mobile vs Laptop - drives the identifier field below (IMEI
              // for mobiles, Serial No for laptops, since laptops don't
              // carry an IMEI) and the bill title/labels when this device
              // is later sold (see Mobile Sales / buildSecondHandSalesBill).
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: DeviceType.mobile, label: Text('Mobile'), icon: Icon(Icons.smartphone_rounded)),
                  ButtonSegment(value: DeviceType.laptop, label: Text('Laptop'), icon: Icon(Icons.laptop_rounded)),
                ],
                selected: {_deviceType},
                onSelectionChanged: (s) => setState(() => _deviceType = s.first),
              ),
            ]),
            SectionCard(title: 'Seller', icon: Icons.person_rounded, children: [
              TextFormField(controller: _sellerNameCtrl, decoration: const InputDecoration(labelText: 'Seller Name')),
              const SizedBox(height: 10),
              TextFormField(controller: _sellerPhoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Seller Phone')),
            ]),
            SectionCard(title: 'Device Details', icon: Icons.phone_iphone_rounded, children: [
              TextFormField(controller: _brandCtrl, decoration: InputDecoration(labelText: _isLaptop ? 'Laptop Brand' : 'Mobile Brand')),
              const SizedBox(height: 10),
              TextFormField(controller: _modelCtrl, decoration: const InputDecoration(labelText: 'Model')),
              const SizedBox(height: 10),
              // IMEI (mobile) is always 15 numeric digits -> numeric keypad.
              // Serial No (laptop) mixes letters and numbers (e.g.
              // "WES/1234") -> normal keyboard. Laptops only carry one
              // serial number, so IMEI 2 is hidden for them.
              TextFormField(
                controller: _imei1Ctrl,
                keyboardType: _isLaptop ? TextInputType.text : TextInputType.number,
                decoration: InputDecoration(labelText: _isLaptop ? 'Serial No' : 'IMEI 1'),
              ),
              if (!_isLaptop) ...[
                const SizedBox(height: 10),
                TextFormField(controller: _imei2Ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'IMEI 2')),
              ],
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
              if (_warranty)
                TextFormField(
                  controller: _warrantyPeriodCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Warranty Period (in days)'),
                ),
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
      deviceType: _deviceType,
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
