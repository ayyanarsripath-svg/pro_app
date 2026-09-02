import '../../models/expense.dart';
import '../../models/ledger_transaction.dart';
import 'expense_repository.dart';
import 'ledger_repository.dart';

/// Category lists shown on the Quick Income/Quick Expense screen (spec:
/// "PRO SERVICE – Quick Income & Expense Entry Feature", items 2 & 3).
/// Income categories map onto the SAME business categories the rest of the
/// P&L engine already groups by (see QuickTransactionRepository), so a
/// quick "₹500 → Service Income" entry lands in exactly the same Service
/// P&L bucket a normal service bill would. Expense categories reuse the
/// app's existing shop-wide expense category list unchanged.
class QuickTransactionCategory {
  static const incomeCategories = [
    'Service Income',
    'Accessories Income',
    'Second Hand Sale',
    'Other Income',
  ];
  static const expenseCategories = ExpenseCategory.defaults;
}

/// Backs the fast in-app entry point behind every piece of the Quick
/// Income & Expense spec (persistent notification, home widget, Quick
/// Settings tile, voice entry all eventually call the same two methods
/// here). Deliberately reuses the systems that already feed Dashboard/P&L
/// instead of inventing a parallel table (spec item 8: "Existing Income &
/// Expense database/schema-ஐ மாற்றி existing data break செய்யக்கூடாது ...
/// Dashboard update ஆக வேண்டும், Daily income update ஆக வேண்டும் ...
/// Duplicate transaction உருவாகக்கூடாது"):
///  - Quick Expense calls the EXACT SAME [ExpenseRepository.create] the
///    full Settings -> Expenses screen already uses, so it shows up there
///    too, not just as a number nobody can trace back later.
///  - Quick Income writes straight to the ledger's revenue side, the same
///    mechanism [OtherSalesRepository] already uses for manual "Other
///    Sales" entries - so Today's Revenue and every Daily/Weekly/Monthly
///    P&L bucket picks it up immediately, attributed to whichever business
///    category was picked instead of a single catch-all.
/// Both paths are plain SQLite writes, so both work fully offline - no
/// network needed to save (spec item 9), and both are already included in
/// the existing Google Drive backup/restore since it's the same database
/// file (spec item 9's "existing Google Drive backup ... automatically
/// include ஆக வேண்டும்" is satisfied for free, nothing extra to wire up).
class QuickTransactionRepository {
  final _ledger = LedgerRepository();
  final _expenseRepo = ExpenseRepository();

  String _ledgerCategoryForIncome(String category) {
    switch (category) {
      case 'Service Income':
        return LedgerCategory.service;
      case 'Accessories Income':
        return LedgerCategory.accessories;
      case 'Second Hand Sale':
        return LedgerCategory.secondHand;
      case 'Other Income':
      default:
        return LedgerCategory.other;
    }
  }

  Future<void> recordIncome({
    required double amount,
    required String category,
    String? note,
    DateTime? date,
  }) async {
    final trimmedNote = note?.trim() ?? '';
    await _ledger.record(
      txnDate: date ?? DateTime.now(),
      category: _ledgerCategoryForIncome(category),
      txnType: LedgerTxnType.revenue,
      referenceType: 'quick_income',
      amount: amount,
      description: trimmedNote.isEmpty ? category : '$category - $trimmedNote',
    );
  }

  Future<void> recordExpense({
    required double amount,
    required String category,
    String? note,
    DateTime? date,
  }) async {
    final trimmedNote = note?.trim();
    await _expenseRepo.create(
      expenseDate: date ?? DateTime.now(),
      category: category,
      amount: amount,
      description: (trimmedNote == null || trimmedNote.isEmpty) ? null : trimmedNote,
      // Tags this row so QuickHistoryScreen can show it separately from
      // the general Expenses list (spec: "quick expenses and quick income
      // ku thaniya oru history create pannikkalam" - it was landing mixed
      // into Expenses with no way to tell it apart).
      source: 'quick',
    );
  }
}
