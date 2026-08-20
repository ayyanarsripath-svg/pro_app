import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/repositories/supplier_repository.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/supplier.dart';
import '../../widgets/section_card.dart';

class SupplierScreen extends StatefulWidget {
  const SupplierScreen({super.key});

  @override
  State<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends State<SupplierScreen> {
  final _repo = SupplierRepository();
  List<Supplier> _suppliers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _repo.all();
    setState(() {
      _suppliers = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _suppliers.isEmpty
              ? const EmptyState(icon: Icons.local_shipping_rounded, message: 'No suppliers yet')
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: _suppliers.length,
                  itemBuilder: (context, i) {
                    final s = _suppliers[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.store_rounded),
                        title: Text(s.name),
                        subtitle: Text('${s.phone ?? ''}\n${s.address ?? ''}'),
                        isThreeLine: true,
                        trailing: auth.canDelete
                            ? IconButton(
                                icon: const Icon(Icons.delete_rounded, color: AppColors.danger),
                                tooltip: 'Delete supplier',
                                onPressed: () => _delete(s),
                              )
                            : null,
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Supplier'),
      ),
    );
  }

  /// Admin/permission-gated Delete (small confirmation dialog, same pattern
  /// used for accessories/spare parts).
  Future<void> _delete(Supplier s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Supplier?'),
        content: Text('${s.name} will be removed from the list. Past purchases from this supplier stay in your records. This cannot be undone from here.'),
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
      await _repo.delete(s.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Supplier deleted')));
      }
      _load();
    }
  }

  Future<void> _add() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Supplier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 10),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: 10),
            TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Address')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      await _repo.create(name: nameCtrl.text.trim(), phone: phoneCtrl.text.trim(), address: addressCtrl.text.trim());
      _load();
    }
  }
}
