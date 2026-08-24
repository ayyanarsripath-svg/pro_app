import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/db/database_helper.dart';
import 'core/services/auth_service.dart';
import 'core/services/backup_service.dart';
import 'core/services/reorder_scheduler_service.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Warms up the offline SQLite database before the UI needs it.
  await DatabaseHelper.instance.database;

  // Fire-and-forget: takes a local backup automatically if the configured
  // interval (default 1 day) has passed since the last one - see
  // BackupService.runAutoBackupIfDue.
  BackupService().runAutoBackupIfDue();

  // Arms every pending supplier-order reminder's exact alarm - this is the
  // safety net for alarms cleared by a device reboot or killed by battery
  // optimisation (see ReorderSchedulerService's doc comment for why this
  // matters). Must happen on every app start, not just when an order is
  // first created.
  ReorderSchedulerService().rescheduleAll();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
      ],
      child: const ProfessionalMobilesApp(),
    ),
  );
}
