import 'package:flutter/material.dart';

import '../../core/services/backup_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

/// "Restore Screen" (spec item 8): lists every genuine PRO SERVICE backup
/// file in Google Drive, newest first, each with its date/time + size and
/// its own [RESTORE] button, plus a prominent [RESTORE LATEST BACKUP]
/// shortcut at the top. Every restore here goes through
/// BackupService.restoreFromGoogleDriveFile, which always acts on the
/// EXACT Drive fileId the shop tapped (spec item 9) and follows the full
/// validate -> safety-backup -> replace -> verify -> automatic rollback on
/// failure flow (spec item 10).
class GoogleDriveRestoreScreen extends StatefulWidget {
  const GoogleDriveRestoreScreen({super.key});

  @override
  State<GoogleDriveRestoreScreen> createState() => _GoogleDriveRestoreScreenState();
}

class _GoogleDriveRestoreScreenState extends State<GoogleDriveRestoreScreen> {
  final _backupService = BackupService();
  bool _loading = true;
  bool _working = false;
  String? _loadError;
  List<DriveBackupFileInfo> _backups = [];

  // Only shown/offered when the Drive folder actually contains backups
  // from more than one device (spec item 13: "Restore should allow
  // selecting backups from the correct device if multiple devices exist").
  String? _deviceFilter; // null = "All devices"

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final backups = await _backupService.listGoogleDriveBackups();
      if (!mounted) return;
      setState(() {
        _backups = backups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<String> get _deviceLabels {
    final labels = _backups.map((b) => b.deviceLabel).whereType<String>().toSet().toList();
    labels.sort();
    return labels;
  }

  List<DriveBackupFileInfo> get _visibleBackups {
    if (_deviceFilter == null) return _backups;
    return _backups.where((b) => b.deviceLabel == _deviceFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleBackups;
    final devices = _deviceLabels;

    return Scaffold(
      appBar: AppBar(title: const Text('Restore from Google Drive')),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
                  ? _buildError(context)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(14),
                        children: [
                          if (visible.isEmpty) _buildEmpty(context),
                          if (visible.isNotEmpty) ...[
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _working ? null : () => _confirmAndRestore(visible.first),
                                icon: const Icon(Icons.restore_rounded),
                                label: const Text('RESTORE LATEST BACKUP'),
                                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (devices.length > 1) _buildDeviceFilter(context, devices),
                            const SizedBox(height: 6),
                            Text(
                              'Google Drive Backups (${visible.length})',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.textSecondaryOf(context)),
                            ),
                            const SizedBox(height: 8),
                            ...visible.map((b) => _buildBackupTile(context, b)),
                          ],
                        ],
                      ),
                    ),
          if (_working)
            Container(
              color: Colors.black.withOpacity(0.35),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Restoring - please wait...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDeviceFilter(BuildContext context, List<String> devices) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          ChoiceChip(
            label: const Text('All devices'),
            selected: _deviceFilter == null,
            onSelected: (_) => setState(() => _deviceFilter = null),
          ),
          for (final d in devices)
            ChoiceChip(
              label: Text('Device $d'),
              selected: _deviceFilter == d,
              onSelected: (_) => setState(() => _deviceFilter = d),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 46, color: AppColors.textSecondaryOf(context).withOpacity(0.4)),
          const SizedBox(height: 10),
          Text(
            'No Google Drive backups found yet.\nRun "Backup to Drive" from Backup & Restore first.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondaryOf(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 42, color: AppColors.danger),
            const SizedBox(height: 10),
            Text(_loadError!, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            ElevatedButton(onPressed: _load, child: const Text('Try Again')),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupTile(BuildContext context, DriveBackupFileInfo backup) {
    final modified = backup.modifiedTime;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_zip_rounded, color: AppColors.primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  modified != null ? formatDateTime(modified) : backup.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  formatFileSize(backup.size),
                  style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _working ? null : () => _confirmAndRestore(backup),
            child: const Text('RESTORE'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndRestore(DriveBackupFileInfo backup) async {
    final modified = backup.modifiedTime;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
          'This will download the backup from ${modified != null ? formatDateTime(modified) : backup.name} '
          '(${formatFileSize(backup.size)}) and replace your current data with it. '
          'Your current data is safety-backed-up first, and will be restored automatically if anything goes wrong. '
          'The app must be restarted after restoring.',
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
      final result = await _backupService.restoreFromGoogleDriveFile(backup);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(result.hasWarnings ? 'Restored (with warnings)' : 'Restore Successful'),
          content: Text(
            result.hasWarnings
                ? 'Data was restored, but some record counts didn\'t exactly match the backup:\n\n${result.mismatches.join('\n')}\n\nPlease close and reopen the app.'
                : 'Your data has been restored from Google Drive. Please close and reopen the app.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore Failed'),
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}
