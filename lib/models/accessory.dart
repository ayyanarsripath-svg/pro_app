class Accessory {
  final String id;
  final String name;
  final String? category;
  final String? brand;
  final String unit;
  final double currentStock;
  final double purchasePrice;
  final double sellingPrice;
  final double lowStockThreshold;
  final bool active;
  final DateTime createdAt;
  // Barcode Scanning + Inventory System - the product's identity (spec item
  // 18: "ONE PRODUCT -> ONE BARCODE -> MANY QUANTITY"). Null until scanned
  // (an existing manufacturer barcode) or generated (an internal one - see
  // BarcodeGenerator) for this accessory.
  final String? barcode;

  Accessory({
    required this.id,
    required this.name,
    this.category,
    this.brand,
    this.unit = 'pcs',
    this.currentStock = 0,
    this.purchasePrice = 0,
    this.sellingPrice = 0,
    this.lowStockThreshold = 3,
    this.active = true,
    required this.createdAt,
    this.barcode,
  });

  bool get isLowStock => currentStock <= lowStockThreshold;
  bool get isOutOfStock => currentStock <= 0;
  double get unitProfit => sellingPrice - purchasePrice;
  double get stockValue => currentStock * purchasePrice;

  Accessory copyWith({double? currentStock, double? purchasePrice, String? barcode}) => Accessory(
        id: id,
        name: name,
        category: category,
        brand: brand,
        unit: unit,
        currentStock: currentStock ?? this.currentStock,
        purchasePrice: purchasePrice ?? this.purchasePrice,
        sellingPrice: sellingPrice,
        lowStockThreshold: lowStockThreshold,
        active: active,
        createdAt: createdAt,
        barcode: barcode ?? this.barcode,
      );

  factory Accessory.fromMap(Map<String, dynamic> m) => Accessory(
        id: m['id'] as String,
        name: m['name'] as String,
        category: m['category'] as String?,
        brand: m['brand'] as String?,
        unit: m['unit'] as String? ?? 'pcs',
        currentStock: (m['current_stock'] as num?)?.toDouble() ?? 0,
        purchasePrice: (m['purchase_price'] as num?)?.toDouble() ?? 0,
        sellingPrice: (m['selling_price'] as num?)?.toDouble() ?? 0,
        lowStockThreshold: (m['low_stock_threshold'] as num?)?.toDouble() ?? 3,
        active: (m['active'] as int? ?? 1) == 1,
        createdAt: DateTime.parse(m['created_at'] as String),
        barcode: m['barcode'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'brand': brand,
        'unit': unit,
        'current_stock': currentStock,
        'purchase_price': purchasePrice,
        'selling_price': sellingPrice,
        'low_stock_threshold': lowStockThreshold,
        'active': active ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'barcode': barcode,
      };
}

class AccessoryTransaction {
  final String id;
  final String accessoryId;
  final String txnType; // purchase | sale | sales_return | stock_return | adjustment
  final double quantity;
  final double unitPrice;
  final String? referenceType;
  final String? referenceId;
  final DateTime txnDate;
  final String? notes;
  // Purchase Stock Entry's optional Batch Number / Invoice Number (spec
  // item 4) - only ever set on a 'purchase' row, null everywhere else.
  final String? batchNumber;
  final String? invoiceNumber;

  AccessoryTransaction({
    required this.id,
    required this.accessoryId,
    required this.txnType,
    required this.quantity,
    this.unitPrice = 0,
    this.referenceType,
    this.referenceId,
    required this.txnDate,
    this.notes,
    this.batchNumber,
    this.invoiceNumber,
  });

  factory AccessoryTransaction.fromMap(Map<String, dynamic> m) => AccessoryTransaction(
        id: m['id'] as String,
        accessoryId: m['accessory_id'] as String,
        txnType: m['txn_type'] as String,
        quantity: (m['quantity'] as num).toDouble(),
        unitPrice: (m['unit_price'] as num?)?.toDouble() ?? 0,
        referenceType: m['reference_type'] as String?,
        referenceId: m['reference_id'] as String?,
        txnDate: DateTime.parse(m['txn_date'] as String),
        notes: m['notes'] as String?,
        batchNumber: m['batch_number'] as String?,
        invoiceNumber: m['invoice_number'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'accessory_id': accessoryId,
        'txn_type': txnType,
        'quantity': quantity,
        'unit_price': unitPrice,
        'reference_type': referenceType,
        'reference_id': referenceId,
        'txn_date': txnDate.toIso8601String(),
        'notes': notes,
        'batch_number': batchNumber,
        'invoice_number': invoiceNumber,
      };
}
