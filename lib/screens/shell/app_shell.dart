import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
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

class _Destination {
  final String label;
  final IconData icon;
  final Widget screen;
  const _Destination(this.label, this.icon, this.screen);
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

  List<_Destination> get _destinations => <_Destination>[
    _Destination('Dashboard', Icons.dashboard_rounded, DashboardScreen(key: _dashboardKey)),
    const _Destination('Customers', Icons.people_alt_rounded, CustomerListScreen()),
    const _Destination('Services', Icons.build_rounded, ServiceListScreen()),
    const _Destination('Spare Parts', Icons.memory_rounded, SparePartsScreen()),
    const _Destination('Accessories', Icons.headset_rounded, AccessoriesScreen()),
    const _Destination('Sales Bills', Icons.receipt_long_rounded, SalesListScreen()),
    const _Destination('2nd Hand Mobile', Icons.phone_iphone_rounded, SecondHandListScreen()),
    const _Destination('Suppliers', Icons.local_shipping_rounded, SupplierScreen()),
    const _Destination('Purchases', Icons.shopping_cart_rounded, PurchaseListScreen()),
    const _Destination('Expenses', Icons.money_off_rounded, ExpenseScreen()),
    const _Destination('Profit & Loss', Icons.bar_chart_rounded, PnlDashboardScreen()),
    const _Destination('Settings', Icons.settings_rounded, SettingsScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final current = _destinations[_index];

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
                    Image.asset('assets/images/logo_color.png', height: 52),
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
                  itemCount: _destinations.length,
                  itemBuilder: (context, i) {
                    final d = _destinations[i];
                    final selected = i == _index;
                    return ListTile(
                      leading: Icon(d.icon, color: selected ? AppColors.primaryBlue : AppColors.textSecondary),
                      title: Text(d.label,
                          style: TextStyle(
                              color: selected ? AppColors.primaryBlue : AppColors.textPrimary,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                      selected: selected,
                      selectedTileColor: AppColors.primaryBlue.withOpacity(0.08),
                      onTap: () {
                        setState(() {
                          if (i == 0) _dashboardKey = UniqueKey();
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
        index: _index,
        children: _destinations.map((d) => d.screen).toList(),
      ),
    );
  }
}
