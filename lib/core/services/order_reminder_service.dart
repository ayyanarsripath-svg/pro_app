import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../repositories/daily_order_repository.dart';
import '../repositories/settings_repository.dart';
import 'app_notifications.dart';
import 'daily_order_auto_send_signal.dart';

/// Local (on-device, no server/API-key) reminder that nudges the shop
/// owner to send today's supplier order - see DailyOrderScreen.
///
/// Deliberately a notification, not a fully silent auto-send: WhatsApp
/// does not let a third-party app send a message on the owner's behalf
/// without the separate, paid WhatsApp Business API, so however this is
/// triggered, the owner still ends up tapping Send inside WhatsApp
/// themselves. This reminder's job is just to make sure that tap never
/// gets forgotten AND that the tap itself does the least possible work
/// (spec: "reminder alarm adikkanum atha paathu na whatsapp send button
/// click pannuvan" / "pdf na just send button mattum press pannuvan") -
/// tapping this notification jumps straight to Daily Orders and
/// automatically re-runs the same PDF-build + open-WhatsApp-with-
/// attachment flow the in-app "Send Order via WhatsApp" button uses (see
/// DailyOrderAutoSendSignal). Note there is a SECOND, independent
/// reminder path too: background_tasks.dart also arms a native Android
/// AlarmManager exact alarm (DailyOrderAlarmReceiver.kt), which survives
/// Doze/OEM background-killers far better than this WorkManager-polled
/// notification does - that native alarm's own notification tap is
/// consumed separately, via background_tasks.dart's
/// consumeDailyOrderAlarmLaunch(), called from main.dart. Both paths feed
/// the same DailyOrderAutoSendSignal, so either one tapped gets the owner
/// to the same one-tap-left WhatsApp state.
class OrderReminderService {
  final _settings = SettingsRepository();
  final _repo = DailyOrderRepository();

  /// Notification payload used to recognise "this tap was the Daily Order
  /// reminder" - AppNotifications' shared response callback compares
  /// against this before firing the auto-send signal, so an unrelated
  /// notification could never accidentally trigger a WhatsApp send.
  static const autoSendPayload = 'daily_order_auto_send';

  /// Thin delegate to [AppNotifications.ensureInitialized] - kept as a
  /// named entry point here since main.dart (and this class's own
  /// [checkAndNotifyIfDue]) already call it by this name.
  ///
  /// REFACTOR (shared-plugin risk fix): this used to own a completely
  /// separate `FlutterLocalNotificationsPlugin()` instance and its own
  /// `.initialize()` call/callback, exactly like BackupService did - see
  /// AppNotifications' class doc comment for the app-wide "last
  /// .initialize() call silently wins" risk that created, and why every
  /// notification in this app now shares ONE plugin instance and ONE
  /// callback registered there instead.
  static Future<void> ensureInitialized() => AppNotifications.ensureInitialized();

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

      // BUG FIX: this used to skip straight to the "already notified today?"
      // check below with no comparison against the shop's actual saved send
      // time at all - so the very first call of the day (often the app-open
      // catch-up right after unlocking in the morning, well before the
      // chosen time) fired the reminder immediately and then marked today
      // as done, silently suppressing the real, later trigger at the
      // configured time (spec: "send time 1:21 ku set panna but
      // automaticallu message ... send aagala" - the 1:21 setting was never
      // actually being honoured). Now nothing fires until "now" has
      // genuinely reached today's configured send time.
      final sendTimeStr = await _settings.get(SettingsRepository.dailyOrderSendTime) ?? '12:30';
      final sendTimeParts = sendTimeStr.split(':');
      final sendHour = int.tryParse(sendTimeParts[0]) ?? 12;
      final sendMinute = sendTimeParts.length > 1 ? (int.tryParse(sendTimeParts[1]) ?? 30) : 30;
      final todaysSendTime = DateTime(now.year, now.month, now.day, sendHour, sendMinute);
      if (now.isBefore(todaysSendTime)) return;

      final lastStr = await _settings.get(SettingsRepository.lastOrderReminderAt);
      if (lastStr != null) {
        final last = DateTime.parse(lastStr);
        final sameDay = last.year == now.year && last.month == now.month && last.day == now.day;
        if (sameDay) return;
      }

      await ensureInitialized();
      // Channel id bumped from 'daily_order_reminder' to
      // 'daily_order_reminder_v2': on Android 8+, a notification channel's
      // sound/vibration settings are locked the FIRST time that channel id
      // is ever created on a device and can never be changed by the app
      // afterwards, even across app updates - only a full uninstall clears
      // it. If the original channel ever got created without sound (or a
      // user/OEM silently muted it), no amount of code changes to this
      // AndroidNotificationDetails would ever bring sound back on an
      // existing install. A new channel id guarantees a fresh channel with
      // these settings (sound + vibration explicitly on) on every device,
      // old and new installs alike.
      // Alarm-style properties (category/fullScreenIntent/visibility): spec
      // asked for something closer to an actual alarm ("reminder alarm
      // adikkanum") rather than a normal, easy-to-miss notification -
      // category .alarm + fullScreenIntent tells Android this is time-
      // critical (higher chance of heads-up display / waking the screen
      // even under battery optimisation), and public visibility shows the
      // full text on the lock screen instead of a hidden placeholder.
      const androidDetails = AndroidNotificationDetails(
        'daily_order_reminder_v2',
        'Daily Order Reminder',
        channelDescription: "Reminds you to send today's supplier order",
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
      );
      await AppNotifications.plugin.show(
        1001,
        'Order Time!',
        "${pending.length} item(s) waiting - tap to auto-open Daily Orders ready to send to your supplier.",
        const NotificationDetails(android: androidDetails),
        // Lets both onDidReceiveNotificationResponse (warm/backgrounded app)
        // and consumeColdStartLaunch (fully-dead-process cold start) above
        // recognise a tap on THIS notification and fire the auto-send
        // signal - see DailyOrderAutoSendSignal's doc comment.
        payload: autoSendPayload,
      );
      await _settings.set(SettingsRepository.lastOrderReminderAt, now.toIso8601String());
    } catch (_) {
      // Never let a reminder failure affect the rest of the app.
    }
  }
}
