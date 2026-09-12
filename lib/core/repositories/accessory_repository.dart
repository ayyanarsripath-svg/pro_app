import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/accessory.dart';
import '../../models/ledger_transaction.dart';
import 'ledger_repository.dart';

class AccessoryRepository {
  final _dbHelper = DatabaseHelper.instance;
  final _ledger = LedgerRepository();

  Future<Accessory> create({
    required String name,
    String? category,
    String? brand,
    String unit = 'pcs',
    double purchasePrice = 0,
    double sellingPrice = 0,
    double lowStockThreshold = 3,
    String? barcode,
  }) async {
    final db = await _dbHelper.database;
    final acc = Accessory(
      id: newId(),
      name: name,
      category: category,
      brand: brand,
      unit: unit,
      purchasePrice: purchasePrice,
      sellingPrice: sellingPrice,
      lowStockThreshold: lowStockThreshold,
      createdAt: DateTime.now(),
      barcode: barcode,
    );
    await db.insert('accessories', acc.toMap());
    return acc;
  }

  /// Looks up an accessory by its exact barcode (manufacturer-scanned or
  /// internally generated) - the core lookup for Purchase Stock Entry,
  /// Sales Bill "Scan Barcode", and the Inventory search/scan screen (spec
  /// items 4, 6, 10). Returns null when no accessory currently owns that
  /// barcode ("Product not found" - spec item 20).
  Future<Accessory?> findByBarcode(String barcode) async {
    final db = await _dbHelper.database;
    final rows = await db.query('accessories', where: 'barcode = ?', whereArgs: [barcode]);
    if (rows.isEmpty) return null;
    return Accessory.fromMap(rows.first);
  }

  /// Duplicate Barcode Protection (spec item 15): true only when no OTHER
  /// accessory already owns this barcode. Pass [excludingId] when checking
  /// during an edit so an accessory doesn't collide with its own existing
  /// barcode. Note this only checks accessories - callers that also need to
  /// guard against a spare part owning the same barcode (barcodes are one
  /// shared identity space) should additionally check
  /// SparePartRepository.isBarcodeAvailable.
  Future<bool> isBarcodeAvailable(String barcode, {String? excludingId}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'accessories',
      where: excludingId != null ? 'barcode = ? AND id != ?' : 'barcode = ?',
      whereArgs: excludingId != null ? [barcode, excludingId] : [barcode],
      limit: 1,
    );
    return rows.isEmpty;
  }

  /// Assigns a scanned or freshly-generated barcode to an existing
  /// accessory (Barcode Generation / "Scan existing manufacturer barcode" -
  /// spec items 5 & 16). Caller is expected to have already checked
  /// [isBarcodeAvailable] (and the spare-part-side equivalent).
  Future<void> setBarcode(String id, String barcode) async {
    final db = await _dbHelper.database;
    await db.update('accessories', {'barcode': barcode}, where: 'id = ?', whereArgs: [id]);
  }

  /// Full movement history for one accessory - every purchase, sale,
  /// adjustment ever recorded against it, oldest first (spec item 9's
  /// "Stock History: Date | Type | Qty | Balance").
  Future<List<AccessoryTransaction>> transactionsFor(String accessoryId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'accessory_transactions',
      where: 'accessory_id = ?',
      whereArgs: [accessoryId],
      orderBy: 'txn_date ASC',
    );
    return rows.map(AccessoryTransaction.fromMap).toList();
  }

  Future<List<Accessory>> all({bool activeOnly = true}) async {
    final db = await _dbHelper.database;
    final rows = await db.query('accessories',
        where: activeOnly ? 'active = 1' : null, orderBy: 'name COLLATE NOCASE');
    return rows.map(Accessory.fromMap).toList();
  }

  Future<List<Accessory>> lowStock() async {
    final items = await all();
    return items.where((a) => a.isLowStock).toList();
  }

  /// Inventory Dashboard's "Today's Purchase" (spec item 14): total ₹ spent
  /// on accessory stock-in transactions within [from, to].
  Future<double> purchaseValueBetween(DateTime from, DateTime to) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
      "SELECT COALESCE(SUM(quantity * unit_price), 0) as total FROM accessory_transactions "
      "WHERE txn_type = 'purchase' AND txn_date >= ? AND txn_date <= ?",
      [from.toIso8601String(), to.toIso8601String()],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Inventory Dashboard's "Today's Sales" (spec item 14): total ₹ from
  /// accessory sale lines within [from, to].
  Future<double> saleValueBetween(DateTime from, DateTime to) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
      "SELECT COALESCE(SUM(-quantity * unit_price), 0) as total FROM accessory_transactions "
      "WHERE txn_type = 'sale' AND txn_date >= ? AND txn_date <= ?",
      [from.toIso8601String(), to.toIso8601String()],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<Accessory?> byId(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('accessories', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Accessory.fromMap(rows.first);
  }

  /// Edits an existing accessory's details - most importantly the
  /// low-stock threshold, which previously could only be set at creation.
  Future<void> update({
    required String id,
    String? name,
    String? category,
    String? brand,
    String? unit,
    double? sellingPrice,
    double? lowStockThreshold,
    String? barcode,
  }) async {
    final db = await _dbHelper.database;
    final rows = await db.query('accessories', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final acc = Accessory.fromMap(rows.first);
    final updated = Accessory(
      id: acc.id,
      name: name ?? acc.name,
      category: category ?? acc.category,
      brand: brand ?? acc.brand,
      unit: unit ?? acc.unit,
      currentStock: acc.currentStock,
      purchasePrice: acc.purchasePrice,
      sellingPrice: sellingPrice ?? acc.sellingPrice,
      lowStockThreshold: lowStockThreshold ?? acc.lowStockThreshold,
      active: acc.active,
      createdAt: acc.createdAt,
      barcode: barcode ?? acc.barcode,
    );
    await db.update('accessories', updated.toMap(), where: 'id = ?', whereArgs: [id]);
  }

  /// Soft-deletes an accessory (admin-gated Delete option).
  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.update('accessories', {'active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  /// Purchase stock-in. Recomputes purchase_price as weighted average and
  /// logs an "investment" ledger row (money spent buying stock - visible in
  /// inventory valuation) WITHOUT touching the Accessories P&L cost line.
  /// Cost of Goods Sold is recognised once, at the moment of sale (see
  /// [recordSaleLine] / SalesRepository), matching the same
  /// realized-cost-only-when-sold rule used for 2nd Hand Mobile so nothing
  /// is double counted between "stock purchased" and "stock sold".
  Future<void> recordPurchase({
    required String accessoryId,
    required double quantity,
    required double unitCost,
    required DateTime date,
    String? purchaseId,
    // Purchase Stock Entry's optional Batch Number / Invoice Number (spec
    // item 4).
    String? batchNumber,
    String? invoiceNumber,
  }) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final rows = await txn.query('accessories', where: 'id = ?', whereArgs: [accessoryId]);
      final acc = Accessory.fromMap(rows.first);
      final newStock = acc.currentStock + quantity;
      final newAvgCost = newStock == 0
          ? unitCost
          : ((acc.currentStock * acc.purchasePrice) + (quantity * unitCost)) / newStock;

      await txn.update('accessories', {'current_stock': newStock, 'purchase_price': newAvgCost},
          where: 'id = ?', whereArgs: [accessoryId]);

      await txn.insert('accessory_transactions', {
        'id': newId(),
        'accessory_id': accessoryId,
        'txn_type': 'purchase',
        'quantity': quantity,
        'unit_price': unitCost,
        'reference_type': 'purchase',
        'reference_id': purchaseId,
        'txn_date': date.toIso8601String(),
        'notes': null,
        'batch_number': batchNumber,
        'invoice_number': invoiceNumber,
      });
    });

    await _ledger.record(
      txnDate: date,
      category: LedgerCategory.accessories,
      txnType: LedgerTxnType.investment,
      referenceType: 'purchase',
      referenceId: purchaseId,
      amount: quantity * unitCost,
      description: 'Accessory purchase',
    );
  }

  /// Called by SalesRepository for each accessory line item on a sales
  /// bill: reduces stock and writes the matching revenue/cost ledger rows
  /// (spec section 4 example: headphone purchase ₹250, sale ₹400).
  Future<void> recordSaleLine({
    required String accessoryId,
    required double quantity,
    required double unitPrice,
    required DateTime date,
    required String saleId,
  }) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final rows = await txn.query('accessories', where: 'id = ?', whereArgs: [accessoryId]);
      final acc = Accessory.fromMap(rows.first);
      await txn.update('accessories', {'current_stock': acc.currentStock - quantity},
          where: 'id = ?', whereArgs: [accessoryId]);
      await txn.insert('accessory_transactions', {
        'id': newId(),
        'accessory_id': accessoryId,
        'txn_type': 'sale',
        'quantity': -quantity,
        'unit_price': unitPrice,
        'reference_type': 'sales_bill',
        'reference_id': saleId,
        'txn_date': date.toIso8601String(),
        'notes': null,
      });
    });
  }

  Future<void> adjustStock({
    required String accessoryId,
    required double quantity,
    required String notes,
    required DateTime date,
  }) async {
    final db = await _dbHelper.database;
    await db.transaction((t) async {
      final rows = await t.query('accessories', where: 'id = ?', whereArgs: [accessoryId]);
      final acc = Accessory.fromMap(rows.first);
      await t.update('accessories', {'current_stock': acc.currentStock + quantity},
          where: 'id = ?', whereArgs: [accessoryId]);
      await t.insert('accessory_transactions', {
        'id': newId(),
        'accessory_id': accessoryId,
        'txn_type': 'adjustment',
        'quantity': quantity,
        'unit_price': acc.purchasePrice,
        'reference_type': 'adjustment',
        'reference_id': null,
        'txn_date': date.toIso8601String(),
        'notes': notes,
      });
    });
  }
}
