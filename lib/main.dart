import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/db/database_helper.dart';
import 'core/services/auth_service.dart';
import 'core/services/backup_service.dart';
import 'core/services/theme_service.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Warms up the offline SQLite database before the UI needs it.
  await DatabaseHelper.instance.database;

  // Fire-and-forget: takes a local backup automatically if more than 7
  // days have passed since the last one (spec "Weekly automatic backup").
  BackupService().runWeeklyAutoBackupIfDue();

  final themeService = ThemeService();
  await themeService.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider.value(value: themeService),
      ],
      child: const ProfessionalMobilesApp(),
    ),
  );
}
