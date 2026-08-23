import 'package:flutter/material.dart';

import '../../core/repositories/accessory_repository.dart';
import '../../core/repositories/purchase_repository.dart';
import '../../core/repositories/spare_part_repository.dart';
import '../../core/repositories/supplier_repository.dart';
import '../../models/accessory.dart';
import '../../models/spare_part.dart';
import '../../models/supplier.dart';
import '../../widgets/section_card.dart';

class _Line {
  final String itemType;
  final String itemId;
  final String itemName;
  final double quantity;
  final double unitCost;
  _Line(this.itemType, this.itemId, this.itemName, this.quantity, this.unitCost);
  double get total => quantity * unitCost;
}

class PurchaseFormScreen extends StatefulWidget {
  const PurchaseFormScreen({super.key});

  @override
  State<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

/// Sentinel entry appended to the Select Supplier dropdown so a purchase can
/// be recorded from a one-off/unsaved supplier without first creating them
/// in Suppliers. Picking it reveals a free-text name field; on submit a new
/// Supplier record is created from that name (so it's in the saved list for
/// next time too).
final _otherSupplier = Supplier(id: '__other__', name: 'Other (not in list)', createdAt: DateTime.now());

class _PurchaseFormScreenState extends State<PurchaseFormScreen> {
  final _supplierRepo = SupplierRepository();
  final _sparePartRepo = SparePartRepository();
  final _accessoryRepo = AccessoryRepository();
  final _purchaseRepo = PurchaseRepository();

  List<Supplier> _suppliers = [];
  List<SparePart> _spareParts = [];
  List<Accessory> _accessories = [];
  Supplier? _selectedSupplier;
  final _otherSupplierNameCtrl = TextEditingController();
  final List<_Line> _lines = [];
  final _paidCtrl = TextEditingController(text: '0');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final suppliers = await _supplierRepo.all();
    final parts = await _sparePartRepo.all();
    final accessories = await _accessoryRepo.all();
    setState(() {
      _suppliers = suppliers;
      _spareParts = parts;
      _accessories = accessories;
    });
  }

  double get _total => _lines.fold(0, (s, l) => s + l.total);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Purchase')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          SectionCard(title: 'Supplier', icon: Icons.store_rounded, children: [
            DropdownButtonFormField<Supplier>(
              value: _selectedSupplier,
              isExpanded: true,
              hint: const Text('Select supplier (optional)'),
              items: [
                ..._suppliers.map((s) => DropdownMenuItem(value: s, child: Text(s.name))),
                DropdownMenuItem(value: _otherSupplier, child: Text(_otherSupplier.name)),
              ],
              onChanged: (v) => setState(() => _selectedSupplier = v),
            ),
            if (_selectedSupplier?.id == _otherSupplier.id) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _otherSupplierNameCtrl,
                decoration: const InputDecoration(labelText: 'Supplier Name'),
              ),
            ],
          ]),
          SectionCard(
            title: 'Items',
            icon: Icons.inventory_2_rounded,
            trailing: TextButton.icon(onPressed: _addLine, icon: const Icon(Icons.add, size: 16), label: const Text('Add')),
            children: [
              if (_lines.isEmpty) const Text('No items added', style: TextStyle(color: Colors.grey)),
              ..._lines.map((l) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.itemName),
                    subtitle: Text('${l.itemType == 'spare_part' ? 'Spare Part' : 'Accessory'}  •  ${l.quantity.toStringAsFixed(0)} x ₹${l.unitCost.toStringAsFixed(0)}'),
                    trailing: Text('₹${l.total.toStringAsFixed(0)}'),
                  )),
            ],
          ),
          SectionCard(title: 'Payment', icon: Icons.payments_rounded, children: [
            Text('Total: ₹${_total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            TextField(controller: _paidCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Paid Amount (₹)')),
          ]),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: (_lines.isEmpty || _saving) ? null : _submit,
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save Purchase'),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Future<void> _addLine() async {
    String itemType = 'spare_part';
    dynamic selected = _spareParts.isNotEmpty ? _spareParts.first : (_accessories.isNotEmpty ? _accessories.first : null);
    if (_spareParts.isEmpty && _accessories.isNotEmpty) itemType = 'accessory';
    final qtyCtrl = TextEditingController(text: '1');
    final costCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          final list = itemType == 'spare_part' ? _spareParts : _accessories;
          return AlertDialog(
            title: const Text('Add Purchase Item'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'spare_part', label: Text('Spare Part')),
                    ButtonSegment(value: 'accessory', label: Text('Accessory')),
                  ],
                  selected: {itemType},
                  onSelectionChanged: (v) => setLocalState(() {
                    itemType = v.first;
                    selected = (itemType == 'spare_part' ? _spareParts : _accessories).isNotEmpty
                        ? (itemType == 'spare_part' ? _spareParts.first : _accessories.first)
                        : null;
                  }),
                ),
                const SizedBox(height: 10),
                if (list.isEmpty)
                  const Text('No items in inventory yet - add one first from Spare Parts / Accessories.')
                else
                  DropdownButtonFormField(
                    value: selected,
                    isExpanded: true,
                    items: list
                        .map<DropdownMenuItem>((item) => DropdownMenuItem(value: item, child: Text((item as dynamic).name as String)))
                        .toList(),
                    onChanged: (v) => setLocalState(() => selected = v),
                  ),
                TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
                TextField(controller: costCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Unit Cost (₹)')),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: list.isEmpty ? null : () => Navigator.pop(context, true), child: const Text('Add')),
            ],
          );
        },
      ),
    );

    if (ok == true && selected != null) {
      final name = itemType == 'spare_part' ? (selected as SparePart).name : (selected as Accessory).name;
      final id = itemType == 'spare_part' ? (selected as SparePart).id : (selected as Accessory).id;
      setState(() {
        _lines.add(_Line(itemType, id, name, double.tryParse(qtyCtrl.text.trim()) ?? 1, double.tryParse(costCtrl.text.trim()) ?? 0));
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    final category = _lines.every((l) => l.itemType == 'spare_part')
        ? 'spare_part'
        : _lines.every((l) => l.itemType == 'accessory')
            ? 'accessory'
            : 'other';

    // "Other" supplier: create a real Supplier record from the typed name
    // (if any) so it's saved for next time; otherwise proceed with no
    // supplier attached, same as leaving the dropdown blank.
    String? supplierId = _selectedSupplier?.id;
    if (_selectedSupplier?.id == _otherSupplier.id) {
      final name = _otherSupplierNameCtrl.text.trim();
      supplierId = name.isEmpty ? null : (await _supplierRepo.create(name: name)).id;
    }

    await _purchaseRepo.create(
      supplierId: supplierId,
      purchaseDate: DateTime.now(),
      category: category,
      items: _lines.map((l) => PurchaseLineInput(itemType: l.itemType, itemId: l.itemId, itemName: l.itemName, quantity: l.quantity, unitCost: l.unitCost)).toList(),
      paidAmount: double.tryParse(_paidCtrl.text.trim()) ?? 0,
    );

    if (mounted) Navigator.pop(context, true);
  }
}
