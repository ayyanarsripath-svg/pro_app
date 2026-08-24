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

  // Just driveFileScope now - backups no longer go into Drive's hidden
  // "app data" folder (driveAppdataScope), which the shop owner could never
  // actually open or browse from the Drive app/website. See
  // _findOrCreateBackupFolder below. Anyone who linked Drive before this
  // change will be asked to reconnect once, since their old authorization
  // doesn't cover this scope yet - that's expected, not a bug.
  static const _driveScopes = [drive.DriveApi.driveFileScope];

  /// Name of the regular, visible Google Drive folder backups now live in
  /// (created once, reused after that) - open it in the Drive app/website
  /// to see one file per month.
  static const _backupFolderName = 'Professional Mobiles Backups';

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

  /// Absolute path to the folder local backups are stored in - shown in
  /// Settings -> Backup & Restore. This lives inside the app's own private
  /// storage (Android's scoped-storage rules), which is exactly why it
  /// never shows up in the phone's own Files app on its own - the Share
  /// button next to each backup (see BackupScreen) is the actual way to
  /// get a copy out, by handing the file to WhatsApp/Drive/email/a file
  /// manager's own "Save a copy" action instead of trying to write into
  /// public storage directly.
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
  ///
  /// Separately, some phones hit a distinct failure that Android reports as
  /// a plain "cancelled" but with an extra detail attached, most commonly
  /// "[16] Account reauth failed" - this is Google Play Services rejecting
  /// a stale/broken cached sign-in state on THAT phone, not a real tap on
  /// Cancel and not a problem with this app's own OAuth setup. Rather than
  /// showing that raw error immediately, this now clears the broken local
  /// state with [GoogleSignIn.disconnect] and retries once automatically -
  /// which fixes it silently for most shops. Only if the retry also fails
  /// does the shop see an error, and it's a plain-English one instead of
  /// the raw Android string.
  Future<bool> signInToGoogleDrive() async {
    await _ensureInitialized();
    try {
      return await _authenticateAndLink();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        final hasExtraDetail = e.description != null && e.description!.trim().isNotEmpty;
        if (!hasExtraDetail) return false; // a genuine tap on Cancel - nothing to show

        try {
          await _googleSignIn.disconnect();
        } catch (_) {
          // nothing was linked yet on this phone to disconnect - fine,
          // fall through to the retry below regardless.
        }
        try {
          return await _authenticateAndLink();
        } on GoogleSignInException catch (retryError) {
          if (retryError.code == GoogleSignInExceptionCode.canceled &&
              !(retryError.description != null && retryError.description!.trim().isNotEmpty)) {
            return false; // the retry itself was a genuine user cancel
          }
          throw Exception(_reauthFailedMessage(retryError));
        }
      }
      throw Exception(_friendlyGoogleError(e));
    }
  }

  Future<bool> _authenticateAndLink() async {
    final account = await _googleSignIn.authenticate();
    await account.authorizationClient.authorizeScopes(_driveScopes);
    await _settings.set(SettingsRepository.googleDriveLinked, 'true');
    return true;
  }

  /// Fully forgets whatever Google account is currently linked (if any) -
  /// revoking this app's access via [GoogleSignIn.disconnect], not just a
  /// local sign-out - and opens the account picker fresh, so the shop can
  /// either link a *different* Google account, or get past a stuck
  /// "Account reauth failed" error without leaving the app. Exposed as its
  /// own "Change Google Account" button in Settings -> Backup & Restore,
  /// separate from the automatic one-time retry inside
  /// [signInToGoogleDrive] above.
  Future<bool> reconnectGoogleDrive() async {
    await _ensureInitialized();
    try {
      await _googleSignIn.disconnect();
    } catch (_) {
      // nothing was linked yet - fine, still proceed to a fresh sign-in.
    }
    await _settings.set(SettingsRepository.googleDriveLinked, 'false');
    try {
      return await _authenticateAndLink();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      throw Exception(_friendlyGoogleError(e));
    }
  }

  /// The specific, actionable message shown when even the automatic
  /// disconnect-and-retry inside [signInToGoogleDrive] couldn't get past a
  /// "cancelled (with extra detail)" error such as "[16] Account reauth
  /// failed". Distinct from [_friendlyGoogleError] (which handles the
  /// other, more standard [GoogleSignInException] codes) because this one
  /// needs to explain a phone-side stuck state, not an app configuration
  /// problem.
  String _reauthFailedMessage(GoogleSignInException e) {
    return 'Google could not confirm your account on this phone (it reported '
        '"${e.description ?? e.code.name}"). This is almost always a stuck '
        'sign-in on the phone itself, not a problem with the app or your '
        'internet.\n\n'
        'Please try:\n'
        '1. Tap "Connect Google Drive" again - it often works the 2nd time.\n'
        '2. If it keeps failing, use "Change Google Account" below, or open '
        'the Google Account app on this phone -> your account -> Security '
        '-> "Apps with access to your account", remove Professional '
        'Mobiles there, then connect again from here.\n'
        '3. Make sure this phone has an active internet connection.';
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

  /// Calendar-month label used both as the Drive file name suffix and shown
  /// to the shop owner - e.g. 2026-08 for August 2026.
  String _monthLabel(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}';

  String _monthlyBackupFileName(DateTime date) => 'professional_mobiles_backup_${_monthLabel(date)}.db';

  /// Finds the (already created, regular/visible) "Professional Mobiles
  /// Backups" folder in the signed-in account's Drive, creating it the
  /// first time this ever runs. Unlike the old appDataFolder, this folder
  /// is a completely normal Drive folder - the shop owner can open Drive
  /// and see it, browse into it, download a file, delete it, whatever they
  /// want, the same as any folder they created by hand.
  Future<String> _findOrCreateBackupFolder(drive.DriveApi driveApi) async {
    final existing = await driveApi.files.list(
      q: "mimeType='application/vnd.google-apps.folder' and name='$_backupFolderName' and trashed=false",
      spaces: 'drive',
    );
    final files = existing.files;
    if (files != null && files.isNotEmpty) return files.first.id!;

    final folder = drive.File()
      ..name = _backupFolderName
      ..mimeType = 'application/vnd.google-apps.folder';
    final created = await driveApi.files.create(folder);
    return created.id!;
  }

  /// Uploads [localFile] as *this calendar month's* Drive backup (spec:
  /// "monthly wise pirichi pirichi save aaganum" - split up and saved
  /// month-wise). If a file for the current month already exists in the
  /// backup folder, its content is replaced in place (files.update) so
  /// every month stays exactly ONE file that always holds the latest, fully
  /// cumulative snapshot of that month's data (every backup here is a full
  /// database copy, never a partial diff, so today's data is always
  /// automatically merged with everything noted earlier that month - there
  /// is nothing separate to "merge"). The moment the calendar month
  /// changes, the next backup simply doesn't find a match and creates a
  /// brand new file instead - so a month ago, or three months ago, is still
  /// sitting there untouched, and the owner just opens the Drive folder and
  /// picks whichever month's file they need.
  Future<String> _uploadMonthlySnapshot(drive.DriveApi driveApi, File localFile) async {
    final folderId = await _findOrCreateBackupFolder(driveApi);
    final fileName = _monthlyBackupFileName(DateTime.now());

    final existing = await driveApi.files.list(
      q: "name='$fileName' and '$folderId' in parents and trashed=false",
      spaces: 'drive',
    );
    final media = drive.Media(localFile.openRead(), await localFile.length());
    final matches = existing.files;

    if (matches != null && matches.isNotEmpty) {
      final fileId = matches.first.id!;
      final updated = await driveApi.files.update(drive.File(), fileId, uploadMedia: media);
      return updated.id ?? fileId;
    }

    final driveFile = drive.File()
      ..name = fileName
      ..parents = [folderId];
    final created = await driveApi.files.create(driveFile, uploadMedia: media);
    return created.id!;
  }

  /// Uploads the current database to this month's Drive backup file. Used
  /// both by the "Backup to Drive" button and the automatic daily backup
  /// (see [runDailyGoogleDriveBackupIfDue]) - both write to the exact same
  /// monthly file, so pressing the button never creates extra clutter.
  /// Unlike [createManualBackup]/[runWeeklyAutoBackupIfDue], this does NOT
  /// add anything to the Local Backups list - it works from a throwaway
  /// temp copy of the database that's deleted right after the upload, so
  /// backing up to Drive every single day forever never piles up local
  /// files on the phone itself.
  ///
  /// [allowInteractiveSignIn] controls what happens if the silent/lightweight
  /// sign-in fails (token expired, access revoked from the Google Account
  /// side, etc.): when true (the default, used by the foreground "Backup to
  /// Drive" button) this opens the account picker right here and
  /// re-authorizes automatically, so a stale connection quietly repairs
  /// itself instead of just failing. When false (used by the background
  /// daily auto-backup below) it never tries to show UI from a background
  /// isolate - it simply throws, gets caught by the caller, and that day
  /// stays "due" for the next successful attempt instead.
  Future<String?> backupToGoogleDrive({bool allowInteractiveSignIn = true}) async {
    try {
      await _ensureInitialized();

      // attemptLightweightAuthentication() itself can be a null Future (not
      // just resolve to a null account) when lightweight auth isn't
      // possible right now - both cases mean "not silently signed in".
      final lightweight = _googleSignIn.attemptLightweightAuthentication();
      GoogleSignInAccount? account = lightweight != null ? await lightweight : null;
      if (account == null) {
        if (!allowInteractiveSignIn) {
          throw Exception('Not signed in to Google Drive - use "Connect Google Drive" first.');
        }
        // Silent sign-in didn't work any more (expired/revoked token) -
        // re-open the account flow right here instead of failing outright,
        // satisfying "reconnect automatically" without a separate trip to
        // Settings first.
        account = await _googleSignIn.authenticate();
        await _settings.set(SettingsRepository.googleDriveLinked, 'true');
      }

      // Reuse a previously granted authorization silently if we still have
      // one; only fall back to an interactive prompt if we don't.
      GoogleSignInClientAuthorization? authorization =
          await account.authorizationClient.authorizationForScopes(_driveScopes);
      authorization ??= await account.authorizationClient.authorizeScopes(_driveScopes);

      final authHeaders = {'Authorization': 'Bearer ${authorization.accessToken}'};
      final client = _GoogleAuthClient(authHeaders);
      final driveApi = drive.DriveApi(client);

      final dbFile = await _dbHelper.dbFile();
      final tempDir = await getTemporaryDirectory();
      final snapshot = await dbFile.copy(p.join(tempDir.path, 'pms_drive_upload_${DateTime.now().millisecondsSinceEpoch}.db'));

      String uploadedId;
      try {
        uploadedId = await _uploadMonthlySnapshot(driveApi, snapshot);
      } finally {
        if (await snapshot.exists()) await snapshot.delete();
      }

      final db = await _dbHelper.database;
      await db.insert('backups', {
        'id': newId(),
        'backup_date': DateTime.now().toIso8601String(),
        'type': 'google_drive',
        'file_path': uploadedId,
        'status': 'success',
        'notes': 'Uploaded to Drive folder "$_backupFolderName" > ${_monthlyBackupFileName(DateTime.now())}',
      });

      return uploadedId;
    } on GoogleSignInException catch (e) {
      throw Exception(_friendlyGoogleError(e));
    }
  }

  /// Called both from the WorkManager background task (once daily, aimed at
  /// ~10 PM - see [scheduleDailyGoogleDriveBackup] in background_tasks.dart)
  /// and every time the app is opened (see main.dart). Backs up to Google
  /// Drive at most once per calendar day - and because this compares
  /// calendar dates rather than a fixed 24-hour duration, and only advances
  /// [SettingsRepository.lastDriveBackupAt] after an upload actually
  /// succeeds, a day that failed (no internet, sign-in hiccup, etc.) simply
  /// stays "due" and is automatically picked up by the very next successful
  /// attempt - nothing extra to implement, since backupToGoogleDrive()
  /// always uploads a fresh full snapshot of the database, not an
  /// incremental diff, so that next attempt captures everything regardless
  /// of how many days were missed.
  ///
  /// Never throws - background execution must not crash the isolate, and a
  /// foreground caller on app open shouldn't see a Drive hiccup as an error.
  /// Returns true only if a backup was actually uploaded just now.
  Future<bool> runDailyGoogleDriveBackupIfDue() async {
    try {
      final enabled = await _settings.get(SettingsRepository.dailyDriveAutoBackupEnabled);
      if (enabled == 'false') return false;

      final linked = await isGoogleDriveLinked;
      if (!linked) return false;

      final now = DateTime.now();
      final lastStr = await _settings.get(SettingsRepository.lastDriveBackupAt);
      if (lastStr != null) {
        final last = DateTime.parse(lastStr);
        final sameDay = last.year == now.year && last.month == now.month && last.day == now.day;
        if (sameDay) return false;
      }

      // allowInteractiveSignIn: false - this can run from a background
      // WorkManager isolate with no foreground Activity to show an account
      // picker in, so it must only ever use a silent/already-authorized
      // connection, never try to pop UI. See backupToGoogleDrive's doc
      // comment.
      await backupToGoogleDrive(allowInteractiveSignIn: false);
      await _settings.set(SettingsRepository.lastDriveBackupAt, now.toIso8601String());
      return true;
    } catch (_) {
      // Leave lastDriveBackupAt untouched so today stays "due" and the next
      // attempt (next WorkManager run, or the next app open) retries - this
      // is the "next day include panni back up aaganum" catch-up behaviour.
      return false;
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
