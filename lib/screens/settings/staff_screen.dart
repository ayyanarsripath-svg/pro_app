import 'package:flutter/material.dart';

import '../../core/repositories/staff_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../models/staff.dart';
import '../../widgets/section_card.dart';

/// One row of explanation for a permission checkbox: a short title plus a
/// plain-language description of what turning it on actually lets someone
/// do. Previously the Add/Edit Staff dialogs showed six bare checkbox
/// labels ("Edit Prices", "Manage Inventory"...) with nothing explaining
/// what they meant or which ones were on by default - this is the single
/// source of truth both dialogs and the on-screen help card read from, so
/// the wording can never drift between the two.
class _PermInfo {
  final String title;
  final String help;
  const _PermInfo(this.title, this.help);
}

const List<_PermInfo> _permissions = [
  _PermInfo('View Profit', 'See profit/margin figures on jobs, sales and the Profit & Loss dashboard. Off by default.'),
  _PermInfo('View Cost', 'See purchase cost and spare-part cost prices. Off by default - customer bills never show this to anyone, regardless of this setting.'),
  _PermInfo('Edit Prices', 'Change a selling price while billing a customer, instead of only using the saved price.'),
  _PermInfo('Manage Expenses', 'Add and record business expenses (rent, electricity, etc).'),
  _PermInfo('Manage Inventory', 'Add stock and edit spare parts & accessories. On by default so staff can do day-to-day restocking.'),
  _PermInfo('Delete Records', 'Delete suppliers, expenses, purchases and other saved records. Off by default - keep this admin-only unless you trust someone with it.'),
];

/// One "Section" choice for the Add/Edit Staff dialog - which whole menu
/// screens that login even sees, before the permission checkboxes above
/// come into play at all. 'full' keeps the original behaviour (every
/// screen); 'billing' and 'inventory' hide Dashboard, Profit & Loss,
/// Expenses and each other's screens entirely, not just individual figures.
class _SectionInfo {
  final String value;
  final String title;
  final String help;
  const _SectionInfo(this.value, this.title, this.help);
}

const List<_SectionInfo> _sections = [
  _SectionInfo('full', 'Full Access', 'Sees every screen (Dashboard, all bills, all inventory, Expenses, Profit & Loss) - only the permissions below limit what they can do.'),
  _SectionInfo('billing', 'Billing Only', 'Sales Bill, Service Bill (+ adding repair parts used), Mobile Sales, Laptop Sales and printing - nothing else. No Dashboard, Profit & Loss, Expenses or inventory screens.'),
  _SectionInfo('inventory', 'Inventory Only', 'Spare Parts, Accessories, Mobile Sales stock, Laptop Sales stock, Suppliers and Purchases - add/reduce stock only. No Dashboard, Profit & Loss, Expenses or billing screens.'),
];

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
                SectionCard(
                  title: 'How this works',
                  icon: Icons.info_outline_rounded,
                  children: [
                    _HowStep(
                      number: '1',
                      text: 'Tap "Add Staff" below to create a login for each staff member: a name and a 4-6 digit PIN. They use that PIN to log in on the phone/tablet instead of the Admin PIN.',
                    ),
                    _HowStep(
                      number: '2',
                      text: 'Pick a Section - Billing Only shows just Sales/Service/2nd-Hand bills + printing; Inventory Only shows just Spare Parts/Accessories/2nd-Hand stock + Suppliers/Purchases. Neither ever sees Dashboard, Profit & Loss or Expenses. Pick Full Access to see everything, as before.',
                    ),
                    _HowStep(
                      number: '3',
                      text: 'Then tick only the permissions that person should have. Everything is off except "Manage Inventory" until you change it - a new staff account starts with the least access on purpose.',
                    ),
                    _HowStep(
                      number: '4',
                      text: 'Tap a staff member any time to change their section or permissions, or use the switch to temporarily block their PIN from logging in without deleting the account.',
                    ),
                    _HowStep(
                      number: '5',
                      text: 'Admin (you) always has full access, including every permission below - it never needs to be granted separately.',
                      isLast: true,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_staff.isEmpty) const EmptyState(icon: Icons.badge_rounded, message: 'No staff yet - tap "Add Staff" to create the first login'),
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
    final sectionLabel = s.isFullSection ? null : (s.isBillingSection ? 'Billing Only' : 'Inventory Only');
    final permsText = perms.isEmpty ? 'No special permissions' : perms.join(', ');
    final combined = sectionLabel == null ? permsText : '$sectionLabel  •  $permsText';
    return '$combined  •  tap to change';
  }

  /// Builds the six permission checkboxes, each with its title + help text,
  /// shared by both the Add and Edit dialogs so the wording always matches.
  List<Widget> _buildPermChecks(List<bool> values, void Function(void Function()) setLocalState) {
    return List.generate(_permissions.length, (i) {
      final p = _permissions[i];
      return CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(p.help, style: const TextStyle(fontSize: 11.5)),
        isThreeLine: true,
        value: values[i],
        onChanged: (v) => setLocalState(() => values[i] = v ?? false),
      );
    });
  }

  /// Builds the "Section" radio choices (Full/Billing/Inventory), shared by
  /// both the Add and Edit dialogs. [section] holds the current value in a
  /// single-element list so the closure can mutate it via setLocalState,
  /// the same trick used for the boolean permission values above.
  List<Widget> _buildSectionPicker(List<String> section, void Function(void Function()) setLocalState) {
    return List.generate(_sections.length, (i) {
      final sec = _sections[i];
      return RadioListTile<String>(
        contentPadding: EdgeInsets.zero,
        title: Text(sec.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sec.help, style: const TextStyle(fontSize: 11.5)),
        isThreeLine: true,
        value: sec.value,
        groupValue: section[0],
        onChanged: (v) => setLocalState(() => section[0] = v ?? 'full'),
      );
    });
  }

  Future<void> _addStaff() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    // Matches Staff's own defaults: everything off except Manage Inventory.
    final values = [false, false, false, false, true, false];
    final section = ['full'];

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Add Staff'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 8),
                TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone')),
                const SizedBox(height: 8),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(labelText: 'PIN (4-6 digits)', helperText: 'This person will use this PIN to log in'),
                ),
                const Divider(),
                const Text('Section', style: TextStyle(fontWeight: FontWeight.w700)),
                const Text('Which menu screens this login even sees', style: TextStyle(fontSize: 11.5)),
                ..._buildSectionPicker(section, setLocalState),
                const Divider(),
                const Text('Permissions', style: TextStyle(fontWeight: FontWeight.w700)),
                ..._buildPermChecks(values, setLocalState),
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

    if (ok == true && nameCtrl.text.trim().isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a name for the staff member')));
      return;
    }
    if (ok == true && pinCtrl.text.trim().length < 4) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN must be at least 4 digits')));
      return;
    }

    if (ok == true && nameCtrl.text.trim().isNotEmpty && pinCtrl.text.trim().length >= 4) {
      await _repo.createStaff(
        name: nameCtrl.text.trim(),
        pin: pinCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        section: section[0],
        canViewProfit: values[0],
        canViewCost: values[1],
        canEditPrices: values[2],
        canManageExpenses: values[3],
        canManageInventory: values[4],
        canDeleteRecords: values[5],
      );
      _load();
    }
  }

  Future<void> _editPermissions(Staff s) async {
    final values = [s.canViewProfit, s.canViewCost, s.canEditPrices, s.canManageExpenses, s.canManageInventory, s.canDeleteRecords];
    final section = [s.section];

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text('Permissions: ${s.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Section', style: TextStyle(fontWeight: FontWeight.w700)),
                const Text('Which menu screens this login even sees', style: TextStyle(fontSize: 11.5)),
                ..._buildSectionPicker(section, setLocalState),
                const Divider(),
                const Text('Permissions', style: TextStyle(fontWeight: FontWeight.w700)),
                ..._buildPermChecks(values, setLocalState),
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

    if (ok == true) {
      final updated = Staff(
        id: s.id, name: s.name, phone: s.phone, pinHash: s.pinHash, role: s.role,
        section: section[0],
        canViewProfit: values[0], canViewCost: values[1], canEditPrices: values[2],
        canManageExpenses: values[3], canManageInventory: values[4], canDeleteRecords: values[5],
        active: s.active, createdAt: s.createdAt,
      );
      await _repo.update(updated);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.name}\'s permissions updated')));
      _load();
    }
  }
}

/// A single numbered line in the "How this works" card.
class _HowStep extends StatelessWidget {
  final String number;
  final String text;
  final bool isLast;
  const _HowStep({required this.number, required this.text, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: AppColors.primaryBlue.withOpacity(0.12),
            child: Text(number, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primaryBlue)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondaryOf(context)))),
        ],
      ),
    );
  }
}
