import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/repositories/spare_part_repository.dart';
import '../../core/services/auth_service.dart';
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
    final auth = context.watch<AuthService>();
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
                                  style: TextStyle(fontWeight: FontWeight.w800, color: part.isLowStock ? AppColors.danger : AppColors.textPrimaryOf(context))),
                              if (part.isLowStock) const Text('LOW STOCK', style: TextStyle(color: AppColors.danger, fontSize: 10, fontWeight: FontWeight.w700)),
                            ],
                          ),
                          onTap: () => _showActions(part, auth),
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

  Future<void> _showActions(SparePart part, AuthService auth) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.add_box_rounded), title: const Text('Record Purchase (Stock In)'), onTap: () => Navigator.pop(context, 'purchase')),
          ListTile(leading: const Icon(Icons.tune_rounded), title: const Text('Adjust Stock'), onTap: () => Navigator.pop(context, 'adjust')),
          ListTile(leading: const Icon(Icons.assignment_return_rounded), title: const Text('Return to Supplier'), onTap: () => Navigator.pop(context, 'return')),
          ListTile(leading: const Icon(Icons.edit_rounded), title: const Text('Edit'), onTap: () => Navigator.pop(context, 'edit')),
          if (auth.canDelete)
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: AppColors.danger),
              title: const Text('Delete', style: TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
        ]),
      ),
    );
    if (!mounted) return;
    if (action == 'purchase') await _recordPurchase(part);
    if (action == 'adjust') await _adjustStock(part);
    if (action == 'return') await _returnToSupplier(part);
    if (action == 'edit') await _editPart(part);
    if (action == 'delete') await _deletePart(part);
  }

  /// Lets the shop edit an existing spare part's details/threshold.
  Future<void> _editPart(SparePart part) async {
    final nameCtrl = TextEditingController(text: part.name);
    final categoryCtrl = TextEditingController(text: part.category ?? '');
    final modelCtrl = TextEditingController(text: part.compatibleModel ?? '');
    final thresholdCtrl = TextEditingController(text: part.lowStockThreshold.toStringAsFixed(0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Spare Part'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
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
    if (ok == true) {
      await _repo.update(
        id: part.id,
        name: nameCtrl.text.trim().isEmpty ? part.name : nameCtrl.text.trim(),
        category: categoryCtrl.text.trim(),
        compatibleModel: modelCtrl.text.trim(),
        lowStockThreshold: double.tryParse(thresholdCtrl.text.trim()) ?? part.lowStockThreshold,
      );
      _load();
    }
  }

  /// Admin/permission-gated Delete (spec: small confirmation dialog).
  Future<void> _deletePart(SparePart part) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Spare Part?'),
        content: Text('${part.name} will be removed from the list. This cannot be undone from here.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _repo.delete(part.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Spare part deleted')));
      }
      _load();
    }
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
    final qtyCtrl = TextEditingController(text: '0');
    final notesCtrl = TextEditingController();

    // Signed quantity typed directly is still supported, but a +/- stepper
    // is offered alongside it - tapping + increases the number, tapping -
    // decreases it, so it's obvious at a glance which direction stock is
    // moving instead of having to remember to type a leading minus sign.
    void bump(void Function(void Function()) setLocalState, int delta) {
      final current = double.tryParse(qtyCtrl.text.trim()) ?? 0;
      setLocalState(() => qtyCtrl.text = (current + delta).toStringAsFixed(current % 1 == 0 ? 0 : 2));
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text('Adjust Stock: ${part.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 32, color: AppColors.danger),
                    tooltip: 'Decrease',
                    onPressed: () => bump(setLocalState, -1),
                  ),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: qtyCtrl,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                      decoration: const InputDecoration(labelText: 'Quantity (+ / -)'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 32, color: AppColors.success),
                    tooltip: 'Increase',
                    onPressed: () => bump(setLocalState, 1),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Reason')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
          ],
        ),
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
