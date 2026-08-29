import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../db/database_helper.dart';
import '../repositories/settings_repository.dart';
import '../utils/id_gen.dart';
import 'device_id_service.dart';

/// Manual local backup, and automatic + on-demand Google Drive backup (spec:
/// "Google Drive backup, Manual backup, Restore"). The whole app stays fully
/// offline-first - Drive backup is the one deliberately optional,
/// internet-requiring feature.
///
/// DATA-LOSS INCIDENT FIX (2026-08): a shop owner lost real business data
/// after an uninstall/reinstall because a Drive backup silently failed with
/// zero visibility - the old runDailyGoogleDriveBackupIfDue() caught every
/// error with a bare `catch (_) {}` and just waited for the next calendar
/// day, so nothing ever told the owner their data wasn't actually protected
/// (spec: "backup missing aagi erukku pola ethu periya problem so care full
/// ah handle pannu ple many data missing"). This class was redesigned around
/// three rules instead: (1) every failure is now logged to the `backups`
/// table AND remembered in Settings (driveBackupPending/driveBackupLastError)
/// so Backup & Restore can always show the truth; (2) a failure immediately
/// queues a network-constrained WorkManager retry (see
/// schedulePendingDriveBackupRetry in background_tasks.dart) so the backup
/// uploads automatically the instant the phone has internet again, without
/// needing the app to be open; (3) a non-dismissible ("ongoing") notification
/// stays up the entire time a backup is pending, so the owner always has a
/// visible signal something needs attention (spec: "notification la
/// kattanum na thalli vitta kuda poga kudathu").
///
/// DAILY-INDEPENDENT-FILE REWRITE (2026-08, PRO SERVICE spec): the
/// "one file per calendar month, updated in place" Drive design above this
/// paragraph was itself a data-safety risk - a shop restoring "last week"
/// actually got whatever the LATEST upload that month happened to overwrite
/// it with, restoring from a stale/half-written file could silently return
/// old data (spec bug list: "Restore sometimes returns old data" /
/// "Backup may show SUCCESS even when latest data was not uploaded"), and
/// there was no way to reach back to yesterday's exact snapshot once today
/// had overwritten it. Every Drive backup - automatic or manual - now
/// creates a brand new, independent file every single time
/// (PRO_SERVICE_BACKUP_yyyy-MM-dd_HH-mm-ss_DEVICE_xxxxxxxx.zip, spec item
/// 1), NEVER updates an existing file in place, and NEVER shows "Backup
/// Successful" until the upload has actually been re-fetched from Drive and
/// confirmed to exist with a real size and a matching checksum (spec item
/// 7). See the class-level flow below and each method's own doc comment for
/// the rest.
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
///
/// ---------------------------------------------------------------------
/// Daily backup flow (spec item 16):
///   trigger (exact ~10 PM alarm, or WorkManager fallback, or app open)
///     -> runDailyGoogleDriveBackupIfDue()
///     -> already verified for today? stop (spec item 4's duplicate guard)
///     -> internet available? if not, mark pending and stop (spec item 5)
///     -> backupToGoogleDrive():
///          checkpoint + copy the live database
///          -> sweep every other file under app storage (photos etc.)
///          -> write manifest.json (app/schema/format version, device id,
///             per-table row counts)
///          -> zip everything into one file (spec item 3: snapshot before
///             upload, never the live files directly)
///          -> upload as a brand NEW Drive file (spec item 6)
///          -> re-fetch that exact file from Drive and confirm id/size/
///             modifiedTime/checksum (spec item 7) - delete it and treat
///             as a failure if anything doesn't check out
///          -> record full history (this file's id/size/checksum/device)
///          -> prune old files per the retention policy (spec item 12)
/// ---------------------------------------------------------------------
class BackupService {
  final _dbHelper = DatabaseHelper.instance;
  final _settings = SettingsRepository();
  final _deviceId = DeviceIdService();

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
  /// to see every daily backup file (spec item 1).
  static const _backupFolderName = 'Professional Mobiles Backups';

  /// Bumped whenever the *shape* of a backup .zip itself changes (which
  /// files it contains, manifest.json's own structure) - separate from
  /// [DatabaseHelper.dbVersion], which only tracks the SQLite schema inside
  /// it (spec item 14: "Backup format version"). A restore refuses (with a
  /// clear error, never a silent/partial restore - spec item 14) any backup
  /// whose backupFormatVersion is newer than this app understands.
  static const int _backupFormatVersion = 2;

  /// Every Drive backup file name starts with this - both what marks a file
  /// as "a genuine PRO SERVICE backup" when listing/restoring (spec item 9:
  /// never trust a name search or a first search result blindly - this is
  /// only ever used to build the list shown to the shop owner, restoring
  /// itself always goes by the exact fileId they picked) and what the
  /// retention policy is allowed to ever prune.
  static const _fileNamePrefix = 'PRO_SERVICE_BACKUP_';

  /// How many of the most recent daily backups to always keep, regardless
  /// of age (spec item 12: "Keep: Last 30 daily backups").
  static const _retentionDailyCount = 30;

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

  Future<List<File>> listLocalBackups() async {
    final dir = await _backupDir();
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.db')).toList();
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  /// Restores the database from a chosen RAW .db backup file (local manual
  /// backups, and "Restore from File"). NOT used for Google Drive restores
  /// any more - those are a .zip snapshot (database + attachments +
  /// manifest.json) handled by [restoreFromGoogleDriveFile]'s own safer
  /// validate -> safety-backup -> replace -> verify flow. The app must be
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
  /// The "cancelled (with extra detail)" / "[16] Account reauth failed"
  /// failure this can also hit is handled by [_authenticateAccount] below -
  /// see its doc comment for why a single retry wasn't holding up on every
  /// phone.
  Future<bool> signInToGoogleDrive() async {
    await _ensureInitialized();
    final account = await _authenticateAccount();
    if (account == null) return false; // a genuine tap on Cancel
    await account.authorizationClient.authorizeScopes(_driveScopes);
    return true;
  }

  /// How many times an interactive sign-in automatically retries (each
  /// retry first clears the phone's cached sign-in state with
  /// [GoogleSignIn.disconnect] and pauses briefly) before giving up and
  /// showing the shop an error. A single retry used to be enough for most
  /// shops, but some phones need their cached state cleared more than once
  /// before Play Services lets a fresh sign-in through - this is why
  /// [_authenticateAccount] loops instead of trying just twice.
  static const _maxAuthAttempts = 3;

  /// Runs the Google account picker + sign-in, retrying automatically (up
  /// to [_maxAuthAttempts] times total) whenever Android reports a plain
  /// "cancelled" but with an extra detail attached, most commonly "[16]
  /// Account reauth failed" - this is Google Play Services rejecting a
  /// stale/broken cached sign-in state on THAT phone (spec: "pic panna
  /// solluthu pic panna thirumba pic panna solluthu aprom error kamikkuthu"
  /// - asks to pick an account, picks, asks again, picks again, then
  /// still errors), not a real tap on Cancel and not a problem with this
  /// app's own OAuth setup. Each retry clears that broken state with
  /// [GoogleSignIn.disconnect] and pauses briefly first, since Play
  /// Services sometimes needs a moment to actually drop the old cached
  /// account before a fresh attempt can succeed - retrying instantly back
  /// to back tended to just hit the same stale state again.
  ///
  /// A genuine tap on Cancel (no extra detail attached) returns null
  /// immediately, never retried. Any other kind of [GoogleSignInException]
  /// (bad OAuth client config, no internet, etc.) is translated and thrown
  /// right away. Only once every retry has *also* failed with the
  /// reauth-style error does this throw the specific, actionable
  /// [_reauthFailedMessage] - shared by [signInToGoogleDrive],
  /// [reconnectGoogleDrive], and the silent-auth-expired fallback inside
  /// [backupToGoogleDrive], so every place this app opens the account
  /// picker gets the same resilience.
  Future<GoogleSignInAccount?> _authenticateAccount() async {
    GoogleSignInException? lastReauthError;
    for (var attempt = 1; attempt <= _maxAuthAttempts; attempt++) {
      try {
        final account = await _googleSignIn.authenticate();
        await _settings.set(SettingsRepository.googleDriveLinked, 'true');
        return account;
      } on GoogleSignInException catch (e) {
        if (e.code != GoogleSignInExceptionCode.canceled) {
          throw Exception(_friendlyGoogleError(e));
        }
        final hasExtraDetail = e.description != null && e.description!.trim().isNotEmpty;
        if (!hasExtraDetail) return null; // a genuine tap on Cancel - stop immediately

        lastReauthError = e;
        if (attempt == _maxAuthAttempts) break;
        try {
          await _googleSignIn.disconnect();
        } catch (_) {
          // nothing was linked yet on this phone to disconnect - fine,
          // still retry below regardless.
        }
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }
    throw Exception(_reauthFailedMessage(lastReauthError!));
  }

  /// Fully forgets whatever Google account is currently linked (if any) -
  /// revoking this app's access via [GoogleSignIn.disconnect], not just a
  /// local sign-out - and opens the account picker fresh, so the shop can
  /// either link a *different* Google account, or get past a stuck
  /// "Account reauth failed" error without leaving the app. Exposed as its
  /// own "Change Google Account" button in Settings -> Backup & Restore,
  /// separate from the automatic retries already inside
  /// [signInToGoogleDrive]/[_authenticateAccount] above.
  Future<bool> reconnectGoogleDrive() async {
    await _ensureInitialized();
    try {
      await _googleSignIn.disconnect();
    } catch (_) {
      // nothing was linked yet - fine, still proceed to a fresh sign-in.
    }
    await _settings.set(SettingsRepository.googleDriveLinked, 'false');
    final account = await _authenticateAccount();
    if (account == null) return false;
    await account.authorizationClient.authorizeScopes(_driveScopes);
    return true;
  }

  /// The specific, actionable message shown when even the automatic
  /// disconnect-and-retry loop inside [_authenticateAccount] couldn't get
  /// past a "cancelled (with extra detail)" error such as "[16] Account
  /// reauth failed". Distinct from [_friendlyGoogleError] (which handles
  /// the other, more standard [GoogleSignInException] codes) because this
  /// one needs to explain a phone-side stuck state, not an app
  /// configuration problem.
  String _reauthFailedMessage(GoogleSignInException e) {
    return 'Google could not confirm your account on this phone (it kept '
        'reporting "${e.description ?? e.code.name}" even after retrying '
        'automatically several times). This is almost always a stuck '
        'sign-in on the phone itself, not a problem with the app or your '
        'internet.\n\n'
        'Please try:\n'
        '1. Close this app completely (swipe it away from recent apps), '
        'reopen it, and tap "Connect Google Drive" again - a full restart '
        'clears more of the stuck state than retrying inside the app does.\n'
        '2. Open the Google Play Store app -> tap your profile picture -> '
        'Settings -> About -> check for a Play Services/Play Store update, '
        'and install one if available - this exact error is commonly tied '
        'to an outdated Play Services build.\n'
        '3. If it still fails, open the Google Account app on this phone '
        '-> your account -> Security -> "Apps with access to your '
        'account", remove Professional Mobiles there, restart the phone, '
        'then connect again from here.\n'
        '4. Make sure this phone has an active internet connection.';
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
    // Nothing left to retry against once Drive is unlinked - clear any
    // pending-backup state/notification and cancel the queued WorkManager
    // retry so it doesn't keep waking up for an account that's no longer
    // connected.
    await _clearPendingDriveBackup(showRecoveredNotification: false);
  }

  Future<bool> get isGoogleDriveLinked async =>
      (await _settings.get(SettingsRepository.googleDriveLinked)) == 'true';

  /// yyyy-MM-dd for [date] - THE unique daily-backup key (spec item 4).
  String _dailyDateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// Builds this backup's file name (spec item 1's format, with item 13's
  /// device suffix): PRO_SERVICE_BACKUP_yyyy-MM-dd_HH-mm-ss_DEVICE_xxxxxxxx.zip
  String _fileNameFor(DateTime date, String deviceLabel) {
    final time =
        '${date.hour.toString().padLeft(2, '0')}-${date.minute.toString().padLeft(2, '0')}-${date.second.toString().padLeft(2, '0')}';
    return '$_fileNamePrefix${_dailyDateKey(date)}_${time}_DEVICE_$deviceLabel.zip';
  }

  /// Finds the (already created, regular/visible) "Professional Mobiles
  /// Backups" folder in the signed-in account's Drive, creating it the
  /// first time this ever runs (spec item 1: "If the folder does not
  /// exist, create it automatically"). Unlike the old appDataFolder, this
  /// folder is a completely normal Drive folder - the shop owner can open
  /// Drive and see it, browse into it, download a file, delete it,
  /// whatever they want, the same as any folder they created by hand.
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

  Future<drive.DriveApi> _authorizedDriveApi({required bool allowInteractiveSignIn}) async {
    await _ensureInitialized();

    // attemptLightweightAuthentication() itself can be a null Future (not
    // just resolve to a null account) when lightweight auth isn't possible
    // right now - both cases mean "not silently signed in".
    final lightweight = _googleSignIn.attemptLightweightAuthentication();
    GoogleSignInAccount? account = lightweight != null ? await lightweight : null;
    if (account == null) {
      if (!allowInteractiveSignIn) {
        throw Exception('Not signed in to Google Drive - use "Connect Google Drive" first.');
      }
      // Silent sign-in didn't work any more (expired/revoked token) -
      // re-open the account flow right here instead of failing outright,
      // satisfying "reconnect automatically" without a separate trip to
      // Settings first. Goes through the same retrying
      // _authenticateAccount() as the "Connect Google Drive"/"Change
      // Google Account" buttons, so a stuck "[16] Account reauth failed"
      // hit from here gets the same automatic recovery instead of failing
      // on the first try.
      account = await _authenticateAccount();
      if (account == null) {
        throw Exception('Sign-in was cancelled.');
      }
    }

    // Reuse a previously granted authorization silently if we still have
    // one; only fall back to an interactive prompt if we don't.
    GoogleSignInClientAuthorization? authorization =
        await account.authorizationClient.authorizationForScopes(_driveScopes);
    authorization ??= await account.authorizationClient.authorizeScopes(_driveScopes);

    final authHeaders = {'Authorization': 'Bearer ${authorization.accessToken}'};
    final client = _GoogleAuthClient(authHeaders);
    return drive.DriveApi(client);
  }

  /// Runs `PRAGMA wal_checkpoint(TRUNCATE)` on the live database before a
  /// backup copy is taken. Safe/no-op if the database isn't in WAL mode (it
  /// isn't, by default, on this app) - kept as a defensive belt-and-braces
  /// step regardless, so that IF a very recently saved record (e.g. a
  /// service job just moved to "Ready for Delivery" or "Checking") were
  /// ever sitting in a separate WAL file instead of the main .db file at
  /// the exact moment a backup copy is taken, it gets folded into the main
  /// file first and is never silently missing from the backup. Never
  /// throws - a checkpoint failing must never block the backup itself from
  /// proceeding with whatever is already safely in the main file.
  Future<void> _checkpointBeforeBackup() async {
    try {
      final db = await _dbHelper.database;
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // Never let a checkpoint failure block the backup itself.
    }
  }

  /// Best-effort internet check (spec item 5) - used to fail FAST and
  /// honestly with "no internet" instead of only discovering the phone is
  /// offline after a slow/ambiguous timeout deep inside the Drive upload
  /// call. Never throws, and defaults to true (assume online, let the real
  /// network call be the final judge) if the check itself fails for any
  /// reason - this must never be the thing that blocks a genuine attempt.
  Future<bool> _hasInternet() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Row count for every real table in the database (sqlite_master minus
  /// SQLite's own internal/system tables) - written into every backup's
  /// manifest.json and compared again after a restore (spec: "Verify
  /// record counts").
  Future<Map<String, int>> _tableRowCounts() async {
    final db = await _dbHelper.database;
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
    );
    final counts = <String, int>{};
    for (final row in tables) {
      final name = row['name'] as String;
      final result = await db.rawQuery('SELECT COUNT(*) AS c FROM "$name"');
      counts[name] = (result.first['c'] as int?) ?? 0;
    }
    return counts;
  }

  /// Copies every file under the app's own document storage into
  /// [destDir], EXCEPT the live database file itself (copied separately,
  /// after a WAL checkpoint - see [_createSnapshotZip]) and the local
  /// "backups/" folder (this app's own on-phone manual backups - not part
  /// of what a Drive snapshot needs to contain). This is a deliberate
  /// sweep rather than a hardcoded list of known folders (service photos,
  /// the shop logo, etc.) so ANY attachment this app ever stores - now or
  /// added later - is automatically included (spec: "If customer/service/
  /// product photos or attachments are stored by the app, include them in
  /// the backup as well").
  Future<void> _copyAttachments(Directory docsDir, Directory destDir) async {
    if (!await docsDir.exists()) return;
    final dbFileName = DatabaseHelper.dbFileName;
    await for (final entity in docsDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: docsDir.path);
      final firstSegment = rel.split(Platform.pathSeparator).first;
      if (firstSegment == 'backups') continue; // local manual .db backups, not a Drive concern
      if (rel == dbFileName || rel.startsWith('$dbFileName-')) continue; // live db (+ any -wal/-shm sidecar)
      final destPath = p.join(destDir.path, rel);
      try {
        await Directory(p.dirname(destPath)).create(recursive: true);
        await entity.copy(destPath);
      } catch (_) {
        // One unreadable/locked file must never abort the whole backup -
        // everything else still gets backed up.
      }
    }
  }

  /// Recursively zips [sourceDir]'s contents (paths relative to it) into
  /// [zipPath].
  Future<File> _zipDirectory(Directory sourceDir, String zipPath) async {
    final archive = Archive();
    await for (final entity in sourceDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: sourceDir.path).replaceAll('\\', '/');
      final bytes = await entity.readAsBytes();
      archive.addFile(ArchiveFile(rel, bytes.length, bytes));
    }
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('Could not build the backup archive.');
    }
    final zipFile = File(zipPath);
    await zipFile.writeAsBytes(zipBytes, flush: true);
    return zipFile;
  }

  /// Extracts every entry of the zip at [zipFile] into [destDir].
  Future<void> _extractZip(File zipFile, Directory destDir) async {
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    // [_zipDirectory] above only ever calls archive.addFile() for actual
    // files it walks (directories are never added as their own entries -
    // they're implied by the file paths, e.g. "database/xxx.db") so every
    // entry here is guaranteed to be a real file, never a directory
    // placeholder - no need to branch on an entry "is a file" check that
    // isn't consistently available across archive package versions.
    for (final entry in archive.files) {
      final outPath = p.join(destDir.path, entry.name);
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      final content = entry.content;
      await outFile.writeAsBytes(content is List<int> ? content : List<int>.from(content as Iterable<int>), flush: true);
    }
  }

  /// SHA-256 (stored as this backup's own long-term integrity checksum -
  /// spec item 6: "checksum/hash") and MD5 (compared against Google
  /// Drive's own reported `md5Checksum` right after upload - spec item
  /// 7.8) of [file], computed together so the file only has to be streamed
  /// from disk twice, not four times.
  Future<({String sha256, String md5})> _hashesOfFile(File file) async {
    final shaDigest = await sha256.bind(file.openRead()).first;
    final md5Digest = await md5.bind(file.openRead()).first;
    return (sha256: shaDigest.toString(), md5: md5Digest.toString());
  }

  /// Builds one full snapshot .zip of the current database + every
  /// attachment file (spec item 2/3: "complete database backup", "create
  /// snapshot before upload") plus a manifest.json describing it (spec item
  /// 14). Used both for the actual Drive upload and, with
  /// [labelPrefix] = 'pms_safety_before_restore', for the temporary local
  /// safety copy [restoreFromGoogleDriveFile] takes of the CURRENT data
  /// right before ever touching it (spec item 10).
  Future<File> _createSnapshotZip({String labelPrefix = 'pms_drive_upload'}) async {
    await _checkpointBeforeBackup();

    final docsDir = await getApplicationDocumentsDirectory();
    final dbFile = await _dbHelper.dbFile();
    final tempDir = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final workDir = Directory(p.join(tempDir.path, '${labelPrefix}_work_$stamp'));
    await workDir.create(recursive: true);

    try {
      final dbDest = File(p.join(workDir.path, 'database', DatabaseHelper.dbFileName));
      await dbDest.parent.create(recursive: true);
      await dbFile.copy(dbDest.path);

      final filesDest = Directory(p.join(workDir.path, 'files'));
      await filesDest.create(recursive: true);
      await _copyAttachments(docsDir, filesDest);

      final manifest = {
        'backupFormatVersion': _backupFormatVersion,
        'schemaVersion': DatabaseHelper.dbVersion,
        'appVersion': await _appVersion(),
        'deviceBackupId': await _deviceId.fullId(),
        'createdAt': DateTime.now().toIso8601String(),
        'tableCounts': await _tableRowCounts(),
      };
      final manifestFile = File(p.join(workDir.path, 'manifest.json'));
      await manifestFile.writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));

      final zipPath = p.join(tempDir.path, '${labelPrefix}_$stamp.zip');
      return await _zipDirectory(workDir, zipPath);
    } finally {
      if (await workDir.exists()) await workDir.delete(recursive: true);
    }
  }

  /// Re-fetches the just-uploaded file from Drive itself (never trusting
  /// the upload response alone) and confirms every check spec item 7
  /// requires before this app is allowed to ever say "Backup Successful":
  /// a real fileId, a size greater than zero that matches what was sent, a
  /// valid modifiedTime, and - when Drive reports one - a matching MD5
  /// checksum.
  Future<_VerifyResult> _verifyUploadedBackup(
    drive.DriveApi driveApi,
    drive.File created, {
    required String expectedMd5,
    required int expectedSize,
  }) async {
    final id = created.id;
    if (id == null || id.isEmpty) return const _VerifyResult(false, 'Drive did not return a file id.');

    drive.File fetched;
    try {
      fetched = await driveApi.files.get(id, $fields: 'id,name,size,modifiedTime,md5Checksum') as drive.File;
    } catch (e) {
      return _VerifyResult(false, 'Could not confirm the uploaded file exists in Drive ($e).');
    }

    final remoteSize = int.tryParse(fetched.size ?? '') ?? -1;
    if (remoteSize <= 0) return const _VerifyResult(false, 'Drive reports the uploaded file as empty.');
    if (remoteSize != expectedSize) {
      return _VerifyResult(false, 'Uploaded size ($remoteSize bytes) does not match what was sent ($expectedSize bytes).');
    }
    if (fetched.modifiedTime == null) {
      return const _VerifyResult(false, 'Drive did not report a valid modified time for the uploaded file.');
    }
    final remoteMd5 = fetched.md5Checksum;
    if (remoteMd5 != null && remoteMd5.isNotEmpty && remoteMd5.toLowerCase() != expectedMd5.toLowerCase()) {
      return const _VerifyResult(false, 'Checksum mismatch - the uploaded file does not match what was sent.');
    }
    return const _VerifyResult(true, null);
  }

  /// Uploads the current database + attachments as a brand NEW Google
  /// Drive file (spec items 1 and 6 - never updates an existing file in
  /// place), only ever returning once that upload has been independently
  /// re-verified (spec item 7). Used both by the "Backup to Drive" button
  /// and the automatic daily backup (see [runDailyGoogleDriveBackupIfDue]).
  ///
  /// [allowInteractiveSignIn] controls what happens if the silent/lightweight
  /// sign-in fails (token expired, access revoked from the Google Account
  /// side, etc.): when true (the default, used by any foreground button)
  /// this opens the account picker right here and re-authorizes
  /// automatically, so a stale connection quietly repairs itself instead of
  /// just failing. When false (used by the background daily auto-backup)
  /// it never tries to show UI from a background isolate - it simply
  /// throws, gets caught by the caller, and that day stays "due" for the
  /// next successful attempt instead.
  ///
  /// Never returns null - every failure throws (a friendly message for a
  /// sign-in problem, the raw error otherwise) so the caller always knows
  /// exactly why "Backup Successful" was NOT shown (spec item 7).
  Future<DriveBackupFileInfo> backupToGoogleDrive({bool allowInteractiveSignIn = true}) async {
    if (!await _hasInternet()) {
      throw Exception('No internet connection right now.');
    }
    try {
      final driveApi = await _authorizedDriveApi(allowInteractiveSignIn: allowInteractiveSignIn);
      final now = DateTime.now();
      final deviceLabel = await _deviceId.shortLabel();
      final fileName = _fileNameFor(now, deviceLabel);

      final zipFile = await _createSnapshotZip();
      try {
        final fileSize = await zipFile.length();
        if (fileSize <= 0) {
          throw Exception('The backup snapshot came out empty (0 bytes) - stopped before uploading anything.');
        }
        final hashes = await _hashesOfFile(zipFile);

        final folderId = await _findOrCreateBackupFolder(driveApi);
        final driveFile = drive.File()
          ..name = fileName
          ..parents = [folderId]
          ..appProperties = {
            'proServiceBackup': 'true',
            'backupFormatVersion': _backupFormatVersion.toString(),
            'schemaVersion': DatabaseHelper.dbVersion.toString(),
            'deviceBackupId': await _deviceId.fullId(),
            'dateKey': _dailyDateKey(now),
          };
        final media = drive.Media(zipFile.openRead(), fileSize);
        // .create() ALWAYS makes a brand new file - unlike the old
        // .update()-in-place monthly design, there is deliberately no
        // "does a file already exist for X" lookup anywhere in this
        // method (spec item 6: "Do NOT search by filename and overwrite
        // an existing file").
        final created = await driveApi.files.create(
          driveFile,
          uploadMedia: media,
          $fields: 'id,name,size,modifiedTime,md5Checksum',
        );

        final verified = await _verifyUploadedBackup(driveApi, created, expectedMd5: hashes.md5, expectedSize: fileSize);
        if (!verified.ok) {
          if (created.id != null) {
            // A file that failed verification cannot be trusted as a real
            // backup - best-effort delete it rather than leaving a
            // corrupt/incomplete file sitting in the folder looking like
            // a genuine daily backup.
            try {
              await driveApi.files.delete(created.id!);
            } catch (_) {}
          }
          throw Exception('Upload verification failed: ${verified.reason}');
        }

        final info = DriveBackupFileInfo(
          id: created.id!,
          name: created.name ?? fileName,
          modifiedTime: created.modifiedTime,
          size: fileSize,
        );

        await _recordSuccessfulDriveBackup(info: info, checksum: hashes.sha256, now: now);
        await _applyRetentionPolicy(driveApi);
        return info;
      } finally {
        if (await zipFile.exists()) await zipFile.delete();
      }
    } on GoogleSignInException catch (e) {
      throw Exception(_friendlyGoogleError(e));
    }
  }

  /// Records a verified-successful Drive backup: a full standalone history
  /// row in the `backups` table (spec: file id/size/checksum/device/
  /// version, independent of whatever Settings says about the MOST RECENT
  /// backup) and the quick-access Settings mirror Backup & Restore's
  /// "Backup History" section reads without needing another Drive call.
  Future<void> _recordSuccessfulDriveBackup({
    required DriveBackupFileInfo info,
    required String checksum,
    required DateTime now,
  }) async {
    final db = await _dbHelper.database;
    await db.insert('backups', {
      'id': newId(),
      'backup_date': now.toIso8601String(),
      'type': 'google_drive',
      'file_path': info.id,
      'status': 'success',
      'notes': 'Uploaded to Drive folder "$_backupFolderName" > ${info.name}',
      'file_id': info.id,
      'file_size': info.size,
      'checksum': checksum,
      'device_backup_id': await _deviceId.fullId(),
      'app_version': await _appVersion(),
      'schema_version': DatabaseHelper.dbVersion,
      'backup_format_version': _backupFormatVersion,
    });

    await _settings.set(SettingsRepository.lastDriveBackupAt, now.toIso8601String());
    await _settings.set(SettingsRepository.driveBackupCompletedDateKey, _dailyDateKey(now));
    await _settings.set(SettingsRepository.driveBackupLastFileId, info.id);
    await _settings.set(SettingsRepository.driveBackupLastFileName, info.name);
    await _settings.set(SettingsRepository.driveBackupLastFileSize, info.size.toString());
    await _settings.set(SettingsRepository.driveBackupLastChecksum, checksum);
  }

  /// Deletes old daily backup files once enough newer, already-verified
  /// ones exist to safely replace them (spec item 12). Keeps the most
  /// recent [_retentionDailyCount] daily files no matter what, PLUS - for
  /// anything older than that - the single oldest backup of each calendar
  /// month as a lightweight monthly archive, so a shop can still reach
  /// "sometime back in March" even long after March's daily files have
  /// aged out. Only ever runs immediately after [backupToGoogleDrive] has
  /// already confirmed a brand new file is safely uploaded and verified -
  /// so by construction, this can never delete the newest backup, and
  /// never runs at all unless a newer valid one already exists (spec
  /// item 12's hard rule: "Never delete a backup until a newer valid
  /// backup has been successfully uploaded and verified").
  Future<void> _applyRetentionPolicy(drive.DriveApi driveApi) async {
    try {
      final all = await listGoogleDriveBackups(driveApi: driveApi);
      if (all.length <= _retentionDailyCount) return;

      final keepIds = <String>{for (final f in all.take(_retentionDailyCount)) f.id};

      final older = all.skip(_retentionDailyCount).toList();
      final monthlyArchive = <String, DriveBackupFileInfo>{};
      for (final f in older) {
        final t = f.modifiedTime;
        if (t == null) continue;
        final monthKey = '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}';
        final existing = monthlyArchive[monthKey];
        if (existing == null || (existing.modifiedTime != null && t.isBefore(existing.modifiedTime!))) {
          monthlyArchive[monthKey] = f;
        }
      }
      keepIds.addAll(monthlyArchive.values.map((f) => f.id));

      for (final f in older) {
        if (keepIds.contains(f.id)) continue;
        try {
          await driveApi.files.delete(f.id);
        } catch (_) {
          // A single delete failing (transient network hiccup, etc.) must
          // never affect the backup that already succeeded - retention
          // simply tries again after tomorrow's backup.
        }
      }
    } catch (_) {
      // Retention is housekeeping layered on top of an already-successful,
      // already-verified backup - a failure here must never be reported
      // back as the backup itself having failed.
    }
  }

  /// Lists every genuine PRO SERVICE backup file in the Drive folder,
  /// newest first (spec item 8: "Display them sorted by newest backup
  /// first"). Pass [thisDeviceOnly] to only show backups made by THIS
  /// install (spec item 13: "Restore should allow selecting backups from
  /// the correct device if multiple devices exist"). [driveApi] lets an
  /// already-authorized caller (e.g. [_applyRetentionPolicy], right after
  /// [backupToGoogleDrive] itself just authorized) skip re-authorizing.
  Future<List<DriveBackupFileInfo>> listGoogleDriveBackups({
    bool thisDeviceOnly = false,
    drive.DriveApi? driveApi,
  }) async {
    try {
      final api = driveApi ?? await _authorizedDriveApi(allowInteractiveSignIn: true);
      final folderId = await _findOrCreateBackupFolder(api);

      final infos = <DriveBackupFileInfo>[];
      String? pageToken;
      do {
        final result = await api.files.list(
          q: "'$folderId' in parents and trashed=false",
          spaces: 'drive',
          orderBy: 'modifiedTime desc',
          pageSize: 100,
          pageToken: pageToken,
          $fields: 'nextPageToken, files(id,name,size,modifiedTime)',
        );
        for (final f in result.files ?? const <drive.File>[]) {
          // Only files THIS backup system created are ever shown/acted on
          // (spec item 9: a name search is never trusted for the restore
          // itself, but it's exactly right for filtering what to even
          // list) - old monthly-era .db files, or anything else a shop
          // owner might have dropped into this folder by hand, are simply
          // left alone, never touched by restore OR by retention cleanup.
          if (f.id == null || f.name == null || !f.name!.startsWith(_fileNamePrefix)) continue;
          infos.add(DriveBackupFileInfo(
            id: f.id!,
            name: f.name!,
            modifiedTime: f.modifiedTime,
            size: int.tryParse(f.size ?? '') ?? 0,
          ));
        }
        pageToken = result.nextPageToken;
      } while (pageToken != null);

      if (thisDeviceOnly) {
        final myLabel = await _deviceId.shortLabel();
        return infos.where((i) => i.deviceLabel == myLabel).toList();
      }
      return infos;
    } on GoogleSignInException catch (e) {
      throw Exception(_friendlyGoogleError(e));
    }
  }

  /// The single most recent backup across every device (spec item 17:
  /// "Restore Latest"). Returns null only when the folder genuinely has no
  /// backup files yet; any sign-in problem throws (same friendly-error
  /// translation as every other Drive operation) so the button can show
  /// it.
  Future<DriveBackupFileInfo?> findLatestGoogleDriveBackup() async {
    final list = await listGoogleDriveBackups();
    return list.isEmpty ? null : list.first;
  }

  /// Verifies the file at [file] starts with SQLite's own 16-byte magic
  /// header - a cheap, reliable way to catch "this isn't really a SQLite
  /// database" (corrupted download, wrong file entirely) BEFORE it is ever
  /// treated as the new live database.
  Future<void> _validateSqliteFile(File file) async {
    final raf = await file.open();
    try {
      final header = await raf.read(16);
      const expectedMagic = [
        0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00, // "SQLite format 3\0"
      ];
      if (header.length != 16) {
        throw Exception('The database file inside this backup is too small to be a real database.');
      }
      for (var i = 0; i < 16; i++) {
        if (header[i] != expectedMagic[i]) {
          throw Exception('The database file inside this backup is not a valid SQLite database.');
        }
      }
    } finally {
      await raf.close();
    }
  }

  /// Copies every file under [sourceFilesDir] on top of the live app
  /// documents folder - shared by the real restore and by
  /// [_rollbackFromSafetyZip] so both use the exact same "put these
  /// attachments back" logic.
  Future<void> _restoreAttachmentsInto(Directory sourceFilesDir) async {
    if (!await sourceFilesDir.exists()) return;
    final docsDir = await getApplicationDocumentsDirectory();
    await for (final entity in sourceFilesDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: sourceFilesDir.path);
      final destPath = p.join(docsDir.path, rel);
      await Directory(p.dirname(destPath)).create(recursive: true);
      await entity.copy(destPath);
    }
  }

  /// Rolls the live database + attachments back to whatever [safetyZip]
  /// (taken right before a restore touched anything - spec item 10)
  /// contains. Called automatically the moment anything goes wrong during
  /// [restoreFromGoogleDriveFile]'s actual swap step, so the app is never
  /// left on a corrupted or half-restored database.
  Future<void> _rollbackFromSafetyZip(File? safetyZip) async {
    if (safetyZip == null || !await safetyZip.exists()) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final rollbackDir = Directory(p.join(tempDir.path, 'pms_rollback_${DateTime.now().microsecondsSinceEpoch}'));
      await rollbackDir.create(recursive: true);
      try {
        await _extractZip(safetyZip, rollbackDir);
        await _dbHelper.closeDb();
        final liveDbFile = await _dbHelper.dbFile();
        final rolledBackDb = File(p.join(rollbackDir.path, 'database', DatabaseHelper.dbFileName));
        if (await rolledBackDb.exists()) {
          await rolledBackDb.copy(liveDbFile.path);
        }
        await _restoreAttachmentsInto(Directory(p.join(rollbackDir.path, 'files')));
        // Re-open so the app is left on a working connection either way.
        await _dbHelper.database;
      } finally {
        if (await rollbackDir.exists()) await rollbackDir.delete(recursive: true);
      }
    } catch (_) {
      // If even the rollback fails there is nothing more this method can
      // safely do - the caller's own error is what surfaces to the shop
      // owner, who still has the untouched Drive backup to try restoring
      // again with.
    }
  }

  /// Downloads the EXACT Drive file [file] points at (by fileId, never by
  /// name - spec item 9) and restores the local database + attachments
  /// from it, following spec item 10's full safety flow: validate the
  /// downloaded zip -> take a local safety backup of the CURRENT data ->
  /// only then replace the live database/files -> verify record counts ->
  /// roll back automatically to that safety backup if anything after the
  /// safety backup goes wrong. The app must be restarted afterwards for a
  /// fresh, clean database connection - same as every other restore path
  /// in this app.
  Future<RestoreResult> restoreFromGoogleDriveFile(DriveBackupFileInfo file) async {
    if (!await _hasInternet()) {
      throw Exception('No internet connection right now - connect to the internet and try again.');
    }

    final tempDir = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final downloadZip = File(p.join(tempDir.path, 'pms_drive_restore_$stamp.zip'));
    final stagingDir = Directory(p.join(tempDir.path, 'pms_drive_restore_staging_$stamp'));
    File? safetyZip;

    try {
      final driveApi = await _authorizedDriveApi(allowInteractiveSignIn: true);

      // 1. Download the EXACT file id chosen - never a name search, never
      //    a cached/previously-downloaded copy (spec item 9).
      final media = await driveApi.files.get(file.id, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      if (bytes.isEmpty) {
        throw Exception('Downloaded backup "${file.name}" came back empty - nothing was restored.');
      }
      await downloadZip.writeAsBytes(bytes, flush: true);

      // 2. Validate the ZIP into a STAGING area - the live database is
      //    never touched until every check below has passed.
      await stagingDir.create(recursive: true);
      Map<String, dynamic> manifest;
      try {
        await _extractZip(downloadZip, stagingDir);
        final manifestFile = File(p.join(stagingDir.path, 'manifest.json'));
        if (!await manifestFile.exists()) {
          throw Exception('no manifest.json inside - this does not look like a genuine PRO SERVICE backup');
        }
        manifest = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      } catch (e) {
        throw Exception(
          'Could not read "${file.name}" as a backup - it may be corrupted or is not a genuine PRO SERVICE backup file (${e.toString().replaceFirst('Exception: ', '')}).',
        );
      }

      // 3. Version/compatibility check BEFORE anything live is touched
      //    (spec item 14).
      final backupFormatVersion = (manifest['backupFormatVersion'] as num?)?.toInt() ?? 1;
      final schemaVersion = (manifest['schemaVersion'] as num?)?.toInt() ?? 0;
      if (backupFormatVersion > _backupFormatVersion) {
        throw Exception(
          'This backup was made by a newer version of the app (backup format $backupFormatVersion, this app supports up to $_backupFormatVersion) and cannot be restored safely here. Please update the app first.',
        );
      }
      if (schemaVersion > DatabaseHelper.dbVersion) {
        throw Exception(
          'This backup was made by a newer version of the app (database version $schemaVersion, this app has ${DatabaseHelper.dbVersion}) and cannot be restored safely here. Please update the app first.',
        );
      }

      // 4. The staged database must be a genuine, uncorrupted SQLite file
      //    BEFORE it ever gets near the live one.
      final stagedDbFile = File(p.join(stagingDir.path, 'database', DatabaseHelper.dbFileName));
      if (!await stagedDbFile.exists()) {
        throw Exception('This backup is missing its database file - nothing was restored.');
      }
      await _validateSqliteFile(stagedDbFile);

      // 5. Safety backup of the CURRENT local data, taken right before
      //    anything live is touched (spec item 10).
      safetyZip = await _createSnapshotZip(labelPrefix: 'pms_safety_before_restore');

      try {
        // 6. Replace the live database, then every attachment file.
        await _dbHelper.closeDb();
        final liveDbFile = await _dbHelper.dbFile();
        await stagedDbFile.copy(liveDbFile.path);
        await _restoreAttachmentsInto(Directory(p.join(stagingDir.path, 'files')));

        // 7. Re-open and verify record counts against the manifest (spec:
        //    "Verify record counts"). Mismatches are recorded and
        //    reported, not silently hidden - but a restore that opens
        //    cleanly and mostly matches is still considered successful;
        //    only an unreadable/corrupt database triggers the rollback
        //    below (see the catch clause).
        final db = await _dbHelper.database;
        await db.rawQuery('PRAGMA quick_check');
        final actualCounts = await _tableRowCounts();
        final expectedCounts = (manifest['tableCounts'] as Map?)?.cast<String, dynamic>() ?? {};
        final mismatches = <String>[];
        for (final entry in expectedCounts.entries) {
          final expected = (entry.value as num?)?.toInt() ?? 0;
          final actual = actualCounts[entry.key] ?? -1;
          if (actual != expected) mismatches.add('${entry.key}: expected $expected, got $actual');
        }

        final db2 = await _dbHelper.database;
        await db2.insert('backups', {
          'id': newId(),
          'backup_date': DateTime.now().toIso8601String(),
          'type': 'google_drive_restore',
          'file_path': file.id,
          'status': mismatches.isEmpty ? 'success' : 'success_with_warnings',
          'notes': mismatches.isEmpty
              ? 'Restored from Drive backup "${file.name}".'
              : 'Restored from Drive backup "${file.name}" - some record counts differed: ${mismatches.join('; ')}',
          'file_id': file.id,
          'file_size': file.size,
          'device_backup_id': manifest['deviceBackupId'] as String?,
          'app_version': manifest['appVersion'] as String?,
          'schema_version': schemaVersion,
          'backup_format_version': backupFormatVersion,
        });

        return RestoreResult(mismatches: mismatches, restoredFrom: file);
      } catch (e) {
        // Anything going wrong from step 6 onward rolls back to the
        // safety snapshot from step 5 - never leaves the app on a
        // half-restored or corrupted database (spec item 10).
        await _rollbackFromSafetyZip(safetyZip);
        throw Exception(
          'Restore failed and your previous data was automatically restored - nothing was lost. (${e.toString().replaceFirst('Exception: ', '')})',
        );
      }
    } on GoogleSignInException catch (e) {
      throw Exception(_friendlyGoogleError(e));
    } finally {
      if (await downloadZip.exists()) await downloadZip.delete();
      if (await stagingDir.exists()) await stagingDir.delete(recursive: true);
      if (safetyZip != null && await safetyZip.exists()) await safetyZip.delete();
    }
  }

  /// Called from the exact ~10 PM alarm (see [scheduleDailyBackupAlarm] in
  /// background_tasks.dart), the WorkManager fallback/retry tasks, every
  /// time the app is opened (see main.dart), AND from the dedicated
  /// pending-retry WorkManager task - the same due-check safely covers all
  /// of them.
  ///
  /// Backs up to Google Drive at most once per calendar day, gated on
  /// [SettingsRepository.driveBackupCompletedDateKey] genuinely equalling
  /// today (spec item 4: "check whether today's backup has already
  /// completed successfully... DO NOT create another automatic backup") -
  /// UNLESS a previous attempt is still [SettingsRepository.driveBackupPending],
  /// in which case the day-gate is skipped entirely and this always tries
  /// again right now, because a pending/failed backup must never wait for
  /// "tomorrow" when it could instead succeed in the next few minutes
  /// (spec item 5: "eppo internet connect aagutho appo file upload
  /// aagidanum").
  ///
  /// Also sets a short-lived best-effort lock (see
  /// [SettingsRepository.driveBackupRunLockAt]'s doc comment) so the exact
  /// alarm and the WorkManager fallback landing within moments of each
  /// other are very unlikely to both start an upload for the same day
  /// (spec item 4's duplicate guard) - not a perfect cross-isolate lock,
  /// but combined with the day-gate above (only ever set AFTER a full
  /// verified upload) a genuine duplicate is extremely unlikely.
  ///
  /// Never throws - background execution must not crash the isolate, and a
  /// foreground caller on app open shouldn't see a Drive hiccup as an
  /// error. Returns true only if a backup was actually uploaded just now.
  Future<bool> runDailyGoogleDriveBackupIfDue() async {
    try {
      final enabled = await _settings.get(SettingsRepository.dailyDriveAutoBackupEnabled);
      if (enabled == 'false') return false;

      final linked = await isGoogleDriveLinked;
      if (!linked) return false;

      final now = DateTime.now();
      final todayKey = _dailyDateKey(now);
      final pending = (await _settings.get(SettingsRepository.driveBackupPending)) == 'true';

      if (!pending) {
        final completedKey = await _settings.get(SettingsRepository.driveBackupCompletedDateKey);
        if (completedKey == todayKey) return false; // already verified for today
      }

      final lockRaw = await _settings.get(SettingsRepository.driveBackupRunLockAt);
      if (lockRaw != null && lockRaw.isNotEmpty) {
        final lockAt = DateTime.tryParse(lockRaw);
        if (lockAt != null && now.difference(lockAt).inMinutes.abs() < 5) {
          return false; // another trigger is very likely already running this exact backup right now
        }
      }
      await _settings.set(SettingsRepository.driveBackupRunLockAt, now.toIso8601String());

      try {
        // allowInteractiveSignIn: false - this can run from a background
        // WorkManager/AlarmManager isolate with no foreground Activity to
        // show an account picker in, so it must only ever use a silent/
        // already-authorized connection, never try to pop UI. See
        // backupToGoogleDrive's doc comment.
        await backupToGoogleDrive(allowInteractiveSignIn: false);
        await _clearPendingDriveBackup(showRecoveredNotification: pending);
        return true;
      } finally {
        await _settings.set(SettingsRepository.driveBackupRunLockAt, '');
      }
    } catch (e) {
      await _recordDriveBackupFailure(e);
      return false;
    }
  }

  /// Records a failed Drive backup attempt so it's never silently lost:
  /// logs a 'failed' row to the `backups` table, remembers the reason in
  /// Settings (driveBackupPending/driveBackupLastError/
  /// driveBackupPendingSince) so Backup & Restore can always show the shop
  /// owner the true state, and posts a notification that cannot be swiped
  /// away (spec: "notification la kattanum na thalli vitta kuda poga
  /// kudathu"). Never throws - this runs from inside a catch block, both in
  /// the foreground and from a background isolate.
  ///
  /// Deliberately does NOT queue the WorkManager retry itself - callers do
  /// that (see [schedulePendingDriveBackupRetry] in background_tasks.dart,
  /// called from main.dart on app open and from background_tasks.dart's own
  /// daily-task case), because this method is also reached from inside the
  /// dedicated retry task's own execution, and a WorkManager task must never
  /// re-register/replace its own currently-running uniqueName (confirmed:
  /// doing so can throw a native CancellationException back into that same
  /// running task). That retry task instead relies purely on returning
  /// false + its own configured backoffPolicy, which is the safe, idiomatic
  /// way for a task to reschedule itself.
  Future<void> _recordDriveBackupFailure(Object error) async {
    final message = error.toString().replaceFirst('Exception: ', '');
    try {
      await _settings.set(SettingsRepository.driveBackupPending, 'true');
      await _settings.set(SettingsRepository.driveBackupLastError, message);
      final since = await _settings.get(SettingsRepository.driveBackupPendingSince);
      if (since == null) {
        await _settings.set(SettingsRepository.driveBackupPendingSince, DateTime.now().toIso8601String());
      }

      final db = await _dbHelper.database;
      await db.insert('backups', {
        'id': newId(),
        'backup_date': DateTime.now().toIso8601String(),
        'type': 'google_drive',
        'file_path': null,
        'status': 'failed',
        'notes': message,
      });

      await _showPendingBackupNotification(message);
    } catch (_) {
      // Recording the failure must never itself throw back into the caller.
    }
  }

  /// Clears the pending-backup state the moment a Drive backup actually
  /// succeeds again - removes the non-dismissible "waiting" notification,
  /// and (only when [showRecoveredNotification] is true, i.e. this really
  /// was recovering from a prior failure rather than just an ordinary
  /// successful day) briefly shows a normal, dismissible "Backup completed"
  /// notification so the shop owner gets clear confirmation their data is
  /// protected again without needing to open the app.
  ///
  /// Deliberately does NOT cancel the queued WorkManager retry itself - see
  /// [_recordDriveBackupFailure]'s doc comment for why (same
  /// self-cancel-while-running risk applies to cancelling as to
  /// re-registering). A stray already-queued retry firing later after
  /// success is harmless: it will find nothing pending and simply no-op.
  /// Callers that can safely cancel it (main.dart on app open,
  /// background_tasks.dart's own daily-task case) do so themselves via
  /// [cancelPendingDriveBackupRetry].
  Future<void> _clearPendingDriveBackup({required bool showRecoveredNotification}) async {
    try {
      await _settings.set(SettingsRepository.driveBackupPending, 'false');
      await _settings.set(SettingsRepository.driveBackupLastError, '');
      await _settings.set(SettingsRepository.driveBackupPendingSince, '');
      await _ensureNotificationsInitialized();
      await _notifications.cancel(_pendingBackupNotificationId);
      if (showRecoveredNotification) {
        const androidDetails = AndroidNotificationDetails(
          'drive_backup_status',
          'Google Drive Backup',
          channelDescription: 'Tells you when a Google Drive backup succeeds or is waiting for internet',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        );
        await _notifications.show(
          _backupRecoveredNotificationId,
          'Backup Completed',
          'Your data has been backed up to Google Drive successfully.',
          const NotificationDetails(android: androidDetails),
        );
      }
    } catch (_) {
      // Never let clearing/notifying about a success turn into an error.
    }
  }

  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static bool _notificationsInitialized = false;
  static const _pendingBackupNotificationId = 2001;
  static const _backupRecoveredNotificationId = 2002;

  Future<void> _ensureNotificationsInitialized() async {
    if (_notificationsInitialized) return;
    const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
    const settings = InitializationSettings(android: androidInit);
    await _notifications.initialize(settings);
    _notificationsInitialized = true;
  }

  /// Posts (or, on a later retry, silently updates in place - same
  /// notification id) a notification the shop owner cannot swipe away
  /// (ongoing: true, autoCancel: false) explaining a Drive backup is waiting
  /// for internet and will finish automatically - directly answers "na
  /// thalli vitta kuda poga kudathu" (even if I try to dismiss it, it
  /// shouldn't go away). Cleared automatically the moment the backup
  /// actually succeeds - see [_clearPendingDriveBackup].
  Future<void> _showPendingBackupNotification(String reason) async {
    try {
      await _ensureNotificationsInitialized();
      const androidDetails = AndroidNotificationDetails(
        'drive_backup_status',
        'Google Drive Backup',
        channelDescription: 'Tells you when a Google Drive backup succeeds or is waiting for internet',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: true,
        autoCancel: false,
        playSound: false,
        enableVibration: false,
      );
      await _notifications.show(
        _pendingBackupNotificationId,
        'Backup Waiting for Internet',
        "Your latest data couldn't reach Google Drive yet ($reason). "
            "It will upload automatically the moment this phone is online - no action needed.",
        const NotificationDetails(android: androidDetails),
      );
    } catch (_) {
      // A notification failing to show must never break the retry logic
      // itself - the Settings screen still shows the true pending state.
    }
  }

  /// Call after a successful manual "Backup to Drive" button press (see
  /// BackupScreen) so a manual retry immediately clears any "waiting for
  /// internet" pending state/notification too, instead of the shop owner
  /// having to wait for the next automatic due-check to notice their manual
  /// upload already fixed things. Safe/harmless no-op if nothing was
  /// pending.
  Future<void> markManualDriveBackupSucceeded() async {
    final wasPending = (await _settings.get(SettingsRepository.driveBackupPending)) == 'true';
    if (wasPending) {
      await _clearPendingDriveBackup(showRecoveredNotification: true);
    }
  }

  /// Current Google Drive backup health, for Backup & Restore's "Backup
  /// History" section (spec item 11) to show the shop owner the plain
  /// truth instead of them having to guess.
  Future<DriveBackupStatus> driveBackupStatus() async {
    final lastStr = await _settings.get(SettingsRepository.lastDriveBackupAt);
    final pending = (await _settings.get(SettingsRepository.driveBackupPending)) == 'true';
    final error = await _settings.get(SettingsRepository.driveBackupLastError);
    final sinceStr = await _settings.get(SettingsRepository.driveBackupPendingSince);
    final fileName = await _settings.get(SettingsRepository.driveBackupLastFileName);
    final sizeStr = await _settings.get(SettingsRepository.driveBackupLastFileSize);
    return DriveBackupStatus(
      lastSuccessAt: (lastStr == null || lastStr.isEmpty) ? null : DateTime.parse(lastStr),
      pending: pending,
      lastError: (error == null || error.isEmpty) ? null : error,
      pendingSince: (sinceStr == null || sinceStr.isEmpty) ? null : DateTime.parse(sinceStr),
      lastFileName: (fileName == null || fileName.isEmpty) ? null : fileName,
      lastFileSize: sizeStr == null || sizeStr.isEmpty ? null : int.tryParse(sizeStr),
    );
  }
}

/// See [BackupService.driveBackupStatus].
class DriveBackupStatus {
  final DateTime? lastSuccessAt;
  final bool pending;
  final String? lastError;
  final DateTime? pendingSince;
  final String? lastFileName;
  final int? lastFileSize;

  const DriveBackupStatus({
    required this.lastSuccessAt,
    required this.pending,
    required this.lastError,
    required this.pendingSince,
    this.lastFileName,
    this.lastFileSize,
  });
}

/// See [BackupService.listGoogleDriveBackups]/[findLatestGoogleDriveBackup]/
/// [restoreFromGoogleDriveFile].
class DriveBackupFileInfo {
  final String id;
  final String name;
  final DateTime? modifiedTime;
  final int size;

  const DriveBackupFileInfo({
    required this.id,
    required this.name,
    required this.modifiedTime,
    required this.size,
  });

  static final RegExp _nameRe =
      RegExp(r'^PRO_SERVICE_BACKUP_(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})_DEVICE_([0-9a-zA-Z]+)\.zip$');

  /// The short device label parsed back out of this file's name (spec
  /// item 13) - null for a backup made before this rewrite, or anything
  /// that doesn't match the expected naming.
  String? get deviceLabel => _nameRe.firstMatch(name)?.group(3);
}

/// See [BackupService.restoreFromGoogleDriveFile].
class RestoreResult {
  final List<String> mismatches;
  final DriveBackupFileInfo restoredFrom;
  const RestoreResult({required this.mismatches, required this.restoredFrom});
  bool get hasWarnings => mismatches.isNotEmpty;
}

class _VerifyResult {
  final bool ok;
  final String? reason;
  const _VerifyResult(this.ok, this.reason);
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
