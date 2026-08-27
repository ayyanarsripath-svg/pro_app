import 'dart:async';

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
          // Includes Type/Model alongside the part/accessory name (spec:
          // "preview la part or accessories name and quantity mattumthan
          // kamikkuthu enakku type or model um sethu preview la kattanum")
          // - previously only "<part name> x<qty>" was written here, so a
          // shop with several entries of the same part name but different
          // models had no way to tell them apart on the home screen widget
          // without opening the app.
          String text;
          if (i < pending.length) {
            final item = pending[i];
            final model = (item.typeModel ?? '').trim();
            text = model.isEmpty ? '${item.partName} x${item.quantity}' : '${item.partName} ($model) x${item.quantity}';
          } else {
            text = '';
          }
          await HomeWidget.saveWidgetData<String>('item_$i', text);
        }
      }

      await HomeWidget.updateWidget(androidName: _androidWidgetName);

      // BUG FIX: "daily order widget refresh aagamattangithu once screen
      // la add pannathukku aprom" - the home-screen widget would refresh
      // the first time then go stale on later adds (worst with the
      // widget's own Quick Add screen and its "Save & Add Another" button,
      // which can call this several times within a couple of seconds).
      // The widget data itself was always being written correctly (see
      // above) - the gap was Android's ACTION_APPWIDGET_UPDATE broadcast
      // above sometimes not being applied by the home screen launcher when
      // several of these land in quick succession (some OEM launchers
      // coalesce/drop a broadcast that arrives while the previous one is
      // still being redrawn). A second, identical update shortly after -
      // by which point the first redraw has finished - is cheap insurance
      // that a dropped/coalesced broadcast is never the reason the widget
      // looks stale. Fire-and-forget: this refresh() call has already done
      // its job by the time this fires, so nothing awaits it.
      unawaited(Future.delayed(const Duration(milliseconds: 800), () async {
        try {
          await HomeWidget.updateWidget(androidName: _androidWidgetName);
        } catch (_) {}
      }));
    } catch (_) {
      // A widget refresh failing (e.g. plugin not ready yet on very first
      // launch) must never break the rest of the app - the widget simply
      // shows stale data until the next successful refresh.
    }
  }
}
