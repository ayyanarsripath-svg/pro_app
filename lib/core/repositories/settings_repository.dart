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
  // Renamed from the old hardcoded 7-day rule: this now holds the actual
  // number of days between auto-backups (default 1 = daily, see
  // BackupService.runAutoBackupIfDue). Kept as a separate key from
  // weeklyAutoBackupEnabled above (which now just means "auto-backup on/off")
  // so nothing about existing installs breaks.
  static const autoBackupFrequencyDays = 'auto_backup_frequency_days';
  static const googleDriveLinked = 'google_drive_linked';
  static const googleDriveFolderId = 'google_drive_folder_id';
  static const googleDriveFolderName = 'google_drive_folder_name';

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
}
