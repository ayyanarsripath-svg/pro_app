import 'package:flutter/services.dart';

import '../repositories/settings_repository.dart';
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
/// kudathu" - it must never go away). So `show()` below starts
/// QuickNotificationForegroundService.kt via the native channel, which
/// anchors this same notification id to a genuine Android foreground
/// service - the one OS-guaranteed mechanism the platform itself won't let
/// the user dismiss, on the lock screen or anywhere else.
///
/// BUILT ENTIRELY NATIVELY (2026-09 fix - "athula income or expenses thouch
/// panna app open aagakudathu ... athukku bathil enakku quick expenses
/// screen or quick income screen open aaganum athula direct ah na enter
/// pannippan": tapping ➕ Income / ➖ Expense must never open the app/PIN
/// screen at all, it must land directly on the entry screen). This used to
/// call [AppNotifications.plugin.show] (flutter_local_notifications) for
/// the actual title/body/action-button content, with the foreground service
/// above only posting a throwaway placeholder first so the OS wouldn't let
/// the notification be swiped away. That worked for keeping the
/// notification pinned, but flutter_local_notifications' action buttons can
/// only ever do one of two things when tapped: run silently in the
/// background, or relaunch this app's own MainActivity (there is no public
/// API to point a specific action at some other Activity) - so ➕/➖ could
/// never skip MainActivity's PIN gate that way, no matter how the
/// post-PIN navigation inside AppShell was tuned (see git history for that
/// earlier attempt). QuickNotificationForegroundService.kt's onStartCommand
/// now builds the ONE real notification itself (title/body passed down as
/// Intent extras from [show] below), with three independent PendingIntents:
/// ➕ Income and ➖ Expense each launch their own tiny standalone
/// Activity/Flutter-engine (QuickIncomeActivity/QuickExpenseActivity, see
/// lib/main.dart's quickIncomeMain/quickExpenseMain) that shows nothing but
/// QuickTransactionScreen - same "never touches MainActivity" trick already
/// proven by the Daily Orders home-screen widget's QuickAddActivity, so
/// typing an entry no longer goes through this app's PIN at all (the
/// phone's own lock screen, if the shop has one set, is still what has to
/// be unlocked to act on any notification button in the first place - this
/// only removes the second, redundant PIN prompt on top of that). 📊
/// Dashboard and a plain tap on the notification body still launch
/// MainActivity as before (see the `open_dashboard` extra/
/// consumeQuickDashboardLaunchFlag in main.dart) - that one shows real
/// profit/income/expense figures, not a single field to fill in, so it
/// keeps the same PIN protection every other screen in the app has.
/// `setVisibility(PUBLIC)` is set directly on the native builder now (was
/// `NotificationVisibility.public` on the old AndroidNotificationDetails)
/// so the buttons and today's totals still show directly on the lock
/// screen with no unlock needed just to see them.
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

      // Starts (or, called again, simply re-triggers onStartCommand on) the
      // already-running foreground service, which builds and posts the
      // ENTIRE real notification itself - title/body passed down as Intent
      // extras. See this class's doc comment for why the ➕/➖/📊 buttons
      // are no longer built via AndroidNotificationDetails/
      // AppNotifications.plugin.show at all. Best-effort and Android-only -
      // iOS has no such channel to reuse, and a failure here must never
      // throw into the rest of the app.
      try {
        await _nativeChannel.invokeMethod('startQuickNotificationService', {
          'title': 'Quick Income & Expense',
          'body': body,
        });
      } catch (_) {}
    } catch (_) {
      // A notification failing to show must never affect the rest of the app.
    }
  }

  /// Removes the persistent notification - called when the shop turns the
  /// Settings toggle off. Stops QuickNotificationForegroundService.kt,
  /// which itself removes the notification id it anchored (see that file's
  /// onDestroy()).
  static Future<void> cancel() async {
    try {
      await _nativeChannel.invokeMethod('stopQuickNotificationService');
    } catch (_) {
      // Never let clearing a notification throw into the caller.
    }
  }
}
