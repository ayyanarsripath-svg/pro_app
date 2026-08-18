import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/service.dart';
import '../../models/ledger_transaction.dart';
import 'ledger_repository.dart';
import 'settings_repository.dart';
import 'spare_part_repository.dart';

/// Service job cards ("repair bills"). Keeps the customer-facing final
/// amount completely separate from the admin-only internal costing, per
/// spec section 2 & 28 (customer bill never shows purchase cost / profit).
class ServiceRepository {
  final _dbHelper = DatabaseHelper.instance;
  final _ledger = LedgerRepository();
  final _settings = SettingsRepository();
  final _spareParts = SparePartRepository();

  Future<String> nextBillNo() async {
    final seq = await _settings.nextSequence('service_seq');
    return 'A${seq.toString().padLeft(3, '0')}';
  }

  Future<ServiceJob> create({
    required String customerId,
    String? mobileName,
    String? model,
    String? imei,
    String? complaint,
    String? deviceCondition,
    String? existingDamage,
    bool accCharger = false,
    bool accCable = false,
    bool accSim = false,
    bool accMemoryCard = false,
    String? accOther,
    String? technician,
    double labourCost = 0,
    bool warranty = false,
    String? warrantyPeriod,
    double estimatedAmount = 0,
    double finalAmount = 0,
    double advance = 0,
    DateTime? expectedDate,
    String? billNo,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final service = ServiceJob(
      id: newId(),
      billNo: billNo ?? await nextBillNo(),
      customerId: customerId,
      mobileName: mobileName,
      model: model,
      imei: imei,
      complaint: complaint,
      deviceCondition: deviceCondition,
      existingDamage: existingDamage,
      accCharger: accCharger,
      accCable: accCable,
      accSim: accSim,
      accMemoryCard: accMemoryCard,
      accOther: accOther,
      technician: technician,
      status: ServiceStatus.checking,
      labourCost: labourCost,
      warranty: warranty,
      warrantyPeriod: warrantyPeriod,
      estimatedAmount: estimatedAmount,
      finalAmount: finalAmount,
      advance: advance,
      paid: advance,
      balance: finalAmount - advance,
      expectedDate: expectedDate,
      deliveryStatus: 'Pending',
      createdAt: now,
      updatedAt: now,
    );

    await db.insert('services', service.toMap());
    await db.insert('service_status_history', ServiceStatusHistory(
      id: newId(),
      serviceId: service.id,
      status: ServiceStatus.checking,
      changedAt: now,
    ).toMap());

    if (advance > 0) {
      await db.insert('service_payments', ServicePayment(
        id: newId(),
        serviceId: service.id,
        amount: advance,
        paymentMethod: 'Advance',
        paidAt: now,
      ).toMap());
    }

    await _syncCoreLedger(service);
    return service;
  }

  /// Re-writes the revenue / labour-cost / additional-expense ledger rows
  /// for a service. Called after create and after any financial edit so the
  /// ledger always matches the current record (no double counting).
  Future<void> _syncCoreLedger(ServiceJob service) async {
    await _ledger.clearForReference('service_core', service.id);
    if (service.finalAmount > 0) {
      await _ledger.record(
        txnDate: service.createdAt,
        category: LedgerCategory.service,
        txnType: LedgerTxnType.revenue,
        referenceType: 'service_core',
        referenceId: service.id,
        amount: service.finalAmount,
        description: 'Service revenue ${service.billNo}',
      );
    }
    if (service.labourCost > 0) {
      await _ledger.record(
        txnDate: service.createdAt,
        category: LedgerCategory.service,
        txnType: LedgerTxnType.directCost,
        referenceType: 'service_core',
        referenceId: service.id,
        amount: service.labourCost,
        description: 'Labour cost ${service.billNo}',
      );
    }
    if (service.additionalExpense > 0) {
      await _ledger.record(
        txnDate: service.createdAt,
        category: LedgerCategory.service,
        txnType: LedgerTxnType.expenseTxn,
        referenceType: 'service_core',
        referenceId: service.id,
        amount: service.additionalExpense,
        description: 'Additional expense ${service.billNo}',
      );
    }
  }

  Future<void> update(ServiceJob service) async {
    final db = await _dbHelper.database;
    final updated = ServiceJob(
      id: service.id,
      billNo: service.billNo,
      customerId: service.customerId,
      mobileName: service.mobileName,
      model: service.model,
      imei: service.imei,
      complaint: service.complaint,
      deviceCondition: service.deviceCondition,
      existingDamage: service.existingDamage,
      accCharger: service.accCharger,
      accCable: service.accCable,
      accSim: service.accSim,
      accMemoryCard: service.accMemoryCard,
      accOther: service.accOther,
      technician: service.technician,
      status: service.status,
      labourCost: service.labourCost,
      warranty: service.warranty,
      warrantyPeriod: service.warrantyPeriod,
      estimatedAmount: service.estimatedAmount,
      finalAmount: service.finalAmount,
      advance: service.advance,
      paid: service.paid,
      balance: service.finalAmount - service.paid,
      expectedDate: service.expectedDate,
      actualDate: service.actualDate,
      deliveryPerson: service.deliveryPerson,
      deliveryStatus: service.deliveryStatus,
      additionalExpense: service.additionalExpense,
      createdAt: service.createdAt,
      updatedAt: DateTime.now(),
    );
    await db.update('services', updated.toMap(), where: 'id = ?', whereArgs: [service.id]);
    await _syncCoreLedger(updated);
  }

  Future<void> changeStatus(String serviceId, String newStatus, {String? changedBy, String? notes}) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    await db.update('services', {'status': newStatus, 'updated_at': now.toIso8601String()},
        where: 'id = ?', whereArgs: [serviceId]);
    await db.insert('service_status_history', ServiceStatusHistory(
      id: newId(),
      serviceId: serviceId,
      status: newStatus,
      changedAt: now,
      changedBy: changedBy,
      notes: notes,
    ).toMap());

    if (newStatus == ServiceStatus.delivered) {
      await db.update(
        'services',
        {'delivery_status': 'Delivered', 'actual_date': now.toIso8601String()},
        where: 'id = ?',
        whereArgs: [serviceId],
      );
    }
  }

  Future<void> recordPayment({
    required String serviceId,
    required double amount,
    String? paymentMethod,
    String? notes,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    await db.insert('service_payments', ServicePayment(
      id: newId(),
      serviceId: serviceId,
      amount: amount,
      paymentMethod: paymentMethod,
      paidAt: now,
      notes: notes,
    ).toMap());

    final rows = await db.query('services', where: 'id = ?', whereArgs: [serviceId]);
    final current = ServiceJob.fromMap(rows.first);
    final newPaid = current.paid + amount;
    await db.update(
      'services',
      {'paid': newPaid, 'balance': current.finalAmount - newPaid, 'updated_at': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [serviceId],
    );
  }

  /// Adds a spare part used in the repair: pulls stock (at current average
  /// cost) and links that exact cost to this service's internal costing.
  Future<void> addSparePartUsage({
    required String serviceId,
    required String sparePartId,
    required String itemName,
    required double quantity,
    required DateTime date,
  }) async {
    final db = await _dbHelper.database;
    final unitCost = await _spareParts.useForService(
      sparePartId: sparePartId,
      quantity: quantity,
      referenceType: 'service',
      referenceId: serviceId,
      date: date,
    );
    final usageId = newId();
    await db.insert('service_spare_parts', {
      'id': usageId,
      'service_id': serviceId,
      'spare_part_id': sparePartId,
      'item_name': itemName,
      'quantity': quantity,
      'unit_cost': unitCost / (quantity == 0 ? 1 : quantity),
      'total_cost': unitCost,
    });
    await _ledger.record(
      txnDate: date,
      category: LedgerCategory.service,
      txnType: LedgerTxnType.directCost,
      referenceType: 'service_spare_part',
      referenceId: usageId,
      amount: unitCost,
      description: '$itemName used in service',
    );
  }

  /// Adds a manual spare-part / misc direct cost line that isn't tracked in
  /// inventory (e.g. a one-off part bought just for this job).
  Future<void> addManualDirectCost({
    required String serviceId,
    required String itemName,
    required double amount,
    required DateTime date,
  }) async {
    final db = await _dbHelper.database;
    final id = newId();
    await db.insert('service_spare_parts', {
      'id': id,
      'service_id': serviceId,
      'spare_part_id': null,
      'item_name': itemName,
      'quantity': 1,
      'unit_cost': amount,
      'total_cost': amount,
    });
    await _ledger.record(
      txnDate: date,
      category: LedgerCategory.service,
      txnType: LedgerTxnType.directCost,
      referenceType: 'service_spare_part',
      referenceId: id,
      amount: amount,
      description: '$itemName (manual)',
    );
  }

  Future<void> addOtherCost({
    required String serviceId,
    required String description,
    required double amount,
    required DateTime date,
  }) async {
    final db = await _dbHelper.database;
    final id = newId();
    await db.insert('service_other_costs', {
      'id': id,
      'service_id': serviceId,
      'description': description,
      'amount': amount,
    });
    await _ledger.record(
      txnDate: date,
      category: LedgerCategory.service,
      txnType: LedgerTxnType.directCost,
      referenceType: 'service_other_cost',
      referenceId: id,
      amount: amount,
      description: description,
    );
  }

  Future<void> addPhoto(String serviceId, String photoPath, {String? caption}) async {
    final db = await _dbHelper.database;
    await db.insert('service_photos', ServicePhoto(
      id: newId(),
      serviceId: serviceId,
      photoPath: photoPath,
      caption: caption,
      takenAt: DateTime.now(),
    ).toMap());
  }

  Future<List<ServiceJob>> all({String? statusFilter}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'services',
      where: statusFilter != null ? 'status = ?' : null,
      whereArgs: statusFilter != null ? [statusFilter] : null,
      orderBy: 'created_at DESC',
    );
    return rows.map(ServiceJob.fromMap).toList();
  }

  Future<List<ServiceJob>> forCustomer(String customerId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('services', where: 'customer_id = ?', whereArgs: [customerId], orderBy: 'created_at DESC');
    return rows.map(ServiceJob.fromMap).toList();
  }

  Future<ServiceJob?> byId(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('services', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ServiceJob.fromMap(rows.first);
  }

  Future<List<ServiceStatusHistory>> statusHistory(String serviceId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('service_status_history', where: 'service_id = ?', whereArgs: [serviceId], orderBy: 'changed_at');
    return rows.map(ServiceStatusHistory.fromMap).toList();
  }

  Future<List<ServicePhoto>> photos(String serviceId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('service_photos', where: 'service_id = ?', whereArgs: [serviceId], orderBy: 'taken_at');
    return rows.map(ServicePhoto.fromMap).toList();
  }

  Future<List<ServiceSparePartUsage>> sparePartUsages(String serviceId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('service_spare_parts', where: 'service_id = ?', whereArgs: [serviceId]);
    return rows.map(ServiceSparePartUsage.fromMap).toList();
  }

  Future<List<ServiceOtherCost>> otherCosts(String serviceId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('service_other_costs', where: 'service_id = ?', whereArgs: [serviceId]);
    return rows.map(ServiceOtherCost.fromMap).toList();
  }

  Future<List<ServicePayment>> payments(String serviceId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('service_payments', where: 'service_id = ?', whereArgs: [serviceId], orderBy: 'paid_at');
    return rows.map(ServicePayment.fromMap).toList();
  }

  /// Admin-only internal costing view (spec section 2) - NEVER surface this
  /// on a customer-facing bill screen/print.
  Future<ServiceProfitBreakdown> profitBreakdown(String serviceId) async {
    final service = await byId(serviceId);
    if (service == null) {
      return ServiceProfitBreakdown(
          serviceRevenue: 0, sparePartCost: 0, otherDirectCost: 0, labourCost: 0, additionalExpense: 0);
    }
    final usages = await sparePartUsages(serviceId);
    final others = await otherCosts(serviceId);
    final sparePartCost = usages.fold<double>(0, (s, u) => s + u.totalCost);
    final otherDirectCost = others.fold<double>(0, (s, o) => s + o.amount);
    return ServiceProfitBreakdown(
      serviceRevenue: service.finalAmount,
      sparePartCost: sparePartCost,
      otherDirectCost: otherDirectCost,
      labourCost: service.labourCost,
      additionalExpense: service.additionalExpense,
    );
  }
}
