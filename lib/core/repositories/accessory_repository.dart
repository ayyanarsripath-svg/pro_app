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
    );
    await db.insert('accessories', acc.toMap());
    return acc;
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

  Future<Accessory?> byId(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('accessories', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Accessory.fromMap(rows.first);
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
