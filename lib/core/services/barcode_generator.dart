import '../db/database_helper.dart';

/// Generates an internal barcode for a spare part / accessory that doesn't
/// already have a manufacturer barcode to scan (spec item 5/16B: "Barcode
/// இல்லாத spare/accessory-க்கு app automatically unique barcode generate
/// செய்ய வேண்டும்" - System B, as opposed to 16A, scanning an existing
/// manufacturer barcode and saving that as-is).
///
/// Shape: a short uppercase letter prefix taken from the product's name,
/// followed by a zero-padded running number - e.g. "Mobile Mic" -> MIC001,
/// "Battery" -> BAT001 (spec's own worked examples). There is no single
/// deterministic rule that reproduces every one of the spec's examples
/// exactly (BAT/CHG/DISP mix 3- and 4-letter abbreviations) - this uses a
/// simple, consistent rule (first 3 letters of the last significant word)
/// instead of a guessed abbreviation dictionary, and the result always
/// lands in an editable Barcode field afterwards (Add/Edit Part/Accessory),
/// so the shop can always rename it to something more specific before
/// saving if they want to.
class BarcodeGenerator {
  BarcodeGenerator._();

  static const _fillerWords = {'mobile', 'spare', 'part', 'parts', 'accessory', 'accessories', 'the', 'a', 'an'};

  /// Generates and returns a barcode string guaranteed to not already be in
  /// use by any spare part OR accessory (barcodes are one shared identity
  /// space - a spare part and an accessory can never accidentally end up
  /// sharing one). Does NOT save it anywhere - callers assign it via
  /// SparePartRepository.setBarcode / AccessoryRepository.setBarcode (or
  /// pass it straight into create()).
  static Future<String> generate(String productName) async {
    final prefix = _prefixFor(productName);
    final db = await DatabaseHelper.instance.database;
    var n = 1;
    while (true) {
      final candidate = '$prefix${n.toString().padLeft(3, '0')}';
      final sparePartRows = await db.query('spare_parts', where: 'barcode = ?', whereArgs: [candidate], limit: 1);
      if (sparePartRows.isNotEmpty) {
        n++;
        continue;
      }
      final accessoryRows = await db.query('accessories', where: 'barcode = ?', whereArgs: [candidate], limit: 1);
      if (accessoryRows.isNotEmpty) {
        n++;
        continue;
      }
      return candidate;
    }
  }

  static String _prefixFor(String productName) {
    final words = productName
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^A-Za-z]'), ''))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'ITM';

    // Prefer the last word that isn't a generic filler ("Mobile Mic" ->
    // "Mic", not "Mobile") - falls back to the last word as-is if every
    // word happens to be a filler (unlikely, but never leaves this empty).
    final meaningful = words.where((w) => !_fillerWords.contains(w.toLowerCase())).toList();
    final chosen = (meaningful.isNotEmpty ? meaningful.last : words.last).toUpperCase();
    return chosen.length <= 3 ? chosen : chosen.substring(0, 3);
  }
}
