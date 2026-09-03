import 'dart:io';

import 'package:flutter/services.dart';

// Same native channel MainActivity.kt already exposes for WhatsApp direct
// share, the Quick Income/Expense notification and the Daily Order alarm -
// reused here purely to trigger the native "restartApp" handler (see
// build-apk.yml's MainActivity.kt for why this has to be done natively,
// not from Dart).
const _nativeChannel = MethodChannel('pro_app/whatsapp_share');

/// Restarts the whole app after a Backup Restore (spec: "if any time backup
/// restore panna app automatically restart aaganum each time restart manual
/// ah panna solluthu" - the shop owner used to have to close and reopen the
/// app by hand after every restore; every restore screen used to say so in
/// its own confirmation dialog/snackbar). Restoring the database swaps out
/// everything every already-open screen/service/repository has cached or
/// connected to (sqflite's own connection included), so a restart has to be
/// a real process relaunch, not just a Navigator.popUntil/rebuild - which is
/// exactly what [restart] asks MainActivity.kt to do natively. Android-only;
/// a no-op (with a short delay so the "Restored" message is still visible
/// for a moment) on any other platform, since there's nothing unsafe left
/// cached to force a restart over there.
class AppRestartService {
  AppRestartService._();

  /// Give the shop owner a brief moment to see the success message before
  /// the screen disappears out from under them.
  static Future<void> restart({Duration delay = const Duration(milliseconds: 900)}) async {
    await Future.delayed(delay);
    if (!Platform.isAndroid) return;
    try {
      await _nativeChannel.invokeMethod('restartApp');
    } catch (_) {
      // If the native relaunch fails for any reason, the shop owner is no
      // worse off than before this feature existed - they just close and
      // reopen the app themselves, same as always.
    }
  }
}
