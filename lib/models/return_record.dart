class ReturnType {
  static const accessorySalesReturn = 'accessory_sales_return';
  static const accessoryStockReturn = 'accessory_stock_return';
  static const secondHandCustomerReturn = 'second_hand_customer_return';
  static const sparePartSupplierReturn = 'spare_part_supplier_return';
}

class ReturnRecord {
  final String id;
  final String returnType;
  final String? referenceType;
  final String? referenceId;
  final String? itemName;
  final double quantity;
  final double amount;
  final String? reason;
  final DateTime returnDate;
  final String? refundMethod;
  final String? notes;
  final DateTime createdAt;

  ReturnRecord({
    required this.id,
    required this.returnType,
    this.referenceType,
    this.referenceId,
    this.itemName,
    this.quantity = 1,
    this.amount = 0,
    this.reason,
    required this.returnDate,
    this.refundMethod,
    this.notes,
    required this.createdAt,
  });

  factory ReturnRecord.fromMap(Map<String, dynamic> m) => ReturnRecord(
        id: m['id'] as String,
        returnType: m['return_type'] as String,
        referenceType: m['reference_type'] as String?,
        referenceId: m['reference_id'] as String?,
        itemName: m['item_name'] as String?,
        quantity: (m['quantity'] as num?)?.toDouble() ?? 1,
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        reason: m['reason'] as String?,
        returnDate: DateTime.parse(m['return_date'] as String),
        refundMethod: m['refund_method'] as String?,
        notes: m['notes'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'return_type': returnType,
        'reference_type': referenceType,
        'reference_id': referenceId,
        'item_name': itemName,
        'quantity': quantity,
        'amount': amount,
        'reason': reason,
        'return_date': returnDate.toIso8601String(),
        'refund_method': refundMethod,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
      };
}
