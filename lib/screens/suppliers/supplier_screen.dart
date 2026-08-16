import 'package:flutter/material.dart';

import '../../core/repositories/supplier_repository.dart';
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
