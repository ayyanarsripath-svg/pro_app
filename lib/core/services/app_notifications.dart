import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'daily_order_auto_send_signal.dart';
import 'order_reminder_service.dart';
import 'quick_action_signal.dart';
import 'quick_notification_service.dart';

/// Single, app-wide [FlutterLocalNotificationsPlugin] instance with exactly
/// ONE `initialize()` call and ONE `onDidReceiveNotificationResponse`
/// callback.
///
/// BUG-RISK FIX (found while building the Quick Income/Expense persistent
/// notification): every notification-showing service in this app used to
/// create its OWN `FlutterLocalNotificationsPlugin()` Dart instance and
/// independently call `.initialize(...)` the first time it needed to show
/// something - OrderReminderService and BackupService both did this. On
/// Android, flutter_local_notifications' method channel is process-global:
/// every `FlutterLocalNotificationsPlugin()` Dart object talks to the SAME
/// underlying native plugin, and each independent `.initialize(...)` call
/// silently REPLACES whichever `onDidReceiveNotificationResponse` callback
/// (if any) a previous `.initialize()` call had registered, app-wide - the
/// LAST one to call `.initialize()` wins, and every earlier registration
/// (even from a completely unrelated feature) is gone with no error or
/// warning. Today that happened to keep working purely by luck (main.dart's
/// call order meant OrderReminderService's own initialize() - the only one
/// with a real callback - always ran last), but the very first new
/// notification-tap callback added anywhere (like the Quick Income/Expense
/// notification's ➕/➖ action buttons) could have silently broken Daily
/// Order reminder taps, or vice versa, purely depending on which service
/// happened to initialize first that run.
///
/// Routing every notification through this single shared plugin + one
/// dispatching callback removes that fragility for good: `initialize()` is
/// now called exactly once, ever, per app run, and this file is the ONLY
/// place a response callback is registered - OrderReminderService,
/// BackupService and QuickNotificationService all just call
/// `AppNotifications.plugin.show/cancel/...` directly.
class AppNotifications {
  AppNotifications._();

  static final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Safe to call from anywhere, any number of times - only the first call
  /// per app run actually does anything. Never throws (see HOTFIX note on
  /// the old OrderReminderService.ensureInitialized(), which this replaces)
  /// - a notification-setup failure must never be able to stop the app from
  /// opening, since this now runs very early in main().
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    try {
      // A proper flat white-on-transparent icon (see build-apk.yml's "Add
      // proper notification small-icon" step) - see
      // OrderReminderService's old doc comment for why @mipmap/ic_launcher
      // must never be used here.
      const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
      const settings = InitializationSettings(android: androidInit);
      await plugin.initialize(settings, onDidReceiveNotificationResponse: _onResponse);
      // Android 13+ requires this one-time runtime "Allow notifications?"
      // permission before ANY notification from this app (reminders,
      // backup status, Quick Income/Expense) can actually be shown. Shown
      // once; the OS remembers the answer after that.
      await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      _initialized = true;
    } catch (_) {
      // Leaves _initialized false so a later call (e.g. the next app open)
      // gets to try again.
    }
  }

  /// Fires while the app process is alive (foreground OR backgrounded but
  /// not killed) - reacts to a tap on ANY notification this app shows,
  /// routed here by [payload]/[actionId] to whichever feature owns it. The
  /// fully-dead-process cold-start case is handled separately by
  /// [consumeColdStartLaunch] below.
  static void _onResponse(NotificationResponse response) {
    if (response.payload == OrderReminderService.autoSendPayload) {
      DailyOrderAutoSendSignal.fire();
      return;
    }
    if (response.payload == QuickNotificationService.payload) {
      _fireQuickAction(response.actionId);
    }
    // Backup notifications (BackupService, ids 2001-2003) are purely
    // informational today - nothing to route on tap.
  }

  static void _fireQuickAction(String? actionId) {
    if (actionId == QuickNotificationService.incomeActionId) {
      QuickActionSignal.fire(QuickActionType.income);
    } else if (actionId == QuickNotificationService.expenseActionId) {
      QuickActionSignal.fire(QuickActionType.expense);
    } else {
      QuickActionSignal.fire(QuickActionType.dashboard);
    }
  }

  /// Call once from main(), right after [ensureInitialized], to catch the
  /// case flutter_local_notifications' own tap callback CAN'T cover: the
  /// app process was fully dead (not just backgrounded) and this exact tap
  /// - the Daily Order reminder OR a Quick Income/Expense notification
  /// button - is what launched it fresh. Replaces both
  /// OrderReminderService's and (a new) QuickNotificationService's own
  /// separate cold-start checks, now that both notifications share this one
  /// plugin instance. Never throws - a failure here must never block app
  /// startup.
  static Future<void> consumeColdStartLaunch() async {
    try {
      final details = await plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return;
      final response = details?.notificationResponse;
      if (response == null) return;
      if (response.payload == OrderReminderService.autoSendPayload) {
        DailyOrderAutoSendSignal.fire();
        return;
      }
      if (response.payload == QuickNotificationService.payload) {
        _fireQuickAction(response.actionId);
      }
    } catch (_) {
      // See ensureInitialized's note - never block app startup.
    }
  }
}
