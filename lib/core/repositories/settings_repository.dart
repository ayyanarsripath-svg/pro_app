import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';

/// Simple key/value store for shop info, admin pin, running bill sequences,
/// backup settings, Google Drive tokens etc.
class SettingsRepository {
  final _dbHelper = DatabaseHelper.instance;

  static const shopName = 'shop_name';
  static const shopTagline = 'shop_tagline';
  static const shopAddress = 'shop_address';
  static const shopPhone = 'shop_phone';
  static const adminPinHash = 'admin_pin_hash';
  static const lastBackupAt = 'last_backup_at';
  static const weeklyAutoBackupEnabled = 'weekly_auto_backup_enabled';
  static const googleDriveLinked = 'google_drive_linked';
  static const lastDriveBackupAt = 'last_drive_backup_at';
  static const dailyDriveAutoBackupEnabled = 'daily_drive_auto_backup_enabled';
  static const complaintPresets = 'complaint_presets';
  static const logoPath = 'logo_path';

  // Daily Orders (daily supplier order note - see DailyOrderScreen). One
  // supplier per day (spec: simpler than per-row supplier splitting), so
  // the picked supplier's own name/phone are stored directly here rather
  // than as a foreign key - the shop can change it any day from Settings
  // without touching the Suppliers list.
  static const dailyOrderSupplierName = 'daily_order_supplier_name';
  static const dailyOrderSupplierPhone = 'daily_order_supplier_phone';
  static const dailyOrderSendTime = 'daily_order_send_time'; // 'HH:mm', e.g. '12:30'
  static const dailyOrderReminderEnabled = 'daily_order_reminder_enabled';
  static const lastOrderReminderAt = 'last_order_reminder_at';

  // NOTE: the Daily Orders home-screen widget's on/off toggle is
  // deliberately NOT a key in this table. Backups (see BackupService) work
  // by copying the whole SQLite database file, so anything stored here goes
  // into every backup and Google Drive upload. The widget toggle is stored
  // instead via DailyOrderWidgetService, which uses the home_widget
  // package's own SharedPreferences-backed storage - a separate file the
  // backup never touches - matching the requirement that widget settings
  // stay purely local to the device.

  Future<String?> get(String key) async {
    final db = await _dbHelper.database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> set(String key, String value) async {
    final db = await _dbHelper.database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String>> getAll() async {
    final db = await _dbHelper.database;
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: (r['value'] as String? ?? '')};
  }

  /// Returns the next running number for a bill-number sequence
  /// (e.g. "service_seq", "sales_seq", "second_hand_purchase_seq",
  /// "second_hand_sale_seq") and persists the increment so numbering is
  /// gap-free and never resets across app restarts.
  Future<int> nextSequence(String sequenceKey) async {
    final current = await get(sequenceKey);
    final next = (int.tryParse(current ?? '0') ?? 0) + 1;
    await set(sequenceKey, next.toString());
    return next;
  }

  /// Shop-editable quick-pick list of common fault/complaint phrases shown
  /// as chips on the service intake form (spec: quick-select presets the
  /// shop can extend themselves). Stored as a simple pipe-separated string
  /// so no JSON dependency is needed; falls back to a sensible default set
  /// the first time the app runs.
  Future<List<String>> getComplaintPresets() async {
    final raw = await get(complaintPresets);
    if (raw == null || raw.trim().isEmpty) {
      return const [
        'Display',
        'Battery',
        'Charging Port',
        'Speaker',
        'Mic',
        'Camera',
        'Button',
        'Water Damage',
        'Software',
      ];
    }
    return raw.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  Future<void> saveComplaintPresets(List<String> presets) async {
    await set(complaintPresets, presets.join('|'));
  }
}
