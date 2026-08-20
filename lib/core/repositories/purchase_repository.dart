import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/purchase.dart';
import '../../models/spare_part.dart';
import '../../models/accessory.dart';
import 'spare_part_repository.dart';
import 'accessory_repository.dart';
import 'ledger_repository.dart';

class PurchaseLineInput {
  final String itemType; // spare_part | accessory
  final String itemId;
  final String itemName;
  final double quantity;
  final double unitCost;

  PurchaseLineInput({
    required this.itemType,
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.unitCost,
  });

  double get totalCost => quantity * unitCost;
}

/// Purchase headers link a supplier to one or more spare-part / accessory
/// line items. Posting a purchase updates inventory + weighted average
/// cost via [SparePartRepository]/[AccessoryRepository], which in turn
/// write the ledger rows the P&L engine reads.
class PurchaseRepository {
  final _dbHelper = DatabaseHelper.instance;
  final _spareParts = SparePartRepository();
  final _accessories = AccessoryRepository();

  Future<Purchase> create({
    required String? supplierId,
    required DateTime purchaseDate,
    required String category,
    required List<PurchaseLineInput> items,
    double paidAmount = 0,
    String? notes,
    String? purchaseNo,
  }) async {
    final db = await _dbHelper.database;
    final total = items.fold<double>(0, (sum, i) => sum + i.totalCost);
    final purchase = Purchase(
      id: newId(),
      purchaseNo: purchaseNo ?? '',
      supplierId: supplierId,
      purchaseDate: purchaseDate,
      category: category,
      totalAmount: total,
      paidAmount: paidAmount,
      notes: notes,
      createdAt: DateTime.now(),
    );

    await db.insert('purchases', purchase.toMap());

    for (final item in items) {
      await db.insert('purchase_items', {
        'id': newId(),
        'purchase_id': purchase.id,
        'item_type': item.itemType,
        'item_id': item.itemId,
        'item_name': item.itemName,
        'quantity': item.quantity,
        'unit_cost': item.unitCost,
        'total_cost': item.totalCost,
      });

      if (item.itemType == 'spare_part') {
        await _spareParts.recordPurchase(
          sparePartId: item.itemId,
          quantity: item.quantity,
          unitCost: item.unitCost,
          date: purchaseDate,
          purchaseId: purchase.id,
        );
      } else if (item.itemType == 'accessory') {
        await _accessories.recordPurchase(
          accessoryId: item.itemId,
          quantity: item.quantity,
          unitCost: item.unitCost,
          date: purchaseDate,
          purchaseId: purchase.id,
        );
      }
    }

    return purchase;
  }

  Future<List<Purchase>> all() async {
    final db = await _dbHelper.database;
    final rows = await db.query('purchases', orderBy: 'purchase_date DESC');
    return rows.map(Purchase.fromMap).toList();
  }

  Future<List<PurchaseItem>> itemsFor(String purchaseId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('purchase_items', where: 'purchase_id = ?', whereArgs: [purchaseId]);
    return rows.map(PurchaseItem.fromMap).toList();
  }

  /// Deletes a purchase: reverses the stock/weighted-average-cost impact of
  /// every line item (exact reversal if nothing else touched that item
  /// since), removes its transaction-log rows and any ledger entries tied
  /// to it (e.g. the accessory "investment" row), then the line items and
  /// the purchase header itself.
  Future<void> delete(String id) async {
    final items = await itemsFor(id);

    for (final item in items) {
      if (item.itemType == 'spare_part') {
        await _reverseSparePart(item);
      } else if (item.itemType == 'accessory') {
        await _reverseAccessory(item);
      }
    }

    final db = await _dbHelper.database;
    await db.delete('purchase_items', where: 'purchase_id = ?', whereArgs: [id]);
    await db.delete('purchases', where: 'id = ?', whereArgs: [id]);
    await LedgerRepository().clearForReference('purchase', id);
  }

  Future<void> _reverseSparePart(PurchaseItem item) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final rows = await txn.query('spare_parts', where: 'id = ?', whereArgs: [item.itemId]);
      if (rows.isEmpty) return;
      final part = SparePart.fromMap(rows.first);
      final newStock = part.currentStock - item.quantity;
      final newAvgCost = newStock > 0
          ? ((part.currentStock * part.avgPurchaseCost) - (item.quantity * item.unitCost)) / newStock
          : 0.0;
      await txn.update(
        'spare_parts',
        {
          'current_stock': newStock < 0 ? 0.0 : newStock,
          'avg_purchase_cost': newAvgCost < 0 ? 0.0 : newAvgCost,
        },
        where: 'id = ?',
        whereArgs: [item.itemId],
      );
      await txn.delete(
        'spare_part_transactions',
        where: 'reference_type = ? AND reference_id = ? AND spare_part_id = ?',
        whereArgs: ['purchase', item.purchaseId, item.itemId],
      );
    });
  }

  Future<void> _reverseAccessory(PurchaseItem item) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      final rows = await txn.query('accessories', where: 'id = ?', whereArgs: [item.itemId]);
      if (rows.isEmpty) return;
      final acc = Accessory.fromMap(rows.first);
      final newStock = acc.currentStock - item.quantity;
      final newAvgCost = newStock > 0
          ? ((acc.currentStock * acc.purchasePrice) - (item.quantity * item.unitCost)) / newStock
          : 0.0;
      await txn.update(
        'accessories',
        {
          'current_stock': newStock < 0 ? 0.0 : newStock,
          'purchase_price': newAvgCost < 0 ? 0.0 : newAvgCost,
        },
        where: 'id = ?',
        whereArgs: [item.itemId],
      );
      await txn.delete(
        'accessory_transactions',
        where: 'reference_type = ? AND reference_id = ? AND accessory_id = ?',
        whereArgs: ['purchase', item.purchaseId, item.itemId],
      );
    });
  }
}
