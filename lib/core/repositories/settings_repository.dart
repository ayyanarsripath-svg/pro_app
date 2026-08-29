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
  static const googleDriveLinked = 'google_drive_linked';
  static const lastDriveBackupAt = 'last_drive_backup_at';
  static const dailyDriveAutoBackupEnabled = 'daily_drive_auto_backup_enabled';
  // Data-loss incident fix (2026-08): the daily Google Drive backup used to
  // fail completely silently (bare catch, nothing logged, nothing shown) -
  // a shop owner had no way to know a backup never actually reached Drive
  // until they lost data restoring from a stale file. These three keys back
  // the new "pending backup" story: driveBackupPending is set the moment an
  // attempt fails and only cleared once a backup actually succeeds again;
  // driveBackupLastError keeps the reason (shown in Settings -> Backup &
  // Restore); driveBackupPendingSince keeps the first failure's timestamp so
  // the UI/notification can say how long it's been waiting. See
  // BackupService.runDailyGoogleDriveBackupIfDue and
  // background_tasks.dart's pending-retry WorkManager task, which together
  // guarantee a failed backup keeps retrying (network-constrained, so it
  // only fires again once the phone actually has internet) until it
  // succeeds, instead of silently waiting for the next calendar day.
  static const driveBackupPending = 'drive_backup_pending';
  static const driveBackupLastError = 'drive_backup_last_error';
  static const driveBackupPendingSince = 'drive_backup_pending_since';

  // Daily Google Drive backup rewrite (2026-08, see BackupService's class
  // doc comment). driveBackupCompletedDateKey is THE unique daily-backup
  // key (spec: "Use a unique daily backup key such as YYYY-MM-DD... Before
  // starting a backup, check whether today's backup has already completed
  // successfully") - set ONLY once a backup for that calendar day has been
  // uploaded AND fully verified (never just "attempted"), so it is always
  // safe to trust as "today is genuinely done". driveBackupRunLockAt is a
  // short-lived best-effort guard against the exact-alarm and WorkManager
  // triggers both landing at nearly the same moment and racing each other
  // into two uploads for the same day - see runDailyGoogleDriveBackupIfDue.
  // The remaining keys mirror the most recent successful upload so Backup
  // & Restore's "Backup History" section (spec item 11) never has to go
  // back out to Drive just to show what it already knows.
  static const driveBackupCompletedDateKey = 'drive_backup_completed_date_key';
  static const driveBackupRunLockAt = 'drive_backup_run_lock_at';
  static const driveBackupLastFileId = 'drive_backup_last_file_id';
  static const driveBackupLastFileName = 'drive_backup_last_file_name';
  static const driveBackupLastFileSize = 'drive_backup_last_file_size';
  static const driveBackupLastChecksum = 'drive_backup_last_checksum';
  static const driveBackupCount = 'drive_backup_count';

  // Random per-install identifier (spec item 13: "include a device
  // identifier in metadata/file name... do not expose sensitive device
  // information to the user") - a freshly generated UUID the very first
  // time BackupService ever needs it, NOT the phone's IMEI/Android ID/serial
  // number, so it never doubles as real hardware-tracking information. See
  // DeviceIdService.
  static const deviceBackupId = 'device_backup_id';
  static const complaintPresets = 'complaint_presets';
  static const conditionPresets = 'condition_presets';
  static const damagePresets = 'damage_presets';
  static const logoPath = 'logo_path';
  // Shop-editable text template for the WhatsApp intimation sent when a
  // service job's status is changed to "Ready for Delivery". Supports the
  // same {customerName}/{mobileName}/{billNo}/{amount}/{shopName} tokens
  // documented in WhatsAppSmsService.readyForDeliveryMessage's fallback.
  static const readyIntimationTemplate = 'ready_intimation_template';
  // Same idea, for the "Received" (job-card intake) and "Delivery" (final
  // handover) WhatsApp intimations - each independently customizable (spec:
  // "received kum ready kum aprom delivery kum thani thaniya customise
  // need"). See WhatsAppSmsService.serviceIntimationMessage /
  // .deliveryMessage for their token lists and fallback wording.
  static const receivedIntimationTemplate = 'received_intimation_template';
  static const deliveryIntimationTemplate = 'delivery_intimation_template';

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
  // Shop-editable WhatsApp caption sent with the Daily Order PDF (spec:
  // "more pdf and whatsapp app message customize panra option need and
  // preview kattanum"). Supports {supplierName}/{itemCount}/{dates} tokens
  // - see WhatsAppSmsService.dailyOrderMessage's fallback for the default
  // wording. dailyOrderPdfNote is an optional free-text line (e.g. special
  // instructions to the supplier) printed at the bottom of the PDF itself -
  // see PdfService.buildDailyOrderPdf.
  static const dailyOrderMessageTemplate = 'daily_order_message_template';
  static const dailyOrderPdfNote = 'daily_order_pdf_note';

  // Which installed WhatsApp app customer intimations (Received/Ready/
  // Delivered/Warranty) should open in, on a phone that has more than one
  // installed - see Settings -> WhatsApp Sending and
  // WhatsAppSmsService.sendWhatsApp. A shop replying to customers from
  // WhatsApp Business was finding intimations silently opening in the
  // *other*, unwatched WhatsApp app instead, which read as "the message
  // never went out". 'auto' (default/unset) leaves this exactly as before
  // - Android's own chooser or previously-set default handler decides.
  // 'business' / 'regular' explicitly target com.whatsapp.w4b / com.whatsapp,
  // falling back to the old generic behaviour if that specific app isn't
  // installed on the phone.
  static const whatsappSendApp = 'whatsapp_send_app';

  // One-time flag: has the "Test Print?" prompt already been shown on the
  // Dashboard once (spec: "app first time open pannumpothu test print
  // option onnu venum, first print poda late aaguthu athu check panna")?
  // Stored in the settings table (same as everything else here) so it
  // survives across app restarts and stays a genuine one-time "first app
  // open" nudge rather than reappearing every launch - the same Test Print
  // action stays permanently available afterwards from Settings -> Printing.
  static const testPrintPromptShown = 'test_print_prompt_shown';

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

  /// Shop-editable quick-pick list for the intake form's Device Condition
  /// chips (spec: quick-pic the overall state instead of typing it every
  /// time) - same pipe-separated storage/extend pattern as complaint
  /// presets.
  Future<List<String>> getConditionPresets() async {
    final raw = await get(conditionPresets);
    if (raw == null || raw.trim().isEmpty) {
      return const [
        'Dead',
        'Hang on Logo',
        'Restart',
        'Only Charging',
        'On Condition',
      ];
    }
    return raw.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  Future<void> saveConditionPresets(List<String> presets) async {
    await set(conditionPresets, presets.join('|'));
  }

  /// Shop-editable quick-pick list for the intake form's Existing Damage
  /// chips - same pipe-separated storage/extend pattern as complaint
  /// presets.
  Future<List<String>> getDamagePresets() async {
    final raw = await get(damagePresets);
    if (raw == null || raw.trim().isEmpty) {
      return const [
        'Dent',
        'Display Broken',
        'Back Door Broken',
        'Camera Glass Broken',
        'Missing SIM Tray',
      ];
    }
    return raw.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  Future<void> saveDamagePresets(List<String> presets) async {
    await set(damagePresets, presets.join('|'));
  }

  /// The shop-customizable WhatsApp "ready for delivery" intimation text.
  /// Null/empty means "use the built-in default" (see
  /// WhatsAppSmsService.readyForDeliveryMessage).
  Future<String?> getReadyIntimationTemplate() => get(readyIntimationTemplate);

  Future<void> saveReadyIntimationTemplate(String template) => set(readyIntimationTemplate, template);

  /// The shop-customizable WhatsApp "job received" intimation text. Null/
  /// empty means "use the built-in default" (see
  /// WhatsAppSmsService.serviceIntimationMessage).
  Future<String?> getReceivedIntimationTemplate() => get(receivedIntimationTemplate);

  Future<void> saveReceivedIntimationTemplate(String template) => set(receivedIntimationTemplate, template);

  /// The shop-customizable WhatsApp "delivered" intimation text. Null/empty
  /// means "use the built-in default" (see WhatsAppSmsService.deliveryMessage).
  Future<String?> getDeliveryIntimationTemplate() => get(deliveryIntimationTemplate);

  Future<void> saveDeliveryIntimationTemplate(String template) => set(deliveryIntimationTemplate, template);

  /// The shop-customizable Daily Order WhatsApp caption. Null/empty means
  /// "use the built-in default" (see WhatsAppSmsService.dailyOrderMessage).
  Future<String?> getDailyOrderMessageTemplate() => get(dailyOrderMessageTemplate);

  Future<void> saveDailyOrderMessageTemplate(String template) => set(dailyOrderMessageTemplate, template);

  /// Optional free-text note printed at the bottom of the Daily Order PDF
  /// (e.g. special instructions to the supplier). Empty means no note line.
  Future<String?> getDailyOrderPdfNote() => get(dailyOrderPdfNote);

  Future<void> saveDailyOrderPdfNote(String note) => set(dailyOrderPdfNote, note);

  /// 'auto' | 'business' (default) | 'regular' - see [whatsappSendApp].
  /// Defaults to 'business' (not 'auto') so a shop that never opens
  /// Settings still gets WhatsApp Business as the first preference for
  /// every customer intimation out of the box (spec: "intimation ...
  /// enakku first preference business whatsapp venum") - still fully
  /// changeable any time from Settings -> WhatsApp Sending.
  Future<String> getWhatsAppSendApp() async => (await get(whatsappSendApp)) ?? 'business';

  Future<void> saveWhatsAppSendApp(String value) => set(whatsappSendApp, value);

  /// See [testPrintPromptShown]. Defaults to false (not shown yet) so a
  /// fresh install/first app open always offers the one-time Test Print
  /// prompt exactly once.
  Future<bool> hasShownTestPrintPrompt() async => (await get(testPrintPromptShown)) == '1';

  Future<void> markTestPrintPromptShown() => set(testPrintPromptShown, '1');
}
