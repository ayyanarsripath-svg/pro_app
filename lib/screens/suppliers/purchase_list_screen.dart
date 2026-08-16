import 'package:flutter/material.dart';

import '../../core/repositories/purchase_repository.dart';
import '../../core/repositories/supplier_repository.dart';
import '../../core/utils/formatters.dart';
import '../../models/purchase.dart';
import '../../widgets/section_card.dart';
import 'purchase_form_screen.dart';

class PurchaseListScreen extends StatefulWidget {
  const PurchaseListScreen({super.key});

  @override
  State<PurchaseListScreen> createState() => _PurchaseListScreenState();
}

class _PurchaseListScreenState extends State<PurchaseListScreen> {
  final _repo = PurchaseRepository();
  final _supplierRepo = SupplierRepository();
  List<Purchase> _purchases = [];
  Map<String, String> _supplierNames = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final purchases = await _repo.all();
    final suppliers = await _supplierRepo.all();
    setState(() {
      _purchases = purchases;
      _supplierNames = {for (final s in suppliers) s.id: s.name};
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _purchases.isEmpty
              ? const EmptyState(icon: Icons.shopping_cart_rounded, message: 'No purchases yet')
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: _purchases.length,
                  itemBuilder: (context, i) {
                    final purchase = _purchases[i];
                    return Card(
                      child: ListTile(
                        title: Text('${purchase.category.toUpperCase()}  •  ${formatCurrency(purchase.totalAmount)}'),
                        subtitle: Text(
                            '${_supplierNames[purchase.supplierId] ?? 'No supplier'}\n${formatDate(purchase.purchaseDate)}  •  Balance: ${formatCurrency(purchase.balance)}'),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const PurchaseFormScreen()));
          if (created == true) _load();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Purchase'),
      ),
    );
  }
}
