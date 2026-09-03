import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/daily_order_item.dart';

class DailyOrderRepository {
  final _dbHelper = DatabaseHelper.instance;

  /// Adds one row to [orderDate]'s note. S.No is "how many rows this date's
  /// current (still-unsent) batch already has, plus one" - counting only
  /// unsent rows means the numbering restarts at 1 for the next batch as
  /// soon as the previous batch is marked sent, instead of continuing to
  /// climb for the rest of the day (e.g. batch one prints 1,2,3; once sent,
  /// a fresh batch noted later the same day prints 1,2,3 again, not 4,5,6).
  Future<DailyOrderItem> create({
    required String orderDate,
    required String partName,
    String? typeModel,
    required String quantity,
    String? phone,
  }) async {
    final db = await _dbHelper.database;
    final existing = await db.query(
      'daily_order_items',
      where: 'order_date = ? AND sent = 0',
      whereArgs: [orderDate],
    );
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

  /// Marks a single sent item as physically received at the shop. Once
  /// received, DailyOrderScreen hides the row (it's done) instead of
  /// deleting it, so the order history stays intact.
  Future<void> markReceived(String id) async {
    final db = await _dbHelper.database;
    await db.update('daily_order_items', {'received': 1}, where: 'id = ?', whereArgs: [id]);
  }

  /// Sends a sent-but-not-yet-received item back to the order note (spec:
  /// "yellow x round touch panna thirumba order note ku antha particular
  /// order poganum" - tapping the yellow Not Received icon must actually
  /// move that item back to the order note, not just show an
  /// acknowledgement toast). Clears [sent]/[sentAt]/[received] so the item
  /// flows straight back into [unsentItems] and gets included in whatever
  /// batch is sent next.
  ///
  /// Recomputes s_no the exact same way [create] does - one more than
  /// however many OTHER items are currently unsent for this item's own
  /// order_date - so it slots in after whatever's already waiting on that
  /// date instead of keeping a stale s_no left over from its old (now-sent)
  /// batch, which could otherwise collide with an s_no already in use.
  Future<void> resetToPending(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('daily_order_items', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final orderDate = rows.first['order_date'] as String;
    final existing = await db.query(
      'daily_order_items',
      where: 'order_date = ? AND sent = 0 AND id != ?',
      whereArgs: [orderDate, id],
    );
    await db.update(
      'daily_order_items',
      {'sent': 0, 'sent_at': null, 'received': 0, 's_no': existing.length + 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Full history (sent and unsent), most recently noted date first - used
  /// by DailyOrderScreen's date-grouped list.
  Future<List<DailyOrderItem>> all() async {
    final db = await _dbHelper.database;
    final rows = await db.query('daily_order_items', orderBy: 'order_date DESC, s_no ASC');
    return rows.map(DailyOrderItem.fromMap).toList();
  }

  /// Most recently ADDED items (by [DailyOrderItem.createdAt], not by
  /// [orderDate]/s_no like [all]/[itemsForDate]) - used by the home-screen
  /// widget's Quick Add screen to show a short "what did I just note down"
  /// history right under the Save buttons (spec: "quick add order la save
  /// and add another button kizha 10 history need kurippa recent items
  /// history top la varanum"), so a shop owner adding several items in a
  /// row there can see their own recent entries without switching to the
  /// full app. Newest first, capped at [limit].
  Future<List<DailyOrderItem>> recent({int limit = 10}) async {
    final db = await _dbHelper.database;
    final rows = await db.query('daily_order_items', orderBy: 'created_at DESC', limit: limit);
    return rows.map(DailyOrderItem.fromMap).toList();
  }
}
