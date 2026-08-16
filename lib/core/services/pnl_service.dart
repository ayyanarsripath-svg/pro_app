import '../db/database_helper.dart';
import '../../models/ledger_transaction.dart';
import '../repositories/second_hand_repository.dart';

class CategorySummary {
  final String label;
  final double revenue;
  final double cost;
  final double expenses;

  CategorySummary({
    required this.label,
    required this.revenue,
    required this.cost,
    required this.expenses,
  });

  double get grossProfit => revenue - cost;
  double get netProfit => grossProfit - expenses;

  CategorySummary operator +(CategorySummary other) => CategorySummary(
        label: 'Combined',
        revenue: revenue + other.revenue,
        cost: cost + other.cost,
        expenses: expenses + other.expenses,
      );

  static CategorySummary zero(String label) =>
      CategorySummary(label: label, revenue: 0, cost: 0, expenses: 0);
}

class BusinessTotals {
  final CategorySummary service;
  final CategorySummary accessories;
  final CategorySummary secondHand;
  final CategorySummary other;
  final double generalExpenses;

  BusinessTotals({
    required this.service,
    required this.accessories,
    required this.secondHand,
    required this.other,
    required this.generalExpenses,
  });

  double get totalRevenue => service.revenue + accessories.revenue + secondHand.revenue + other.revenue;
  double get totalDirectCost => service.cost + accessories.cost + secondHand.cost + other.cost;
  double get grossProfit => totalRevenue - totalDirectCost;
  double get categoryExpenses => service.expenses + accessories.expenses + secondHand.expenses + other.expenses;
  double get operatingExpenses => categoryExpenses + generalExpenses;
  double get netProfit => grossProfit - operatingExpenses;

  List<CategorySummary> get categories => [service, accessories, secondHand, other];
}

/// Reads the unified ledger (+ 2nd-hand phone records for realized-vs-
/// potential profit) to compute every Profit & Loss view in the spec:
/// daily / weekly / monthly / custom range, category cards, the summary
/// table, month comparisons and the month-end report.
class PnlService {
  final _dbHelper = DatabaseHelper.instance;
  final _secondHand = SecondHandRepository();

  Future<CategorySummary> _standardCategorySummary({
    required String label,
    required String category,
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'ledger_transactions',
      where: 'category = ? AND txn_date >= ? AND txn_date <= ?',
      whereArgs: [category, from.toIso8601String(), to.toIso8601String()],
    );

    double revenue = 0, cost = 0, expenses = 0;
    for (final row in rows) {
      final amount = (row['amount'] as num).toDouble();
      switch (row['txn_type'] as String) {
        case LedgerTxnType.revenue:
          revenue += amount;
          break;
        case LedgerTxnType.directCost:
          cost += amount;
          break;
        case LedgerTxnType.expenseTxn:
          expenses += amount;
          break;
        case LedgerTxnType.returnTxn:
          revenue += amount; // stored as negative
          break;
      }
    }
    return CategorySummary(label: label, revenue: revenue, cost: cost, expenses: expenses);
  }

  Future<CategorySummary> serviceSummary(DateTime from, DateTime to) =>
      _standardCategorySummary(label: 'Service', category: LedgerCategory.service, from: from, to: to);

  Future<CategorySummary> accessoriesSummary(DateTime from, DateTime to) =>
      _standardCategorySummary(label: 'Accessories', category: LedgerCategory.accessories, from: from, to: to);

  Future<CategorySummary> otherSummary(DateTime from, DateTime to) =>
      _standardCategorySummary(label: 'Other Sales', category: LedgerCategory.other, from: from, to: to);

  /// 2nd Hand uses realized accounting: cost = total investment of phones
  /// that actually SOLD within the range (regardless of purchase date),
  /// never the investment of still-unsold stock (spec section 9/30).
  Future<CategorySummary> secondHandSummary(DateTime from, DateTime to) async {
    final db = await _dbHelper.database;
    final saleRows = await db.query(
      'second_hand_sales',
      where: 'sale_date >= ? AND sale_date <= ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
    );

    double revenue = 0, cost = 0;
    for (final row in saleRows) {
      revenue += (row['sale_price'] as num).toDouble();
      final phone = await _secondHand.byId(row['phone_id'] as String);
      if (phone != null) cost += phone.totalInvestment;
    }

    final returnRows = await db.query(
      'ledger_transactions',
      where: "category = ? AND txn_type = ? AND txn_date >= ? AND txn_date <= ?",
      whereArgs: [LedgerCategory.secondHand, LedgerTxnType.returnTxn, from.toIso8601String(), to.toIso8601String()],
    );
    for (final row in returnRows) {
      revenue += (row['amount'] as num).toDouble(); // stored negative
    }

    final expenseRows = await db.query(
      'ledger_transactions',
      where: "category = ? AND txn_type = ? AND txn_date >= ? AND txn_date <= ?",
      whereArgs: [LedgerCategory.secondHand, LedgerTxnType.expenseTxn, from.toIso8601String(), to.toIso8601String()],
    );
    final expenses = expenseRows.fold<double>(0, (s, r) => s + (r['amount'] as num).toDouble());

    return CategorySummary(label: '2nd Hand Mobile', revenue: revenue, cost: cost, expenses: expenses);
  }

  Future<double> generalExpenses(DateTime from, DateTime to) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'ledger_transactions',
      where: "category = ? AND txn_type = ? AND txn_date >= ? AND txn_date <= ?",
      whereArgs: [LedgerCategory.expense, LedgerTxnType.expenseTxn, from.toIso8601String(), to.toIso8601String()],
    );
    return rows.fold<double>(0, (s, r) => s + (r['amount'] as num).toDouble());
  }

  Future<BusinessTotals> totals(DateTime from, DateTime to) async {
    final service = await serviceSummary(from, to);
    final accessories = await accessoriesSummary(from, to);
    final secondHand = await secondHandSummary(from, to);
    final other = await otherSummary(from, to);
    final general = await generalExpenses(from, to);
    return BusinessTotals(
      service: service,
      accessories: accessories,
      secondHand: secondHand,
      other: other,
      generalExpenses: general,
    );
  }

  /// This month's raw 2nd-hand cash-flow stats (spec section 9): how many
  /// phones were bought this period and how much was invested, independent
  /// of whether they've sold yet.
  Future<Map<String, double>> secondHandPeriodInvestmentStats(DateTime from, DateTime to) async {
    final db = await _dbHelper.database;
    final purchaseRows = await db.query(
      'second_hand_phones',
      where: 'purchase_date >= ? AND purchase_date <= ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
    );
    double purchaseCost = 0;
    for (final row in purchaseRows) {
      purchaseCost += (row['purchase_price'] as num?)?.toDouble() ?? 0;
    }

    final investmentRows = await db.query(
      'ledger_transactions',
      where: "category = ? AND txn_type = ? AND txn_date >= ? AND txn_date <= ? AND description LIKE 'Repair:%'",
      whereArgs: [LedgerCategory.secondHand, LedgerTxnType.investment, from.toIso8601String(), to.toIso8601String()],
    );
    final repairCost = investmentRows.fold<double>(0, (s, r) => s + (r['amount'] as num).toDouble());

    final saleRows = await db.query(
      'second_hand_sales',
      where: 'sale_date >= ? AND sale_date <= ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
    );

    return {
      'phonesPurchased': purchaseRows.length.toDouble(),
      'purchaseCost': purchaseCost,
      'repairCost': repairCost,
      'totalInvestment': purchaseCost + repairCost,
      'phonesSold': saleRows.length.toDouble(),
    };
  }

  /// Month-over-month comparison (spec section 17).
  Future<Map<String, BusinessTotals>> compareMonths(DateTime currentMonthStart, DateTime previousMonthStart) async {
    final currentEnd = DateTime(currentMonthStart.year, currentMonthStart.month + 1, 1)
        .subtract(const Duration(seconds: 1));
    final previousEnd = DateTime(previousMonthStart.year, previousMonthStart.month + 1, 1)
        .subtract(const Duration(seconds: 1));
    final current = await totals(currentMonthStart, currentEnd);
    final previous = await totals(previousMonthStart, previousEnd);
    return {'current': current, 'previous': previous};
  }
}
