import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/services/backup_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/section_card.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _backupService = BackupService();
  List<File> _backups = [];
  String _backupDirPath = '';
  bool _loading = true;
  bool _driveLinked = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final backups = await _backupService.listLocalBackups();
    final linked = await _backupService.isGoogleDriveLinked;
    final dirPath = await _backupService.backupDirPath();
    setState(() {
      _backups = backups;
      _driveLinked = linked;
      _backupDirPath = dirPath;
      _loading = false;
    });
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
                SectionCard(title: 'Manual Backup', icon: Icons.save_rounded, children: [
                  Text('Creates a local copy of your entire database right now.', style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12.5)),
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
                SectionCard(title: 'Weekly Automatic Backup', icon: Icons.auto_mode_rounded, children: [
                  Text(
                    'A local backup is taken automatically whenever the app is opened and more than 7 days have passed since the last one.',
                    style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12.5),
                  ),
                ]),
                SectionCard(title: 'Google Drive Backup (Optional)', icon: Icons.cloud_rounded, children: [
                  Text(_driveLinked ? 'Linked to Google Drive.' : 'Not linked yet.', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    'Requires internet + your own Google Cloud OAuth client (see README "Google Drive Backup Setup"). Everything else in this app works fully offline without this.',
                    style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  if (_driveLinked)
                    Text(
                      "Once connected, all your data (except photos) backs up to Google Drive automatically every day, aimed at around 10 PM - no need to tap anything, and no permission popups. Android doesn't guarantee the exact minute, so as a safety net this also runs the moment you open the app if that day's backup hasn't happened yet. If a day is missed (no internet, phone off, etc.), it's simply included in the next successful backup - nothing is lost.\n\nSaved into a normal, visible \"Professional Mobiles Backups\" folder in your own Google Drive - open the Drive app any time to see it. One file per month, always holding that month's latest complete data (today's data is automatically included with everything noted earlier that month), so you can open whichever month you need.",
                      style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12),
                    ),
                  const SizedBox(height: 10),
                  Row(children: [
                    if (!_driveLinked)
                      ElevatedButton.icon(onPressed: _working ? null : _linkDrive, icon: const Icon(Icons.login_rounded), label: const Text('Connect Google Drive')),
                    if (_driveLinked) ...[
                      ElevatedButton.icon(onPressed: _working ? null : _backupToDrive, icon: const Icon(Icons.cloud_upload_rounded), label: const Text('Backup to Drive')),
                      const SizedBox(width: 8),
                      OutlinedButton(onPressed: _working ? null : _unlinkDrive, child: const Text('Disconnect')),
                    ],
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
      final file = await _backupService.createManualBackup();
      // Shows exactly where the file landed, not just "Backup created" -
      // the shop kept asking "backup save aana pinnaadi enga
      // pogudhu/store aaguthu" with no way to tell from the old message
      // alone (spec: "backup create panna enga save aaguthunu kattu").
      // Long-duration SnackBar (6s) since a folder path takes a moment
      // longer to read than a short confirmation.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup created - saved to ${file.path}'),
            duration: const Duration(seconds: 6),
          ),
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
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      dialogTitle: 'Choose a backup file to restore',
    );
    if (result == null || result.files.single.path == null) return;
    final file = File(result.files.single.path!);
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
      if (mounted && !ok) {
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
      final id = await _backupService.backupToGoogleDrive();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(id != null ? 'Uploaded to Google Drive' : 'Google Drive backup failed')),
        );
      }
    } catch (e) {
      _showError('Google Drive backup failed', e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
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
