import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/services/backup_service.dart';
import '../../core/services/background_tasks.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/section_card.dart';
import 'google_drive_restore_screen.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> with WidgetsBindingObserver {
  final _backupService = BackupService();
  List<File> _backups = [];
  String _backupDirPath = '';
  bool _loading = true;
  bool _driveLinked = false;
  bool _working = false;
  DriveBackupStatus? _driveStatus;

  // Total count of Drive backup files currently available (spec item 11:
  // "Number of available Drive backups") - fetched separately/lazily since
  // it needs its own Drive call, and must never block the rest of the
  // screen from showing while it's in flight.
  int? _driveBackupCount;

  // True until proven otherwise (hasExactAlarmPermission() defaults to
  // true on any check failure/non-Android platform) so this never flashes
  // a false warning while the very first check is still in flight - same
  // pattern as DailyOrderScreen's own exact-alarm check.
  bool _exactAlarmOk = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _recheckExactAlarm();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catches the shop owner coming straight back from the "Allow Exact
    // Alarm Timing" system Settings screen (see _requestExactAlarm below)
    // without having to manually reopen this screen.
    if (state == AppLifecycleState.resumed) _recheckExactAlarm();
  }

  Future<void> _recheckExactAlarm() async {
    final ok = await hasExactAlarmPermission();
    if (mounted) setState(() => _exactAlarmOk = ok);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final backups = await _backupService.listLocalBackups();
    final linked = await _backupService.isGoogleDriveLinked;
    final dirPath = await _backupService.backupDirPath();
    final driveStatus = await _backupService.driveBackupStatus();
    setState(() {
      _backups = backups;
      _driveLinked = linked;
      _backupDirPath = dirPath;
      _driveStatus = driveStatus;
      _loading = false;
    });
    if (linked) _refreshDriveBackupCount();
  }

  /// Fetched separately from the rest of [_load] since it needs its own
  /// Drive call - never blocks the screen from showing while it's still in
  /// flight, and any failure here (offline, etc.) just leaves the count
  /// blank rather than showing an error over the whole screen.
  Future<void> _refreshDriveBackupCount() async {
    try {
      final list = await _backupService.listGoogleDriveBackups();
      if (mounted) setState(() => _driveBackupCount = list.length);
    } catch (_) {
      // Leave it blank - Backup History still shows everything it already
      // knows locally.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                SectionCard(title: 'Manual Backup (This Phone Only)', icon: Icons.save_rounded, children: [
                  Text(
                    'Creates an extra copy of your entire database, saved on THIS phone right now (in the app\'s own storage, and optionally also to a folder you choose). '
                    'This does NOT upload to Google Drive by itself - it is just an extra local copy, not a replacement for the automatic Google Drive backup below. '
                    'If this phone is lost, damaged, or uninstalled, a purely local copy cannot help you - only a Google Drive backup can.',
                    style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12.5),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    ElevatedButton.icon(
                      onPressed: _working ? null : _createBackup,
                      icon: const Icon(Icons.backup_rounded),
                      label: const Text('Backup Now'),
                    ),
                    // File-picker based restore, separate from the
                    // list-based "Restore" button on each item under
                    // "Local Backups" below - this one lets the shop pick
                    // a .db backup file from anywhere on the phone (e.g.
                    // one they were sent on WhatsApp, or saved from Google
                    // Drive/a file manager), not just the backups this
                    // install itself created (spec: "restore button click
                    // panna file choose panra maadhiri vaikkanum").
                    OutlinedButton.icon(
                      onPressed: _working ? null : _restoreFromFile,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('Restore from File'),
                    ),
                  ]),
                  if (_backupDirPath.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Manual backups are saved to: $_backupDirPath',
                        style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 11.5),
                      ),
                    ),
                ]),
                SectionCard(title: 'Google Drive Backup - Automatic, Every Day', icon: Icons.cloud_rounded, children: [
                  Text(_driveLinked ? 'Linked to Google Drive.' : 'Not linked yet.', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    'Requires internet + your own Google Cloud OAuth client (see README "Google Drive Backup Setup"). Everything else in this app works fully offline without this.',
                    style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  if (_driveLinked) ...[
                    Text(
                      "Once connected, this is the ONLY automatic backup this app takes, and it protects your data even if this phone is lost, damaged, or the app is uninstalled and reinstalled - that is exactly what a purely local backup cannot do.\n\n"
                      "A complete new backup file - your entire database plus any photos - is created and uploaded every day, timed to fire exactly around 10 PM using the phone's own alarm clock (not just a background task, which Android can delay). Nothing is ever overwritten: every day gets its own independent, verified snapshot, so you can restore from any single day separately.\n\n"
                      "If there is no internet right at 10 PM (or the phone is off), the backup simply waits - it does NOT wait for tomorrow. The moment this phone gets internet again, it uploads automatically on its own, with a notification staying up the whole time it's waiting so you always know. Opening the app also always double-checks and retries immediately if anything is still pending. \"Backup Successful\" is only ever shown after the file has been re-checked on Google Drive itself, never just because an upload started.\n\n"
                      "Saved into a normal, visible \"Professional Mobiles Backups\" folder in your own Google Drive - open the Drive app any time to see every day's file. The last 30 daily backups are always kept, plus one older file per month further back, so Drive storage doesn't grow forever.",
                      style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    _buildDriveStatusBanner(context),
                    if (!_exactAlarmOk) ...[
                      const SizedBox(height: 10),
                      _buildExactAlarmWarning(context),
                    ],
                  ],
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (!_driveLinked)
                      ElevatedButton.icon(onPressed: _working ? null : _linkDrive, icon: const Icon(Icons.login_rounded), label: const Text('Connect Google Drive')),
                    if (_driveLinked) ...[
                      ElevatedButton.icon(onPressed: _working ? null : _backupToDrive, icon: const Icon(Icons.cloud_upload_rounded), label: const Text('Backup to Drive')),
                      OutlinedButton(onPressed: _working ? null : _unlinkDrive, child: const Text('Disconnect')),
                    ],
                    // "Restore Backup" for Google Drive (spec: "google driver
                    // backup la extra oru button create pannu athu restore
                    // backup nu name vai atha click panna earkanavey back up
                    // aana file automatically restore aakanum") - shown even
                    // when not yet linked, since tapping it in that state is
                    // exactly how the shop gets told to connect first (spec:
                    // "login pannalana intimation pannanum"). Opens the full
                    // Restore Screen (spec item 8) listing every daily backup
                    // rather than only ever silently grabbing the latest one.
                    OutlinedButton.icon(
                      onPressed: _working ? null : _openRestoreScreen,
                      icon: const Icon(Icons.cloud_download_rounded),
                      label: const Text('Restore Backup'),
                    ),
                  ]),
                  if (_driveLinked) ...[
                    const SizedBox(height: 8),
                    // Fixes a stuck "Account reauth failed" error without
                    // leaving the app - fully forgets this device's Google
                    // sign-in and reopens the account picker fresh, and also
                    // lets the shop switch to a different Google account on
                    // purpose.
                    OutlinedButton.icon(
                      onPressed: _working ? null : _reconnectDrive,
                      icon: const Icon(Icons.sync_rounded, size: 18),
                      label: const Text('Change Google Account / Reconnect'),
                    ),
                  ],
                ]),
                if (_driveLinked) SectionCard(title: 'Backup History', icon: Icons.history_rounded, children: [_buildBackupHistory(context)]),
                SectionCard(title: 'Local Backups (${_backups.length})', icon: Icons.folder_zip_rounded, children: [
                  if (_backupDirPath.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'These live inside the app\'s own private storage, so they will NOT show up if you browse your phone\'s Files app - that is normal on Android, not a bug. Use the Share button on any backup below to hand it to WhatsApp, Google Drive, email, or a file manager\'s own "Save a copy" action.\n\nApp storage path: $_backupDirPath',
                        style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 11.5),
                      ),
                    ),
                  if (_backups.isEmpty) Text('No backups yet.', style: TextStyle(color: AppColors.textSecondaryOf(context))),
                  ..._backups.map((f) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_rounded),
                        title: Text(p.basename(f.path), style: const TextStyle(fontSize: 12.5)),
                        subtitle: Text(formatDateTime(f.statSync().modified)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Share this backup file',
                              icon: const Icon(Icons.share_rounded, size: 20),
                              onPressed: _working ? null : () => _shareBackup(f),
                            ),
                            TextButton(onPressed: _working ? null : () => _restore(f), child: const Text('Restore')),
                          ],
                        ),
                      )),
                ]),
              ],
            ),
    );
  }

  /// Plain-truth status banner (spec item 5: a correct, transparent backup
  /// workflow, not a silent one) - shows exactly what BackupService itself
  /// knows: when the last Google Drive backup actually succeeded, and - if
  /// one is currently pending/failed - the reason and how long it's been
  /// waiting, so the shop owner never has to wonder whether their data is
  /// actually protected.
  Widget _buildDriveStatusBanner(BuildContext context) {
    final status = _driveStatus;
    if (status == null) return const SizedBox.shrink();

    if (status.pending) {
      final since = status.pendingSince;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 18),
            SizedBox(width: 6),
            Text('Backup waiting for internet', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.orange)),
          ]),
          const SizedBox(height: 6),
          Text(
            'Reason: ${status.lastError ?? "unknown"}${since != null ? '\nWaiting since: ${formatDateTime(since)}' : ''}\n'
            'This will upload automatically the moment this phone is online - no action needed, but you can also tap "Backup to Drive" below to try right now.',
            style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12),
          ),
        ]),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green),
      ),
      child: Row(children: [
        const Icon(Icons.cloud_done_rounded, color: Colors.green, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            status.lastSuccessAt != null
                ? 'Last successful backup: ${formatDateTime(status.lastSuccessAt!)}'
                : 'No successful Google Drive backup yet - tap "Backup to Drive" below to start.',
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.green),
          ),
        ),
      ]),
    );
  }

  /// Spec item 11's "Backup History": last successful backup's date/time,
  /// file name/size, current pending status, and how many Drive backups
  /// are available in total - everything Backup & Restore already knows
  /// locally (driveBackupStatus) plus the lazily-fetched Drive count from
  /// [_refreshDriveBackupCount], laid out as the plain "Last Backup /
  /// Status / Latest Backup Size" example the spec shows.
  Widget _buildBackupHistory(BuildContext context) {
    final status = _driveStatus;
    if (status == null) return const SizedBox.shrink();

    Widget row(String label, String value, {Color? valueColor}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(label, style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12.5)),
            ),
            Expanded(
              child: Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: valueColor)),
            ),
          ],
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      row('Last Backup:', status.lastSuccessAt != null ? formatDateTime(status.lastSuccessAt!) : 'Never'),
      row(
        'Status:',
        status.pending ? 'Pending - waiting for internet' : (status.lastSuccessAt != null ? 'Successfully backed up' : 'Not backed up yet'),
        valueColor: status.pending ? Colors.orange : (status.lastSuccessAt != null ? Colors.green : null),
      ),
      if (status.lastFileName != null) row('Latest Backup File:', status.lastFileName!),
      if (status.lastFileSize != null) row('Latest Backup Size:', formatFileSize(status.lastFileSize!)),
      row('Available Backups:', _driveBackupCount != null ? '$_driveBackupCount on Google Drive' : 'Checking...'),
    ]);
  }

  /// Nudges the shop owner to grant Android 12+'s "Alarms & reminders"
  /// permission when it's missing (spec item 4: "If exact alarm
  /// permission is required, guide the user to enable it") - without it,
  /// the exact ~10 PM trigger silently falls back to an inexact (possibly
  /// hours-late) alarm; the WorkManager fallback still gets that day's
  /// backup done regardless, so this is a warning to fix timing, not a
  /// "backup broken" error.
  Widget _buildExactAlarmWarning(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.alarm_off_rounded, color: Colors.orange, size: 18),
          SizedBox(width: 6),
          Expanded(child: Text('Exact 10 PM timing not allowed yet', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.orange))),
        ]),
        const SizedBox(height: 6),
        Text(
          'The daily backup will still happen (a fallback still runs it), but without this permission Android may delay it. Allow exact alarms for the most reliable ~10 PM timing.',
          style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await requestExactAlarmPermission();
            _recheckExactAlarm();
          },
          icon: const Icon(Icons.alarm_rounded, size: 18),
          label: const Text('Allow Exact Alarm Timing'),
        ),
      ]),
    );
  }

  /// Shows an error in a dialog (not just a snackbar) so a long "why this
  /// failed" message - e.g. the Google OAuth setup explanation - is fully
  /// readable instead of getting clipped at the bottom of the screen.
  void _showError(String title, Object error) {
    if (!mounted) return;
    final message = error.toString().replaceFirst('Exception: ', '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _createBackup() async {
    setState(() => _working = true);
    try {
      // Always takes the actual backup into the app's own private storage
      // first (that copy is what powers the "Local Backups" list and its
      // per-item Restore button below, and never depends on the shop
      // picking anywhere) - then, on every "Backup Now" tap, lets the shop
      // save a second, real copy anywhere they choose (spec: "backup now
      // button click panna file share option mattum than varuthu, local
      // file la save aagura option kattala, local file la save aaganum").
      //
      // PREVIOUSLY this used getDirectoryPath() + a plain File.copy() to
      // the chosen folder - but on Android's scoped storage, the folder
      // picker returns a SAF content:// URI, not a real filesystem path,
      // so File(...).copy() against it always threw and silently fell back
      // to the share sheet every single time. That's exactly why the shop
      // only ever saw "Share" and never a real local save. saveFile's
      // `bytes` parameter has file_picker perform the actual write itself
      // through SAF, so this now reliably lands as a genuine file at the
      // name/folder the shop picks - no share sheet detour needed.
      final file = await _backupService.createManualBackup();
      if (!mounted) return;

      final bytes = await file.readAsBytes();
      final savedUri = await FilePicker.saveFile(
        dialogTitle: 'Choose where to save this backup file',
        fileName: p.basename(file.path),
        bytes: bytes,
      );

      final message = savedUri == null
          // Shop cancelled the save dialog - still keep them informed
          // exactly where the (private-storage) copy landed, since it
          // wasn't lost, just not additionally saved elsewhere.
          ? 'Backup created - saved to ${file.path}'
          : 'Backup saved to your chosen location.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
        );
      }
    } catch (e) {
      _showError('Backup failed', e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
    _load();
  }

  /// "Restore from File" - opens Android's own file picker (not limited to
  /// this app's private storage) so the shop can restore from a backup
  /// .db file saved anywhere: Downloads, a Google Drive/WhatsApp download,
  /// an SD card, etc. Complements the per-item "Restore" button under
  /// "Local Backups" below, which only offers backups this exact app
  /// install already knows about.
  Future<void> _restoreFromFile() async {
    // file_picker 11+ refactored FilePicker to static methods (no more
    // `.platform` instance) and now defaults allowMultiple to true -
    // explicitly false here since exactly one file is expected below.
    // file_picker 12 also changed pickFiles() to return the picked files
    // list directly (List<PlatformFile>?) instead of the old
    // FilePickerResult wrapper object, so there is no `.files` getter
    // anymore - the result itself is the list, and an empty list (not
    // null) is what a user cancel now looks like.
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      dialogTitle: 'Choose a backup file to restore',
    );
    if (result == null || result.isEmpty || result.single.path == null) {
      return;
    }
    final file = File(result.single.path!);
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Backup?'),
        content: Text(
          'This will replace your current data with "${p.basename(file.path)}". Make sure this file is a genuine Professional Mobiles backup - restoring the wrong file can leave the app unable to open. The app must be restarted after restoring.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _working = true);
    try {
      await _backupService.restoreFrom(file);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restored. Please close and reopen the app.')));
      }
    } catch (e) {
      _showError('Restore failed', e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  // Previously this called signInToGoogleDrive() with no try/catch: an
  // unconfigured/mismatched Google OAuth client throws instead of
  // returning, so the button just sat on "working" forever with no error
  // shown - exactly the "click பண்ணா entha responsum illa" symptom. Now
  // every outcome (success / cancel / real error) always clears _working
  // and, on a real error, shows why.
  Future<void> _linkDrive() async {
    setState(() => _working = true);
    try {
      final ok = await _backupService.signInToGoogleDrive();
      if (ok) {
        // Arms the exact ~10 PM alarm (+ the WorkManager fallback,
        // already registered from app startup regardless) the moment
        // Drive backup actually has something to back up TO - see
        // background_tasks.dart's scheduleDailyBackupAlarm.
        await scheduleDailyBackupAlarm();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Google sign-in was cancelled')));
      }
    } catch (e) {
      _showError('Google Drive connection failed', e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
    _load();
  }

  /// "Change Google Account / Reconnect" - fully revokes whatever is
  /// currently linked and reopens the account picker fresh. Used both to
  /// deliberately switch accounts and as a manual escape hatch if a shop
  /// keeps hitting the "Account reauth failed" error even after the
  /// automatic one-time retry inside signInToGoogleDrive().
  Future<void> _reconnectDrive() async {
    setState(() => _working = true);
    try {
      final ok = await _backupService.reconnectGoogleDrive();
      if (mounted && !ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Google sign-in was cancelled')));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Google Drive reconnected')));
      }
    } catch (e) {
      _showError('Google Drive connection failed', e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
    _load();
  }

  /// Hands the backup .db file to Android's native share sheet - the shop
  /// picks WhatsApp, Google Drive, email, Bluetooth, or a file manager's
  /// own "Save a copy" action. This is the actual way to get a copy of a
  /// local backup out of the app, since the file itself lives in private
  /// app storage and never appears in the phone's Files app on its own.
  Future<void> _shareBackup(File file) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: 'Professional Mobiles backup - ${p.basename(file.path)}',
          files: [XFile(file.path)],
        ),
      );
    } catch (e) {
      _showError('Could not open the share sheet', e);
    }
  }

  Future<void> _unlinkDrive() async {
    setState(() => _working = true);
    try {
      await _backupService.signOutOfGoogleDrive();
      // Nothing left to back up automatically once Drive is disconnected -
      // stop the exact alarm (the WorkManager fallback task stays
      // registered but is a fast no-op once isGoogleDriveLinked is false,
      // see runDailyGoogleDriveBackupIfDue).
      await cancelDailyBackupAlarm();
    } catch (e) {
      _showError('Could not disconnect', e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
    _load();
  }

  Future<void> _backupToDrive() async {
    setState(() => _working = true);
    try {
      final info = await _backupService.backupToGoogleDrive();
      // Lets a manual retry immediately clear any "waiting for internet"
      // pending state/notification too, instead of only the next
      // automatic due-check noticing - see BackupService's doc comment.
      await _backupService.markManualDriveBackupSucceeded();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uploaded to Google Drive: ${info.name}')),
        );
      }
    } catch (e) {
      _showError('Google Drive backup failed', e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
    _load();
  }

  /// "Restore Backup" under Google Drive Backup (spec item 8: a full
  /// Restore Screen listing every daily backup, not just silently grabbing
  /// the latest one) - offers to connect first if Drive isn't linked yet
  /// (spec: "login pannalana intimation pannanum"), otherwise opens
  /// [GoogleDriveRestoreScreen].
  Future<void> _openRestoreScreen() async {
    if (!_driveLinked) {
      if (!mounted) return;
      final connect = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Not Connected to Google Drive'),
          content: const Text(
            'You are not logged in to Google Drive yet, so there is no backup to restore from here. Connect Google Drive first, then tap "Restore Backup" again.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Connect Google Drive')),
          ],
        ),
      );
      if (connect == true) await _linkDrive();
      return;
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const GoogleDriveRestoreScreen()));
    _load();
  }

  Future<void> _restore(File file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Backup?'),
        content: Text('This will replace your current data with the backup from ${formatDateTime(file.statSync().modified)}. The app must be restarted after restoring.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore')),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _working = true);
      try {
        await _backupService.restoreFrom(file);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restored. Please close and reopen the app.')));
        }
      } catch (e) {
        _showError('Restore failed', e);
      } finally {
        if (mounted) setState(() => _working = false);
      }
    }
  }
}
