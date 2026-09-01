import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../repositories/settings_repository.dart';
import 'app_notifications.dart';
import 'pnl_service.dart';

/// Persistent Quick Income/Expense notification (spec: "PRO SERVICE - Quick
/// Income & Expense Entry Feature" - a persistent, always-available ➕
/// Income / ➖ Expense entry point, visible even on the lock screen, that
/// auto-updates with today's running totals instead of the shop owner
/// having to open the app first).
///
/// Directly answers "mobile screen lock la erukkumpothu quic income quick
/// expenses notificiation la varala" (the notification doesn't show up
/// while the phone is locked): this feature had never actually been built
/// yet (it was paused mid-way over the shared-plugin-callback risk fixed in
/// AppNotifications), so there was nothing TO show. It exists now.
///
/// `ongoing: true` + `autoCancel: false` means the shop owner cannot swipe
/// it away (only the Settings toggle below removes it); `visibility:
/// public` means the ➕/➖ buttons and today's totals show directly on the
/// lock screen with no unlock needed first.
///
/// Shown once on every app open and refreshed every time a Quick
/// Income/Expense entry is saved (see QuickTransactionScreen) so the totals
/// in its body stay live. Also re-posted on a periodic background timer via
/// android_alarm_manager_plus (see background_tasks.dart's
/// scheduleQuickNotificationRefresh/quickNotificationRefreshCallback) -
/// Android clears EVERY notification, for every app, on device reboot, and
/// there is no way around that short of tying this to a running foreground
/// service (deliberately avoided here - foreground services are exactly the
/// kind of thing aggressive OEM battery managers kill, which would make
/// this notification LESS reliable, not more). The periodic re-arm is the
/// same trade-off this app's other exact alarms already make (see
/// background_tasks.dart's daily backup alarm) - after a reboot, this
/// notification reappears on its own within that timer's interval, without
/// needing the app opened first.
class QuickNotificationService {
  QuickNotificationService._();

  static const _id = 3001;
  static const payload = 'quick_actions_notification';
  static const incomeActionId = 'quick_income';
  static const expenseActionId = 'quick_expense';
  static const dashboardActionId = 'quick_dashboard';

  /// Shows (or, called again later, silently updates in place - same
  /// notification id) the persistent notification with today's running
  /// Income/Expense totals in the body. No-ops (and clears any previously
  /// shown copy) if the shop has turned this off in Settings.
  static Future<void> show() async {
    try {
      final settings = SettingsRepository();
      final enabledStr = await settings.get(SettingsRepository.quickNotificationEnabled);
      if (enabledStr == 'false') {
        await cancel();
        return;
      }

      await AppNotifications.ensureInitialized();

      var body = 'Tap Income or Expense to add an entry in one tap.';
      try {
        final now = DateTime.now();
        // Same "today" range shape PnlDashboardScreen itself uses for its
        // own Daily view (inclusive end-of-day, not next-midnight) - kept
        // identical so this notification's totals always match what the
        // in-app P&L dashboard would show for today.
        final startOfDay = DateTime(now.year, now.month, now.day);
        final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
        final totals = await PnlService().totals(startOfDay, endOfDay);
        final income = totals.totalRevenue;
        final expense = totals.totalDirectCost + totals.operatingExpenses;
        body = 'Today - Income: ₹${income.toStringAsFixed(0)}   Expense: ₹${expense.toStringAsFixed(0)}';
      } catch (_) {
        // Today's totals are a nice-to-have in the body text - never let a
        // P&L read failure stop the notification (and its action buttons)
        // from showing at all.
      }

      const androidDetails = AndroidNotificationDetails(
        'quick_income_expense',
        'Quick Income & Expense',
        channelDescription: "Always-available Income/Expense entry, updated with today's running totals",
        importance: Importance.high,
        priority: Priority.high,
        ongoing: true,
        autoCancel: false,
        playSound: false,
        enableVibration: false,
        visibility: NotificationVisibility.public,
        actions: [
          AndroidNotificationAction(incomeActionId, '➕ Income', showsUserInterface: true),
          AndroidNotificationAction(expenseActionId, '➖ Expense', showsUserInterface: true),
          AndroidNotificationAction(dashboardActionId, '📊 Dashboard', showsUserInterface: true),
        ],
      );
      await AppNotifications.plugin.show(
        _id,
        'Quick Income & Expense',
        body,
        const NotificationDetails(android: androidDetails),
        payload: payload,
      );
    } catch (_) {
      // A notification failing to show must never affect the rest of the app.
    }
  }

  /// Removes the persistent notification - called when the shop turns the
  /// Settings toggle off.
  static Future<void> cancel() async {
    try {
      await AppNotifications.ensureInitialized();
      await AppNotifications.plugin.cancel(_id);
    } catch (_) {
      // Never let clearing a notification throw into the caller.
    }
  }
}
