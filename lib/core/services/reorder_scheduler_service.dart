import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:permission_handler/permission_handler.dart';

import '../repositories/reorder_repository.dart';
import '../../models/reorder_task.dart';

/// Schedules the "supplier order" reminder notification for an exact
/// wall-clock time and fires it reliably.
///
/// Written to avoid the three most common reasons a "set 2:42, fires at a
/// different time / never fires" bug happens on Android:
///  1. Not initialising the `timezone` package's local zone. Without
///     `tz.setLocalLocation(...)`, flutter_local_notifications' zonedSchedule
///     treats a `TZDateTime` as UTC, not the phone's real timezone - on a
///     device set to IST (UTC+5:30) that silently shifts every scheduled
///     time. We always set the local zone before scheduling (see `init()`).
///  2. Not requesting Android 12+'s "exact alarm" permission or Android
///     13+'s notification permission. Without them Android silently
///     downgrades the alarm to an *inexact* one (fires within a ~15 minute
///     window) or drops it entirely - which looks exactly like "close to
///     the time but wrong, or never happens". We request both explicitly
///     and surface it in the UI if either is missing.
///  3. No "catch up" pass, so an alarm cleared by a reboot, by
///     battery-optimisation killing the app, or by the OS simply missing it
///     (common on Xiaomi/Vivo/Oppo phones unless the app is exempted from
///     battery optimisation) means the order silently never goes out. We
///     also re-check every pending order every time the app is opened or
///     resumed and fire immediately if its time has already passed.
class ReorderSchedulerService {
  static final ReorderSchedulerService _instance = ReorderSchedulerService._internal();
  factory ReorderSchedulerService() => _instance;
  ReorderSchedulerService._internal();

  final _repo = ReorderRepository();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialised = false;

  static const _channelId = 'reorder_channel';
  static const _channelName = 'Supplier Order Reminders';
  static const _channelDesc = 'Alerts you the moment a supplier order is due to be sent on WhatsApp';

  /// A due order's id, broadcast so the UI can react (generate the PDF /
  /// open the WhatsApp share sheet) the moment a notification is tapped or
  /// a catch-up pass finds one due. Screens listen to this instead of the
  /// plugin's raw callback so both the "tapped while running" and the
  /// "found on app resume" paths behave identically.
  final ValueNotifier<String?> dueTaskId = ValueNotifier<String?>(null);

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    tz_data.initializeTimeZones();
    // This app is built for a single shop in India (spec is entirely IST /
    // Tamil Nadu based) so the local zone is fixed to IST rather than left
    // uninitialised. Leaving it uninitialised is what caused the original
    // bug class: flutter_local_notifications' zonedSchedule interprets an
    // uninitialised `tz.local` as UTC, so "2:42 PM" got scheduled 5 hours
    // 30 minutes away from the intended IST time.
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final id = response.payload;
        if (id != null) dueTaskId.value = id;
      },
    );

    // Covers the cold-start case: if the app was fully closed and the user
    // opened it by tapping the reminder notification, onDidReceiveNotification
    // Response above never fires for that launch - this is the API
    // flutter_local_notifications expects you to check instead.
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final id = launchDetails!.notificationResponse?.payload;
      if (id != null) dueTaskId.value = id;
    }

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));
  }

  /// Ask for the two Android permissions exact scheduling needs. Safe to
  /// call repeatedly; returns true only if both are granted.
  Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    final notif = await Permission.notification.request();
    final exactAlarm = await Permission.scheduleExactAlarm.request();
    return notif.isGranted && exactAlarm.isGranted;
  }

  Future<bool> hasExactAlarmPermission() async {
    if (!Platform.isAndroid) return true;
    return await Permission.scheduleExactAlarm.isGranted;
  }

  /// Builds the exact target instant from a plain [scheduledAt] (already in
  /// local wall-clock time, e.g. "today/tomorrow at 14:42:00"). Only ever
  /// rounds *forward* to the next day if the time already passed today -
  /// never adjusts minutes/seconds, so "2:42" always means 2:42:00 and
  /// nothing subtly recomputes it to a different minute.
  tz.TZDateTime _nextInstance(DateTime scheduledAt) {
    final now = tz.TZDateTime.now(tz.local);
    var target = tz.TZDateTime(
      tz.local,
      scheduledAt.year,
      scheduledAt.month,
      scheduledAt.day,
      scheduledAt.hour,
      scheduledAt.minute,
      0, // seconds - always zero, so "2:42" always means 2:42:00, never 2:41:5x
    );
    if (target.isBefore(now)) {
      target = target.add(const Duration(days: 1));
    }
    return target;
  }

  Future<void> schedule(ReorderTask task) async {
    await init();
    final target = _nextInstance(task.scheduledAt);

    await _plugin.zonedSchedule(
      task.notificationId,
      'Order ready for ${task.supplierName}',
      task.note.length > 80 ? '${task.note.substring(0, 80)}...' : task.note,
      target,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: false,
          category: AndroidNotificationCategory.reminder,
        ),
      ),
      // exactAllowWhileIdle keeps firing even in Doze - a plain "exact"
      // schedule can still be delayed by the OS once the screen has been
      // off for a while, which matched the "sometimes never fires" report.
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // DateTimeComponents.time makes this fire at the same clock time every
      // day *natively* inside Android's AlarmManager when repeatDaily is on,
      // instead of us hand-computing "add one more day" after every fire -
      // that kind of manual re-scheduling is a classic source of drift bugs.
      matchDateTimeComponents: task.repeatDaily ? DateTimeComponents.time : null,
      payload: task.id,
    );
  }

  Future<void> cancel(ReorderTask task) async {
    await init();
    await _plugin.cancel(task.notificationId);
  }

  /// Re-arms every pending/notified order's alarm. Call this once on every
  /// app start - it's the safety net for alarms cleared by a device reboot
  /// or by the OS killing the app under battery optimisation.
  Future<void> rescheduleAll() async {
    await init();
    final tasks = await _repo.pendingOrNotified();
    for (final t in tasks) {
      if (!t.repeatDaily && t.scheduledAt.isBefore(DateTime.now())) {
        // One-time order whose time already passed while the app/alarm was
        // dead - surface it immediately instead of silently dropping it.
        dueTaskId.value = t.id;
        continue;
      }
      await schedule(t);
    }
  }

  /// Foreground catch-up: called on app start/resume. Anything whose time
  /// has passed but wasn't marked notified/sent gets surfaced right away,
  /// so a missed OS alarm still doesn't mean a silently-skipped order.
  Future<List<ReorderTask>> checkAndCollectDue() async {
    final tasks = await _repo.pendingOrNotified();
    final due = tasks.where((t) => !t.scheduledAt.isAfter(DateTime.now())).toList();
    for (final t in due) {
      await _repo.updateStatus(t.id, ReorderTask.statusNotified);
    }
    return due;
  }
}
