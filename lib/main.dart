import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/db/database_helper.dart';
import 'core/services/auth_service.dart';
import 'core/services/background_tasks.dart';
import 'core/services/backup_service.dart';
import 'core/services/daily_order_widget_service.dart';
import 'core/services/logo_service.dart';
import 'core/services/menu_order_service.dart';
import 'core/services/order_reminder_service.dart';
import 'core/services/theme_service.dart';
import 'core/repositories/settings_repository.dart';
import 'core/theme/app_theme.dart';
import 'screens/orders/quick_add_order_screen.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Warms up the offline SQLite database before the UI needs it.
  await DatabaseHelper.instance.database;

  // Fire-and-forget: takes a local backup automatically if more than 7
  // days have passed since the last one (spec "Weekly automatic backup").
  BackupService().runWeeklyAutoBackupIfDue();

  // Registers the ~10 PM daily Google Drive backup with Android's
  // WorkManager (no permission prompt - see backup_service.dart), and also
  // runs today's Drive backup right now if it's still due (e.g. the
  // background run hasn't happened yet, ran late, or failed last time due
  // to no internet) - this app-open catch-up is what guarantees a missed
  // day never stays missed for long.
  scheduleDailyGoogleDriveBackup();
  BackupService().runDailyGoogleDriveBackupIfDue();

  // Daily Orders reminder (see screens/orders/daily_order_screen.dart) -
  // registers the background WorkManager trigger at the shop's saved send
  // time (defaults to 12:30 the first time this ever runs), and also
  // checks right now in case that trigger already fired late today, or
  // hasn't run yet, or the phone was off - same catch-up pattern as the
  // Drive backup above.
  final settings = SettingsRepository();
  final savedTime = await settings.get(SettingsRepository.dailyOrderSendTime) ?? '12:30';
  final timeParts = savedTime.split(':');
  final reminderHour = int.tryParse(timeParts[0]) ?? 12;
  final reminderMinute = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 30) : 30;
  scheduleDailyOrderReminder(hour: reminderHour, minute: reminderMinute);
  // Proactively ask for the Android 13+ "Allow notifications?" permission
  // right here, in the foreground, on every app open - instead of only ever
  // asking deep inside checkAndNotifyIfDue() (which only runs this the day
  // pending items actually exist). That mattered because the WorkManager
  // background trigger below fires from a headless isolate with no Activity
  // to show a permission dialog from - if the very first time this
  // permission was ever requested happened to be from that background
  // isolate, Android has nothing to show the user and the request silently
  // does nothing, so the reminder notification could stay permanently
  // blocked without the shop ever seeing a prompt. Requesting it here
  // guarantees it's asked (and, once answered, remembered by the OS) during
  // an interactive session, well before any background-timed reminder can
  // ever fire.
  await OrderReminderService.ensureInitialized();
  OrderReminderService().checkAndNotifyIfDue();

  // Daily Orders home-screen widget (Phase 2) - refreshes on every app
  // startup so the widget reflects carry-forward changes even if the shop
  // owner never opens the Daily Orders screen itself that day (see
  // DailyOrderWidgetService's doc comment for the other refresh points).
  DailyOrderWidgetService().refresh();

  final themeService = ThemeService();
  await themeService.load();

  final menuOrderService = MenuOrderService();
  await menuOrderService.load();

  final logoService = LogoService();
  await logoService.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider.value(value: themeService),
        ChangeNotifierProvider.value(value: menuOrderService),
        ChangeNotifierProvider.value(value: logoService),
      ],
      child: const ProfessionalMobilesApp(),
    ),
  );
}

/// Second, minimal Flutter entry point used ONLY by the Daily Orders
/// home-screen widget's "+ Add"/card tap (see QuickAddActivity.kt and
/// DailyOrderWidgetProvider.kt, both injected into android/ by the CI
/// build script since that folder is regenerated fresh every build).
///
/// This used to be a homewidgetpro://quickadd deep link that still routed
/// through MainActivity and this file's main() - which is exactly why the
/// widget tap kept visibly "opening pro_app" (splash, then jumping past
/// the PIN screen) no matter how that in-app routing was tuned. Now the
/// widget launches a completely separate Android Activity/task
/// (QuickAddActivity) that boots THIS entry point instead of main() - a
/// fresh, tiny Flutter engine that skips every bit of main()'s other
/// startup work (backup scheduling, reminder scheduling, theme/menu/logo
/// services) and shows nothing but QuickAddOrderScreen. MainActivity is
/// never created, so a widget tap no longer looks or behaves like the app
/// opening at all - closing this screen (X, back, or after Save) finishes
/// that entire separate task straight back to the home screen, matching
/// the standalone ("thaniya") behaviour asked for.
@pragma('vm:entry-point')
Future<void> quickAddMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _QuickAddApp());
}

class _QuickAddApp extends StatelessWidget {
  const _QuickAddApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: AppColors.primaryBlue,
        brightness: Brightness.light,
      ),
      home: const QuickAddOrderScreen(),
    );
  }
}
