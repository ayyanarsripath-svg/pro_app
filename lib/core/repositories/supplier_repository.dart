import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/supplier.dart';

class SupplierRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<Supplier> create({required String name, String? phone, String? address, String? notes}) async {
    final db = await _dbHelper.database;
    final supplier = Supplier(
      id: newId(),
      name: name,
      phone: phone,
      address: address,
      notes: notes,
      createdAt: DateTime.now(),
    );
    await db.insert('suppliers', supplier.toMap());
    return supplier;
  }

  Future<void> update(Supplier supplier) async {
    final db = await _dbHelper.database;
    await db.update('suppliers', supplier.toMap(), where: 'id = ?', whereArgs: [supplier.id]);
  }

  Future<List<Supplier>> all() async {
    final db = await _dbHelper.database;
    final rows = await db.query('suppliers', orderBy: 'name COLLATE NOCASE');
    return rows.map(Supplier.fromMap).toList();
  }

  Future<Supplier?> byId(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('suppliers', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Supplier.fromMap(rows.first);
  }

  /// Deletes a supplier. Purchases already recorded against this supplier
  /// keep their own history (supplier_id is simply left dangling on old
  /// rows), so past purchase/P&L numbers are never affected.
  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
  }
}
