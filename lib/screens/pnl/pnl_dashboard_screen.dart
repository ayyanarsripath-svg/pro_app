import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/repositories/other_sales_repository.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/pnl_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/section_card.dart';
import '../../widgets/stat_card.dart';
import 'month_end_report_screen.dart';

enum _RangePreset { today, thisWeek, thisMonth, previousMonth, custom }

class PnlDashboardScreen extends StatefulWidget {
  const PnlDashboardScreen({super.key});

  @override
  State<PnlDashboardScreen> createState() => _PnlDashboardScreenState();
}

class _PnlDashboardScreenState extends State<PnlDashboardScreen> {
  final _pnl = PnlService();
  final _pdfService = PdfService();
  final _otherSalesRepo = OtherSalesRepository();

  _RangePreset _preset = _RangePreset.thisMonth;
  late DateTime _from;
  late DateTime _to;
  BusinessTotals? _totals;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _applyPreset(_RangePreset.thisMonth);
  }

  void _applyPreset(_RangePreset preset) {
    final now = DateTime.now();
    switch (preset) {
      case _RangePreset.today:
        _from = DateTime(now.year, now.month, now.day);
        _to = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case _RangePreset.thisWeek:
        final weekday = now.weekday;
        _from = DateTime(now.year, now.month, now.day).subtract(Duration(days: weekday - 1));
        _to = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case _RangePreset.thisMonth:
        _from = DateTime(now.year, now.month, 1);
        _to = DateTime(now.year, now.month + 1, 1).subtract(const Duration(seconds: 1));
        break;
      case _RangePreset.previousMonth:
        _from = DateTime(now.year, now.month - 1, 1);
        _to = DateTime(now.year, now.month, 1).subtract(const Duration(seconds: 1));
        break;
      case _RangePreset.custom:
        break;
    }
    setState(() => _preset = preset);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final totals = await _pnl.totals(_from, _to);
    setState(() {
      _totals = totals;
      _loading = false;
    });
  }

  Future<void> _pickCustomRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (range != null) {
      setState(() {
        _from = range.start;
        _to = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
        _preset = _RangePreset.custom;
      });
      _load();
    }
  }

  String get _periodLabel {
    switch (_preset) {
      case _RangePreset.today:
        return 'Today - ${formatDate(_from)}';
      case _RangePreset.thisWeek:
        return 'This Week (${formatDate(_from)} - ${formatDate(_to)})';
      case _RangePreset.thisMonth:
        return formatMonthLabel(_from);
      case _RangePreset.previousMonth:
        return formatMonthLabel(_from);
      case _RangePreset.custom:
        return '${formatDate(_from)} - ${formatDate(_to)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (!auth.canSeeProfit) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, size: 48, color: AppColors.textSecondary),
                const SizedBox(height: 12),
                const Text('Profit & Loss is restricted', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 6),
                const Text('Ask an Admin to grant "View Profit" access to your account.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addOtherSale,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Other Sale'),
      ),
      body: _loading || _totals == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _rangeSelector(),
                  const SizedBox(height: 6),
                  Text(_periodLabel, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                  const SizedBox(height: 14),
                  _categoryCards(),
                  const SizedBox(height: 18),
                  _totalBusinessCard(),
                  const SizedBox(height: 18),
                  _revenueChart(),
                  const SizedBox(height: 18),
                  _table(),
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _printReport,
                        icon: const Icon(Icons.print_rounded),
                        label: const Text('Print / PDF'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MonthEndReportScreen())),
                        icon: const Icon(Icons.summarize_rounded),
                        label: const Text('Month-End Report'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _rangeSelector() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _presetChip('Today', _RangePreset.today),
          _presetChip('This Week', _RangePreset.thisWeek),
          _presetChip('This Month', _RangePreset.thisMonth),
          _presetChip('Previous Month', _RangePreset.previousMonth),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: const Text('Custom Range'),
              selected: _preset == _RangePreset.custom,
              onSelected: (_) => _pickCustomRange(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String label, _RangePreset preset) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(label: Text(label), selected: _preset == preset, onSelected: (_) => _applyPreset(preset)),
      );

  Widget _categoryCards() {
    final t = _totals!;
    return Column(
      children: [
        _categoryCard('SERVICE', t.service, AppColors.primaryBlue, Icons.build_rounded),
        const SizedBox(height: 10),
        _categoryCard('ACCESSORIES', t.accessories, AppColors.flameOrange, Icons.headset_rounded),
        const SizedBox(height: 10),
        _categoryCard('2ND HAND MOBILE', t.secondHand, AppColors.accentPurple, Icons.phone_iphone_rounded),
        const SizedBox(height: 10),
        _categoryCard('OTHER SALES', t.other, AppColors.info, Icons.sell_rounded),
      ],
    );
  }

  Widget _categoryCard(String title, CategorySummary c, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: color, letterSpacing: 0.5)),
          ]),
          const SizedBox(height: 10),
          Row(
            children: [
              _cellStat('Revenue', c.revenue),
              _cellStat('Cost', c.cost),
              _cellStat('Profit', c.netProfit, highlight: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cellStat(String label, double value, {bool highlight = false}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(
              formatCurrency(value),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                color: highlight ? (value < 0 ? AppColors.danger : AppColors.success) : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      );

  Widget _totalBusinessCard() {
    final t = _totals!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TOTAL BUSINESS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
          const SizedBox(height: 12),
          _grandRow('Total Revenue', t.totalRevenue),
          _grandRow('Total Direct Cost', t.totalDirectCost),
          _grandRow('Gross Profit', t.grossProfit),
          _grandRow('Operating Expenses', t.operatingExpenses),
          const Divider(color: Colors.white38),
          _grandRow('NET PROFIT', t.netProfit, big: true),
        ],
      ),
    );
  }

  Widget _grandRow(String label, double value, {bool big = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: big ? 14 : 12.5, fontWeight: big ? FontWeight.w800 : FontWeight.w500)),
            Text(formatCurrency(value), style: TextStyle(color: Colors.white, fontSize: big ? 18 : 13.5, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _revenueChart() {
    final t = _totals!;
    final entries = [
      ('Service', t.service.revenue, AppColors.primaryBlue),
      ('Accessories', t.accessories.revenue, AppColors.flameOrange),
      ('2nd Hand', t.secondHand.revenue, AppColors.accentPurple),
      ('Other', t.other.revenue, AppColors.info),
    ];
    final maxVal = entries.map((e) => e.$2).fold<double>(0, (a, b) => a > b ? a : b);

    return SectionCard(
      title: 'Monthly Revenue by Category',
      icon: Icons.bar_chart_rounded,
      children: [
        SizedBox(
          height: 160,
          child: BarChart(
            BarChartData(
              maxY: maxVal <= 0 ? 100 : maxVal * 1.25,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= entries.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(entries[i].$1, style: const TextStyle(fontSize: 10)),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (int i = 0; i < entries.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(toY: entries[i].$2, color: entries[i].$3, width: 26, borderRadius: BorderRadius.circular(4)),
                  ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _table() {
    final t = _totals!;
    return SectionCard(
      title: 'Monthly P&L Table',
      icon: Icons.table_chart_rounded,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 36,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 40,
            columns: const [
              DataColumn(label: Text('Category')),
              DataColumn(label: Text('Revenue')),
              DataColumn(label: Text('Cost')),
              DataColumn(label: Text('Gross Profit')),
              DataColumn(label: Text('Expenses')),
              DataColumn(label: Text('Net Profit')),
            ],
            rows: [
              _dataRow('Service', t.service),
              _dataRow('Accessories', t.accessories),
              _dataRow('2nd Hand', t.secondHand),
              _dataRow('Other Sales', t.other),
              DataRow(cells: [
                const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w800))),
                DataCell(Text(formatCurrency(t.totalRevenue), style: const TextStyle(fontWeight: FontWeight.w800))),
                DataCell(Text(formatCurrency(t.totalDirectCost), style: const TextStyle(fontWeight: FontWeight.w800))),
                DataCell(Text(formatCurrency(t.grossProfit), style: const TextStyle(fontWeight: FontWeight.w800))),
                DataCell(Text(formatCurrency(t.categoryExpenses + t.generalExpenses), style: const TextStyle(fontWeight: FontWeight.w800))),
                DataCell(Text(formatCurrency(t.netProfit), style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  DataRow _dataRow(String label, CategorySummary c) => DataRow(cells: [
        DataCell(Text(label)),
        DataCell(Text(formatCurrency(c.revenue))),
        DataCell(Text(formatCurrency(c.cost))),
        DataCell(Text(formatCurrency(c.grossProfit))),
        DataCell(Text(formatCurrency(c.expenses))),
        DataCell(Text(formatCurrency(c.netProfit))),
      ]);

  Future<void> _addOtherSale() async {
    final descCtrl = TextEditingController();
    final revenueCtrl = TextEditingController();
    final costCtrl = TextEditingController(text: '0');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Other Sale'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description (e.g. Laptop sold)')),
            const SizedBox(height: 10),
            TextField(controller: revenueCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Revenue (₹)')),
            const SizedBox(height: 10),
            TextField(controller: costCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cost (₹, optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok == true && descCtrl.text.trim().isNotEmpty) {
      await _otherSalesRepo.recordEntry(
        date: DateTime.now(),
        description: descCtrl.text.trim(),
        revenue: double.tryParse(revenueCtrl.text.trim()) ?? 0,
        cost: double.tryParse(costCtrl.text.trim()) ?? 0,
      );
      _load();
    }
  }

  Future<void> _printReport() async {
    final bytes = await _pdfService.buildPnlReport(periodLabel: _periodLabel, totals: _totals!);
    await Printing.layoutPdf(onLayout: (format) async => bytes);
  }
}
