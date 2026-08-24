import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../db/database_helper.dart';
import '../repositories/settings_repository.dart';
import '../utils/id_gen.dart';

/// Manual + automatic local backup, and optional Google Drive backup (spec:
/// "Google Drive backup, Automatic backup, Manual backup, Restore"). The
/// whole app stays fully offline-first - Drive backup is the one
/// deliberately optional, internet-requiring feature.
///
/// Where local backups actually live, and why they used to seem invisible:
/// `getApplicationDocumentsDirectory()` (used below for the live database
/// too) is the app's *private* internal storage - Android does not show it
/// in the Files app / any file manager, by design, on any Android version.
/// A backup was always being created there; it just could never be found by
/// browsing storage. [createManualBackup] still keeps a copy there (fast,
/// always available for the in-app Restore list), but [exportBackupToFolder]
/// now lets the owner save a copy into any folder they can see and pick -
/// Downloads, WhatsApp, an SD card, anywhere - via Android's normal "Save
/// As" picker, and the Backup screen shows the private path too so it's
/// never a mystery again.
///
/// GOOGLE DRIVE SETUP (do this once, see README "Google Drive Backup
/// Setup"): create your own OAuth 2.0 Android client in Google Cloud
/// Console, register the app's package name + SHA-1, and Drive backup will
/// start working with no code changes - google_sign_in reads the client
/// config from android/app/google-services.json / the Android manifest.
class BackupService {
  final _dbHelper = DatabaseHelper.instance;
  final _settings = SettingsRepository();

  // driveFileScope (not the hidden driveAppdataScope this used to request) -
  // lets the app create/see a normal, visible folder in the owner's own My
  // Drive, and driveScope on top of it so the folder-picker below can list
  // the owner's existing folders to save into, per their explicit request.
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveScope],
  );

  Future<Directory> _backupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// The private backup folder's path, shown in the Backup screen so the
  /// owner always knows exactly where "Backup Now" writes to (even though,
  /// per the doc comment above, this specific folder isn't Files-app
  /// visible - that's what [exportBackupToFolder] is for).
  Future<String> backupDirPath() async => (await _backupDir()).path;

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

  /// Lets the owner choose exactly where a backup copy is saved (Downloads,
  /// an SD card, a WhatsApp folder to auto-sync it, etc.) via Android's own
  /// "Save As" picker - this is the offline manual backup the owner can
  /// actually find afterwards. Returns the chosen path, or null if the
  /// picker was cancelled.
  Future<String?> exportBackupToFolder() async {
    final backup = await createManualBackup();
    final bytes = await backup.readAsBytes();
    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save backup to...',
      fileName: p.basename(backup.path),
      bytes: bytes,
      type: FileType.any,
    );
    return savedPath;
  }

  /// Call this once on app startup. If more days than the configured
  /// frequency (default 1 = daily) have passed since the last backup of any
  /// type, a fresh local backup is taken automatically.
  Future<void> runAutoBackupIfDue() async {
    final enabled = await _settings.get(SettingsRepository.weeklyAutoBackupEnabled);
    if (enabled == 'false') return;

    final frequencyDays = int.tryParse(
          await _settings.get(SettingsRepository.autoBackupFrequencyDays) ?? '1',
        ) ??
        1;

    final lastBackupStr = await _settings.get(SettingsRepository.lastBackupAt);
    final due = lastBackupStr == null ||
        DateTime.now().difference(DateTime.parse(lastBackupStr)) > Duration(days: frequencyDays);
    if (!due) return;

    final dbFile = await _dbHelper.dbFile();
    final dir = await _backupDir();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final dest = File(p.join(dir.path, 'pms_auto_$stamp.db'));
    final copy = await dbFile.copy(dest.path);

    final db = await _dbHelper.database;
    await db.insert('backups', {
      'id': newId(),
      'backup_date': DateTime.now().toIso8601String(),
      'type': 'auto',
      'file_path': copy.path,
      'status': 'success',
      'notes': null,
    });
    await _settings.set(SettingsRepository.lastBackupAt, DateTime.now().toIso8601String());
  }

  Future<int> get autoBackupFrequencyDays async =>
      int.tryParse(await _settings.get(SettingsRepository.autoBackupFrequencyDays) ?? '1') ?? 1;

  Future<void> setAutoBackupFrequencyDays(int days) async =>
      _settings.set(SettingsRepository.autoBackupFrequencyDays, days.toString());

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

  /// Signs in and surfaces the *real* failure reason instead of a plain
  /// true/false, so a SHA-1 / OAuth-client mismatch shows up as an actual
  /// diagnosable message in the Backup screen rather than a silent
  /// "cancelled". This is the #1 cause of "select account" failing with
  /// "sign-in cancelled" or an "ApiException: 10" style error - see the
  /// README's Google Drive Backup Setup section for the exact fix.
  Future<GoogleSignInResult> signInToGoogleDrive() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        return GoogleSignInResult(success: false, message: 'Sign-in was cancelled.');
      }
      await _settings.set(SettingsRepository.googleDriveLinked, 'true');
      return GoogleSignInResult(success: true);
    } catch (e) {
      final msg = e.toString();
      String hint = msg;
      if (msg.contains('ApiException: 10') || msg.contains('DEVELOPER_ERROR')) {
        hint = 'Sign-in blocked (DEVELOPER_ERROR / code 10): the SHA-1 fingerprint registered in Google Cloud '
            'Console for this app\'s OAuth client does not match the key this APK was actually signed with. '
            'See README "Google Drive Backup Setup" - re-check the SHA-1 there against the one your current '
            'build was signed with.';
      } else if (msg.contains('ApiException: 12500') || msg.toLowerCase().contains('sign_in_failed')) {
        hint = 'Sign-in failed (SIGN_IN_FAILED): usually the same SHA-1/package-name mismatch as DEVELOPER_ERROR, '
            'or the OAuth consent screen / Drive API is not fully enabled yet in Google Cloud Console.';
      } else if (msg.contains('network')) {
        hint = 'Network error during sign-in - check the internet connection and try again.';
      }
      return GoogleSignInResult(success: false, message: hint);
    }
  }

  Future<void> signOutOfGoogleDrive() async {
    await _googleSignIn.signOut();
    await _settings.set(SettingsRepository.googleDriveLinked, 'false');
  }

  Future<bool> get isGoogleDriveLinked async =>
      (await _settings.get(SettingsRepository.googleDriveLinked)) == 'true';

  Future<drive.DriveApi?> _driveApi() async {
    final account = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
    if (account == null) return null;
    final authHeaders = await account.authHeaders;
    final client = _GoogleAuthClient(authHeaders);
    return drive.DriveApi(client);
  }

  /// Lists folders in the owner's My Drive root, for the "pick where backups
  /// go" screen. Normal, visible folders only - never the hidden App Data
  /// folder this app used to write to.
  Future<List<drive.File>> listDriveFolders() async {
    final api = await _driveApi();
    if (api == null) return [];
    final result = await api.files.list(
      q: "mimeType='application/vnd.google-apps.folder' and trashed=false and 'root' in parents",
      spaces: 'drive',
      $fields: 'files(id,name)',
    );
    return result.files ?? [];
  }

  Future<drive.File> createDriveFolder(String name) async {
    final api = await _driveApi();
    if (api == null) throw StateError('Not signed in to Google Drive');
    final folder = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder';
    return api.files.create(folder);
  }

  Future<void> setBackupFolder(String id, String name) async {
    await _settings.set(SettingsRepository.googleDriveFolderId, id);
    await _settings.set(SettingsRepository.googleDriveFolderName, name);
  }

  Future<String?> get backupFolderName async => _settings.get(SettingsRepository.googleDriveFolderName);

  /// Uploads to the folder the owner picked via [setBackupFolder]. If none
  /// has been picked yet, creates (once) and uses a normal, visible
  /// "Professional Mobiles Backups" folder in their My Drive - never the
  /// hidden App Data folder this app used to write to, which is why past
  /// backups never showed up when browsing Drive normally.
  Future<String?> backupToGoogleDrive() async {
    final api = await _driveApi();
    if (api == null) return null;

    var folderId = await _settings.get(SettingsRepository.googleDriveFolderId);
    if (folderId == null) {
      final created = await createDriveFolder('Professional Mobiles Backups');
      folderId = created.id;
      if (folderId != null) {
        await setBackupFolder(folderId, 'Professional Mobiles Backups');
      }
    }

    final backupFile = await createManualBackup();
    final driveFile = drive.File()
      ..name = p.basename(backupFile.path)
      ..parents = folderId != null ? [folderId] : null;

    final media = drive.Media(backupFile.openRead(), await backupFile.length());
    final uploaded = await api.files.create(driveFile, uploadMedia: media);

    final db = await _dbHelper.database;
    await db.insert('backups', {
      'id': newId(),
      'backup_date': DateTime.now().toIso8601String(),
      'type': 'google_drive',
      'file_path': uploaded.id,
      'status': 'success',
      'notes': 'Uploaded to Drive folder: ${await backupFolderName ?? 'Professional Mobiles Backups'}',
    });

    return uploaded.id;
  }
}

class GoogleSignInResult {
  final bool success;
  final String? message;
  GoogleSignInResult({required this.success, this.message});
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
