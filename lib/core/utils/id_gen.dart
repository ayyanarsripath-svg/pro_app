import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Internal primary key generator (not shown to users).
String newId() => _uuid.v4();

/// Human friendly running bill numbers, e.g. A125, SH042, SB018.
/// [prefix] identifies the document type, [sequence] is the next running
/// number (callers should read + increment this via SettingsRepository so
/// numbering survives app restarts and stays gap-free per document type).
String formatBillNo(String prefix, int sequence) {
  return '$prefix${sequence.toString().padLeft(3, '0')}';
}
