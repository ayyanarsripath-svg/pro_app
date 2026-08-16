import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../db/database_helper.dart';
import '../repositories/settings_repository.dart';
import '../utils/id_gen.dart';

/// Manual + weekly-automatic local backup, and optional Google Drive backup
/// (spec: "Google Drive backup, Weekly automatic backup, Manual backup,
/// Restore"). The whole app stays fully offline-first - Drive backup is the
/// one deliberately optional, internet-requiring feature.
///
/// GOOGLE DRIVE SETUP (do this once, see README "Google Drive Backup
/// Setup"): create your own OAuth 2.0 Android client in Google Cloud
/// Console, register the app's package name + SHA-1, and Drive backup will
/// start working with no code changes - google_sign_in reads the client
/// config from android/app/google-services.json / the Android manifest.
class BackupService {
  final _dbHelper = DatabaseHelper.instance;
  final _settings = SettingsRepository();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveAppdataScope, drive.DriveApi.driveFileScope],
  );

  Future<Directory> _backupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copies the live SQLite file into /backups/<timestamp>.db. Safe to call
  /// any time - sqflite keeps the file consistent, and the app continues
  /// running against the original connection.
  Future<File> createManualBackup() async {
    final dbFile = await _dbHelper.dbFile();
    final dir = await _backupDir();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final dest = File(p.join(dir.path, 'pms_backup_$stamp.db'));
    final copy = await dbFile.copy(dest.path);

    final db = await _dbHelper.database;
    await db.insert('backups', {
      'id': newId(),
      'backup_date': DateTime.now().toIso8601String(),
      'type': 'manual',
      'file_path': copy.path,
      'status': 'success',
      'notes': null,
    });
    await _settings.set(SettingsRepository.lastBackupAt, DateTime.now().toIso8601String());
    return copy;
  }

  /// Call this once on app startup. If more than 7 days have passed since
  /// the last backup (of any type), a fresh local backup is taken
  /// automatically (spec "Weekly automatic backup").
  Future<void> runWeeklyAutoBackupIfDue() async {
    final enabled = await _settings.get(SettingsRepository.weeklyAutoBackupEnabled);
    if (enabled == 'false') return;

    final lastBackupStr = await _settings.get(SettingsRepository.lastBackupAt);
    final due = lastBackupStr == null ||
        DateTime.now().difference(DateTime.parse(lastBackupStr)) > const Duration(days: 7);
    if (!due) return;

    final dbFile = await _dbHelper.dbFile();
    final dir = await _backupDir();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final dest = File(p.join(dir.path, 'pms_weekly_$stamp.db'));
    final copy = await dbFile.copy(dest.path);

    final db = await _dbHelper.database;
    await db.insert('backups', {
      'id': newId(),
      'backup_date': DateTime.now().toIso8601String(),
      'type': 'weekly_auto',
      'file_path': copy.path,
      'status': 'success',
      'notes': null,
    });
    await _settings.set(SettingsRepository.lastBackupAt, DateTime.now().toIso8601String());
  }

  Future<List<File>> listLocalBackups() async {
    final dir = await _backupDir();
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.db')).toList();
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  /// Restores the database from a chosen backup file. The app must be
  /// restarted afterwards so a fresh sqflite connection opens the restored
  /// file cleanly.
  Future<void> restoreFrom(File backupFile) async {
    await _dbHelper.closeDb();
    final liveFile = await _dbHelper.dbFile();
    await backupFile.copy(liveFile.path);
  }

  // ---------------------------------------------------------------------
  // Google Drive (optional - requires the shop owner's own OAuth client,
  // see class doc comment above).
  // ---------------------------------------------------------------------

  Future<bool> signInToGoogleDrive() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return false;
    await _settings.set(SettingsRepository.googleDriveLinked, 'true');
    return true;
  }

  Future<void> signOutOfGoogleDrive() async {
    await _googleSignIn.signOut();
    await _settings.set(SettingsRepository.googleDriveLinked, 'false');
  }

  Future<bool> get isGoogleDriveLinked async =>
      (await _settings.get(SettingsRepository.googleDriveLinked)) == 'true';

  Future<String?> backupToGoogleDrive() async {
    final account = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
    if (account == null) return null;

    final authHeaders = await account.authHeaders;
    final client = _GoogleAuthClient(authHeaders);
    final driveApi = drive.DriveApi(client);

    final backupFile = await createManualBackup();
    final driveFile = drive.File()
      ..name = p.basename(backupFile.path)
      ..parents = ['appDataFolder'];

    final media = drive.Media(backupFile.openRead(), await backupFile.length());
    final uploaded = await driveApi.files.create(driveFile, uploadMedia: media);

    final db = await _dbHelper.database;
    await db.insert('backups', {
      'id': newId(),
      'backup_date': DateTime.now().toIso8601String(),
      'type': 'google_drive',
      'file_path': uploaded.id,
      'status': 'success',
      'notes': 'Uploaded to Google Drive App Data folder',
    });

    return uploaded.id;
  }
}

class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();
  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}
