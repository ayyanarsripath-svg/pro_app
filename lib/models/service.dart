/// Canonical service statuses (spec section 20).
class ServiceStatus {
  static const received = 'Received';
  static const checking = 'Checking';
  static const repairing = 'Repairing';
  static const partPending = 'Part Pending';
  static const ready = 'Ready';
  static const delivered = 'Delivered';
  static const warranty = 'Warranty';
  static const cancelled = 'Cancelled';

  static const all = [
    received,
    checking,
    repairing,
    partPending,
    ready,
    delivered,
    warranty,
    cancelled,
  ];
}

class ServiceJob {
  final String id;
  final String billNo;
  final String customerId;
  final String? mobileName;
  final String? model;
  final String? imei;
  final String? complaint; final String? faultAmounts;
  final String? deviceCondition;
  final String? existingDamage;
  final bool accCharger;
  final bool accCable;
  final bool accSim;
  final bool accMemoryCard;
  final String? accOther;
  final String? technician;
  final String status;
  final double labourCost;
  final bool warranty;
  final String? warrantyPeriod;
  final double estimatedAmount;
  final double finalAmount;
  final double advance;
  final double paid;
  final double balance;
  final DateTime? expectedDate;
  final DateTime? actualDate;
  final String? deliveryPerson;
  final String deliveryStatus;
  final double additionalExpense;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  ServiceJob({
    required this.id,
    required this.billNo,
    required this.customerId,
    this.mobileName,
    this.model,
    this.imei,
    this.complaint, this.faultAmounts,
    this.deviceCondition,
    this.existingDamage,
    this.accCharger = false,
    this.accCable = false,
    this.accSim = false,
    this.accMemoryCard = false,
    this.accOther,
    this.technician,
    this.status = ServiceStatus.checking,
    this.labourCost = 0,
    this.warranty = false,
    this.warrantyPeriod,
    this.estimatedAmount = 0,
    this.finalAmount = 0,
    this.advance = 0,
    this.paid = 0,
    this.balance = 0,
    this.expectedDate,
    this.actualDate,
    this.deliveryPerson,
    this.deliveryStatus = 'Pending',
    this.additionalExpense = 0,
    this.active = true,
    required this.createdAt,
    required this.updatedAt,
  });

bool get isPaymentPending => displayBalance > 0;
  bool get isDelivered => status == ServiceStatus.delivered;

  /// The amount to treat as the bill total for display: the real Final
  /// Amount once the shop sets it via Edit, or the Estimated Amount quoted
  /// at intake until then. Mirrors PdfService._billTotal so the in-app
  /// screens and the printed receipt always agree - a fresh job with an
  /// advance paid no longer shows "TOTAL ₹0" and a negative balance.
  double get billTotal => finalAmount > 0 ? finalAmount : estimatedAmount;

  /// Balance computed from [billTotal] rather than the possibly-still-₹0
  /// stored finalAmount.
  double get displayBalance => billTotal - paid;

  factory ServiceJob.fromMap(Map<String, dynamic> m) => ServiceJob(
        id: m['id'] as String,
        billNo: m['bill_no'] as String,
        customerId: m['customer_id'] as String,
        mobileName: m['mobile_name'] as String?,
        model: m['model'] as String?,
        imei: m['imei'] as String?,
        complaint: m['complaint'] as String?, faultAmounts: m['fault_amounts'] as String?,
        deviceCondition: m['device_condition'] as String?,
        existingDamage: m['existing_damage'] as String?,
        accCharger: (m['acc_charger'] as int? ?? 0) == 1,
        accCable: (m['acc_cable'] as int? ?? 0) == 1,
        accSim: (m['acc_sim'] as int? ?? 0) == 1,
        accMemoryCard: (m['acc_memory_card'] as int? ?? 0) == 1,
        accOther: m['acc_other'] as String?,
        technician: m['technician'] as String?,
        status: m['status'] as String? ?? ServiceStatus.checking,
        labourCost: (m['labour_cost'] as num?)?.toDouble() ?? 0,
        warranty: (m['warranty'] as int? ?? 0) == 1,
        warrantyPeriod: m['warranty_period'] as String?,
        estimatedAmount: (m['estimated_amount'] as num?)?.toDouble() ?? 0,
        finalAmount: (m['final_amount'] as num?)?.toDouble() ?? 0,
        advance: (m['advance'] as num?)?.toDouble() ?? 0,
        paid: (m['paid'] as num?)?.toDouble() ?? 0,
        balance: (m['balance'] as num?)?.toDouble() ?? 0,
        expectedDate: m['expected_date'] != null ? DateTime.parse(m['expected_date'] as String) : null,
        actualDate: m['actual_date'] != null ? DateTime.parse(m['actual_date'] as String) : null,
        deliveryPerson: m['delivery_person'] as String?,
        deliveryStatus: m['delivery_status'] as String? ?? 'Pending',
        additionalExpense: (m['additional_expense'] as num?)?.toDouble() ?? 0,
        active: (m['active'] as int? ?? 1) == 1,
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'bill_no': billNo,
        'customer_id': customerId,
        'mobile_name': mobileName,
        'model': model,
        'imei': imei,
        'complaint': complaint, 'fault_amounts': faultAmounts,
        'device_condition': deviceCondition,
        'existing_damage': existingDamage,
        'acc_charger': accCharger ? 1 : 0,
        'acc_cable': accCable ? 1 : 0,
        'acc_sim': accSim ? 1 : 0,
        'acc_memory_card': accMemoryCard ? 1 : 0,
        'acc_other': accOther,
        'technician': technician,
        'status': status,
        'labour_cost': labourCost,
        'warranty': warranty ? 1 : 0,
        'warranty_period': warrantyPeriod,
        'estimated_amount': estimatedAmount,
        'final_amount': finalAmount,
        'advance': advance,
        'paid': paid,
        'balance': balance,
        'expected_date': expectedDate?.toIso8601String(),
        'actual_date': actualDate?.toIso8601String(),
        'delivery_person': deliveryPerson,
        'delivery_status': deliveryStatus,
        'additional_expense': additionalExpense,
        'active': active ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

class ServiceStatusHistory {
  final String id;
  final String serviceId;
  final String status;
  final DateTime changedAt;
  final String? changedBy;
  final String? notes;

  ServiceStatusHistory({
    required this.id,
    required this.serviceId,
    required this.status,
    required this.changedAt,
    this.changedBy,
    this.notes,
  });

  factory ServiceStatusHistory.fromMap(Map<String, dynamic> m) => ServiceStatusHistory(
        id: m['id'] as String,
        serviceId: m['service_id'] as String,
        status: m['status'] as String,
        changedAt: DateTime.parse(m['changed_at'] as String),
        changedBy: m['changed_by'] as String?,
        notes: m['notes'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'service_id': serviceId,
        'status': status,
        'changed_at': changedAt.toIso8601String(),
        'changed_by': changedBy,
        'notes': notes,
      };
}

class ServicePhoto {
  final String id;
  final String serviceId;
  final String photoPath;
  final String? caption;
  final DateTime takenAt;

  ServicePhoto({
    required this.id,
    required this.serviceId,
    required this.photoPath,
    this.caption,
    required this.takenAt,
  });

  factory ServicePhoto.fromMap(Map<String, dynamic> m) => ServicePhoto(
        id: m['id'] as String,
        serviceId: m['service_id'] as String,
        photoPath: m['photo_path'] as String,
        caption: m['caption'] as String?,
        takenAt: DateTime.parse(m['taken_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'service_id': serviceId,
        'photo_path': photoPath,
        'caption': caption,
        'taken_at': takenAt.toIso8601String(),
      };
}

class ServiceSparePartUsage {
  final String id;
  final String serviceId;
  final String? sparePartId;
  final String itemName;
  final double quantity;
  final double unitCost;
  final double totalCost;

  ServiceSparePartUsage({
    required this.id,
    required this.serviceId,
    this.sparePartId,
    required this.itemName,
    this.quantity = 1,
    this.unitCost = 0,
    this.totalCost = 0,
  });

  factory ServiceSparePartUsage.fromMap(Map<String, dynamic> m) => ServiceSparePartUsage(
        id: m['id'] as String,
        serviceId: m['service_id'] as String,
        sparePartId: m['spare_part_id'] as String?,
        itemName: m['item_name'] as String,
        quantity: (m['quantity'] as num?)?.toDouble() ?? 1,
        unitCost: (m['unit_cost'] as num?)?.toDouble() ?? 0,
        totalCost: (m['total_cost'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'service_id': serviceId,
        'spare_part_id': sparePartId,
        'item_name': itemName,
        'quantity': quantity,
        'unit_cost': unitCost,
        'total_cost': totalCost,
      };
}

class ServiceOtherCost {
  final String id;
  final String serviceId;
  final String description;
  final double amount;

  ServiceOtherCost({
    required this.id,
    required this.serviceId,
    required this.description,
    required this.amount,
  });

  factory ServiceOtherCost.fromMap(Map<String, dynamic> m) => ServiceOtherCost(
        id: m['id'] as String,
        serviceId: m['service_id'] as String,
        description: m['description'] as String,
        amount: (m['amount'] as num).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'service_id': serviceId,
        'description': description,
        'amount': amount,
      };
}

class ServicePayment {
  final String id;
  final String serviceId;
  final double amount;
  final String? paymentMethod;
  final DateTime paidAt;
  final String? notes;

  ServicePayment({
    required this.id,
    required this.serviceId,
    required this.amount,
    this.paymentMethod,
    required this.paidAt,
    this.notes,
  });

  factory ServicePayment.fromMap(Map<String, dynamic> m) => ServicePayment(
        id: m['id'] as String,
        serviceId: m['service_id'] as String,
        amount: (m['amount'] as num).toDouble(),
        paymentMethod: m['payment_method'] as String?,
        paidAt: DateTime.parse(m['paid_at'] as String),
        notes: m['notes'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'service_id': serviceId,
        'amount': amount,
        'payment_method': paymentMethod,
        'paid_at': paidAt.toIso8601String(),
        'notes': notes,
      };
}

/// Computed, admin-only internal costing view for one service (spec section 2).
class ServiceProfitBreakdown {
  final double serviceRevenue;
  final double sparePartCost;
  final double otherDirectCost;
  final double labourCost;
  final double additionalExpense;

  ServiceProfitBreakdown({
    required this.serviceRevenue,
    required this.sparePartCost,
    required this.otherDirectCost,
    required this.labourCost,
    required this.additionalExpense,
  });

  double get totalDirectCost => sparePartCost + otherDirectCost + labourCost;
  double get grossProfit => serviceRevenue - totalDirectCost;
  double get netProfit => grossProfit - additionalExpense;
}
