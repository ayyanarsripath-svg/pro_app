import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/warranty_claim.dart';

class WarrantyRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<WarrantyClaim> fileClaim({
    required String claimType,
    required String referenceId,
    required String description,
  }) async {
    final db = await _dbHelper.database;
    final claim = WarrantyClaim(
      id: newId(),
      claimType: claimType,
      referenceId: referenceId,
      claimDate: DateTime.now(),
      description: description,
      status: 'Open',
      createdAt: DateTime.now(),
    );
    await db.insert('warranty_claims', claim.toMap());
    return claim;
  }

  Future<void> resolve(String id, {required String resolution, double cost = 0}) async {
    final db = await _dbHelper.database;
    await db.update('warranty_claims', {'resolution': resolution, 'cost': cost, 'status': 'Resolved'},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<List<WarrantyClaim>> forReference(String referenceId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('warranty_claims', where: 'reference_id = ?', whereArgs: [referenceId], orderBy: 'claim_date DESC');
    return rows.map(WarrantyClaim.fromMap).toList();
  }

  Future<List<WarrantyClaim>> all() async {
    final db = await _dbHelper.database;
    final rows = await db.query('warranty_claims', orderBy: 'claim_date DESC');
    return rows.map(WarrantyClaim.fromMap).toList();
  }
}
