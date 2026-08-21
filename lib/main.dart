import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
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
import 'core/services/widget_launch_state.dart';
import 'core/repositories/settings_repository.dart';
import 'app.dart';

/// homewidgetpro://quickadd - the deep link the widget's native "+ Add"
/// button launches the app with (see DailyOrderWidgetProvider.kt, injected
/// by the CI build script). Anything else is a plain tap, handled as a
/// normal app open.
bool _isQuickAddUri(Uri? uri) => uri?.host == 'quickadd';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cold start via the widget's "+ Add" button -> skip straight to
  // QuickAddOrderScreen, no PIN screen (see WidgetLaunchState / app.dart).
  final initialWidgetUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
  if (_isQuickAddUri(initialWidgetUri)) {
    WidgetLaunchState.quickAddRequested.value = true;
  }
  // Same deep link, but the app process was already alive (e.g. sitting
  // in the background) when the button was tapped.
  HomeWidget.widgetClicked.listen((uri) {
    if (_isQuickAddUri(uri)) {
      WidgetLaunchState.quickAddRequested.value = true;
    }
  });

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
