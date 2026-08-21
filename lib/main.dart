import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/db/database_helper.dart';
import 'core/services/auth_service.dart';
import 'core/services/backup_service.dart';
import 'core/services/logo_service.dart';
import 'core/services/menu_order_service.dart';
import 'core/services/theme_service.dart';
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
