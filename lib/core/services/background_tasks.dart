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

/// Registers a daily background check, timed to the shop's chosen Daily
/// Orders send time (Settings inside Daily Orders - defaults to 12:30 if
/// never set), that shows a local notification reminding the owner to open
/// the app and send that day's supplier order if anything is still
/// pending. Re-call this (e.g. right after the owner changes the time in
/// Settings) - existingWorkPolicy.replace means the new time always takes
/// over immediately instead of waiting for the old cycle to finish.
///
/// Same Android WorkManager timing caveat as the Drive backup above
/// applies here too - that's why OrderReminderService.checkAndNotifyIfDue()
/// is also checked every time the app opens (see main.dart), so a late or
/// missed background trigger still gets caught.
Future<void> scheduleDailyOrderReminder({required int hour, required int minute}) async {
  await _ensureWorkManagerInitialized();

  final now = DateTime.now();
  var next = DateTime(now.year, now.month, now.day, hour, minute);
  if (!next.isAfter(now)) {
    next = next.add(const Duration(days: 1));
  }

  await Workmanager().registerPeriodicTask(
    dailyOrderReminderUniqueName,
    dailyOrderReminderTaskName,
    frequency: const Duration(hours: 24),
    initialDelay: next.difference(now),
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
