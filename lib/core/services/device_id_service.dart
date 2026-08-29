import 'package:uuid/uuid.dart';

import '../repositories/settings_repository.dart';

/// Generates (once) and remembers a random per-install identifier used to
/// tell one shop device apart from another when the same Google Drive
/// account backs up more than one phone (spec item 13: "Multiple Device
/// Protection... include a device identifier in metadata/file name...
/// However, do not expose sensitive device information to the user").
///
/// Deliberately NOT the phone's IMEI, Android ID, or serial number - this
/// is a fresh, meaningless UUID stored only in this app's own Settings
/// table, so it carries no real hardware-tracking information and resets
/// naturally on a clean reinstall (which is fine: a reinstalled phone
/// restoring from Drive doesn't need to keep pretending to be the exact
/// same "device" as before).
class DeviceIdService {
  static const _uuid = Uuid();
  final _settings = SettingsRepository();

  /// Full UUID - stored in every backup's manifest.json (schema/version
  /// metadata, spec item 14) so a restore can at least tell "same install"
  /// apart from "a different one" even though the short label below is all
  /// that's shown to the shop owner.
  Future<String> fullId() async {
    final existing = await _settings.get(SettingsRepository.deviceBackupId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _uuid.v4();
    await _settings.set(SettingsRepository.deviceBackupId, id);
    return id;
  }

  /// Short (8 hex char), filename-safe label derived from the full UUID -
  /// e.g. "a1b2c3d4" - used as the "_DEVICE_xxx" suffix in every Drive
  /// backup's file name (spec item 13's example:
  /// "PRO_SERVICE_BACKUP_2026-08-29_22-00-15_DEVICE_xxx.zip"). Short and
  /// opaque on purpose - just enough to group "this phone's" backups
  /// together and keep two phones from ever colliding on the same file
  /// name, without meaning anything on its own.
  Future<String> shortLabel() async {
    final id = await fullId();
    return id.replaceAll('-', '').substring(0, 8);
  }
}
