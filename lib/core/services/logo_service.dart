import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../repositories/settings_repository.dart';

/// Holds the shop's own logo/photo, once they've replaced the default
/// "PROFESSIONAL MOBILES" phoenix logo from Settings (spec request: "an
/// option in Settings to change the app logo"). Same ChangeNotifier +
/// SettingsRepository pattern as [ThemeService]/[MenuOrderService] so the
/// drawer header and printed bills pick up a new logo immediately, with no
/// app restart needed.
///
/// The picked image is copied into the app's own documents folder (not
/// referenced by its original gallery path, which can move or be deleted
/// by the user later) and the path is saved in Settings. Everywhere the
/// logo is shown falls back to the bundled default artwork when no custom
/// logo has been set.
class LogoService extends ChangeNotifier {
  static const _key = SettingsRepository.logoPath;

  final _settings = SettingsRepository();

  File? _logoFile;
  File? get logoFile => _logoFile;
  bool get hasCustomLogo => _logoFile != null;

  Future<void> load() async {
    final path = await _settings.get(_key);
    if (path != null && path.isNotEmpty && await File(path).exists()) {
      _logoFile = File(path);
    } else {
      _logoFile = null;
    }
    notifyListeners();
  }

  /// Copies [source] into app storage as the new logo and persists it.
  Future<void> setLogo(File source) async {
    final docs = await getApplicationDocumentsDirectory();
    final ext = p.extension(source.path).isNotEmpty ? p.extension(source.path) : '.png';
    final dest = File(p.join(docs.path, 'shop_logo$ext'));
    await source.copy(dest.path);
    await _settings.set(_key, dest.path);
    _logoFile = dest;
    notifyListeners();
  }

  /// Reverts to the default bundled logo.
  Future<void> clearLogo() async {
    if (_logoFile != null && await _logoFile!.exists()) {
      await _logoFile!.delete();
    }
    await _settings.set(_key, '');
    _logoFile = null;
    notifyListeners();
  }
}
