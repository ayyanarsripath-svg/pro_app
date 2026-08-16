import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/purchase.dart';
import 'spare_part_repository.dart';
import 'accessory_repository.dart';

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
}
