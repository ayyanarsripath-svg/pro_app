import 'package:flutter/foundation.dart';

enum QuickActionType { income, expense, dashboard }

/// Tiny in-memory "the 📊 Dashboard button (or a plain body tap) on the
/// Quick Income/Expense notification was tapped" signal, fired from
/// main.dart's consumeQuickDashboardLaunch() and picked up by AppShell,
/// which reacts by landing on the Dashboard tab - same
/// fire-once-picked-up-by-whoever's-listening pattern as
/// DailyOrderAutoSendSignal (see its own doc comment for why a plain
/// incrementing counter, not a one-shot bool, is what safely survives a
/// cold app-start launched BY the notification tap itself: [fire] can
/// happen before AppShell even exists yet, since it only mounts after the
/// PIN gate is passed).
///
/// ➕ Income / ➖ Expense do NOT go through this signal - they launch their
/// own standalone Activity/screen directly from the notification
/// (QuickIncomeActivity/QuickExpenseActivity, see main.dart), skipping this
/// app and its PIN gate entirely. See QuickNotificationService's class doc
/// comment for the full picture.
class QuickActionSignal {
  QuickActionSignal._();

  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  /// Which action was tapped for the [tick] value currently held - read
  /// this alongside tick, never on its own, since it's just the most recent
  /// value and isn't itself versioned.
  static QuickActionType? lastType;

  static void fire(QuickActionType type) {
    lastType = type;
    tick.value++;
  }
}
