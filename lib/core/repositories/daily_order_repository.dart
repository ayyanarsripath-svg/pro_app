import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/daily_order_item.dart';

class DailyOrderRepository {
  final _dbHelper = DatabaseHelper.instance;

  /// Adds one row to [orderDate]'s note. S.No is simply "how many rows this
  /// date already has, plus one" - matches the spec's plain running s.no
  /// per day.
  Future<DailyOrderItem> create({
    required String orderDate,
    required String partName,
    String? typeModel,
    required String quantity,
    String? phone,
  }) async {
    final db = await _dbHelper.database;
    final existing = await db.query('daily_order_items', where: 'order_date = ?', whereArgs: [orderDate]);
    final item = DailyOrderItem(
      id: newId(),
      orderDate: orderDate,
      sNo: existing.length + 1,
      partName: partName,
      typeModel: typeModel,
      quantity: quantity,
      phone: phone,
      sent: false,
      createdAt: DateTime.now(),
    );
    await db.insert('daily_order_items', item.toMap());
    return item;
  }

  Future<void> update(DailyOrderItem item) async {
    final db = await _dbHelper.database;
    await db.update('daily_order_items', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('daily_order_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<DailyOrderItem>> itemsForDate(String orderDate) async {
    final db = await _dbHelper.database;
    final rows = await db.query('daily_order_items', where: 'order_date = ?', whereArgs: [orderDate], orderBy: 's_no ASC');
    return rows.map(DailyOrderItem.fromMap).toList();
  }

  /// Every item not yet sent, regardless of which date it was noted on,
  /// oldest date first. This IS the "carry forward to the next day" rule
  /// in practice: a day that never got sent simply stays unsent and keeps
  /// showing up here (each row still carrying its own original date) until
  /// it's actually sent - no separate "rollover" step needed.
  Future<List<DailyOrderItem>> unsentItems() async {
    final db = await _dbHelper.database;
    final rows = await db.query('daily_order_items', where: 'sent = 0', orderBy: 'order_date ASC, s_no ASC');
    return rows.map(DailyOrderItem.fromMap).toList();
  }

  /// Marks a batch of items sent in one go (used right after the Send
  /// Order flow) - all get the same sent_at timestamp since they were sent
  /// together in the same PDF/WhatsApp message.
  Future<void> markSent(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final id in ids) {
      batch.update('daily_order_items', {'sent': 1, 'sent_at': now}, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  /// Full history (sent and unsent), most recently noted date first - used
  /// by DailyOrderScreen's date-grouped list.
  Future<List<DailyOrderItem>> all() async {
    final db = await _dbHelper.database;
    final rows = await db.query('daily_order_items', orderBy: 'order_date DESC, s_no ASC');
    return rows.map(DailyOrderItem.fromMap).toList();
  }
}
