import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/second_hand_phone.dart';
import '../../models/ledger_transaction.dart';
import 'ledger_repository.dart';
import 'return_repository.dart';
import 'settings_repository.dart';
import 'spare_part_repository.dart';
import '../../models/return_record.dart';

/// 2nd Hand Mobile module - completely separate from Accessories, per spec
/// section 6. Every purchase, repair cost and sale is transaction-based so
/// realized profit is never confused with potential/unsold profit
/// (spec section 9).
class SecondHandRepository {
  final _dbHelper = DatabaseHelper.instance;
  final _ledger = LedgerRepository();
  final _settings = SettingsRepository();
  final _spareParts = SparePartRepository();

  Future<String> nextPurchaseNo() async {
    final seq = await _settings.nextSequence('second_hand_purchase_seq');
    return 'SH${seq.toString().padLeft(3, '0')}';
  }

  Future<String> nextSaleBillNo() async {
    final seq = await _settings.nextSequence('second_hand_sale_seq');
    return 'SHB${seq.toString().padLeft(3, '0')}';
  }

  Future<SecondHandPhone> recordPurchase({
    required DateTime purchaseDate,
    String? sellerName,
    String? sellerPhone,
    String? brand,
    String? model,
    String? imei1,
    String? imei2,
    String? ram,
    String? storage,
    String? colour,
    String? conditionGrade,
    String? batteryHealth,
    String? displayCondition,
    String? bodyCondition,
    String? accessoriesReceived,
    required double purchasePrice,
    double otherCost = 0,
    double expectedSellingPrice = 0,
    bool warranty = false,
    String? warrantyPeriod,
    String? notes,
    String? photoPath,
  }) async {
    final db = await _dbHelper.database;
    final phone = SecondHandPhone(
      id: newId(),
      purchaseNo: await nextPurchaseNo(),
      purchaseDate: purchaseDate,
      sellerName: sellerName,
      sellerPhone: sellerPhone,
      brand: brand,
      model: model,
      imei1: imei1,
      imei2: imei2,
      ram: ram,
      storage: storage,
      colour: colour,
      conditionGrade: conditionGrade,
      batteryHealth: batteryHealth,
      displayCondition: displayCondition,
      bodyCondition: bodyCondition,
      accessoriesReceived: accessoriesReceived,
      purchasePrice: purchasePrice,
      otherCost: otherCost,
      expectedSellingPrice: expectedSellingPrice,
      warranty: warranty,
      warrantyPeriod: warrantyPeriod,
      notes: notes,
      photoPath: photoPath,
      status: SecondHandStatus.purchased,
      createdAt: DateTime.now(),
    );
    await db.insert('second_hand_phones', phone.toMap());

    // The purchase price is an investment into stock, not an expense yet -
    // it becomes "cost" against revenue only when the phone actually sells
    // (handled in recordSale), matching spec section 9's realized-vs-
    // potential profit rule. We still log it so "Investment Value" on the
    // stock dashboard (section 8) can be computed from the ledger too.
    await _ledger.record(
      txnDate: purchaseDate,
      category: LedgerCategory.secondHand,
      txnType: LedgerTxnType.investment,
      referenceType: 'second_hand_phone',
      referenceId: phone.id,
      amount: purchasePrice + otherCost,
      description: '2nd hand purchase ${phone.purchaseNo}',
    );

    return phone;
  }

  Future<void> updateStatus(String phoneId, String status) async {
    final db = await _dbHelper.database;
    await db.update('second_hand_phones', {'status': status}, where: 'id = ?', whereArgs: [phoneId]);
  }

  Future<void> update(SecondHandPhone phone) async {
    final db = await _dbHelper.database;
    await db.update('second_hand_phones', phone.toMap(), where: 'id = ?', whereArgs: [phone.id]);
  }

  /// Adds a repair line (spec section 7 example: Display Repair ₹1,500,
  /// Battery ₹800). If linked to a spare part, stock is consumed at that
  /// part's current average cost.
  Future<void> addRepairItem({
    required String phoneId,
    required String description,
    String? sparePartId,
    double quantity = 1,
    required double cost,
    required DateTime date,
  }) async {
    final db = await _dbHelper.database;
    double actualCost = cost;
    if (sparePartId != null) {
      actualCost = await _spareParts.useForService(
        sparePartId: sparePartId,
        quantity: quantity,
        referenceType: 'second_hand',
        referenceId: phoneId,
        date: date,
      );
    }
    await db.insert('second_hand_repair_items', {
      'id': newId(),
      'phone_id': phoneId,
      'description': description,
      'spare_part_id': sparePartId,
      'quantity': quantity,
      'cost': actualCost,
    });
    await _ledger.record(
      txnDate: date,
      category: LedgerCategory.secondHand,
      txnType: LedgerTxnType.investment,
      referenceType: 'second_hand_phone',
      referenceId: phoneId,
      amount: actualCost,
      description: 'Repair: $description',
    );
    // Move to "Repairing" automatically the first time a repair cost is added.
    final rows = await db.query('second_hand_phones', where: 'id = ?', whereArgs: [phoneId]);
    final phone = SecondHandPhone.fromMap(rows.first);
    if (phone.status == SecondHandStatus.purchased) {
      await updateStatus(phoneId, SecondHandStatus.repairing);
    }
  }

  Future<List<SecondHandRepairItem>> repairItems(String phoneId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('second_hand_repair_items', where: 'phone_id = ?', whereArgs: [phoneId]);
    return rows.map(SecondHandRepairItem.fromMap).toList();
  }

  /// Records the sale of a 2nd hand phone: this is the ONLY moment realized
  /// gross profit is recognised (spec section 9 - unsold stock's expected
  /// profit must never be counted as realized).
  Future<SecondHandSale> recordSale({
    required String phoneId,
    required String? customerId,
    required DateTime saleDate,
    required double salePrice,
    String? paymentMethod,
    double paid = 0,
    bool warranty = false,
    String? warrantyPeriod,
    String? notes,
  }) async {
    final db = await _dbHelper.database;
    final billNo = await nextSaleBillNo();
    final sale = SecondHandSale(
      id: newId(),
      phoneId: phoneId,
      billNo: billNo,
      customerId: customerId,
      saleDate: saleDate,
      salePrice: salePrice,
      paymentMethod: paymentMethod,
      paid: paid,
      balance: salePrice - paid,
      warranty: warranty,
      warrantyPeriod: warrantyPeriod,
      notes: notes,
      createdAt: DateTime.now(),
    );
    await db.insert('second_hand_sales', sale.toMap());
    await db.update(
      'second_hand_phones',
      {
        'status': SecondHandStatus.sold,
        'actual_selling_price': salePrice,
        'sale_date': saleDate.toIso8601String(),
        'customer_id': customerId,
      },
      where: 'id = ?',
      whereArgs: [phoneId],
    );

    await _ledger.record(
      txnDate: saleDate,
      category: LedgerCategory.secondHand,
      txnType: LedgerTxnType.revenue,
      referenceType: 'second_hand_sale',
      referenceId: sale.id,
      amount: salePrice,
      description: '2nd hand sale $billNo',
    );

    return sale;
  }

  Future<void> recordReturn({
    required String phoneId,
    required String saleId,
    required double refundAmount,
    required DateTime date,
    String? reason,
    bool restock = true,
  }) async {
    await _ledger.record(
      txnDate: date,
      category: LedgerCategory.secondHand,
      txnType: LedgerTxnType.returnTxn,
      referenceType: 'second_hand_sale',
      referenceId: saleId,
      amount: -refundAmount,
      description: 'Customer return: $reason',
    );
    if (restock) {
      await updateStatus(phoneId, SecondHandStatus.readyForSale);
      final db = await _dbHelper.database;
      await db.update('second_hand_phones', {'actual_selling_price': null, 'sale_date': null},
          where: 'id = ?', whereArgs: [phoneId]);
    } else {
      await updateStatus(phoneId, SecondHandStatus.returned);
    }
    await ReturnRepository().log(
      returnType: ReturnType.secondHandCustomerReturn,
      referenceType: 'second_hand_sale',
      referenceId: saleId,
      amount: refundAmount,
      reason: reason,
      returnDate: date,
    );
  }

  /// Most recent sale row for a phone (a phone only has one sale unless it
  /// was returned and resold, in which case the latest is what matters for
  /// re-printing the bill).
  Future<SecondHandSale?> latestSaleForPhone(String phoneId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'second_hand_sales',
      where: 'phone_id = ?',
      whereArgs: [phoneId],
      orderBy: 'sale_date DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SecondHandSale.fromMap(rows.first);
  }

  Future<List<SecondHandPhone>> all({String? statusFilter}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'second_hand_phones',
      where: statusFilter != null ? 'status = ?' : null,
      whereArgs: statusFilter != null ? [statusFilter] : null,
      orderBy: 'purchase_date DESC',
    );
    final phones = <SecondHandPhone>[];
    for (final row in rows) {
      final items = await repairItems(row['id'] as String);
      final repairCost = items.where((i) => i.sparePartId == null).fold<double>(0, (s, i) => s + i.cost);
      final sparePartCost = items.where((i) => i.sparePartId != null).fold<double>(0, (s, i) => s + i.cost);
      phones.add(SecondHandPhone.fromMap(row, repairCost: repairCost, sparePartCost: sparePartCost));
    }
    return phones;
  }

  Future<SecondHandPhone?> byId(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('second_hand_phones', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final items = await repairItems(id);
    final repairCost = items.where((i) => i.sparePartId == null).fold<double>(0, (s, i) => s + i.cost);
    final sparePartCost = items.where((i) => i.sparePartId != null).fold<double>(0, (s, i) => s + i.cost);
    return SecondHandPhone.fromMap(rows.first, repairCost: repairCost, sparePartCost: sparePartCost);
  }

  /// Stock dashboard summary (spec section 8).
  Future<Map<String, double>> stockSummary() async {
    final phones = await all();
    final unsold = phones.where((p) => p.status != SecondHandStatus.sold && p.status != SecondHandStatus.returned);
    final sold = phones.where((p) => p.status == SecondHandStatus.sold);

    final investmentValue = unsold.fold<double>(0, (s, p) => s + p.totalInvestment);
    final expectedSalesValue = unsold.fold<double>(0, (s, p) => s + p.expectedSellingPrice);
    final soldValue = sold.fold<double>(0, (s, p) => s + (p.actualSellingPrice ?? 0));
    final realizedProfit = sold.fold<double>(0, (s, p) => s + p.realizedProfit);
    final potentialProfit = unsold.fold<double>(0, (s, p) => s + p.potentialProfit);

    return {
      'totalPhones': phones.length.toDouble(),
      'unsoldCount': unsold.length.toDouble(),
      'investmentValue': investmentValue,
      'expectedSalesValue': expectedSalesValue,
      'soldValue': soldValue,
      'currentStockValue': investmentValue,
      'realizedProfit': realizedProfit,
      'potentialProfit': potentialProfit,
    };
  }
}
