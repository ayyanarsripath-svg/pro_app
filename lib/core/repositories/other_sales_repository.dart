import '../../models/ledger_transaction.dart';
import 'ledger_repository.dart';

/// "Other Sales" (spec category #5) is deliberately open-ended - anything
/// that doesn't fit Service / Accessories / 2nd Hand (e.g. a laptop sold
/// outright, a one-off repair-adjacent service, misc income). Rather than
/// build a dedicated inventory module for something intentionally
/// miscellaneous, this gives Admin a quick manual entry that posts straight
/// to the same ledger the rest of the P&L engine reads.
class OtherSalesRepository {
  final _ledger = LedgerRepository();

  Future<void> recordEntry({
    required DateTime date,
    required String description,
    required double revenue,
    double cost = 0,
  }) async {
    if (revenue > 0) {
      await _ledger.record(
        txnDate: date,
        category: LedgerCategory.other,
        txnType: LedgerTxnType.revenue,
        referenceType: 'other_sale',
        referenceId: null,
        amount: revenue,
        description: description,
      );
    }
    if (cost > 0) {
      await _ledger.record(
        txnDate: date,
        category: LedgerCategory.other,
        txnType: LedgerTxnType.directCost,
        referenceType: 'other_sale',
        referenceId: null,
        amount: cost,
        description: '$description (cost)',
      );
    }
  }
}
