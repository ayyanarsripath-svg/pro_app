import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/return_record.dart';

/// General-purpose returns log (spec section 31). Category-specific stock /
/// ledger effects are handled by the owning repository (SalesRepository,
/// SecondHandRepository, SparePartRepository) - this table is the audit
/// trail shown in Reports.
class ReturnRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<ReturnRecord> log({
    required String returnType,
    String? referenceType,
    String? referenceId,
    String? itemName,
    double quantity = 1,
    double amount = 0,
    String? reason,
    required DateTime returnDate,
    String? refundMethod,
    String? notes,
  }) async {
    final db = await _dbHelper.database;
    final record = ReturnRecord(
      id: newId(),
      returnType: returnType,
      referenceType: referenceType,
      referenceId: referenceId,
      itemName: itemName,
      quantity: quantity,
      amount: amount,
      reason: reason,
      returnDate: returnDate,
      refundMethod: refundMethod,
      notes: notes,
      createdAt: DateTime.now(),
    );
    await db.insert('returns', record.toMap());
    return record;
  }

  Future<List<ReturnRecord>> all() async {
    final db = await _dbHelper.database;
    final rows = await db.query('returns', orderBy: 'return_date DESC');
    return rows.map(ReturnRecord.fromMap).toList();
  }
}
