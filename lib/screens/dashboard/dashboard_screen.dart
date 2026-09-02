import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/pnl_service.dart';
import '../../core/repositories/service_repository.dart';
import '../../core/repositories/settings_repository.dart';
import '../../core/repositories/spare_part_repository.dart';
import '../../core/repositories/accessory_repository.dart';
import '../../core/repositories/second_hand_repository.dart';
import '../../models/service.dart';
import '../../models/second_hand_phone.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/section_card.dart';
import '../pnl/pnl_dashboard_screen.dart';
import '../quick/quick_history_screen.dart';
import '../quick/quick_transaction_screen.dart';
import '../services/service_list_screen.dart';

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
  final _settingsRepo = SettingsRepository();
  final _pdfService = PdfService();
  bool _testPrinting = false;

  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // One-time "Test Print?" nudge on first-ever app open (spec: "app first
    // time open pannumpothu test print option onnu venum, first print poda
    // late aaguthu athu check panna") - scheduled for after the first frame
    // so it never competes with this screen's own build/dialog context not
    // being ready yet. Settings -> Printing -> Test Print stays available
    // permanently afterwards; this is purely a one-time nudge, not the only
    // way to reach it (see _maybeShowTestPrintPrompt).
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTestPrintPrompt());
  }

  Future<void> _maybeShowTestPrintPrompt() async {
    final alreadyShown = await _settingsRepo.hasShownTestPrintPrompt();
    if (alreadyShown || !mounted) return;
    await _settingsRepo.markTestPrintPromptShown();
    if (!mounted) return;
    final doTest = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Test Print?'),
        content: const Text(
          'Oru bill-ku muthal murai print eduthaa, konjam late aagalam (printer warm-up '
          'aaga time edukkum). Ippove oru chinna test slip print panni printer connection '
          'check pannikonga - இது வேணும்னா Settings -> Printing -ல எப்பவும் use pannalam.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Test Print Now')),
        ],
      ),
    );
    if (doTest == true) await _runTestPrint();
  }

  /// Shared by the first-launch prompt above and Settings -> Printing's own
  /// Test Print button - builds and hands the same tiny test slip
  /// (PdfService.buildTestPrintPdf) to the OS print dialog. Best-effort:
  /// never throws out to the caller, since this is only a convenience check,
  /// not something that should ever crash the Dashboard.
  Future<void> _runTestPrint() async {
    if (_testPrinting) return;
    setState(() => _testPrinting = true);
    try {
      final bytes = await _pdfService.buildTestPrintPdf();
      await Printing.layoutPdf(format: PdfPageFormat.a5, name: 'Test_Print', onLayout: (format) async => bytes);
    } catch (_) {
      // Best-effort only - see doc comment above.
    } finally {
      if (mounted) setState(() => _testPrinting = false);
    }
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
              const SizedBox(height: 14),
              // Quick Income & Expense Entry (spec: "PRO SERVICE – Quick
              // Income & Expense Entry Feature") - fastest in-app path to
              // log a stray income/expense without opening a full service
              // bill or the Expenses screen. Refreshes the totals above the
              // moment a save completes, same as every other "did this
              // change the dashboard numbers?" flow on this screen.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.success),
                      onPressed: () async {
                        final saved = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(builder: (_) => const QuickTransactionScreen()),
                        );
                        if (saved == true) _refresh();
                      },
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: const Text('Quick Income'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                      onPressed: () async {
                        final saved = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(builder: (_) => const QuickTransactionScreen(startAsExpense: true)),
                        );
                        if (saved == true) _refresh();
                      },
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      label: const Text('Quick Expense'),
                    ),
                  ),
                ],
              ),
              // Dedicated Quick Income/Quick Expense history (spec: "quick
              // expenses and quick income ku thaniya oru history create
              // pannikkalam") - a small text link right under the two
              // buttons above, since it's a secondary "look back at what I
              // already entered" action, not a primary dashboard stat.
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const QuickHistoryScreen()),
                  ),
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: const Text('Quick History'),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    // Tappable - opens exactly which bills are still
                    // pending instead of just showing a count (spec:
                    // "pending service click panna entha bill pending la
                    // erukkunu kamikkanum").
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ServiceListScreen(pendingOnly: true)),
                      ),
                      child: _QuickStat(
                        title: 'Pending Services',
                        value: data.pendingServiceCount.toString(),
                        icon: Icons.build_circle_rounded,
                        color: AppColors.flameOrange,
                      ),
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
                      _miniStat('Total Devices', data.secondHandStock['totalPhones'] ?? 0, isCurrency: false),
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
