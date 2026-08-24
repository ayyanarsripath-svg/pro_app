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
