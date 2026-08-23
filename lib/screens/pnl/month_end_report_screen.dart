import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/db/database_helper.dart';
import '../../core/repositories/accessory_repository.dart';
import '../../core/repositories/second_hand_repository.dart';
import '../../core/repositories/spare_part_repository.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/pnl_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/section_card.dart';

/// Spec section 32 - one consolidated snapshot for the month, including
/// outstanding customer dues and inventory valuation alongside the P&L.
class MonthEndReportScreen extends StatefulWidget {
  const MonthEndReportScreen({super.key});

  @override
  State<MonthEndReportScreen> createState() => _MonthEndReportScreenState();
}

class _MonthEndReportScreenState extends State<MonthEndReportScreen> {
  final _pnl = PnlService();
  final _pdfService = PdfService();
  final _sparePartRepo = SparePartRepository();
  final _accessoryRepo = AccessoryRepository();
  final _secondHandRepo = SecondHandRepository();
  final _dbHelper = DatabaseHelper.instance;

  DateTime _monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
  BusinessTotals? _totals;
  double _outstanding = 0;
  double _inventoryValue = 0;
  double _secondHandStockValue = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final monthEnd = DateTime(_monthStart.year, _monthStart.month + 1, 1).subtract(const Duration(seconds: 1));
    final totals = await _pnl.totals(_monthStart, monthEnd);

    final db = await _dbHelper.database;
    // active = 1 filters keep a deleted service/sales-bill/2nd-hand-phone's
    // still-pending balance out of this total - otherwise deleting a bill
    // wouldn't actually remove its balance from Outstanding Customer
    // Payments, even though it no longer shows anywhere in the app.
    final serviceBalances = await db.rawQuery('SELECT COALESCE(SUM(balance),0) as total FROM services WHERE balance > 0 AND active = 1');
    final salesBalances = await db.rawQuery('SELECT COALESCE(SUM(balance),0) as total FROM sales_bills WHERE balance > 0 AND active = 1');
    final shBalances = await db.rawQuery(
      'SELECT COALESCE(SUM(s.balance),0) as total FROM second_hand_sales s '
      'JOIN second_hand_phones p ON p.id = s.phone_id '
      'WHERE s.balance > 0 AND p.active = 1',
    );
    final outstanding = (serviceBalances.first['total'] as num).toDouble() +
        (salesBalances.first['total'] as num).toDouble() +
        (shBalances.first['total'] as num).toDouble();

    final spareParts = await _sparePartRepo.all();
    final accessories = await _accessoryRepo.all();
    final inventoryValue = spareParts.fold<double>(0, (s, p) => s + p.stockValue) + accessories.fold<double>(0, (s, a) => s + a.stockValue);

    final shStock = await _secondHandRepo.stockSummary();

    setState(() {
      _totals = totals;
      _outstanding = outstanding;
      _inventoryValue = inventoryValue;
      _secondHandStockValue = shStock['currentStockValue'] ?? 0;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Month-End Business Report'),
        actions: [
          IconButton(icon: const Icon(Icons.print_rounded), onPressed: _print),
        ],
      ),
      body: _loading || _totals == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(formatMonthLabel(_monthStart), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_month_rounded),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _monthStart,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDatePickerMode: DatePickerMode.year,
                      );
                      if (picked != null) {
                        setState(() => _monthStart = DateTime(picked.year, picked.month, 1));
                        _load();
                      }
                    },
                  ),
                ),
                SectionCard(title: 'By Category', icon: Icons.category_rounded, children: [
                  _catBlock('Service', _totals!.service),
                  const Divider(),
                  _catBlock('Accessories', _totals!.accessories),
                  const Divider(),
                  _catBlock('Mobile Sales', _totals!.secondHand),
                  const Divider(),
                  _catBlock('Other', _totals!.other),
                ]),
                SectionCard(title: 'Overall', icon: Icons.summarize_rounded, children: [
                  _line('TOTAL REVENUE', _totals!.totalRevenue, bold: true),
                  _line('TOTAL COST', _totals!.totalDirectCost, bold: true),
                  _line('GROSS PROFIT', _totals!.grossProfit, bold: true),
                  _line('TOTAL EXPENSE', _totals!.operatingExpenses, bold: true),
                  const Divider(),
                  _line('NET PROFIT', _totals!.netProfit, bold: true, big: true),
                ]),
                SectionCard(title: 'Balances', icon: Icons.account_balance_wallet_rounded, children: [
                  _line('Outstanding Customer Payments', _outstanding),
                  _line('Inventory Value (Spare Parts + Accessories)', _inventoryValue),
                  _line('Mobile & Laptop Stock Value', _secondHandStockValue),
                ]),
              ],
            ),
    );
  }

  Widget _catBlock(String label, CategorySummary c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            _line('Revenue', c.revenue),
            _line('Cost', c.cost),
            _line('Profit', c.netProfit),
          ],
        ),
      );

  Widget _line(String label, double value, {bool bold = false, bool big = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontSize: big ? 15 : 13)),
            Text(formatCurrency(value),
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  fontSize: big ? 17 : 13,
                  color: value < 0 ? AppColors.danger : AppColors.textPrimaryOf(context),
                )),
          ],
        ),
      );

  Future<void> _print() async {
    final bytes = await _pdfService.buildPnlReport(periodLabel: formatMonthLabel(_monthStart), totals: _totals!);
    await Printing.layoutPdf(name: 'MonthEnd_${formatMonthLabel(_monthStart)}', onLayout: (format) async => bytes);
  }
}
