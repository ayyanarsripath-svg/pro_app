import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/reorder_task.dart';

class ReorderRepository {
  final _dbHelper = DatabaseHelper.instance;

  /// Deterministic-ish local notification id. flutter_local_notifications
  /// needs a 32-bit int; deriving it from a fresh uuid keeps ids unique
  /// without a separate counter table.
  int _newNotificationId() => DateTime.now().microsecondsSinceEpoch.remainder(1 << 31);

  Future<ReorderTask> create({
    required String note,
    String? supplierId,
    required String supplierName,
    required String supplierPhone,
    required DateTime scheduledAt,
    bool repeatDaily = false,
  }) async {
    final db = await _dbHelper.database;
    final task = ReorderTask(
      id: newId(),
      note: note,
      supplierId: supplierId,
      supplierName: supplierName,
      supplierPhone: supplierPhone,
      scheduledAt: scheduledAt,
      repeatDaily: repeatDaily,
      status: ReorderTask.statusPending,
      notificationId: _newNotificationId(),
      createdAt: DateTime.now(),
    );
    await db.insert('reorder_tasks', task.toMap());
    return task;
  }

  Future<void> update(ReorderTask task) async {
    final db = await _dbHelper.database;
    await db.update('reorder_tasks', task.toMap(), where: 'id = ?', whereArgs: [task.id]);
  }

  Future<void> updateStatus(String id, String status, {String? pdfPath}) async {
    final db = await _dbHelper.database;
    final values = <String, dynamic>{'status': status};
    if (pdfPath != null) values['pdf_path'] = pdfPath;
    await db.update('reorder_tasks', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('reorder_tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ReorderTask>> all() async {
    final db = await _dbHelper.database;
    final rows = await db.query('reorder_tasks', orderBy: 'scheduled_at ASC');
    return rows.map(ReorderTask.fromMap).toList();
  }

  Future<List<ReorderTask>> pendingOrNotified() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'reorder_tasks',
      where: 'status IN (?, ?)',
      whereArgs: [ReorderTask.statusPending, ReorderTask.statusNotified],
      orderBy: 'scheduled_at ASC',
    );
    return rows.map(ReorderTask.fromMap).toList();
  }

  Future<ReorderTask?> byId(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('reorder_tasks', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ReorderTask.fromMap(rows.first);
  }
}
