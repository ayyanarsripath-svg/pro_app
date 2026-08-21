import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

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
    setState(() {
      _backups = backups;
      _driveLinked = linked;
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
                  ElevatedButton.icon(
                    onPressed: _working ? null : _createBackup,
                    icon: const Icon(Icons.backup_rounded),
                    label: const Text('Backup Now'),
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
                      'Once connected, all your data (except photos) backs up to Google Drive automatically every day, aimed at around 10 PM - no need to tap anything, and no permission popups. Android doesn't guarantee the exact minute, so as a safety net this also runs the moment you open the app if that day's backup hasn't happened yet. If a day is missed (no internet, phone off, etc.), it's simply included in the next successful backup - nothing is lost.',
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
                ]),
                SectionCard(title: 'Local Backups (${_backups.length})', icon: Icons.folder_zip_rounded, children: [
                  if (_backups.isEmpty) Text('No backups yet.', style: TextStyle(color: AppColors.textSecondaryOf(context))),
                  ..._backups.map((f) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_rounded),
                        title: Text(p.basename(f.path), style: const TextStyle(fontSize: 12.5)),
                        subtitle: Text(formatDateTime(f.statSync().modified)),
                        trailing: TextButton(onPressed: _working ? null : () => _restore(f), child: const Text('Restore')),
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
      await _backupService.createManualBackup();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup created')));
    } catch (e) {
      _showError('Backup failed', e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
    _load();
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
