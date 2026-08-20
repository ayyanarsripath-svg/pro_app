import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/logo_service.dart';
import '../../core/services/menu_order_service.dart';
import '../dashboard/dashboard_screen.dart';
import '../customers/customer_list_screen.dart';
import '../services/service_list_screen.dart';
import '../inventory/spare_parts_screen.dart';
import '../inventory/accessories_screen.dart';
import '../sales/sales_list_screen.dart';
import '../second_hand/second_hand_list_screen.dart';
import '../suppliers/supplier_screen.dart';
import '../suppliers/purchase_list_screen.dart';
import '../expenses/expense_screen.dart';
import '../pnl/pnl_dashboard_screen.dart';
import '../settings/settings_screen.dart';

/// [id] is a stable identifier used to persist the shop's chosen menu
/// order (see [MenuOrderService]) - it never changes even though [label]
/// or the item's position on screen can, so a saved order always maps back
/// to the right screen.
class _Destination {
  final String id;
  final String label;
  final IconData icon;
  final Widget screen;
  const _Destination(this.id, this.label, this.icon, this.screen);
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  // A fresh key forces DashboardScreen to rebuild its State (and refetch)
  // rather than reusing the one IndexedStack has kept alive since app
  // launch - without this, marking a job Delivered (or any other data
  // change) never showed up on the dashboard until the app was restarted.
  Key _dashboardKey = UniqueKey();

  // The full, fixed set of menu items in their built-in default order.
  // MenuOrderService only ever reorders this list for display - it's never
  // used to decide which screens exist, so a saved order can never hide or
  // lose one.
  List<_Destination> get _baseDestinations => <_Destination>[
    _Destination('dashboard', 'Dashboard', Icons.dashboard_rounded, DashboardScreen(key: _dashboardKey)),
    const _Destination('customers', 'Customers', Icons.people_alt_rounded, CustomerListScreen()),
    const _Destination('services', 'Services', Icons.build_rounded, ServiceListScreen()),
    const _Destination('spare_parts', 'Spare Parts', Icons.memory_rounded, SparePartsScreen()),
    const _Destination('accessories', 'Accessories', Icons.headset_rounded, AccessoriesScreen()),
    const _Destination('sales', 'Sales Bills', Icons.receipt_long_rounded, SalesListScreen()),
    const _Destination('second_hand', '2nd Hand Mobile', Icons.phone_iphone_rounded, SecondHandListScreen()),
    const _Destination('suppliers', 'Suppliers', Icons.local_shipping_rounded, SupplierScreen()),
    const _Destination('purchases', 'Purchases', Icons.shopping_cart_rounded, PurchaseListScreen()),
    const _Destination('expenses', 'Expenses', Icons.money_off_rounded, ExpenseScreen()),
    const _Destination('pnl', 'Profit & Loss', Icons.bar_chart_rounded, PnlDashboardScreen()),
    const _Destination('settings', 'Settings', Icons.settings_rounded, SettingsScreen()),
  ];

  /// [_baseDestinations] reordered to match the shop's saved preference
  /// (Settings -> Customize Menu), if any.
  List<_Destination> _orderedDestinations(MenuOrderService menuOrder) {
    final base = _baseDestinations;
    final byId = {for (final d in base) d.id: d};
    final orderedIds = menuOrder.applyTo(base.map((d) => d.id).toList());
    return orderedIds.map((id) => byId[id]!).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final logo = context.watch<LogoService>();
    final menuOrder = context.watch<MenuOrderService>();
    final destinations = _orderedDestinations(menuOrder);
    // _index is a position in this ordered list, not a fixed screen - if
    // the shop changes the order while sitting on a non-Dashboard tab, the
    // previous index would silently point at a different screen. Clamping
    // is enough here since _index only ever changes via taps within range.
    // (Written out instead of int.clamp(), which returns num and would not
    // type-check as a List index.)
    final safeIndex = _index < 0 ? 0 : (_index >= destinations.length ? destinations.length - 1 : _index);
    final current = destinations[safeIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(current.label),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Chip(
                avatar: Icon(auth.isAdmin ? Icons.shield_rounded : Icons.badge_rounded, size: 16, color: Colors.white),
                label: Text(auth.current?.name ?? '', style: const TextStyle(color: Colors.white, fontSize: 12)),
                backgroundColor: Colors.white.withOpacity(0.15),
                side: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(gradient: AppColors.brandGradient),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Shown at its full aspect ratio (BoxFit.contain) inside
                    // a taller box than before, so a custom shop photo with
                    // a different shape than the original square logo is
                    // never squeezed down to a sliver - it always displays
                    // as large as the header allows without being cropped.
                    SizedBox(
                      height: 68,
                      width: double.infinity,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: logo.hasCustomLogo
                            ? Image.file(logo.logoFile!, height: 68, fit: BoxFit.contain)
                            : Image.asset('assets/images/logo_color.png', height: 68, fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('PROFESSIONAL MOBILES',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                    const Text('& Laptop Service', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: destinations.length,
                  itemBuilder: (context, i) {
                    final d = destinations[i];
                    final selected = i == _index;
                    return ListTile(
                      leading: Icon(d.icon, color: selected ? AppColors.primaryBlue : AppColors.textSecondaryOf(context)),
                      title: Text(d.label,
                          style: TextStyle(
                              color: selected ? AppColors.primaryBlue : AppColors.textPrimaryOf(context),
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                      selected: selected,
                      selectedTileColor: AppColors.primaryBlue.withOpacity(0.08),
                      onTap: () {
                        setState(() {
                          if (d.id == 'dashboard') _dashboardKey = UniqueKey();
                          _index = i;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: AppColors.danger),
                title: const Text('Lock App', style: TextStyle(color: AppColors.danger)),
                onTap: () {
                  Navigator.pop(context);
                  context.read<AuthService>().logout();
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: safeIndex,
        children: destinations.map((d) => d.screen).toList(),
      ),
    );
  }
}
