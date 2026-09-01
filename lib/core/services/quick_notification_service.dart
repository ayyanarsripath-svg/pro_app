import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../repositories/settings_repository.dart';
import 'app_notifications.dart';
import 'pnl_service.dart';

// Same native channel MainActivity.kt already exposes for WhatsApp direct
// share, App Signing Info and the Daily Order alarm - reused here to
// start/stop QuickNotificationForegroundService.kt (see that file for why:
// binding this notification's id to a real foreground service is what
// actually stops the OS from letting it be swiped away, including from the
// lock screen).
const _nativeChannel = MethodChannel('pro_app/whatsapp_share');

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
/// `ongoing: true` + `autoCancel: false` alone turned out NOT to reliably
/// stop the shop from swiping it away while the phone was locked, on some
/// OEM lock-screen UIs (spec: "quick income and quick expenses notification
/// lock screen la erukkumpothu thalli vitta poiduthu ... athu pogavey
/// kudathu" - it must never go away). So `show()` below now also starts
/// QuickNotificationForegroundService.kt via the native channel, which
/// anchors this same notification id to a genuine Android foreground
/// service - the one OS-guaranteed mechanism the platform itself won't let
/// the user dismiss, on the lock screen or anywhere else. `visibility:
/// public` means the ➕/➖ buttons and today's totals show directly on the
/// lock screen with no unlock needed first.
///
/// ORDERING MATTERS here (2026-09 fix): the native service must be started
/// BEFORE [AppNotifications.plugin.show] posts the real content, not after.
/// The service's own onStartCommand has to call Android's startForeground()
/// with SOME notification on this id the moment it starts - that call was
/// happening AFTER .show() in an earlier version of this file, so its
/// bare-bones placeholder (no ➕/➖ buttons, no tap action) silently
/// clobbered the rich one .show() had just posted, leaving a notification
/// that looked present but did nothing when tapped (spec: "touch panna
/// entha responsesum varala ... thotta amount enter pannramathiri
/// varamattangithu" - tapping it never opened the amount-entry screen).
/// Starting the service first means its placeholder goes up first, and
/// [AppNotifications.plugin.show]'s later call to the OS's regular
/// notify()-with-same-id then simply overwrites that placeholder in place
/// with the real title/body/actions - no second startForeground() call
/// needed for that, updating an already-anchored notification's content is
/// exactly what plain notify() is for.
///
/// Shown once on every app open and refreshed every time a Quick
/// Income/Expense entry is saved (see QuickTransactionScreen) so the totals
/// in its body stay live. Also re-posted on a periodic background timer via
/// android_alarm_manager_plus (see background_tasks.dart's
/// scheduleQuickNotificationRefresh/quickNotificationRefreshCallback) -
/// Android clears EVERY notification (and stops every foreground service),
/// for every app, on device reboot, so the periodic re-arm is what brings
/// both the notification AND its foreground-service anchor back after a
/// reboot, without needing the app opened first - same trade-off this
/// app's other exact alarms already make (see background_tasks.dart's
/// daily backup alarm).
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

      // Lock-screen dismiss fix: anchors this notification id to a real
      // foreground service so the OS won't let it be swiped away. MUST run
      // BEFORE the plugin.show() call below - see the ORDERING MATTERS
      // note on this class's doc comment for why the reverse order broke
      // the ➕/➖ action buttons and tap-to-open entirely. Best-effort and
      // Android-only - iOS has no such channel to reuse, and a failure
      // here must never stop the notification's actual content (posted
      // below) from showing.
      try {
        await _nativeChannel.invokeMethod('startQuickNotificationService');
      } catch (_) {}

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
    // Stops QuickNotificationForegroundService.kt too, which itself
    // removes the notification id it anchored (see that file's
    // onDestroy()) - otherwise the foreground service would keep the
    // (now content-less) notification alive even after the cancel() call
    // above.
    try {
      await _nativeChannel.invokeMethod('stopQuickNotificationService');
    } catch (_) {}
  }
}
