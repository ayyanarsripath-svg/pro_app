import 'package:flutter/material.dart';

import '../repositories/settings_repository.dart';

/// Holds the app's light/dark theme choice and persists it so it survives
/// app restarts. Kept as a ChangeNotifier (same pattern as AuthService) so
/// MaterialApp rebuilds instantly the moment the Settings screen toggle is
/// flipped, with no restart needed.
class ThemeService extends ChangeNotifier {
  static const _key = 'theme_mode';

  final _settings = SettingsRepository();

  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    final raw = await _settings.get(_key);
    _mode = raw == 'dark' ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> setDark(bool dark) async {
    _mode = dark ? ThemeMode.dark : ThemeMode.light;
    await _settings.set(_key, dark ? 'dark' : 'light');
    notifyListeners();
  }
}
