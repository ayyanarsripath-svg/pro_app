/// The unified accounting ledger (spec section 30). Every purchase, sale,
/// service part usage, return, adjustment and expense writes rows here.
/// The Profit & Loss engine reads ONLY from this table (plus expense
/// allocation), never from "sales - current stock", so historical P&L stays
/// correct even after later stock adjustments.
class LedgerCategory {
  static const service = 'service';
  static const accessories = 'accessories';
  static const sparePartsInternal = 'spare_parts'; // spare part cost inside a service, not a standalone sales category
  static const secondHand = 'second_hand';
  static const other = 'other';
  static const expense = 'expense';
}

class LedgerTxnType {
  static const revenue = 'revenue';
  static const directCost = 'direct_cost';
  static const expenseTxn = 'expense';
  static const investment = 'investment'; // money put into 2nd hand stock (purchase+repair)
  static const refund = 'refund';
  static const returnTxn = 'return';
}

class LedgerTransaction {
  final String id;
  final DateTime txnDate;
  final String category;
  final String txnType;
  final String? referenceType;
  final String? referenceId;
  final double amount;
  final String? description;
  final DateTime createdAt;

  LedgerTransaction({
    required this.id,
    required this.txnDate,
    required this.category,
    required this.txnType,
    this.referenceType,
    this.referenceId,
    required this.amount,
    this.description,
    required this.createdAt,
  });

  factory LedgerTransaction.fromMap(Map<String, dynamic> m) => LedgerTransaction(
        id: m['id'] as String,
        txnDate: DateTime.parse(m['txn_date'] as String),
        category: m['category'] as String,
        txnType: m['txn_type'] as String,
        referenceType: m['reference_type'] as String?,
        referenceId: m['reference_id'] as String?,
        amount: (m['amount'] as num).toDouble(),
        description: m['description'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'txn_date': txnDate.toIso8601String(),
        'category': category,
        'txn_type': txnType,
        'reference_type': referenceType,
        'reference_id': referenceId,
        'amount': amount,
        'description': description,
        'created_at': createdAt.toIso8601String(),
      };
}
