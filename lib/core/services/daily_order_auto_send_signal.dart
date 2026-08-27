import 'package:flutter/foundation.dart';

/// Tiny in-memory "someone tapped the Daily Order reminder notification"
/// signal, shared between the notification callback (see
/// OrderReminderService/main.dart) and the two UI spots that need to react
/// to it: AppShell (jump straight to the Daily Orders tab) and
/// DailyOrderScreen itself (automatically kick off the same PDF-build +
/// open-WhatsApp-with-attachment flow the "Send Order via WhatsApp" button
/// already does - spec: "reminder alarm adikkanum, atha paathu na whatsapp
/// send button click pannuvan" / "pdf na just send button mattum press
/// pannuvan" i.e. the shop just wants to land on an already-prepared
/// WhatsApp share and tap Send inside WhatsApp themselves).
///
/// Deliberately a plain incrementing counter (not a one-shot bool) stored in
/// a ValueNotifier: [fire] can happen before either listener has even been
/// created yet (a cold app-start via notification tap, where AppShell/
/// DailyOrderScreen don't exist until after the PIN gate is passed) - both
/// listeners re-check [tick.value] once as soon as they mount, so a signal
/// fired earlier is never missed, and later warm-app taps still work via
/// the normal listener callback path.
class DailyOrderAutoSendSignal {
  DailyOrderAutoSendSignal._();

  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  static void fire() => tick.value++;
}
