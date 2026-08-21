import 'package:flutter/foundation.dart';

/// Set from main.dart whenever the app was opened (cold start, or already
/// running in the background) via the Daily Orders home-screen widget's
/// "+ Add" button. `_RootGate` in app.dart watches this and jumps straight
/// to `QuickAddOrderScreen`, skipping the shop's staff PIN login screen
/// entirely - noting down one order item on the way past should never
/// need a full login.
///
/// Reset back to false once the quick-add screen has been shown/closed
/// (see QuickAddOrderScreen), so a normal app re-open afterward goes
/// through the regular PIN gate again as usual.
class WidgetLaunchState {
  WidgetLaunchState._();

  static final ValueNotifier<bool> quickAddRequested = ValueNotifier<bool>(false);
}
