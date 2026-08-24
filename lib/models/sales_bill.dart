class SalesBill {
  final String id;
  final String billNo;
  final String billType; // accessory | other
  final String? customerId;
  final DateTime saleDate;
  final double subtotal;
  final double discount;
  final double total;
  final double paid;
  final double balance;
  final String? paymentMethod;
  final String? notes;
  final bool active;
  final DateTime createdAt;
  // Optional warranty on the sold accessory/item (spec: a warranty toggle +
  // period-in-days on Sales Bill creation - prints the period on the bill
  // when on, "Nil" when off - see PdfService.buildSalesBill).
  final bool warranty;
  final int? warrantyPeriodDays;

  SalesBill({
    required this.id,
    required this.billNo,
    this.billType = 'accessory',
    this.customerId,
    required this.saleDate,
    this.subtotal = 0,
    this.discount = 0,
    this.total = 0,
    this.paid = 0,
    this.balance = 0,
    this.paymentMethod,
    this.notes,
    this.active = true,
    required this.createdAt,
    this.warranty = false,
    this.warrantyPeriodDays,
  });

  factory SalesBill.fromMap(Map<String, dynamic> m) => SalesBill(
        id: m['id'] as String,
        billNo: m['bill_no'] as String,
        billType: m['bill_type'] as String? ?? 'accessory',
        customerId: m['customer_id'] as String?,
        saleDate: DateTime.parse(m['sale_date'] as String),
        subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0,
        discount: (m['discount'] as num?)?.toDouble() ?? 0,
        total: (m['total'] as num?)?.toDouble() ?? 0,
        paid: (m['paid'] as num?)?.toDouble() ?? 0,
        balance: (m['balance'] as num?)?.toDouble() ?? 0,
        paymentMethod: m['payment_method'] as String?,
        notes: m['notes'] as String?,
        active: (m['active'] as int? ?? 1) == 1,
        createdAt: DateTime.parse(m['created_at'] as String),
        warranty: (m['warranty'] as int? ?? 0) == 1,
        warrantyPeriodDays: (m['warranty_period_days'] as num?)?.toInt(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'bill_no': billNo,
        'bill_type': billType,
        'customer_id': customerId,
        'sale_date': saleDate.toIso8601String(),
        'subtotal': subtotal,
        'discount': discount,
        'total': total,
        'paid': paid,
        'balance': balance,
        'payment_method': paymentMethod,
        'notes': notes,
        'active': active ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'warranty': warranty ? 1 : 0,
        'warranty_period_days': warrantyPeriodDays,
      };
}

class SalesBillItem {
  final String id;
  final String saleId;
  final String? accessoryId;
  final String itemName;
  final double quantity;
  final double rate;
  final double cost; // internal - never shown on customer bill
  final double total;

  SalesBillItem({
    required this.id,
    required this.saleId,
    this.accessoryId,
    required this.itemName,
    required this.quantity,
    required this.rate,
    this.cost = 0,
    required this.total,
  });

  factory SalesBillItem.fromMap(Map<String, dynamic> m) => SalesBillItem(
        id: m['id'] as String,
        saleId: m['sale_id'] as String,
        accessoryId: m['accessory_id'] as String?,
        itemName: m['item_name'] as String,
        quantity: (m['quantity'] as num).toDouble(),
        rate: (m['rate'] as num).toDouble(),
        cost: (m['cost'] as num?)?.toDouble() ?? 0,
        total: (m['total'] as num).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'sale_id': saleId,
        'accessory_id': accessoryId,
        'item_name': itemName,
        'quantity': quantity,
        'rate': rate,
        'cost': cost,
        'total': total,
      };
}
