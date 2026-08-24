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

  // HOTFIX: this used to have no try/catch of its own at all, relying on
  // every caller to wrap it - which was true right up until main.dart
  // started calling this directly and unguarded on every app startup (to
  // request the notification permission proactively - see main.dart's
  // comment). If _plugin.initialize() or requestNotificationsPermission()
  // ever threw on a particular device/Android version (a missing/renamed
  // notification icon resource, a manifest merge quirk, anything), that
  // exception propagated straight out of main() BEFORE runApp() was ever
  // reached - Flutter never got the chance to mount a single widget, so the
  // app opened to a permanently blank white screen with no error shown at
  // all (spec: "app open panna thum kamikkama full white color la erukku").
  // Wrapping the whole body here guarantees this can never happen again,
  // regardless of which caller reaches it or whether that caller remembers
  // to guard it too - reminder setup failing must never be able to stop the
  // app from opening.
  static Future<void> ensureInitialized() async {
    if (_pluginInitialized) return;
    try {
      // A proper flat white-on-transparent icon (see build-apk.yml's "Add
      // proper notification small-icon" step) - @mipmap/ic_launcher (the
      // full-colour app icon) used to be passed here, which Android 5.0+
      // collapses into a blank/unrecognisable white blob in the status bar
      // since it only ever renders a notification icon's alpha channel.
      const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
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
          ?.requestNotificationsPermission();
      _pluginInitialized = true;
    } catch (_) {
      // Never let reminder setup failing block app startup - see the
      // HOTFIX note above. Leaves _pluginInitialized false so a later call
      // (e.g. the next app open) gets to try again.
    }
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
      const androidDetails = AndroidNotificationDetails(
        'daily_order_reminder_v2',
        'Daily Order Reminder',
        channelDescription: "Reminds you to send today's supplier order",
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
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
