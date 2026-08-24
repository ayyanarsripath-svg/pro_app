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
  String _backupDirPath = '';
  int _frequencyDays = 1;
  bool _loading = true;
  bool _driveLinked = false;
  String? _driveFolderName;
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
    final freq = await _backupService.autoBackupFrequencyDays;
    final folderName = linked ? await _backupService.backupFolderName : null;
    setState(() {
      _backups = backups;
      _driveLinked = linked;
      _backupDirPath = dirPath;
      _frequencyDays = freq;
      _driveFolderName = folderName;
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
                  const Text('Creates a local copy of your entire database right now.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _working ? null : _createBackup,
                        icon: const Icon(Icons.backup_rounded),
                        label: const Text('Backup Now'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _working ? null : _exportBackup,
                        icon: const Icon(Icons.folder_open_rounded),
                        label: const Text('Save Backup To...'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('"Backup Now" is saved app-privately at:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        SelectableText(_backupDirPath, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                        const SizedBox(height: 6),
                        const Text(
                          'This folder is private to the app - Android hides it from the Files app on every phone, by design, so searching for "backup" there will never find it. Use "Save Backup To..." instead to put a copy somewhere you can see and reach it (Downloads, an SD card, etc.) - that\'s the reliable offline manual backup.',
                          style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ]),
                SectionCard(title: 'Automatic Backup', icon: Icons.auto_mode_rounded, children: [
                  Text(
                    'A local backup is taken automatically whenever the app is opened and more than $_frequencyDays day${_frequencyDays == 1 ? '' : 's'} have passed since the last one.',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Note: this checks only when you open the app (there\'s no separate background service) - so it fires the first time you open the app on or after the due day.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    const Text('Frequency:', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 10),
                    ChoiceChip(
                      label: const Text('Daily'),
                      selected: _frequencyDays == 1,
                      onSelected: (_) => _setFrequency(1),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Weekly'),
                      selected: _frequencyDays == 7,
                      onSelected: (_) => _setFrequency(7),
                    ),
                  ]),
                ]),
                SectionCard(title: 'Google Drive Backup (Optional)', icon: Icons.cloud_rounded, children: [
                  Text(_driveLinked ? 'Linked to Google Drive.' : 'Not linked yet.', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (_driveLinked) ...[
                    const SizedBox(height: 4),
                    Text('Saving to Drive folder: ${_driveFolderName ?? 'Professional Mobiles Backups (default)'}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Requires internet + your own Google Cloud OAuth client (see README "Google Drive Backup Setup"). Everything else in this app works fully offline without this.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (!_driveLinked)
                      ElevatedButton.icon(onPressed: _working ? null : _linkDrive, icon: const Icon(Icons.login_rounded), label: const Text('Connect Google Drive')),
                    if (_driveLinked) ...[
                      ElevatedButton.icon(onPressed: _working ? null : _backupToDrive, icon: const Icon(Icons.cloud_upload_rounded), label: const Text('Backup to Drive')),
                      OutlinedButton.icon(onPressed: _working ? null : _chooseDriveFolder, icon: const Icon(Icons.folder_rounded), label: const Text('Choose Folder')),
                      OutlinedButton(onPressed: _working ? null : _unlinkDrive, child: const Text('Disconnect')),
                    ],
                  ]),
                ]),
                SectionCard(title: 'Local Backups (${_backups.length})', icon: Icons.folder_zip_rounded, children: [
                  if (_backups.isEmpty) const Text('No backups yet.', style: TextStyle(color: AppColors.textSecondary)),
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

  Future<void> _createBackup() async {
    setState(() => _working = true);
    await _backupService.createManualBackup();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup created')));
    setState(() => _working = false);
    _load();
  }

  Future<void> _exportBackup() async {
    setState(() => _working = true);
    final path = await _backupService.exportBackupToFolder();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(path != null ? 'Saved to: $path' : 'Save cancelled')),
      );
    }
    setState(() => _working = false);
    _load();
  }

  Future<void> _setFrequency(int days) async {
    await _backupService.setAutoBackupFrequencyDays(days);
    _load();
  }

  Future<void> _linkDrive() async {
    setState(() => _working = true);
    final result = await _backupService.signInToGoogleDrive();
    if (mounted && !result.success) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Google sign-in failed'),
          content: Text(result.message ?? 'Unknown error'),
          actions: [ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    }
    setState(() => _working = false);
    _load();
  }

  Future<void> _unlinkDrive() async {
    setState(() => _working = true);
    await _backupService.signOutOfGoogleDrive();
    setState(() => _working = false);
    _load();
  }

  Future<void> _backupToDrive() async {
    setState(() => _working = true);
    final id = await _backupService.backupToGoogleDrive();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(id != null ? 'Uploaded to Google Drive' : 'Google Drive backup failed')),
      );
    }
    setState(() => _working = false);
    _load();
  }

  Future<void> _chooseDriveFolder() async {
    setState(() => _working = true);
    final folders = await _backupService.listDriveFolders();
    setState(() => _working = false);
    if (!mounted) return;

    final choice = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Choose a Drive folder for backups', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 10),
              if (folders.isEmpty) const Text('No folders found in your Drive root yet.', style: TextStyle(color: AppColors.textSecondary)),
              ...folders.map((f) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_rounded, color: AppColors.warning),
                    title: Text(f.name ?? 'Untitled'),
                    onTap: () => Navigator.pop(context, {'id': f.id ?? '', 'name': f.name ?? 'Untitled'}),
                  )),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.create_new_folder_rounded, color: AppColors.primaryBlue),
                title: const Text('Create new folder "Professional Mobiles Backups"'),
                onTap: () => Navigator.pop(context, {'id': '__create__', 'name': 'Professional Mobiles Backups'}),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null) return;
    setState(() => _working = true);
    if (choice['id'] == '__create__') {
      final created = await _backupService.createDriveFolder(choice['name']!);
      if (created.id != null) {
        await _backupService.setBackupFolder(created.id!, choice['name']!);
      }
    } else {
      await _backupService.setBackupFolder(choice['id']!, choice['name']!);
    }
    setState(() => _working = false);
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
      await _backupService.restoreFrom(file);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restored. Please close and reopen the app.')));
      }
      setState(() => _working = false);
    }
  }
}
