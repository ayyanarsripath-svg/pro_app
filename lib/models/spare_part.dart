class SparePart {
  final String id;
  final String name;
  final String? category;
  final String? compatibleModel;
  final String unit;
  final double currentStock;
  final double avgPurchaseCost;
  final double lowStockThreshold;
  final bool active;
  final DateTime createdAt;

  SparePart({
    required this.id,
    required this.name,
    this.category,
    this.compatibleModel,
    this.unit = 'pcs',
    this.currentStock = 0,
    this.avgPurchaseCost = 0,
    this.lowStockThreshold = 2,
    this.active = true,
    required this.createdAt,
  });

  bool get isLowStock => currentStock <= lowStockThreshold;
  double get stockValue => currentStock * avgPurchaseCost;

  SparePart copyWith({double? currentStock, double? avgPurchaseCost}) => SparePart(
        id: id,
        name: name,
        category: category,
        compatibleModel: compatibleModel,
        unit: unit,
        currentStock: currentStock ?? this.currentStock,
        avgPurchaseCost: avgPurchaseCost ?? this.avgPurchaseCost,
        lowStockThreshold: lowStockThreshold,
        active: active,
        createdAt: createdAt,
      );

  factory SparePart.fromMap(Map<String, dynamic> m) => SparePart(
        id: m['id'] as String,
        name: m['name'] as String,
        category: m['category'] as String?,
        compatibleModel: m['compatible_model'] as String?,
        unit: m['unit'] as String? ?? 'pcs',
        currentStock: (m['current_stock'] as num?)?.toDouble() ?? 0,
        avgPurchaseCost: (m['avg_purchase_cost'] as num?)?.toDouble() ?? 0,
        lowStockThreshold: (m['low_stock_threshold'] as num?)?.toDouble() ?? 2,
        active: (m['active'] as int? ?? 1) == 1,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'compatible_model': compatibleModel,
        'unit': unit,
        'current_stock': currentStock,
        'avg_purchase_cost': avgPurchaseCost,
        'low_stock_threshold': lowStockThreshold,
        'active': active ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };
}

class SparePartTransaction {
  final String id;
  final String sparePartId;
  final String txnType; // purchase | service_usage | adjustment | supplier_return | second_hand_usage
  final double quantity; // + stock in, - stock out
  final double unitCost;
  final String? referenceType;
  final String? referenceId;
  final DateTime txnDate;
  final String? notes;

  SparePartTransaction({
    required this.id,
    required this.sparePartId,
    required this.txnType,
    required this.quantity,
    this.unitCost = 0,
    this.referenceType,
    this.referenceId,
    required this.txnDate,
    this.notes,
  });

  factory SparePartTransaction.fromMap(Map<String, dynamic> m) => SparePartTransaction(
        id: m['id'] as String,
        sparePartId: m['spare_part_id'] as String,
        txnType: m['txn_type'] as String,
        quantity: (m['quantity'] as num).toDouble(),
        unitCost: (m['unit_cost'] as num?)?.toDouble() ?? 0,
        referenceType: m['reference_type'] as String?,
        referenceId: m['reference_id'] as String?,
        txnDate: DateTime.parse(m['txn_date'] as String),
        notes: m['notes'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'spare_part_id': sparePartId,
        'txn_type': txnType,
        'quantity': quantity,
        'unit_cost': unitCost,
        'reference_type': referenceType,
        'reference_id': referenceId,
        'txn_date': txnDate.toIso8601String(),
        'notes': notes,
      };
}
