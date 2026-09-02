import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/expense.dart';
import '../../models/ledger_transaction.dart';
import 'ledger_repository.dart';

/// Expenses feed straight into Profit & Loss. A "general" allocation only
/// reduces overall Net Profit; a category-specific allocation also reduces
/// that category's own P&L (spec section 14).
class ExpenseRepository {
  final _dbHelper = DatabaseHelper.instance;
  final _ledger = LedgerRepository();

  String _ledgerCategoryFor(String allocation) {
    switch (allocation) {
      case ExpenseAllocation.service:
        return LedgerCategory.service;
      case ExpenseAllocation.accessories:
        return LedgerCategory.accessories;
      case ExpenseAllocation.secondHand:
        return LedgerCategory.secondHand;
      case ExpenseAllocation.other:
        return LedgerCategory.other;
      case ExpenseAllocation.general:
      default:
        return LedgerCategory.expense;
    }
  }

  Future<Expense> create({
    required DateTime expenseDate,
    required String category,
    required double amount,
    String? paymentMethod,
    String? description,
    String allocation = ExpenseAllocation.general,
    String? source,
  }) async {
    final db = await _dbHelper.database;
    final expense = Expense(
      id: newId(),
      expenseDate: expenseDate,
      category: category,
      amount: amount,
      paymentMethod: paymentMethod,
      description: description,
      allocation: allocation,
      source: source,
      createdAt: DateTime.now(),
    );
    await db.insert('expenses', expense.toMap());

    await _ledger.record(
      txnDate: expenseDate,
      category: _ledgerCategoryFor(allocation),
      txnType: LedgerTxnType.expenseTxn,
      referenceType: 'expense',
      referenceId: expense.id,
      amount: amount,
      description: '$category${description != null ? ' - $description' : ''}',
    );

    return expense;
  }

  Future<void> update(Expense expense) async {
    final db = await _dbHelper.database;
    await db.update('expenses', expense.toMap(), where: 'id = ?', whereArgs: [expense.id]);
    await _ledger.clearForReference('expense', expense.id);
    await _ledger.record(
      txnDate: expense.expenseDate,
      category: _ledgerCategoryFor(expense.allocation),
      txnType: LedgerTxnType.expenseTxn,
      referenceType: 'expense',
      referenceId: expense.id,
      amount: expense.amount,
      description: '${expense.category}${expense.description != null ? ' - ${expense.description}' : ''}',
    );
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
    await _ledger.clearForReference('expense', id);
  }

  Future<List<Expense>> all({DateTime? from, DateTime? to}) async {
    final db = await _dbHelper.database;
    if (from != null && to != null) {
      final rows = await db.query(
        'expenses',
        where: 'expense_date >= ? AND expense_date <= ?',
        whereArgs: [from.toIso8601String(), to.toIso8601String()],
        orderBy: 'expense_date DESC',
      );
      return rows.map(Expense.fromMap).toList();
    }
    final rows = await db.query('expenses', orderBy: 'expense_date DESC');
    return rows.map(Expense.fromMap).toList();
  }

  /// Just the expenses added from Quick Expense (source = 'quick') - feeds
  /// QuickHistoryScreen, kept separate from [all] (the general Expenses
  /// screen still shows everything, quick or not, since it's all real
  /// money either way).
  Future<List<Expense>> quickOnly() async {
    final db = await _dbHelper.database;
    final rows = await db.query('expenses', where: "source = 'quick'", orderBy: 'created_at DESC');
    return rows.map(Expense.fromMap).toList();
  }
}
