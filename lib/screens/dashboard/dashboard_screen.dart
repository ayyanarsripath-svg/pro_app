import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/pnl_service.dart';
import '../../core/repositories/service_repository.dart';
import '../../core/repositories/spare_part_repository.dart';
import '../../core/repositories/accessory_repository.dart';
import '../../core/repositories/second_hand_repository.dart';
import '../../models/service.dart';
import '../../models/second_hand_phone.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/section_card.dart';
import '../pnl/pnl_dashboard_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _pnl = PnlService();
  final _services = ServiceRepository();
  final _spareParts = SparePartRepository();
  final _accessories = AccessoryRepository();
  final _secondHand = SecondHandRepository();

  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final totals = await _pnl.totals(todayStart, todayEnd);
    final activeServices = await _services.all();
    final pending = activeServices.where((s) => s.status != ServiceStatus.delivered && s.status != ServiceStatus.cancelled).toList();
    final lowSpareParts = await _spareParts.lowStock();
    final lowAccessories = await _accessories.lowStock();
    final shStock = await _secondHand.stockSummary();
    final recentServices = activeServices.take(5).toList();

    return _DashboardData(
      totals: totals,
      pendingServiceCount: pending.length,
      lowStockCount: lowSpareParts.length + lowAccessories.length,
      secondHandStock: shStock,
      recentServices: recentServices,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<_DashboardData>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final data = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text("Today's Business", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.5,
                children: [
                  StatCard(label: "Today's Revenue", value: data.totals.totalRevenue, icon: Icons.trending_up_rounded, color: AppColors.success),
                  StatCard(label: "Today's Cost", value: data.totals.totalDirectCost, icon: Icons.inventory_2_rounded, color: AppColors.warning),
                  StatCard(label: "Gross Profit", value: data.totals.grossProfit, icon: Icons.savings_rounded, color: AppColors.info),
                  StatCard(label: "Net Profit", value: data.totals.netProfit, icon: Icons.account_balance_wallet_rounded, color: AppColors.accentPurple),
                ],
              ),
              if (!auth.canSeeProfit)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Profit figures are hidden for your account. Ask Admin for access.',
                      style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 11.5)),
                ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _QuickStat(
                      title: 'Pending Services',
                      value: data.pendingServiceCount.toString(),
                      icon: Icons.build_circle_rounded,
                      color: AppColors.flameOrange,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickStat(
                      title: 'Low Stock Alerts',
                      value: data.lowStockCount.toString(),
                      icon: Icons.warning_amber_rounded,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SectionCard(
                title: 'Mobile & Laptop Stock',
                icon: Icons.phone_iphone_rounded,
                children: [
                  Row(
                    children: [
                      _miniStat('Total Phones', data.secondHandStock['totalPhones'] ?? 0, isCurrency: false),
                      _miniStat('Unsold', data.secondHandStock['unsoldCount'] ?? 0, isCurrency: false),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _miniStat('Stock Value', data.secondHandStock['currentStockValue'] ?? 0),
                      _miniStat('Potential Profit', data.secondHandStock['potentialProfit'] ?? 0),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Services', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  TextButton(
                    onPressed: () => Navigator.of(context, rootNavigator: false).push(
                      MaterialPageRoute(builder: (_) => const PnlDashboardScreen()),
                    ),
                    child: const Text('View Full P&L'),
                  ),
                ],
              ),
              ...data.recentServices.map((s) => Card(
                    child: ListTile(
                      title: Text('${s.billNo} - ${s.mobileName ?? ''}'),
                      subtitle: Text(s.complaint ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: StatusBadge(s.status, fontSize: 10),
                    ),
                  )),
              if (data.recentServices.isEmpty) const EmptyState(icon: Icons.build_rounded, message: 'No services yet'),
            ],
          );
        },
      ),
    );
  }

  Widget _miniStat(String label, double value, {bool isCurrency = true}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.textSecondaryOf(context))),
          const SizedBox(height: 2),
          Text(
            isCurrency ? '₹${value.toStringAsFixed(0)}' : value.toStringAsFixed(0),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _QuickStat extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _QuickStat({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
                Text(title, style: TextStyle(fontSize: 11.5, color: AppColors.textSecondaryOf(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardData {
  final BusinessTotals totals;
  final int pendingServiceCount;
  final int lowStockCount;
  final Map<String, double> secondHandStock;
  final List<ServiceJob> recentServices;

  _DashboardData({
    required this.totals,
    required this.pendingServiceCount,
    required this.lowStockCount,
    required this.secondHandStock,
    required this.recentServices,
  });
}
