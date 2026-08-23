import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/sales_bill.dart';
import '../../models/ledger_transaction.dart';
import 'accessory_repository.dart';
import 'ledger_repository.dart';
import 'return_repository.dart';
import 'settings_repository.dart';
import '../../models/return_record.dart';

class SaleLineInput {
  final String? accessoryId;
  final String itemName;
  final double quantity;
  final double rate;
  final double cost; // internal purchase cost per unit - never printed on customer bill

  SaleLineInput({
    this.accessoryId,
    required this.itemName,
    required this.quantity,
    required this.rate,
    this.cost = 0,
  });

  double get total => quantity * rate;
  double get totalCost => quantity * cost;
}

/// Sales bill = accessories (or other product) sold to a walk-in customer.
/// Kept entirely separate from Service billing and 2nd Hand sales per the
/// spec's module boundaries, but shares the same premium bill design.
class SalesRepository {
  final _dbHelper = DatabaseHelper.instance;
  final _accessories = AccessoryRepository();
  final _ledger = LedgerRepository();
  final _returns = ReturnRepository();
  final _settings = SettingsRepository();

  Future<String> nextBillNo() async {
    final seq = await _settings.nextSequence('sales_bill_seq');
    return 'SB${seq.toString().padLeft(3, '0')}';
  }

  Future<SalesBill> create({
    required String? customerId,
    required DateTime saleDate,
    required List<SaleLineInput> items,
    double discount = 0,
    double paid = 0,
    String? paymentMethod,
    String? notes,
  }) async {
    final db = await _dbHelper.database;
    final subtotal = items.fold<double>(0, (sum, i) => sum + i.total);
    final total = subtotal - discount;
    final balance = total - paid;
    final billNo = await nextBillNo();

    final bill = SalesBill(
      id: newId(),
      billNo: billNo,
      billType: 'accessory',
      customerId: customerId,
      saleDate: saleDate,
      subtotal: subtotal,
      discount: discount,
      total: total,
      paid: paid,
      balance: balance,
      paymentMethod: paymentMethod,
      notes: notes,
      createdAt: DateTime.now(),
    );

    await db.insert('sales_bills', bill.toMap());

    double totalCost = 0;
    for (final item in items) {
      await db.insert('sales_bill_items', {
        'id': newId(),
        'sale_id': bill.id,
        'accessory_id': item.accessoryId,
        'item_name': item.itemName,
        'quantity': item.quantity,
        'rate': item.rate,
        'cost': item.cost,
        'total': item.total,
      });

      if (item.accessoryId != null) {
        await _accessories.recordSaleLine(
          accessoryId: item.accessoryId!,
          quantity: item.quantity,
          unitPrice: item.rate,
          date: saleDate,
          saleId: bill.id,
        );
      }
      totalCost += item.totalCost;
    }

    await _ledger.record(
      txnDate: saleDate,
      category: LedgerCategory.accessories,
      txnType: LedgerTxnType.revenue,
      referenceType: 'sales_bill',
      referenceId: bill.id,
      amount: total,
      description: 'Accessory sale $billNo',
    );
    if (totalCost > 0) {
      await _ledger.record(
        txnDate: saleDate,
        category: LedgerCategory.accessories,
        txnType: LedgerTxnType.directCost,
        referenceType: 'sales_bill',
        referenceId: bill.id,
        amount: totalCost,
        description: 'Cost of goods sold $billNo',
      );
    }

    return bill;
  }

  Future<List<SalesBill>> all({bool activeOnly = true}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'sales_bills',
      where: activeOnly ? 'active = 1' : null,
      orderBy: 'sale_date DESC',
    );
    return rows.map(SalesBill.fromMap).toList();
  }

  /// Soft-deletes a Sales Bill (same pattern as ServiceRepository.delete /
  /// SecondHandRepository.delete) - keeps the row for accounting history
  /// but clears its ledger entries (revenue + cost of goods sold) so
  /// dashboard/P&L totals correctly drop the deleted bill's amount.
  Future<void> delete(String saleId) async {
    final db = await _dbHelper.database;
    await _ledger.clearForReference('sales_bill', saleId);
    await db.update('sales_bills', {'active': 0}, where: 'id = ?', whereArgs: [saleId]);
  }

  Future<List<SalesBillItem>> itemsFor(String saleId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('sales_bill_items', where: 'sale_id = ?', whereArgs: [saleId]);
    return rows.map(SalesBillItem.fromMap).toList();
  }

  Future<void> recordReturn({
    required String saleId,
    required String accessoryId,
    required double quantity,
    required double amount,
    required DateTime date,
    String? reason,
  }) async {
    await _accessories.adjustStock(
      accessoryId: accessoryId,
      quantity: quantity,
      notes: 'Sales return: $reason',
      date: date,
    );
    await _ledger.record(
      txnDate: date,
      category: LedgerCategory.accessories,
      txnType: LedgerTxnType.returnTxn,
      referenceType: 'sales_bill',
      referenceId: saleId,
      amount: -amount,
      description: 'Sales return: $reason',
    );
    await _returns.log(
      returnType: ReturnType.accessorySalesReturn,
      referenceType: 'sales_bill',
      referenceId: saleId,
      quantity: quantity,
      amount: amount,
      reason: reason,
      returnDate: date,
    );
  }
}
