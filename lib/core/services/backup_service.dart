import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../db/database_helper.dart';
import '../repositories/settings_repository.dart';
import '../utils/id_gen.dart';

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
/// kattanum na thalli vitta kuda poga kudathu"). The old "weekly automatic
/// LOCAL backup" feature has been removed entirely (spec: "weekly automatic
/// backup remove pannittu daily automatic back up create pannu google
/// drive ku") - daily Google Drive backup (with the retry-until-success
/// behaviour above) is now the one and only automatic backup story; manual
/// local "Backup Now" still exists purely as an extra, on-demand safety copy
/// kept on the phone itself, and is clearly labelled as NOT reaching Google
/// Drive on its own (see BackupScreen) - confusing the two was very likely
/// what caused the incident, since "Backup Now" was mistaken for something
/// that also updated the Drive copy.
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
  /// Unlike [createManualBackup], this does NOT
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
        // Settings first. Goes through the same retrying
        // _authenticateAccount() as the "Connect Google Drive"/"Change
        // Google Account" buttons, so a stuck "[16] Account reauth failed"
        // hit from the "Backup to Drive" button gets the same automatic
        // recovery instead of failing on the first try.
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

  /// Called from the WorkManager background task (once daily, aimed at ~10
  /// PM - see [scheduleDailyGoogleDriveBackup] in background_tasks.dart),
  /// every time the app is opened (see main.dart), AND from the dedicated
  /// pending-retry WorkManager task queued by [_recordDriveBackupFailure]
  /// (see [schedulePendingDriveBackupRetry] in background_tasks.dart) - the
  /// same due-check safely covers all three callers.
  ///
  /// Backs up to Google Drive at most once per calendar day UNLESS a
  /// previous attempt is still [SettingsRepository.driveBackupPending] -
  /// in that case the same-day gate is skipped entirely and this always
  /// tries again right now, because a pending/failed backup must never wait
  /// for "tomorrow" when it could instead succeed in the next few minutes
  /// (spec: "internet ellana file load aagi waite pannanum eppo inter net
  /// connect aagutho appo file upload aagidanum").
  ///
  /// DATA-LOSS INCIDENT FIX: this used to swallow every failure with a bare
  /// `catch (_) {}` and simply wait for the next calendar day - completely
  /// invisible to the shop owner, which is very likely what let a real
  /// backup gap go unnoticed until data was actually lost. Every failure now
  /// goes through [_recordDriveBackupFailure], which logs it, remembers it
  /// in Settings so Backup & Restore can always show it, and shows a
  /// notification that cannot be swiped away. Whichever caller invoked this
  /// method then queues a network-constrained WorkManager retry (see
  /// [schedulePendingDriveBackupRetry] in background_tasks.dart) so this
  /// same method runs again automatically the moment the phone has internet
  /// - see that function's and [_recordDriveBackupFailure]'s doc comments
  /// for exactly why the queuing itself happens at the call site rather
  /// than inside this method.
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

      final pending = (await _settings.get(SettingsRepository.driveBackupPending)) == 'true';
      if (!pending) {
        final now = DateTime.now();
        final lastStr = await _settings.get(SettingsRepository.lastDriveBackupAt);
        if (lastStr != null) {
          final last = DateTime.parse(lastStr);
          final sameDay = last.year == now.year && last.month == now.month && last.day == now.day;
          if (sameDay) return false;
        }
      }

      // allowInteractiveSignIn: false - this can run from a background
      // WorkManager isolate with no foreground Activity to show an account
      // picker in, so it must only ever use a silent/already-authorized
      // connection, never try to pop UI. See backupToGoogleDrive's doc
      // comment.
      await backupToGoogleDrive(allowInteractiveSignIn: false);
      await _settings.set(SettingsRepository.lastDriveBackupAt, DateTime.now().toIso8601String());
      await _clearPendingDriveBackup(showRecoveredNotification: pending);
      return true;
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
    await _settings.set(SettingsRepository.lastDriveBackupAt, DateTime.now().toIso8601String());
    if (wasPending) {
      await _clearPendingDriveBackup(showRecoveredNotification: true);
    }
  }

  /// Current Google Drive backup health, for Backup & Restore to show the
  /// shop owner the plain truth instead of them having to guess (spec item
  /// 5: a correct, transparent workflow designed end-to-end).
  Future<DriveBackupStatus> driveBackupStatus() async {
    final lastStr = await _settings.get(SettingsRepository.lastDriveBackupAt);
    final pending = (await _settings.get(SettingsRepository.driveBackupPending)) == 'true';
    final error = await _settings.get(SettingsRepository.driveBackupLastError);
    final sinceStr = await _settings.get(SettingsRepository.driveBackupPendingSince);
    return DriveBackupStatus(
      lastSuccessAt: (lastStr == null || lastStr.isEmpty) ? null : DateTime.parse(lastStr),
      pending: pending,
      lastError: (error == null || error.isEmpty) ? null : error,
      pendingSince: (sinceStr == null || sinceStr.isEmpty) ? null : DateTime.parse(sinceStr),
    );
  }
}

/// See [BackupService.driveBackupStatus].
class DriveBackupStatus {
  final DateTime? lastSuccessAt;
  final bool pending;
  final String? lastError;
  final DateTime? pendingSince;

  const DriveBackupStatus({
    required this.lastSuccessAt,
    required this.pending,
    required this.lastError,
    required this.pendingSince,
  });
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
