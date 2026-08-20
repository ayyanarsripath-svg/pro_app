import 'package:flutter/material.dart';

import '../repositories/settings_repository.dart';

/// Persists the order the main menu (drawer) shows its items in, so the
/// shop can drag their most-used screens (Services, Customers, whatever
/// they open all day) to the top instead of always scrolling past ones
/// they rarely touch (spec request: "move the menu items myself / bring
/// the ones I use often to the top, from Settings").
///
/// Stored as a comma-separated list of the stable [_Destination.id] values
/// from AppShell. Same ChangeNotifier + SettingsRepository pattern as
/// [ThemeService] so the drawer rebuilds immediately when the order is
/// changed from Settings, with no app restart needed.
class MenuOrderService extends ChangeNotifier {
  static const _key = 'menu_order';

  final _settings = SettingsRepository();

  List<String> _order = [];
  List<String> get order => List.unmodifiable(_order);

  Future<void> load() async {
    final raw = await _settings.get(_key);
    _order = (raw == null || raw.trim().isEmpty) ? [] : raw.split(',').where((s) => s.isNotEmpty).toList();
    notifyListeners();
  }

  Future<void> setOrder(List<String> ids) async {
    _order = ids;
    await _settings.set(_key, ids.join(','));
    notifyListeners();
  }

  /// Reorders [allIds] (the app's full, fixed set of menu item ids) to
  /// match the saved preference, with any id that has no saved position
  /// (new screens added in an app update, or a first run with nothing
  /// saved yet) kept at the end in its original order - so a stale or
  /// incomplete saved order can never hide a menu item.
  List<String> applyTo(List<String> allIds) {
    if (_order.isEmpty) return allIds;
    final known = _order.where(allIds.contains).toList();
    final missing = allIds.where((id) => !known.contains(id)).toList();
    return [...known, ...missing];
  }
}
