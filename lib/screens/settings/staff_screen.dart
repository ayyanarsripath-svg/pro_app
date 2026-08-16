import 'package:flutter/material.dart';

import '../../core/repositories/staff_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../models/staff.dart';
import '../../widgets/section_card.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  final _repo = StaffRepository();
  List<Staff> _staff = [];
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
      _staff = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff & Permissions')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                if (_staff.isEmpty) const EmptyState(icon: Icons.badge_rounded, message: 'No staff yet'),
                ..._staff.map((s) => Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Icon(s.isAdmin ? Icons.shield_rounded : Icons.person_rounded)),
                        title: Text(s.name),
                        subtitle: Text(s.isAdmin ? 'Admin - full access' : _permSummary(s)),
                        trailing: s.isAdmin
                            ? null
                            : Switch(
                                value: s.active,
                                onChanged: (v) async {
                                  await _repo.setActive(s.id, v);
                                  _load();
                                },
                              ),
                        onTap: s.isAdmin ? null : () => _editPermissions(s),
                      ),
                    )),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStaff,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Staff'),
      ),
    );
  }

  String _permSummary(Staff s) {
    final perms = <String>[];
    if (s.canViewProfit) perms.add('View Profit');
    if (s.canViewCost) perms.add('View Cost');
    if (s.canEditPrices) perms.add('Edit Prices');
    if (s.canManageExpenses) perms.add('Manage Expenses');
    if (s.canManageInventory) perms.add('Manage Inventory');
    if (s.canDeleteRecords) perms.add('Delete Records');
    return perms.isEmpty ? 'No special permissions' : perms.join(', ');
  }

  Future<void> _addStaff() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    bool viewProfit = false, viewCost = false, editPrices = false, manageExpenses = false, manageInventory = true, deleteRecords = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Add Staff'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone')),
                TextField(controller: pinCtrl, obscureText: true, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'PIN (4-6 digits)')),
                const Divider(),
                CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('View Profit'), value: viewProfit, onChanged: (v) => setLocalState(() => viewProfit = v ?? false)),
                CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('View Cost'), value: viewCost, onChanged: (v) => setLocalState(() => viewCost = v ?? false)),
                CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Edit Prices'), value: editPrices, onChanged: (v) => setLocalState(() => editPrices = v ?? false)),
                CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Manage Expenses'), value: manageExpenses, onChanged: (v) => setLocalState(() => manageExpenses = v ?? false)),
                CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Manage Inventory'), value: manageInventory, onChanged: (v) => setLocalState(() => manageInventory = v ?? false)),
                CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Delete Records'), value: deleteRecords, onChanged: (v) => setLocalState(() => deleteRecords = v ?? false)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty && pinCtrl.text.trim().length >= 4) {
      await _repo.createStaff(
        name: nameCtrl.text.trim(),
        pin: pinCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        canViewProfit: viewProfit,
        canViewCost: viewCost,
        canEditPrices: editPrices,
        canManageExpenses: manageExpenses,
        canManageInventory: manageInventory,
        canDeleteRecords: deleteRecords,
      );
      _load();
    }
  }

  Future<void> _editPermissions(Staff s) async {
    bool viewProfit = s.canViewProfit, viewCost = s.canViewCost, editPrices = s.canEditPrices;
    bool manageExpenses = s.canManageExpenses, manageInventory = s.canManageInventory, deleteRecords = s.canDeleteRecords;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text('Permissions: ${s.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('View Profit'), value: viewProfit, onChanged: (v) => setLocalState(() => viewProfit = v ?? false)),
              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('View Cost'), value: viewCost, onChanged: (v) => setLocalState(() => viewCost = v ?? false)),
              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Edit Prices'), value: editPrices, onChanged: (v) => setLocalState(() => editPrices = v ?? false)),
              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Manage Expenses'), value: manageExpenses, onChanged: (v) => setLocalState(() => manageExpenses = v ?? false)),
              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Manage Inventory'), value: manageInventory, onChanged: (v) => setLocalState(() => manageInventory = v ?? false)),
              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Delete Records'), value: deleteRecords, onChanged: (v) => setLocalState(() => deleteRecords = v ?? false)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (ok == true) {
      final updated = Staff(
        id: s.id, name: s.name, phone: s.phone, pinHash: s.pinHash, role: s.role,
        canViewProfit: viewProfit, canViewCost: viewCost, canEditPrices: editPrices,
        canManageExpenses: manageExpenses, canManageInventory: manageInventory, canDeleteRecords: deleteRecords,
        active: s.active, createdAt: s.createdAt,
      );
      await _repo.update(updated);
      _load();
    }
  }
}
