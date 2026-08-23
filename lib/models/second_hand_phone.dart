class SecondHandStatus {
  static const purchased = 'Purchased';
  static const repairing = 'Repairing';
  static const readyForSale = 'Ready for Sale';
  static const sold = 'Sold';
  static const returned = 'Returned';
  static const reserved = 'Reserved';

  static const all = [purchased, repairing, readyForSale, sold, returned, reserved];
}

/// Mobile vs Laptop - the shop now sells both 2nd hand mobiles and laptops
/// through this same purchase/repair/sell flow (Mobile Sales screen), so
/// one discriminator column tells the two apart instead of duplicating the
/// whole module. Mobiles are identified by IMEI; laptops don't have one,
/// so they're tracked by Serial No instead (stored in the [imei1] field -
/// see SecondHandPhone.serialOrImeiLabel).
class DeviceType {
  static const mobile = 'mobile';
  static const laptop = 'laptop';

  static const all = [mobile, laptop];
}

class SecondHandPhone {
  final String id;
  final String purchaseNo;
  final DateTime purchaseDate;
  final String deviceType;
  final String? sellerName;
  final String? sellerPhone;
  final String? brand;
  final String? model;
  final String? imei1;
  final String? imei2;
  final String? ram;
  final String? storage;
  final String? colour;
  final String? conditionGrade;
  final String? batteryHealth;
  final String? displayCondition;
  final String? bodyCondition;
  final String? accessoriesReceived;
  final double purchasePrice;
  final double otherCost; // misc costs not tied to a specific repair line item
  final double expectedSellingPrice;
  final double? actualSellingPrice;
  final DateTime? saleDate;
  final String? customerId;
  final bool warranty;
  final String? warrantyPeriod;
  final String? notes;
  final String? photoPath;
  final String status;
  final bool active;
  final DateTime createdAt;

  // Populated by the repository from second_hand_repair_items - not a DB column.
  final double repairCost;
  final double sparePartCost;

  SecondHandPhone({
    required this.id,
    required this.purchaseNo,
    required this.purchaseDate,
    this.deviceType = DeviceType.mobile,
    this.sellerName,
    this.sellerPhone,
    this.brand,
    this.model,
    this.imei1,
    this.imei2,
    this.ram,
    this.storage,
    this.colour,
    this.conditionGrade,
    this.batteryHealth,
    this.displayCondition,
    this.bodyCondition,
    this.accessoriesReceived,
    this.purchasePrice = 0,
    this.otherCost = 0,
    this.expectedSellingPrice = 0,
    this.actualSellingPrice,
    this.saleDate,
    this.customerId,
    this.warranty = false,
    this.warrantyPeriod,
    this.notes,
    this.photoPath,
    this.status = SecondHandStatus.purchased,
    this.active = true,
    required this.createdAt,
    this.repairCost = 0,
    this.sparePartCost = 0,
  });

  bool get isLaptop => deviceType == DeviceType.laptop;

  /// IMEI (mobile) / Serial No (laptop) label for screens that show one
  /// generic "identifier" field regardless of device type.
  String get identifierLabel => isLaptop ? 'Serial No' : 'IMEI';

  /// Total Investment = Purchase Price + Repair Cost + Spare Parts + Other Direct Costs
  double get totalInvestment => purchasePrice + repairCost + sparePartCost + otherCost;

  /// Profit = Selling Price - Total Investment (uses actual selling price once sold,
  /// falls back to expected selling price for "potential profit" while unsold).
  double get realizedProfit =>
      status == SecondHandStatus.sold ? (actualSellingPrice ?? 0) - totalInvestment : 0;

  double get potentialProfit => expectedSellingPrice - totalInvestment;

  bool get isLoss => (actualSellingPrice != null) && (actualSellingPrice! - totalInvestment) < 0;

  factory SecondHandPhone.fromMap(Map<String, dynamic> m,
      {double repairCost = 0, double sparePartCost = 0}) {
    return SecondHandPhone(
      id: m['id'] as String,
      purchaseNo: m['purchase_no'] as String,
      purchaseDate: DateTime.parse(m['purchase_date'] as String),
      deviceType: m['device_type'] as String? ?? DeviceType.mobile,
      sellerName: m['seller_name'] as String?,
      sellerPhone: m['seller_phone'] as String?,
      brand: m['brand'] as String?,
      model: m['model'] as String?,
      imei1: m['imei1'] as String?,
      imei2: m['imei2'] as String?,
      ram: m['ram'] as String?,
      storage: m['storage'] as String?,
      colour: m['colour'] as String?,
      conditionGrade: m['condition_grade'] as String?,
      batteryHealth: m['battery_health'] as String?,
      displayCondition: m['display_condition'] as String?,
      bodyCondition: m['body_condition'] as String?,
      accessoriesReceived: m['accessories_received'] as String?,
      purchasePrice: (m['purchase_price'] as num?)?.toDouble() ?? 0,
      otherCost: (m['other_cost'] as num?)?.toDouble() ?? 0,
      expectedSellingPrice: (m['expected_selling_price'] as num?)?.toDouble() ?? 0,
      actualSellingPrice: (m['actual_selling_price'] as num?)?.toDouble(),
      saleDate: m['sale_date'] != null ? DateTime.parse(m['sale_date'] as String) : null,
      customerId: m['customer_id'] as String?,
      warranty: (m['warranty'] as int? ?? 0) == 1,
      warrantyPeriod: m['warranty_period'] as String?,
      notes: m['notes'] as String?,
      photoPath: m['photo_path'] as String?,
      status: m['status'] as String? ?? SecondHandStatus.purchased,
      active: (m['active'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(m['created_at'] as String),
      repairCost: repairCost,
      sparePartCost: sparePartCost,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'purchase_no': purchaseNo,
        'purchase_date': purchaseDate.toIso8601String(),
        'device_type': deviceType,
        'seller_name': sellerName,
        'seller_phone': sellerPhone,
        'brand': brand,
        'model': model,
        'imei1': imei1,
        'imei2': imei2,
        'ram': ram,
        'storage': storage,
        'colour': colour,
        'condition_grade': conditionGrade,
        'battery_health': batteryHealth,
        'display_condition': displayCondition,
        'body_condition': bodyCondition,
        'accessories_received': accessoriesReceived,
        'purchase_price': purchasePrice,
        'other_cost': otherCost,
        'expected_selling_price': expectedSellingPrice,
        'actual_selling_price': actualSellingPrice,
        'sale_date': saleDate?.toIso8601String(),
        'customer_id': customerId,
        'warranty': warranty ? 1 : 0,
        'warranty_period': warrantyPeriod,
        'notes': notes,
        'photo_path': photoPath,
        'status': status,
        'active': active ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };
}

class SecondHandRepairItem {
  final String id;
  final String phoneId;
  final String description;
  final String? sparePartId;
  final double quantity;
  final double cost;

  SecondHandRepairItem({
    required this.id,
    required this.phoneId,
    required this.description,
    this.sparePartId,
    this.quantity = 1,
    this.cost = 0,
  });

  factory SecondHandRepairItem.fromMap(Map<String, dynamic> m) => SecondHandRepairItem(
        id: m['id'] as String,
        phoneId: m['phone_id'] as String,
        description: m['description'] as String,
        sparePartId: m['spare_part_id'] as String?,
        quantity: (m['quantity'] as num?)?.toDouble() ?? 1,
        cost: (m['cost'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'phone_id': phoneId,
        'description': description,
        'spare_part_id': sparePartId,
        'quantity': quantity,
        'cost': cost,
      };
}

class SecondHandSale {
  final String id;
  final String phoneId;
  final String billNo;
  final String? customerId;
  final DateTime saleDate;
  final double salePrice;
  final double discount;
  final String? paymentMethod;
  final double paid;
  final double balance;
  final bool warranty;
  final String? warrantyPeriod;
  final String? notes;
  final DateTime createdAt;

  SecondHandSale({
    required this.id,
    required this.phoneId,
    required this.billNo,
    this.customerId,
    required this.saleDate,
    required this.salePrice,
    this.discount = 0,
    this.paymentMethod,
    this.paid = 0,
    this.balance = 0,
    this.warranty = false,
    this.warrantyPeriod,
    this.notes,
    required this.createdAt,
  });

  factory SecondHandSale.fromMap(Map<String, dynamic> m) => SecondHandSale(
        id: m['id'] as String,
        phoneId: m['phone_id'] as String,
        billNo: m['bill_no'] as String,
        customerId: m['customer_id'] as String?,
        saleDate: DateTime.parse(m['sale_date'] as String),
        salePrice: (m['sale_price'] as num).toDouble(),
        discount: (m['discount'] as num?)?.toDouble() ?? 0,
        paymentMethod: m['payment_method'] as String?,
        paid: (m['paid'] as num?)?.toDouble() ?? 0,
        balance: (m['balance'] as num?)?.toDouble() ?? 0,
        warranty: (m['warranty'] as int? ?? 0) == 1,
        warrantyPeriod: m['warranty_period'] as String?,
        notes: m['notes'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'phone_id': phoneId,
        'bill_no': billNo,
        'customer_id': customerId,
        'sale_date': saleDate.toIso8601String(),
        'sale_price': salePrice,
        'discount': discount,
        'payment_method': paymentMethod,
        'paid': paid,
        'balance': balance,
        'warranty': warranty ? 1 : 0,
        'warranty_period': warrantyPeriod,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
      };
}
