import 'package:flutter/foundation.dart';

enum QuickActionType { income, expense, dashboard }

/// Tiny in-memory "someone tapped a Quick Income/Expense notification
/// action" signal, shared between the notification callback (see
/// AppNotifications) and AppShell, which reacts by pushing
/// QuickTransactionScreen (or just landing on the Dashboard tab for a plain
/// body/📊 tap) - same fire-once-picked-up-by-whoever's-listening pattern as
/// DailyOrderAutoSendSignal (see its own doc comment for why a plain
/// incrementing counter, not a one-shot bool, is what safely survives a
/// cold app-start launched BY the notification tap itself: [fire] can
/// happen before AppShell even exists yet, since it only mounts after the
/// PIN gate is passed).
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
