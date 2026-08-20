import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/repositories/purchase_repository.dart';
import '../../core/repositories/supplier_repository.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
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
    final auth = context.watch<AuthService>();
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
                        trailing: auth.canDelete
                            ? IconButton(
                                icon: const Icon(Icons.delete_rounded, color: AppColors.danger),
                                tooltip: 'Delete purchase',
                                onPressed: () => _delete(purchase),
                              )
                            : null,
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

  /// Admin/permission-gated Delete. Reverses the stock/cost impact of every
  /// line item in this purchase before removing it (see
  /// PurchaseRepository.delete).
  Future<void> _delete(Purchase purchase) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Purchase?'),
        content: Text(
            'This ${purchase.category} purchase (${formatCurrency(purchase.totalAmount)}) will be removed and the stock it added will be reversed. This cannot be undone from here.'),
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
      await _repo.delete(purchase.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Purchase deleted')));
      }
      _load();
    }
  }
}
