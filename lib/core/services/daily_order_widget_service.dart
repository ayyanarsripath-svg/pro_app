import 'package:home_widget/home_widget.dart';

import '../repositories/daily_order_repository.dart';
import '../repositories/settings_repository.dart';

/// Pushes today's pending Daily Order data to the Android home-screen
/// widget (see DailyOrderWidgetProvider.kt, injected into android/ by the
/// CI build script since that folder is regenerated fresh every build and
/// is never committed to this repo).
///
/// The widget itself cannot run Dart code or query the database directly -
/// it only ever displays whatever this last wrote into SharedPreferences
/// via [HomeWidget.saveWidgetData]. That means this must be called
/// whenever the underlying data could plausibly have changed: see
/// DailyOrderScreen._load() (covers add/delete/send/settings-save, since
/// they all call _load() afterward) and main.dart's startup call (covers
/// carry-forward changing which items are "today's" without the user
/// opening Daily Orders at all).
///
/// Native side shows up to [_maxRows] pending items as static text rows,
/// not a true scrolling list - a real scrolling widget list needs a
/// RemoteViewsService list adapter, a much larger native component than
/// this feature warrants. The widget resizes across three layout tiers
/// (mini/medium/maximum) matching however large the shop owner has dragged
/// it on their home screen - see the widget provider's onAppWidgetOptionsChanged.
class DailyOrderWidgetService {
  static const _androidWidgetName = 'DailyOrderWidgetProvider';
  static const _widgetEnabledKey = 'widget_enabled';
  static const _maxRows = 8;

  final _repo = DailyOrderRepository();
  final _settings = SettingsRepository();

  /// Whether the widget is turned on. Backed by the same home_widget
  /// SharedPreferences storage the native widget itself reads from -
  /// deliberately NOT stored via SettingsRepository/SQLite, since
  /// BackupService backs up the whole database file and this on/off toggle
  /// must stay purely local to the device, never in a backup or Drive
  /// upload.
  Future<bool> isEnabled() async {
    final v = await HomeWidget.getWidgetData<String>(_widgetEnabledKey, defaultValue: 'true');
    return v != 'false';
  }

  Future<void> setEnabled(bool enabled) async {
    try {
      await HomeWidget.saveWidgetData<String>(_widgetEnabledKey, enabled ? 'true' : 'false');
    } catch (_) {
      // Same fail-safe reasoning as refresh() below.
    }
  }

  Future<void> refresh() async {
    try {
      final enabled = await isEnabled();

      if (enabled) {
        final pending = await _repo.unsentItems();
        final supplierName = await _settings.get(SettingsRepository.dailyOrderSupplierName);
        await HomeWidget.saveWidgetData<String>(
          'supplier_name',
          (supplierName == null || supplierName.trim().isEmpty) ? 'Daily Orders' : supplierName,
        );
        await HomeWidget.saveWidgetData<int>('pending_count', pending.length);
        for (var i = 0; i < _maxRows; i++) {
          final text = i < pending.length ? '${pending[i].partName} x${pending[i].quantity}' : '';
          await HomeWidget.saveWidgetData<String>('item_$i', text);
        }
      }

      await HomeWidget.updateWidget(androidName: _androidWidgetName);
    } catch (_) {
      // A widget refresh failing (e.g. plugin not ready yet on very first
      // launch) must never break the rest of the app - the widget simply
      // shows stale data until the next successful refresh.
    }
  }
}
