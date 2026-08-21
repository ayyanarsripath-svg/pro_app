import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../repositories/daily_order_repository.dart';
import '../repositories/settings_repository.dart';

/// Local (on-device, no server/API-key) reminder that nudges the shop
/// owner to send today's supplier order - see DailyOrderScreen.
///
/// Deliberately a notification, not a fully silent auto-send: WhatsApp
/// does not let a third-party app send a message on the owner's behalf
/// without the separate, paid WhatsApp Business API, so however this is
/// triggered, the owner still ends up tapping Send inside WhatsApp
/// themselves. This reminder's job is just to make sure that tap never
/// gets forgotten - see DailyOrderScreen's Send Order button for the
/// (as close to one-tap as technically possible) send flow this leads
/// into.
class OrderReminderService {
  final _settings = SettingsRepository();
  final _repo = DailyOrderRepository();

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _pluginInitialized = false;

  static Future<void> ensureInitialized() async {
    if (_pluginInitialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings);
    // Android 13+ requires this one-time runtime "Allow notifications?"
    // permission before ANY notification (including this reminder) can
    // actually be shown - unlike the WorkManager background scheduling in
    // background_tasks.dart, there's no silent alternative for
    // notifications specifically. Shown once; the OS remembers the
    // answer after that.
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.r9yMnTm4NSzvG9rrwjM2ec8xZgh1cafXH8();
    _pluginInitialized = true;
  }

  /// Called both from the WorkManager background task (once daily, timed
  /// to the shop's chosen Daily Orders send time - see
  /// background_tasks.dart) and every time the app is opened (see
  /// main.dart) - the same "calendar-day due-check" pattern already used
  /// for the Google Drive backup, so a reminder is never shown twice in
  /// one day, and a background trigger that ran late (or didn't run at
  /// all - phone off, Doze mode, etc.) is always caught the moment the app
  /// next opens. Shows nothing if there's no pending (unsent) order item
  /// waiting, and never throws - a reminder failing must never affect the
  /// rest of the app.
  Future<void> checkAndNotifyIfDue() async {
    try {
      final enabled = await _settings.get(SettingsRepository.dailyOrderReminderEnabled);
      if (enabled == 'false') return;

      final pending = await _repo.unsentItems();
      if (pending.isEmpty) return;

      final now = DateTime.now();
      final lastStr = await _settings.get(SettingsRepository.lastOrderReminderAt);
      if (lastStr != null) {
        final last = DateTime.parse(lastStr);
        final sameDay = last.year == now.year && last.month == now.month && last.day == now.day;
        if (sameDay) return;
      }

      await ensureInitialized();
      const androidDetails = AndroidNotificationDetails(
        'daily_order_reminder',
        'Daily Order Reminder',
        channelDescription: "Reminds you to send today's supplier order",
        importance: Importance.high,
        priority: Priority.high,
      );
      await _plugin.show(
        1001,
        'Order Time!',
        "${pending.length} item(s) waiting - open Daily Orders to send today's order to your supplier.",
        const NotificationDetails(android: androidDetails),
      );
      await _settings.set(SettingsRepository.lastOrderReminderAt, now.toIso8601String());
    } catch (_) {
      // Never let a reminder failure affect the rest of the app.
    }
  }
}
