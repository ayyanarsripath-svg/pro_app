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
///
/// Uses the google_sign_in 7.x API (the old GoogleSignInClient-based API -
/// .signIn()/.signInSilently()/.currentUser/.authHeaders - was deprecated by
/// Google and stopped completing sign-in on newer Play Services, which is
/// what caused the "sign_in_failed (10: )" DEVELOPER_ERROR some devices hit
/// even with a correctly configured OAuth client). The new API is a single
/// shared GoogleSignIn.instance that must be initialize()'d once, splits
/// "who is this" (authenticate / attemptLightweightAuthentication) from
/// "what can they let us access" (authorizationClient), and throws
/// GoogleSignInException instead of PlatformException.
class BackupService {
  final _dbHelper = DatabaseHelper.instance;
  final _settings = SettingsRepository();

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _initialized = false;

  static const _driveScopes = [drive.DriveApi.driveAppdataScope, drive.DriveApi.driveFileScope];

  /// Web OAuth client id (NOT the Android client id below it). Android's
  /// Credential Manager - what google_sign_in 7.x uses under the hood on
  /// Android - calls this the "server client id" and requires one even
  /// though this app has no server: without it, initialize() throws
  /// GoogleSignInExceptionCode.clientConfigurationError ("serverClientId
  /// must be provided on Android"). Created as a separate OAuth 2.0 "Web
  /// application" client in Google Cloud Console (Credentials) - it is
  /// only ever used as this audience value, never for an actual web sign-in
  /// flow, so it has no authorised origins/redirect URIs. See README
  /// "Google Drive Backup Setup".
  static const _serverClientId =
      '565887732327-7f6lovmktnnav8hiupjr8qgjoujaj406.apps.googleusercontent.com';

  /// initialize() only needs to run once per app run - safe to call before
  /// every Drive operation since it no-ops after the first call.
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _googleSignIn.initialize(serverClientId: _serverClientId);
    _initialized = true;
  }

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

  /// Opens the "choose a Google account" picker, then asks that account to
  /// grant the Drive scopes this app needs, and links Drive backup.
  ///
  /// Before this fix, if sign-in itself failed - almost always because this
  /// build's Google Cloud OAuth client hasn't been set up yet, or its
  /// SHA-1/package name don't match this APK (see README "Google Drive
  /// Backup Setup") - the old API threw a [PlatformException] that nothing
  /// caught, so the "Connect Google Drive" button just looked frozen after
  /// tapping an account: no error, no snackbar, nothing. It now always
  /// resolves, and throws a plain-English [Exception] the screen can show.
  Future<bool> signInToGoogleDrive() async {
    try {
      await _ensureInitialized();
      final account = await _googleSignIn.authenticate();
      await account.authorizationClient.authorizeScopes(_driveScopes);
      await _settings.set(SettingsRepository.googleDriveLinked, 'true');
      return true;
    } on GoogleSignInException catch (e) {
if (e.code == GoogleSignInExceptionCode.canceled) return (e.description != null && e.description!.trim().isNotEmpty) ? (throw Exception('Sign-in reported "cancelled", but Android included this extra detail: ${e.description}')) : false; // diagnostic: surface e.description instead of assuming a real user cancel
      throw Exception(_friendlyGoogleError(e));
    }
  }

  /// Translates the raw Google sign-in error codes into something a shop
  /// owner (not a developer) can act on.
  String _friendlyGoogleError(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        // The modern equivalent of the old "sign_in_failed (10: )" /
        // DEVELOPER_ERROR - by far the most common cause is no OAuth client
        // configured yet for this app, or its SHA-1 fingerprint / package
        // name doesn't match this build.
        return 'Google sign-in failed (${e.code.name}${e.description != null ? ': ${e.description}' : ''}). '
            'This almost always means the Google Cloud OAuth client for this '
            'app isn\'t set up yet, or its SHA-1 fingerprint / package name '
            'doesn\'t match this build. See README "Google Drive Backup Setup".';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'Google sign-in couldn\'t be shown right now. Please try again.';
      case GoogleSignInExceptionCode.userMismatch:
        return 'A different Google account is already linked on this device. Sign out and try again.';
      case GoogleSignInExceptionCode.interrupted:
        return 'No internet connection, or sign-in was interrupted. Try again once you\'re online.';
      case GoogleSignInExceptionCode.canceled:
        return 'Sign-in was cancelled.';
      default:
        return 'Google sign-in failed: ${e.description ?? e.code}.';
    }
  }

  Future<void> signOutOfGoogleDrive() async {
    await _ensureInitialized();
    await _googleSignIn.signOut();
    await _settings.set(SettingsRepository.googleDriveLinked, 'false');
  }

  Future<bool> get isGoogleDriveLinked async =>
      (await _settings.get(SettingsRepository.googleDriveLinked)) == 'true';

  Future<String?> backupToGoogleDrive() async {
    try {
      await _ensureInitialized();

      // attemptLightweightAuthentication() itself can be a null Future (not
      // just resolve to a null account) when lightweight auth isn't
      // possible right now - both cases mean "not silently signed in".
      final lightweight = _googleSignIn.attemptLightweightAuthentication();
      final account = lightweight != null ? await lightweight : null;
      if (account == null) {
        throw Exception('Not signed in to Google Drive - use "Connect Google Drive" first.');
      }

      // Reuse a previously granted authorization silently if we still have
      // one; only fall back to an interactive prompt if we don't.
      GoogleSignInClientAuthorization? authorization =
          await account.authorizationClient.authorizationForScopes(_driveScopes);
      authorization ??= await account.authorizationClient.authorizeScopes(_driveScopes);

      final authHeaders = {'Authorization': 'Bearer ${authorization.accessToken}'};
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
    } on GoogleSignInException catch (e) {
      throw Exception(_friendlyGoogleError(e));
    }
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
