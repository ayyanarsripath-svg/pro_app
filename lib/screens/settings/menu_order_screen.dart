import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/menu_order_service.dart';
import '../../core/theme/app_theme.dart';

/// One entry the shop can drag to reorder. Kept as a small standalone list
/// here (rather than importing AppShell's private _Destination) so this
/// screen only needs ids + display info, not the actual screen widgets.
class MenuItemInfo {
  final String id;
  final String label;
  final IconData icon;
  const MenuItemInfo(this.id, this.label, this.icon);
}

const List<MenuItemInfo> kMenuItems = [
  MenuItemInfo('dashboard', 'Dashboard', Icons.dashboard_rounded),
  MenuItemInfo('customers', 'Customers', Icons.people_alt_rounded),
  MenuItemInfo('services', 'Services', Icons.build_rounded),
  MenuItemInfo('spare_parts', 'Spare Parts', Icons.memory_rounded),
  MenuItemInfo('accessories', 'Accessories', Icons.headset_rounded),
  MenuItemInfo('sales', 'Sales Bills', Icons.receipt_long_rounded),
  MenuItemInfo('second_hand', '2nd Hand Mobile', Icons.phone_iphone_rounded),
  MenuItemInfo('suppliers', 'Suppliers', Icons.local_shipping_rounded),
  MenuItemInfo('purchases', 'Purchases', Icons.shopping_cart_rounded),
  MenuItemInfo('expenses', 'Expenses', Icons.money_off_rounded),
  MenuItemInfo('pnl', 'Profit & Loss', Icons.bar_chart_rounded),
  MenuItemInfo('settings', 'Settings', Icons.settings_rounded),
];

/// Lets the shop drag their most-used screens to the top of the drawer
/// menu instead of always scrolling past ones they rarely open (spec
/// request: "move/adjust the menu list myself, bring what I use often up
/// to the top, from Settings"). Saved order is picked up by AppShell's
/// drawer immediately - no restart needed.
class MenuOrderScreen extends StatefulWidget {
  const MenuOrderScreen({super.key});

  @override
  State<MenuOrderScreen> createState() => _MenuOrderScreenState();
}

class _MenuOrderScreenState extends State<MenuOrderScreen> {
  late List<MenuItemInfo> _items;

  @override
  void initState() {
    super.initState();
    final order = context.read<MenuOrderService>().applyTo(kMenuItems.map((m) => m.id).toList());
    final byId = {for (final m in kMenuItems) m.id: m};
    _items = order.map((id) => byId[id]!).toList();
  }

  Future<void> _save() async {
    await context.read<MenuOrderService>().setOrder(_items.map((m) => m.id).toList());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Menu order saved')));
      Navigator.pop(context);
    }
  }

  Future<void> _resetToDefault() async {
    setState(() => _items = List.of(kMenuItems));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customize Menu'),
        actions: [
          TextButton(
            onPressed: _resetToDefault,
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: AppColors.primaryBlue.withOpacity(0.06),
            child: Text(
              'Press and hold the handle, then drag to reorder. Put the screens you open most often at the top - the drawer menu will show them in this order.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondaryOf(context)),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: _items.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _items.removeAt(oldIndex);
                  _items.insert(newIndex, item);
                });
              },
              itemBuilder: (context, i) {
                final m = _items[i];
                return ListTile(
                  key: ValueKey(m.id),
                  leading: Icon(m.icon, color: AppColors.primaryBlue),
                  title: Text(m.label),
                  trailing: const Icon(Icons.drag_handle_rounded),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('Save Order'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
