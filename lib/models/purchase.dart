class Purchase {
  final String id;
  final String purchaseNo;
  final String? supplierId;
  final DateTime purchaseDate;
  final String category; // spare_part | accessory | other
  final double totalAmount;
  final double paidAmount;
  final String? notes;
  final DateTime createdAt;

  Purchase({
    required this.id,
    required this.purchaseNo,
    this.supplierId,
    required this.purchaseDate,
    required this.category,
    this.totalAmount = 0,
    this.paidAmount = 0,
    this.notes,
    required this.createdAt,
  });

  double get balance => totalAmount - paidAmount;

  factory Purchase.fromMap(Map<String, dynamic> m) => Purchase(
        id: m['id'] as String,
        purchaseNo: m['purchase_no'] as String? ?? '',
        supplierId: m['supplier_id'] as String?,
        purchaseDate: DateTime.parse(m['purchase_date'] as String),
        category: m['category'] as String,
        totalAmount: (m['total_amount'] as num?)?.toDouble() ?? 0,
        paidAmount: (m['paid_amount'] as num?)?.toDouble() ?? 0,
        notes: m['notes'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'purchase_no': purchaseNo,
        'supplier_id': supplierId,
        'purchase_date': purchaseDate.toIso8601String(),
        'category': category,
        'total_amount': totalAmount,
        'paid_amount': paidAmount,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
      };
}

class PurchaseItem {
  final String id;
  final String purchaseId;
  final String itemType; // spare_part | accessory
  final String itemId;
  final String itemName;
  final double quantity;
  final double unitCost;
  final double totalCost;

  PurchaseItem({
    required this.id,
    required this.purchaseId,
    required this.itemType,
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.unitCost,
    required this.totalCost,
  });

  factory PurchaseItem.fromMap(Map<String, dynamic> m) => PurchaseItem(
        id: m['id'] as String,
        purchaseId: m['purchase_id'] as String,
        itemType: m['item_type'] as String,
        itemId: m['item_id'] as String,
        itemName: m['item_name'] as String,
        quantity: (m['quantity'] as num).toDouble(),
        unitCost: (m['unit_cost'] as num).toDouble(),
        totalCost: (m['total_cost'] as num).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'purchase_id': purchaseId,
        'item_type': itemType,
        'item_id': itemId,
        'item_name': itemName,
        'quantity': quantity,
        'unit_cost': unitCost,
        'total_cost': totalCost,
      };
}
