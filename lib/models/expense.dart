/// Which part of the business an expense should be charged against
/// (spec section 14). "general" flows into overall Net Profit only;
/// the others also reduce that specific category's P&L.
class ExpenseAllocation {
  static const general = 'general';
  static const service = 'service';
  static const accessories = 'accessories';
  static const secondHand = 'second_hand';
  static const other = 'other';

  static const all = [general, service, accessories, secondHand, other];
}

class ExpenseCategory {
  static const defaults = [
    'Shop Rent',
    'Electricity',
    'Internet',
    'Transport',
    'Salary',
    'Tools',
    'Consumables',
    'Packaging',
    'Courier',
    'Miscellaneous',
  ];
}

class Expense {
  final String id;
  final DateTime expenseDate;
  final String category;
  final double amount;
  final String? paymentMethod;
  final String? description;
  final String allocation;
  // Tags an expense added from the Quick Expense screen as 'quick', so
  // QuickHistoryScreen can show just those, separate from the general
  // Expenses list (see DatabaseHelper's oldVersion < 11 migration). Null
  // for every expense added the normal way, via Settings -> Expenses.
  final String? source;
  final DateTime createdAt;

  Expense({
    required this.id,
    required this.expenseDate,
    required this.category,
    required this.amount,
    this.paymentMethod,
    this.description,
    this.allocation = ExpenseAllocation.general,
    this.source,
    required this.createdAt,
  });

  factory Expense.fromMap(Map<String, dynamic> m) => Expense(
        id: m['id'] as String,
        expenseDate: DateTime.parse(m['expense_date'] as String),
        category: m['category'] as String,
        amount: (m['amount'] as num).toDouble(),
        paymentMethod: m['payment_method'] as String?,
        description: m['description'] as String?,
        allocation: m['allocation'] as String? ?? ExpenseAllocation.general,
        source: m['source'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'expense_date': expenseDate.toIso8601String(),
        'category': category,
        'amount': amount,
        'payment_method': paymentMethod,
        'description': description,
        'allocation': allocation,
        'source': source,
        'created_at': createdAt.toIso8601String(),
      };
}
