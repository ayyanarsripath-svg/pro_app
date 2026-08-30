import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';

import '../repositories/settings_repository.dart';
import 'backup_service.dart';
import 'daily_order_auto_send_signal.dart';
import 'order_reminder_service.dart';

// Same native channel MainActivity.kt already exposes for WhatsApp direct
// share and App Signing Info - reused here for the exact-alarm Daily Order
// reminder (DailyOrderAlarmReceiver.kt). Kept private to this file since
// nothing outside background_tasks.dart needs to talk to it directly.
const _nativeChannel = MethodChannel('pro_app/whatsapp_share');

/// Shared WorkManager task registry.
///
/// IMPORTANT: WorkManager only supports ONE globally-registered
/// callbackDispatcher per Flutter app - registering a second, separate
/// Workmanager().initialize(...) callback anywhere else would silently
/// break whichever one registered first. So every periodic background task
/// this app needs (daily Google Drive backup FALLBACK - see
/// [scheduleDailyBackupAlarm] below for the actual PRIMARY exact-time
/// trigger, daily order reminder, and any future one) is registered
/// through THIS file only, and dispatched by [task] name inside the
/// single [callbackDispatcher] below - never add a second dispatcher
/// elsewhere.
const dailyDriveBackupTaskName = 'daily_google_drive_backup_task';
const dailyDriveBackupUniqueName = 'daily_google_drive_backup';
const dailyOrderReminderTaskName = 'daily_order_reminder_task';
const dailyOrderReminderUniqueName = 'daily_order_reminder';

// Data-loss incident fix (2026-08): a ONE-OFF, network-constrained retry
// queued (from a safe, non-self-referential caller - see
// schedulePendingDriveBackupRetry below) whenever a Drive backup attempt
// actually fails. Unlike the main daily task above (which always reports
// success back to WorkManager for that periodic slot regardless of the
// backup's real outcome), THIS task's result is reported honestly - see
// callbackDispatcher below - so returning false makes WorkManager itself
// keep retrying with its own backoff policy, and because it's constrained
// to NetworkType.connected it can only ever actually run once the phone
// genuinely has internet again. That's what makes "eppo internet varutho
// appo automatic ah upload aaganum" (upload automatically the moment
// internet comes back) true even if the shop owner never reopens the app.
const pendingDriveBackupRetryTaskName = 'pending_google_drive_backup_retry_task';
const pendingDriveBackupRetryUniqueName = 'pending_google_drive_backup_retry';

/// Arbitrary but unique android_alarm_manager_plus alarm id for the exact
/// ~10 PM daily Drive backup trigger (see [scheduleDailyBackupAlarm]) -
/// only has to be unique among this app's own AndroidAlarmManager alarms
/// (there is only this one today).
const _dailyBackupAlarmId = 930100;

/// WorkManager entry point - runs in its own background isolate, completely
/// separate from the app's UI isolate, whenever Android decides to execute
/// one of the periodic tasks registered below. Must stay a top-level
/// function annotated with @pragma('vm:entry-point') so the Android side
/// can still find it after the app process is killed.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case dailyDriveBackupTaskName:
        // Always reports success to WorkManager for THIS periodic slot
        // regardless of the actual backup outcome - a failure here queues
        // the separate, dedicated pendingDriveBackupRetryTaskName below
        // (a different uniqueName, so this is safe to register from here -
        // see that task's own doc comment for why it must never do the same
        // to itself), which is the task that actually gets retried.
        try {
          await BackupService().runDailyGoogleDriveBackupIfDue();
          if ((await BackupService().driveBackupStatus()).pending) {
            await schedulePendingDriveBackupRetry();
          }
        } catch (_) {}
        return Future.value(true);
      case dailyOrderReminderTaskName:
        try {
          await OrderReminderService().checkAndNotifyIfDue();
        } catch (_) {}
        return Future.value(true);
      case pendingDriveBackupRetryTaskName:
        // Reports the REAL outcome (true/false) instead of always true -
        // that's what makes WorkManager retry THIS SAME task automatically,
        // honouring its own backoffPolicy below, until it actually succeeds.
        // Deliberately does NOT itself call schedulePendingDriveBackupRetry
        // or cancelPendingDriveBackupRetry - a WorkManager task must never
        // re-register/replace or cancel its own currently-running
        // uniqueName (confirmed: doing so can throw a native
        // CancellationException back into that same running task).
        // Returning false + its own backoffPolicy is the safe, idiomatic
        // way for a task to reschedule itself.
        try {
          final ok = await BackupService().runDailyGoogleDriveBackupIfDue();
          return Future.value(ok);
        } catch (_) {
          return Future.value(false);
        }
      default:
        return Future.value(true);
    }
  });
}

/// Queues (or replaces an already-queued) one-off retry for the very next
/// moment the phone has internet, via WorkManager's NetworkType.connected
/// constraint - the actual mechanism behind the "wait for internet, then
/// upload automatically" requirement. Safe/idempotent to call repeatedly
/// (existingWorkPolicy.replace keeps only one retry queued at a time, always
/// reflecting the latest failure).
///
/// IMPORTANT: only ever call this from a context that is NOT the
/// pendingDriveBackupRetryTaskName task's own execution (i.e. from
/// main.dart on app open, or from callbackDispatcher's dailyDriveBackupTaskName
/// case above) - registering/replacing a WorkManager task while it is its
/// own currently-running instance can throw a native CancellationException.
/// If the retry task itself fails again, it relies purely on returning
/// false + its own backoffPolicy (see callbackDispatcher) to reschedule
/// itself instead of calling this.
Future<void> schedulePendingDriveBackupRetry() async {
  await _ensureWorkManagerInitialized();
  await Workmanager().registerOneOffTask(
    pendingDriveBackupRetryUniqueName,
    pendingDriveBackupRetryTaskName,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.replace,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 15),
  );
}

/// Cancels a queued pending-backup retry - called once a Drive backup
/// actually succeeds again, and when the shop disconnects Google Drive
/// entirely (nothing left to retry against). Safe to call even if nothing
/// is queued. Same self-reference caution as
/// [schedulePendingDriveBackupRetry] above applies here too.
Future<void> cancelPendingDriveBackupRetry() async {
  await _ensureWorkManagerInitialized();
  await Workmanager().cancelByUniqueName(pendingDriveBackupRetryUniqueName);
}

bool _wmInitialized = false;

/// initialize() only needs to run once per app run - every schedule*
/// function below calls this first, and it's a no-op after the first call.
Future<void> _ensureWorkManagerInitialized() async {
  if (_wmInitialized) return;
  await Workmanager().initialize(callbackDispatcher);
  _wmInitialized = true;
}

/// Registers the FALLBACK ~10 PM Google Drive backup with Android's
/// WorkManager (spec item 4: "Use WorkManager as fallback/retry
/// mechanism. Do not depend only on WorkManager for exact 10 PM timing")
/// - [scheduleDailyBackupAlarm] below is the PRIMARY, exact-time trigger.
/// Safe to call on every app startup - registerPeriodicTask() with
/// ExistingPeriodicWorkPolicy.keep leaves an already-scheduled task alone
/// instead of restarting its cycle. WorkManager needs no runtime
/// permission prompt for this (unlike exact-alarm scheduling), so the shop
/// owner is never asked anything.
///
/// IMPORTANT (please read before assuming "night 10 o clock" is exact):
/// Android's WorkManager does not guarantee an exact run time, even though
/// the initial delay below is computed to land on 10 PM - the OS can push
/// it later for battery/Doze-mode reasons. That's a deliberate Android
/// platform limitation, not a bug here - it's exactly why this exists
/// purely as a fallback alongside the exact alarm, and why
/// runDailyGoogleDriveBackupIfDue() is *also* called every time the app is
/// opened (see main.dart): even if BOTH background triggers run late, or
/// can't silently sign in, that day's backup still happens the moment the
/// shop owner next opens the app. Both this task and the exact alarm
/// funnel through the exact same due-check (runDailyGoogleDriveBackupIfDue
/// in backup_service.dart), which is what stops them from ever creating
/// two backups for the same day (spec item 4).
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

/// PRIMARY exact-time trigger for the daily Google Drive backup (spec item
/// 4: "Use Android AlarmManager / exact alarm where permitted"). Unlike
/// the Daily Order reminder's own exact alarm (DailyOrderAlarmReceiver.kt,
/// a plain BroadcastReceiver that can only run native Kotlin - show a
/// notification, nothing more), android_alarm_manager_plus's exact alarm
/// re-enters the Dart VM in its own background isolate, so the REAL backup
/// logic (BackupService.runDailyGoogleDriveBackupIfDue - snapshot, zip,
/// Drive upload, verification, all of it) can run directly from the alarm
/// itself instead of only being able to nudge the shop to open the app.
///
/// Fires once via [AndroidAlarmManager.oneShotAt] (NOT periodic - the exact
/// time of day has to be recomputed fresh every time so it keeps landing on
/// 10 PM local time across DST/timezone-offset changes, so
/// [backupAlarmCallback] below re-arms tomorrow's firing itself once this
/// one finishes) rather than [scheduleDailyGoogleDriveBackup]'s WorkManager
/// task above, which stays registered alongside this purely as the
/// required fallback/retry mechanism - see that function's doc comment for
/// why relying on WorkManager alone isn't good enough for "around 10 PM".
///
/// Safe to call repeatedly (app startup, and from the callback itself) -
/// oneShotAt with the same [_dailyBackupAlarmId] simply replaces whatever
/// was scheduled before. Never throws: if the exact-alarm plugin can't be
/// reached at all (a very old/unusual Android build), the WorkManager
/// fallback above still gets the backup done, just without the exact-time
/// guarantee - see [hasExactAlarmPermission]/[requestExactAlarmPermission]
/// for the one-time permission this needs on Android 12+ to actually land
/// exactly on time rather than being silently downgraded to inexact.
Future<void> scheduleDailyBackupAlarm() async {
  if (!Platform.isAndroid) return;
  try {
    await AndroidAlarmManager.initialize();
    final now = DateTime.now();
    var next10pm = DateTime(now.year, now.month, now.day, 22);
    if (!next10pm.isAfter(now)) {
      next10pm = next10pm.add(const Duration(days: 1));
    }
    await AndroidAlarmManager.oneShotAt(
      next10pm,
      _dailyBackupAlarmId,
      backupAlarmCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );
  } catch (_) {
    // WorkManager fallback above still covers the daily backup.
  }
}

/// Cancels the exact daily backup alarm - called when the shop disconnects
/// Google Drive entirely (nothing left to back up automatically) or turns
/// off the daily auto-backup toggle. Safe to call even if nothing is
/// currently scheduled.
Future<void> cancelDailyBackupAlarm() async {
  if (!Platform.isAndroid) return;
  try {
    await AndroidAlarmManager.initialize();
    await AndroidAlarmManager.cancel(_dailyBackupAlarmId);
  } catch (_) {}
}

/// Arbitrary but unique android_alarm_manager_plus alarm id for the
/// pre-backup reminder below - only has to differ from [_dailyBackupAlarmId].
const _preBackupReminderAlarmId = 930200;

/// Reminder alarm that fires a configurable number of minutes BEFORE the
/// ~10 PM automatic Google Drive backup (see [scheduleDailyBackupAlarm] just
/// above) - added so a shop owner has a chance to back up manually
/// themselves if the automatic one is about to fail (spec: "google drive
/// backup pannrathukku munnadi remider or alaram adikkiramathiri oru option
/// add pannu settings la. suppose automatic backup aagalana na manual ah
/// backup pannippan"). Off by default
/// (SettingsRepository.preBackupReminderEnabled) - the owner turns it on
/// from Settings and picks how many minutes of lead time
/// (SettingsRepository.preBackupReminderLeadMinutes, default 30).
///
/// Same oneShotAt + self-rearm pattern as [scheduleDailyBackupAlarm] above -
/// the exact minute has to be recomputed fresh every day (DST/timezone-safe)
/// and re-armed for tomorrow from inside the callback itself. Safe to call
/// repeatedly (app startup, right after the owner changes either Settings
/// value, and from the callback itself) - a new call always replaces
/// whatever was scheduled before under the same alarm id. If the setting is
/// off, this cancels any previously-armed reminder instead of scheduling
/// anything, so turning the toggle off takes effect immediately.
Future<void> schedulePreBackupReminderAlarm() async {
  if (!Platform.isAndroid) return;
  try {
    final settings = SettingsRepository();
    final enabled = await settings.get(SettingsRepository.preBackupReminderEnabled);
    if (enabled != 'true') {
      await cancelPreBackupReminderAlarm();
      return;
    }
    final leadStr = await settings.get(SettingsRepository.preBackupReminderLeadMinutes);
    final leadMinutes = int.tryParse(leadStr ?? '') ?? 30;

    await AndroidAlarmManager.initialize();
    final now = DateTime.now();
    var todays10pm = DateTime(now.year, now.month, now.day, 22);
    var reminderTime = todays10pm.subtract(Duration(minutes: leadMinutes));
    if (!reminderTime.isAfter(now)) {
      reminderTime = reminderTime.add(const Duration(days: 1));
    }
    await AndroidAlarmManager.oneShotAt(
      reminderTime,
      _preBackupReminderAlarmId,
      preBackupReminderAlarmCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );
  } catch (_) {
    // This reminder is a convenience on top of the exact 10PM backup alarm
    // and WorkManager fallback above - never let it block anything else.
  }
}

/// Cancels the pre-backup reminder alarm - called when the owner turns the
/// Settings toggle off. Safe to call even if nothing is currently scheduled.
Future<void> cancelPreBackupReminderAlarm() async {
  if (!Platform.isAndroid) return;
  try {
    await AndroidAlarmManager.initialize();
    await AndroidAlarmManager.cancel(_preBackupReminderAlarmId);
  } catch (_) {}
}

/// android_alarm_manager_plus entry point for [schedulePreBackupReminderAlarm]'s
/// exact alarm - see [backupAlarmCallback] below for why this needs its own
/// fresh isolate/re-initialize/@pragma boilerplate. Shows the reminder
/// notification (BackupService.showPreBackupReminderIfNeeded - which itself
/// no-ops if the setting is off or today's automatic backup already
/// succeeded) and always re-arms tomorrow's firing before returning.
@pragma('vm:entry-point')
void preBackupReminderAlarmCallback() async {
  try {
    await AndroidAlarmManager.initialize();
  } catch (_) {}
  try {
    await BackupService().showPreBackupReminderIfNeeded();
  } catch (_) {}
  try {
    await schedulePreBackupReminderAlarm();
  } catch (_) {}
}

/// android_alarm_manager_plus entry point for [scheduleDailyBackupAlarm]'s
/// exact alarm - runs in its own fresh background isolate (a distinct Dart
/// VM instance from both the app's UI isolate and WorkManager's own
/// callbackDispatcher above), so it re-initializes AndroidAlarmManager
/// itself before doing anything else. Must stay a top-level function
/// annotated with @pragma('vm:entry-point') so the Android side can still
/// find it after the app process is killed - same requirement as
/// [callbackDispatcher] above.
///
/// Runs the exact same due-checked backup as the WorkManager fallback task
/// (see [callbackDispatcher]'s dailyDriveBackupTaskName case) - both funnel
/// through BackupService.runDailyGoogleDriveBackupIfDue()'s own
/// once-per-verified-day gate plus its short-lived run lock, which
/// together are what stop the exact alarm and the WorkManager fallback
/// from ever creating two backups for the same day if they happen to land
/// close together (spec item 4). Always re-arms tomorrow's exact alarm
/// before returning, success or failure, since [AndroidAlarmManager.oneShotAt]
/// only ever fires once.
@pragma('vm:entry-point')
void backupAlarmCallback() async {
  try {
    await AndroidAlarmManager.initialize();
  } catch (_) {}
  try {
    await BackupService().runDailyGoogleDriveBackupIfDue();
    if ((await BackupService().driveBackupStatus()).pending) {
      await schedulePendingDriveBackupRetry();
    } else {
      await cancelPendingDriveBackupRetry();
    }
  } catch (_) {}
  try {
    await scheduleDailyBackupAlarm();
  } catch (_) {}
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
///
/// BUG FIX: the WorkManager registration below used to pass
/// ExistingPeriodicWorkPolicy.replace unconditionally, and this function is
/// called from BOTH main.dart (every single app open) AND Settings' save
/// handler. .replace tears down and re-registers the periodic task from
/// scratch, resetting its internal 15-minute timer back to zero - so a shop
/// owner who opens the app more often than every 15 minutes could keep this
/// catch-up poll perpetually restarting and never actually get an
/// uninterrupted 15 minutes to fire (the native exact alarm below is now
/// the primary, reliable trigger, but this WorkManager poll is still the
/// catch-up net for the rare case the exact alarm itself got dropped).
/// [forceReset] now defaults to false (existingWorkPolicy.keep, matching
/// scheduleDailyGoogleDriveBackup's already-correct pattern) so a routine
/// app open leaves an already-running cycle alone; only Settings' save
/// handler passes forceReset: true, since changing the send time is exactly
/// the one case where the cycle genuinely needs to restart.
Future<void> scheduleDailyOrderReminder({required int hour, required int minute, bool forceReset = false}) async {
  await _ensureWorkManagerInitialized();

  await Workmanager().registerPeriodicTask(
    dailyOrderReminderUniqueName,
    dailyOrderReminderTaskName,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: forceReset ? ExistingPeriodicWorkPolicy.replace : ExistingPeriodicWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 5),
  );

  // Also arms a native Android AlarmManager exact alarm for this same
  // hour:minute (DailyOrderAlarmReceiver.kt) - this is the actual fix for
  // "reminder never fires even with no-restriction battery settings on":
  // WorkManager's periodic polling above is still kept as a catch-up, but
  // an exact alarm is what real Android alarm-clock/reminder apps use
  // specifically because it survives Doze and OEM background-killers far
  // more reliably than JobScheduler-based WorkManager does. Never lets a
  // platform-channel hiccup (e.g. running on a very old/unusual Android
  // build) block the rest of Settings from saving.
  try {
    await _nativeChannel.invokeMethod('scheduleDailyOrderAlarm', {'hour': hour, 'minute': minute});
  } catch (_) {}
}

/// Cancels the background order-reminder trigger - called when the owner
/// switches the Daily Orders reminder off in Settings.
Future<void> cancelDailyOrderReminder() async {
  await _ensureWorkManagerInitialized();
  await Workmanager().cancelByUniqueName(dailyOrderReminderUniqueName);
  try {
    await _nativeChannel.invokeMethod('cancelDailyOrderAlarm');
  } catch (_) {}
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

/// Opens Android 12+'s "Alarms & reminders" permission screen for this
/// app, needed for the exact-alarm Daily Order reminder above to actually
/// fire at the precise minute instead of being silently downgraded to an
/// inexact (possibly late-by-hours) alarm - there is no in-app runtime
/// prompt for this, only this one-time Settings hand-off, same pattern as
/// [requestIgnoreBatteryOptimizations]. No-op (does nothing, never throws)
/// on Android 11 and below, where this permission doesn't exist and every
/// exact alarm is already allowed by default.
Future<void> requestExactAlarmPermission() async {
  if (!Platform.isAndroid) return;
  try {
    await _nativeChannel.invokeMethod('requestExactAlarmPermission');
  } catch (_) {}
}

/// Reports whether the exact-alarm ("Alarms & reminders") permission
/// above is ACTUALLY granted right now - unlike
/// [requestExactAlarmPermission], which only ever opens the Settings
/// screen and has no idea what the owner chose there. Used by
/// DailyOrderScreen to show a clear, always-visible warning ("reminder
/// may not fire on time - tap to fix") whenever the reminder is turned on
/// but this permission is still missing, instead of the alarm silently
/// falling back to an inexact, possibly hours-late trigger with nothing
/// in the app ever telling the owner why (spec: "notification time ku
/// kattuthu but alarm or reminder varala ella settings um allow
/// kuduthuttan" - settings show the right time but the alarm never
/// actually fires even though the owner believes every permission is
/// already allowed - a missing exact-alarm grant is the single most
/// likely silent cause).
/// Returns true on Android 11 and below (no such permission exists there,
/// every exact alarm is always allowed) and true if the check itself
/// fails for any reason - this function's job is to warn about a
/// confirmed problem, never to invent a false one from a plugin hiccup.
/// Returns true (skips the check) on non-Android platforms too.
Future<bool> hasExactAlarmPermission() async {
  if (!Platform.isAndroid) return true;
  try {
    final granted = await _nativeChannel.invokeMethod<bool>('canScheduleExactAlarms');
    return granted ?? true;
  } catch (_) {
    return true;
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

/// Call once from main(), right after the app boots, to catch the case
/// where THIS launch is happening because the shop owner tapped the
/// native exact-alarm reminder notification (DailyOrderAlarmReceiver.kt) -
/// that notification's contentIntent launches MainActivity with an
/// "open_daily_orders" extra, completely separately from
/// flutter_local_notifications (see OrderReminderService's own,
/// independent tap-handling - the exact alarm fires and is tapped purely
/// natively, so Dart never sees it any other way). Asks MainActivity "did
/// your launching Intent carry that flag?", consumes it (so re-checking
/// later never re-fires the same auto-send), and fires the same
/// DailyOrderAutoSendSignal used by the flutter_local_notifications path
/// if so - either reminder tapped lands the owner in the same one-tap-
/// left-for-WhatsApp state. Never throws - a platform-channel hiccup here
/// must never block app startup.
Future<bool> consumeDailyOrderAlarmLaunch() async {
  if (!Platform.isAndroid) return false;
  try {
    final launched = await _nativeChannel.invokeMethod('consumeDailyOrderLaunchFlag');
    if (launched == true) {
      DailyOrderAutoSendSignal.fire();
      return true;
    }
  } catch (_) {}
  return false;
}
