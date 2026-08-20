import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/repositories/accessory_repository.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/accessory.dart';
import '../../widgets/section_card.dart';

class AccessoriesScreen extends StatefulWidget {
  const AccessoriesScreen({super.key});

  @override
  State<AccessoriesScreen> createState() => _AccessoriesScreenState();
}

class _AccessoriesScreenState extends State<AccessoriesScreen> {
  final _repo = AccessoryRepository();
  List<Accessory> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _repo.all();
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final stockValue = _items.fold<double>(0, (s, a) => s + a.stockValue);
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
                    decoration: BoxDecoration(color: AppColors.flameOrange.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${_items.length} Accessories', style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('Stock Value: ₹${stockValue.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.flameOrange)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_items.isEmpty) const EmptyState(icon: Icons.headset_rounded, message: 'No accessories yet'),
                  ..._items.map((a) => Card(
                        child: ListTile(
                          title: Text(a.name),
                          subtitle: Text('${a.category ?? ''} ${a.brand ?? ''}\nBuy ₹${a.purchasePrice.toStringAsFixed(0)}  →  Sell ₹${a.sellingPrice.toStringAsFixed(0)}  (Profit ₹${a.unitProfit.toStringAsFixed(0)}/unit)'),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${a.currentStock.toStringAsFixed(0)} ${a.unit}',
                                  style: TextStyle(fontWeight: FontWeight.w800, color: a.isLowStock ? AppColors.danger : AppColors.textPrimaryOf(context))),
                              if (a.isLowStock) const Text('LOW STOCK', style: TextStyle(color: AppColors.danger, fontSize: 10, fontWeight: FontWeight.w700)),
                            ],
                          ),
                          onTap: () => _showActions(a, auth),
                        ),
                      )),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAccessory,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Accessory'),
      ),
    );
  }

  Future<void> _addAccessory() async {
    final nameCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final brandCtrl = TextEditingController();
    final purchaseCtrl = TextEditingController();
    final sellCtrl = TextEditingController();
    final thresholdCtrl = TextEditingController(text: '3');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Accessory'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name (e.g. Headphone)')),
              const SizedBox(height: 10),
              TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Category')),
              const SizedBox(height: 10),
              TextField(controller: brandCtrl, decoration: const InputDecoration(labelText: 'Brand')),
              const SizedBox(height: 10),
              TextField(controller: purchaseCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Purchase Price (₹)')),
              const SizedBox(height: 10),
              TextField(controller: sellCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Selling Price (₹)')),
              const SizedBox(height: 10),
              TextField(controller: thresholdCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Low Stock Threshold')),
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
        brand: brandCtrl.text.trim(),
        purchasePrice: double.tryParse(purchaseCtrl.text.trim()) ?? 0,
        sellingPrice: double.tryParse(sellCtrl.text.trim()) ?? 0,
        lowStockThreshold: double.tryParse(thresholdCtrl.text.trim()) ?? 3,
      );
      _load();
    }
  }

  /// Restock / Edit / Delete menu for a single accessory (Edit is how the
  /// low-stock threshold - and other details - can now be changed after
  /// creation, which previously wasn't possible).
  Future<void> _showActions(Accessory a, AuthService auth) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.add_shopping_cart_rounded),
              title: const Text('Record Purchase'),
              onTap: () => Navigator.pop(context, 'purchase'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            if (auth.canDelete)
              ListTile(
                leading: const Icon(Icons.delete_rounded, color: AppColors.danger),
                title: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'purchase') {
      await _recordPurchase(a);
    } else if (action == 'edit') {
      await _editAccessory(a);
    } else if (action == 'delete') {
      await _deleteAccessory(a);
    }
  }

  /// Lets the shop edit an already-created accessory - most importantly the
  /// low-stock threshold, which previously could only be set at creation.
  Future<void> _editAccessory(Accessory a) async {
    final nameCtrl = TextEditingController(text: a.name);
    final categoryCtrl = TextEditingController(text: a.category ?? '');
    final brandCtrl = TextEditingController(text: a.brand ?? '');
    final sellCtrl = TextEditingController(text: a.sellingPrice.toStringAsFixed(0));
    final thresholdCtrl = TextEditingController(text: a.lowStockThreshold.toStringAsFixed(0));

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Accessory'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Category')),
              const SizedBox(height: 10),
              TextField(controller: brandCtrl, decoration: const InputDecoration(labelText: 'Brand')),
              const SizedBox(height: 10),
              TextField(controller: sellCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Selling Price (₹)')),
              const SizedBox(height: 10),
              TextField(controller: thresholdCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Low Stock Threshold')),
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
        id: a.id,
        name: nameCtrl.text.trim().isEmpty ? a.name : nameCtrl.text.trim(),
        category: categoryCtrl.text.trim(),
        brand: brandCtrl.text.trim(),
        sellingPrice: double.tryParse(sellCtrl.text.trim()) ?? a.sellingPrice,
        lowStockThreshold: double.tryParse(thresholdCtrl.text.trim()) ?? a.lowStockThreshold,
      );
      _load();
    }
  }

  /// Admin/permission-gated Delete (spec: small confirmation dialog).
  Future<void> _deleteAccessory(Accessory a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Accessory?'),
        content: Text('${a.name} will be removed from the list. This cannot be undone from here.'),
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
      await _repo.delete(a.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Accessory deleted')));
      }
      _load();
    }
  }

  Future<void> _recordPurchase(Accessory a) async {
    final qtyCtrl = TextEditingController(text: '1');
    final costCtrl = TextEditingController(text: a.purchasePrice.toStringAsFixed(0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Purchase: ${a.name}'),
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
        accessoryId: a.id,
        quantity: double.tryParse(qtyCtrl.text.trim()) ?? 0,
        unitCost: double.tryParse(costCtrl.text.trim()) ?? 0,
        date: DateTime.now(),
      );
      _load();
    }
  }
}
