import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:workmanager/workmanager.dart';

import 'backup_service.dart';
import 'order_reminder_service.dart';

/// Shared WorkManager task registry.
///
/// IMPORTANT: WorkManager only supports ONE globally-registered
/// callbackDispatcher per Flutter app - registering a second, separate
/// Workmanager().initialize(...) callback anywhere else would silently
/// break whichever one registered first. So every periodic background task
/// this app needs (daily Google Drive backup, daily order reminder, and
/// any future one) is registered through THIS file only, and dispatched by
/// [task] name inside the single [callbackDispatcher] below - never add a
/// second dispatcher elsewhere.
const dailyDriveBackupTaskName = 'daily_google_drive_backup_task';
const dailyDriveBackupUniqueName = 'daily_google_drive_backup';
const dailyOrderReminderTaskName = 'daily_order_reminder_task';
const dailyOrderReminderUniqueName = 'daily_order_reminder';

/// WorkManager entry point - runs in its own background isolate, completely
/// separate from the app's UI isolate, whenever Android decides to execute
/// one of the periodic tasks registered below. Must stay a top-level
/// function annotated with @pragma('vm:entry-point') so the Android side
/// can still find it after the app process is killed.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      switch (task) {
        case dailyDriveBackupTaskName:
          await BackupService().runDailyGoogleDriveBackupIfDue();
          break;
        case dailyOrderReminderTaskName:
          await OrderReminderService().checkAndNotifyIfDue();
          break;
      }
    } catch (_) {
      // Swallow - WorkManager retries failed tasks on its own backoff
      // policy anyway, and each service's own calendar-date due-check
      // makes sure a missed/failed run is simply picked up by the next
      // successful one (background retry, or the moment the app is next
      // opened - see main.dart).
    }
    return Future.value(true);
  });
}

bool _wmInitialized = false;

/// initialize() only needs to run once per app run - every schedule*
/// function below calls this first, and it's a no-op after the first call.
Future<void> _ensureWorkManagerInitialized() async {
  if (_wmInitialized) return;
  await Workmanager().initialize(callbackDispatcher);
  _wmInitialized = true;
}

/// Registers the daily ~10 PM Google Drive backup with Android's
/// WorkManager. Safe to call on every app startup - registerPeriodicTask()
/// with ExistingPeriodicWorkPolicy.keep leaves an already-scheduled task
/// alone instead of restarting its cycle. WorkManager needs no runtime
/// permission prompt for this (unlike exact-alarm scheduling), so the shop
/// owner is never asked anything.
///
/// IMPORTANT (please read before assuming "night 10 o clock" is exact):
/// Android's WorkManager does not guarantee an exact run time, even though
/// the initial delay below is computed to land on 10 PM - the OS can push
/// it later for battery/Doze-mode reasons. That's a deliberate Android
/// platform limitation, not a bug here, and it's exactly why
/// runDailyGoogleDriveBackupIfDue() is *also* called every time the app is
/// opened (see main.dart): even if the background trigger runs late, or
/// can't silently sign in, that day's backup still happens the moment the
/// shop owner next opens the app.
Future<void> scheduleDailyGoogleDriveBackup() async {
  await _ensureWorkManagerInitialized();

  final now = DateTime.now();
  var next10pm = DateTime(now.year, now.month, now.day, 22);
  if (!next10pm.isAfter(now)) {
    next10pm = next10pm.add(const Duration(days: 1));
  }

  await Workmanager().registerPeriodicTask(
    dailyDriveBackupUniqueName,
    dailyDriveBackupTaskName,
    frequency: const Duration(hours: 24),
    initialDelay: next10pm.difference(now),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 15),
  );
}

/// Registers a background check that shows a local notification reminding
/// the owner to open the app and send that day's supplier order, as soon as
/// possible after the shop's chosen Daily Orders send time (Settings inside
/// Daily Orders - defaults to 12:30 if never set) has actually passed and
/// there's still something pending. Re-call this (e.g. right after the
/// owner changes the time in Settings) - existingWorkPolicy.replace resets
/// the cycle immediately instead of waiting for the old one to finish.
///
/// Runs every 15 minutes (Android WorkManager's own minimum periodic
/// interval - it will not accept anything shorter) rather than once every
/// 24 hours timed to land exactly on the chosen minute. A single
/// once-a-day trigger is fragile: WorkManager gives no exact-time guarantee
/// at all, so if Doze/battery-optimisation/an OEM task-killer pushes that
/// one attempt back or drops it entirely, the whole day's reminder is
/// silently lost. Polling every 15 minutes instead means a missed tick
/// barely matters - the next one is only 15 minutes away. This is safe to
/// fire this often because OrderReminderService.checkAndNotifyIfDue() does
/// its own gating: it only ever actually shows a notification once "now"
/// has reached today's configured send time, and only once per calendar
/// day (see that method) - every other tick is a fast, harmless no-op.
/// Same catch-up pattern as the Drive backup above also applies here - see
/// main.dart, which calls checkAndNotifyIfDue() on every app open too.
Future<void> scheduleDailyOrderReminder({required int hour, required int minute}) async {
  await _ensureWorkManagerInitialized();

  await Workmanager().registerPeriodicTask(
    dailyOrderReminderUniqueName,
    dailyOrderReminderTaskName,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 5),
  );
}

/// Cancels the background order-reminder trigger - called when the owner
/// switches the Daily Orders reminder off in Settings.
Future<void> cancelDailyOrderReminder() async {
  await _ensureWorkManagerInitialized();
  await Workmanager().cancelByUniqueName(dailyOrderReminderUniqueName);
}

/// Opens Android's own "Allow [app] to ignore battery optimizations?"
/// system dialog for THIS app specifically. Many phones (Xiaomi/MIUI,
/// Vivo, Oppo/ColorOS, Realme especially - see spec: "daily order widget
/// problem ... order not send automatically to fixed time") kill
/// WorkManager's background reminder trigger outright unless the app is
/// whitelisted from battery/Doze restrictions, which silently drops the
/// "Order Time!" notification with no error the shop would ever see - it
/// just never fires. This one system dialog (tap "Allow") is the
/// standard-Android half of the fix; see DailyOrderScreen's Settings
/// dialog for the MIUI-style "Autostart" instructions this button's
/// dialog also shows, since Autostart is a separate OEM-only toggle with
/// no public Android API to request it - the shop has to turn that on by
/// hand.
///
/// Safe/idempotent to call repeatedly: if the app is already whitelisted,
/// Android just closes the dialog immediately with nothing for the owner
/// to do. Android-only (matches the rest of this app); no-op elsewhere.
/// Never throws into the caller - a phone that doesn't support this intent
/// (very old/heavily customized Android builds) just does nothing instead
/// of crashing the settings screen.
Future<void> requestIgnoreBatteryOptimizations() async {
  if (!Platform.isAndroid) return;
  try {
    final intent = AndroidIntent(
      action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
      data: 'package:com.example.pro_app',
    );
    await intent.launch();
  } catch (_) {
    // Some OEM Android builds don't support this specific intent action -
    // fail silently rather than crash the settings screen; the shop can
    // still use the manual OEM battery-settings steps shown alongside
    // this button.
  }
}

/// Opens the phone's general battery-optimization app list (Android's
/// stock "Battery optimization" screen showing every installed app) as a
/// fallback when the direct per-app request above isn't supported on a
/// particular OEM build - the owner can find "Professional Mobiles" in
/// that list themselves and set it to "Don't optimize". Same
/// never-throws, Android-only behaviour as [requestIgnoreBatteryOptimizations].
Future<void> openBatteryOptimizationSettings() async {
  if (!Platform.isAndroid) return;
  try {
    final intent = AndroidIntent(action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS');
    await intent.launch();
  } catch (_) {}
}

/// Opens this app's own "App info" settings page - from there the owner
/// can reach OEM-specific battery/autostart controls that live under
/// "App info" on many phones (e.g. MIUI's "Battery saver" per-app option,
/// or a "Permissions" section containing Autostart on some ROMs) when
/// they aren't reachable via any standard Android intent.
Future<void> openAppSettings() async {
  if (!Platform.isAndroid) return;
  try {
    final intent = AndroidIntent(
      action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
      data: 'package:com.example.pro_app',
    );
    await intent.launch();
  } catch (_) {}
}
