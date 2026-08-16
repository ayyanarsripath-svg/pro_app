import 'package:flutter/material.dart';

import '../../core/repositories/spare_part_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../models/spare_part.dart';
import '../../widgets/section_card.dart';

class SparePartsScreen extends StatefulWidget {
  const SparePartsScreen({super.key});

  @override
  State<SparePartsScreen> createState() => _SparePartsScreenState();
}

class _SparePartsScreenState extends State<SparePartsScreen> {
  final _repo = SparePartRepository();
  List<SparePart> _parts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final parts = await _repo.all();
    setState(() {
      _parts = parts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final stockValue = _parts.fold<double>(0, (s, p) => s + p.stockValue);
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${_parts.length} Spare Parts', style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('Stock Value: ₹${stockValue.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryBlue)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_parts.isEmpty) const EmptyState(icon: Icons.memory_rounded, message: 'No spare parts yet'),
                  ..._parts.map((part) => Card(
                        child: ListTile(
                          title: Text(part.name),
                          subtitle: Text('${part.category ?? ''} ${part.compatibleModel ?? ''}\nAvg Cost: ₹${part.avgPurchaseCost.toStringAsFixed(0)}'),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${part.currentStock.toStringAsFixed(0)} ${part.unit}',
                                  style: TextStyle(fontWeight: FontWeight.w800, color: part.isLowStock ? AppColors.danger : AppColors.textPrimary)),
                              if (part.isLowStock) const Text('LOW STOCK', style: TextStyle(color: AppColors.danger, fontSize: 10, fontWeight: FontWeight.w700)),
                            ],
                          ),
                          onTap: () => _showActions(part),
                        ),
                      )),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPart,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Part'),
      ),
    );
  }

  Future<void> _addPart() async {
    final nameCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final thresholdCtrl = TextEditingController(text: '2');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Spare Part'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name (e.g. Samsung A15 Display)')),
              const SizedBox(height: 10),
              TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Category')),
              const SizedBox(height: 10),
              TextField(controller: modelCtrl, decoration: const InputDecoration(labelText: 'Compatible Model')),
              const SizedBox(height: 10),
              TextField(controller: thresholdCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Low Stock Alert Threshold')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      await _repo.create(
        name: nameCtrl.text.trim(),
        category: categoryCtrl.text.trim(),
        compatibleModel: modelCtrl.text.trim(),
        lowStockThreshold: double.tryParse(thresholdCtrl.text.trim()) ?? 2,
      );
      _load();
    }
  }

  Future<void> _showActions(SparePart part) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.add_box_rounded), title: const Text('Record Purchase (Stock In)'), onTap: () => Navigator.pop(context, 'purchase')),
          ListTile(leading: const Icon(Icons.tune_rounded), title: const Text('Adjust Stock'), onTap: () => Navigator.pop(context, 'adjust')),
          ListTile(leading: const Icon(Icons.assignment_return_rounded), title: const Text('Return to Supplier'), onTap: () => Navigator.pop(context, 'return')),
        ]),
      ),
    );
    if (action == 'purchase') await _recordPurchase(part);
    if (action == 'adjust') await _adjustStock(part);
    if (action == 'return') await _returnToSupplier(part);
  }

  Future<void> _returnToSupplier(SparePart part) async {
    final qtyCtrl = TextEditingController(text: '1');
    final notesCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Return to Supplier: ${part.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
            const SizedBox(height: 10),
            TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Reason')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Return')),
        ],
      ),
    );
    if (ok == true) {
      await _repo.returnToSupplier(
        sparePartId: part.id,
        quantity: double.tryParse(qtyCtrl.text.trim()) ?? 0,
        date: DateTime.now(),
        notes: notesCtrl.text.trim(),
      );
      _load();
    }
  }

  Future<void> _recordPurchase(SparePart part) async {
    final qtyCtrl = TextEditingController(text: '1');
    final costCtrl = TextEditingController(text: part.avgPurchaseCost.toStringAsFixed(0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Purchase: ${part.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
            const SizedBox(height: 10),
            TextField(controller: costCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Unit Cost (₹)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add Stock')),
        ],
      ),
    );
    if (ok == true) {
      await _repo.recordPurchase(
        sparePartId: part.id,
        quantity: double.tryParse(qtyCtrl.text.trim()) ?? 0,
        unitCost: double.tryParse(costCtrl.text.trim()) ?? 0,
        date: DateTime.now(),
      );
      _load();
    }
  }

  Future<void> _adjustStock(SparePart part) async {
    final qtyCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Adjust Stock: ${part.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: qtyCtrl, keyboardType: const TextInputType.numberWithOptions(signed: true), decoration: const InputDecoration(labelText: 'Quantity (+ / -)')),
            const SizedBox(height: 10),
            TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Reason')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
        ],
      ),
    );
    if (ok == true) {
      await _repo.adjustStock(
        sparePartId: part.id,
        quantity: double.tryParse(qtyCtrl.text.trim()) ?? 0,
        notes: notesCtrl.text.trim(),
        date: DateTime.now(),
      );
      _load();
    }
  }
}
