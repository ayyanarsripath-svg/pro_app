import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/spare_part.dart';
import '../../models/return_record.dart';
import '../../models/spare_part_usage.dart';
import 'return_repository.dart';

class SparePartRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<SparePart> create({
    required String name,
    String? category,
    String? compatibleModel,
    String unit = 'pcs',
    double lowStockThreshold = 2,
  }) async {
    final db = await _dbHelper.database;
    final part = SparePart(
      id: newId(),
      name: name,
      category: category,
      compatibleModel: compatibleModel,
      unit: unit,
      lowStockThreshold: lowStockThreshold,
      createdAt: DateTime.now(),
    );
    await db.insert('spare_parts', part.toMap());
    return part;
  }

  Future<List<SparePart>> all({bool activeOnly = true}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'spare_parts',
      where: activeOnly ? 'active = 1' : null,
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(SparePart.fromMap).toList();
  }

  Future<List<SparePart>> lowStock() async {
    final parts = await all();
    return parts.where((p) => p.isLowStock).toList();
  }

  Future<SparePart?> byId(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('spare_parts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return SparePart.fromMap(rows.first);
  }

  /// Edits an existing spare part's details (name/category/model/threshold).
  Future<void> update({
    required String id,
    String? name,
    String? category,
    String? compatibleModel,
    String? unit,
    double? lowStockThreshold,
  }) async {
    final db = await _dbHelper.database;
    final rows = await db.query('spare_parts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final part = SparePart.fromMap(rows.first);
    final updated = SparePart(
      id: part.id,
      name: name ?? part.name,
      category: category ?? part.category,
      compatibleModel: compatibleModel ?? part.compatibleModel,
      unit: unit ?? part.unit,
      currentStock: part.currentStock,
      avgPurchaseCost: part.avgPurchaseCost,
      lowStockThreshold: lowStockThreshold ?? part.lowStockThreshold,
      active: part.active,
      createdAt: part.createdAt,
    );
    await db.update('spare_parts', updated.toMap(), where: 'id = ?', whereArgs: [id]);
  }

  /// Soft-deletes a spare part (admin-gated Delete option).
  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.update('spare_parts', {'active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  /// Records a spare-part purchase: increases stock and recomputes the
  /// weighted-average purchase cost used for internal service costing
  /// (spec section 3 example: Samsung A15 Display, 5 x ₹1,500).
  Future<void> recordPurchase({
    required String sparePartId,
    required double quantity,
    required double unitCost,
    required DateTime date,
    String? purchaseId,
    String? notes,
  }) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final rows = await txn.query('spare_parts', where: 'id = ?', whereArgs: [sparePartId]);
      final part = SparePart.fromMap(rows.first);
      final newStock = part.currentStock + quantity;
      final newAvgCost = newStock == 0
          ? unitCost
          : ((part.currentStock * part.avgPurchaseCost) + (quantity * unitCost)) / newStock;

      await txn.update(
        'spare_parts',
        {'current_stock': newStock, 'avg_purchase_cost': newAvgCost},
        where: 'id = ?',
        whereArgs: [sparePartId],
      );

      await txn.insert('spare_part_transactions', {
        'id': newId(),
        'spare_part_id': sparePartId,
        'txn_type': 'purchase',
        'quantity': quantity,
        'unit_cost': unitCost,
        'reference_type': 'purchase',
        'reference_id': purchaseId,
        'txn_date': date.toIso8601String(),
        'notes': notes,
      });
    });
  }

  /// Consumes stock for a service repair or a 2nd-hand phone repair job,
  /// linking the exact cost (at that part's current average cost) to the
  /// service/phone so its internal profit calculation is accurate
  /// (spec section 2 & section 3 example: Service A125 -> Display Cost ₹1,500).
  Future<double> useForService({
    required String sparePartId,
    required double quantity,
    required String referenceType, // 'service' | 'second_hand'
    required String referenceId,
    required DateTime date,
    Transaction? txn,
  }) async {
    Future<double> run(Transaction t) async {
      final rows = await t.query('spare_parts', where: 'id = ?', whereArgs: [sparePartId]);
      final part = SparePart.fromMap(rows.first);
      final unitCost = part.avgPurchaseCost;
      final newStock = part.currentStock - quantity;

      await t.update('spare_parts', {'current_stock': newStock}, where: 'id = ?', whereArgs: [sparePartId]);

      await t.insert('spare_part_transactions', {
        'id': newId(),
        'spare_part_id': sparePartId,
        'txn_type': referenceType == 'second_hand' ? 'second_hand_usage' : 'service_usage',
        'quantity': -quantity,
        'unit_cost': unitCost,
        'reference_type': referenceType,
        'reference_id': referenceId,
        'txn_date': date.toIso8601String(),
        'notes': null,
      });
      return unitCost * quantity;
    }

    if (txn != null) return run(txn);
    final db = await _dbHelper.database;
    return db.transaction(run);
  }

  /// Full audit trail of every spare part used on a Service Bill (spec item
  /// 2's "Spare Parts list") - every row [useForService] has ever written
  /// for `reference_type = 'service'`, joined with the part's own name and
  /// that bill's number/mobile name/model, newest first. Read-only: this is
  /// purely a report over data every "Add Part" already recorded, not a new
  /// place to enter anything.
  Future<List<SparePartUsage>> serviceUsageLog({DateTime? from, DateTime? to}) async {
    final db = await _dbHelper.database;
    // s.active = 1 excludes a soft-deleted Service Bill's usage rows - a
    // delete already clears that bill's own P&L ledger entries (see
    // ServiceRepository.delete), so leaving this report showing cost for a
    // deleted bill would contradict the "this is exactly what's counted in
    // P&L" promise this screen makes.
    final where = StringBuffer("t.txn_type = 'service_usage' AND t.reference_type = 'service' AND s.active = 1");
    final args = <Object?>[];
    if (from != null && to != null) {
      where.write(' AND t.txn_date >= ? AND t.txn_date <= ?');
      args.addAll([from.toIso8601String(), to.toIso8601String()]);
    }
    final rows = await db.rawQuery('''
      SELECT t.id, t.quantity, t.unit_cost, t.txn_date,
             p.name AS part_name, p.category AS part_category,
             s.bill_no, s.mobile_name, s.model
      FROM spare_part_transactions t
      JOIN spare_parts p ON p.id = t.spare_part_id
      JOIN services s ON s.id = t.reference_id
      WHERE $where
      ORDER BY t.txn_date DESC
    ''', args);
    return rows.map(SparePartUsage.fromMap).toList();
  }

  Future<void> adjustStock({
    required String sparePartId,
    required double quantity, // signed
    required String notes,
    required DateTime date,
  }) async {
    final db = await _dbHelper.database;
    await db.transaction((t) async {
      final rows = await t.query('spare_parts', where: 'id = ?', whereArgs: [sparePartId]);
      final part = SparePart.fromMap(rows.first);
      await t.update('spare_parts', {'current_stock': part.currentStock + quantity},
          where: 'id = ?', whereArgs: [sparePartId]);
      await t.insert('spare_part_transactions', {
        'id': newId(),
        'spare_part_id': sparePartId,
        'txn_type': 'adjustment',
        'quantity': quantity,
        'unit_cost': part.avgPurchaseCost,
        'reference_type': 'adjustment',
        'reference_id': null,
        'txn_date': date.toIso8601String(),
        'notes': notes,
      });
    });
  }

  /// Supplier return: reduces stock, does not touch the average cost of
  /// remaining stock.
  Future<void> returnToSupplier({
    required String sparePartId,
    required double quantity,
    required DateTime date,
    String? notes,
  }) async {
    final db = await _dbHelper.database;
    await db.transaction((t) async {
      final rows = await t.query('spare_parts', where: 'id = ?', whereArgs: [sparePartId]);
      final part = SparePart.fromMap(rows.first);
      await t.update('spare_parts', {'current_stock': part.currentStock - quantity},
          where: 'id = ?', whereArgs: [sparePartId]);
      await t.insert('spare_part_transactions', {
        'id': newId(),
        'spare_part_id': sparePartId,
        'txn_type': 'supplier_return',
        'quantity': -quantity,
        'unit_cost': part.avgPurchaseCost,
        'reference_type': 'supplier_return',
        'reference_id': null,
        'txn_date': date.toIso8601String(),
        'notes': notes,
      });
    });
    await ReturnRepository().log(
      returnType: ReturnType.sparePartSupplierReturn,
      referenceType: 'spare_part',
      referenceId: sparePartId,
      quantity: quantity,
      returnDate: date,
      notes: notes,
    );
  }
}
