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
    String? complaint, String? faultAmounts,
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
    String? warrantyPeriods,
    String? offers,
    double estimatedAmount = 0,
    double finalAmount = 0,
    double advance = 0,
    double discount = 0,
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
      complaint: complaint, faultAmounts: faultAmounts,
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
      warrantyPeriods: warrantyPeriods,
      offers: offers,
      estimatedAmount: estimatedAmount,
      finalAmount: finalAmount,
      discount: discount,
      advance: advance,
      paid: advance,
      balance: finalAmount - advance - discount,
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
    // Net of any bargained-off discount, same as displayBalance - so P&L
    // never overstates realized service revenue/profit by the discounted
    // amount (matches the 2nd Hand Sale netPrice convention).
    final netRevenue = service.finalAmount - service.discount;
    if (netRevenue > 0) {
      await _ledger.record(
        txnDate: service.createdAt,
        category: LedgerCategory.service,
        txnType: LedgerTxnType.revenue,
        referenceType: 'service_core',
        referenceId: service.id,
        amount: netRevenue,
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
      complaint: service.complaint, faultAmounts: service.faultAmounts,
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
      warrantyPeriods: service.warrantyPeriods,
      offers: service.offers,
      estimatedAmount: service.estimatedAmount,
      finalAmount: service.finalAmount,
      discount: service.discount,
      advance: service.advance,
      paid: service.paid,
      balance: service.finalAmount - service.paid - service.discount,
      expectedDate: service.expectedDate,
      actualDate: service.actualDate,
      deliveryPerson: service.deliveryPerson,
      deliveryStatus: service.deliveryStatus,
      additionalExpense: service.additionalExpense,
      active: service.active,
      createdAt: service.createdAt,
      updatedAt: DateTime.now(),
    );
    await db.update('services', updated.toMap(), where: 'id = ?', whereArgs: [service.id]);
    await _syncCoreLedger(updated);
  }


  /// Soft-deletes a service job (spec: Delete option gated by admin
  /// "Delete Records" permission). Keeps the row itself (spec: accounting
  /// integrity) but clears this service's ledger entries (core amount,
  /// spare-part costs, other costs) so dashboard/P&L totals correctly
  /// drop the deleted bill's amount.
  Future<void> delete(String serviceId) async {
    final db = await _dbHelper.database;
    await _ledger.clearForReference('service_core', serviceId);
    final usages = await sparePartUsages(serviceId);
    for (final u in usages) {
      await _ledger.clearForReference('service_spare_part', u.id);
    }
    final others = await otherCosts(serviceId);
    for (final o in others) {
      await _ledger.clearForReference('service_other_cost', o.id);
    }
    await db.update('services', {'active': 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [serviceId]);
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
      {'paid': newPaid, 'balance': current.finalAmount - newPaid - current.discount, 'updated_at': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [serviceId],
    );
  }

  /// BUG FIX (P&L daily/weekly/monthly tally): every direct-cost method
  /// below used to ledger its cost on [date] - literally "today", whatever
  /// day the technician happened to add the part/cost, days or weeks after
  /// the job was actually created. Meanwhile the job's REVENUE is always
  /// ledgered on the service's own createdAt (see _syncCoreLedger). A job
  /// created Monday whose part gets added Thursday therefore split its
  /// revenue and cost across two different ledger dates - Monday's P&L
  /// looked artificially profitable (revenue, no matching cost yet) and
  /// Thursday's looked artificially lossy (cost with no matching revenue),
  /// even though the two fell in the same month and the MONTHLY total
  /// still happened to add up. Daily and Weekly views had no such luck
  /// (spec: "profit and loss dash board and monthly and weekly calculation
  /// thappa kamikkuthu" - matches exactly this symptom). Every direct cost
  /// tied to a service now ledgers on the SAME date as that service's
  /// revenue, so a single bill's revenue and cost always land in the same
  /// P&L day/week/month no matter which day the part was actually used.
  /// [date] itself is untouched for inventory purposes (stock still
  /// depletes on the real day the part was used, which is correct).
  Future<DateTime> _ledgerDateForService(String serviceId, DateTime fallback) async {
    final service = await byId(serviceId);
    return service?.createdAt ?? fallback;
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
      txnDate: await _ledgerDateForService(serviceId, date),
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
      txnDate: await _ledgerDateForService(serviceId, date),
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
      txnDate: await _ledgerDateForService(serviceId, date),
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

  Future<List<ServiceJob>> all({String? statusFilter, bool activeOnly = true}) async {
    final db = await _dbHelper.database;
    final conditions = <String>[];
    final args = <Object?>[];
    if (activeOnly) conditions.add('active = 1');
    if (statusFilter != null) {
      conditions.add('status = ?');
      args.add(statusFilter);
    }
    final rows = await db.query(
      'services',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
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
