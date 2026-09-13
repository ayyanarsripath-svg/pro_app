/// Best-effort parser for the multi-field voice-fill mic on Add Spare
/// Part/Add Accessory (spec: "ella feild laium inside bar la oru mic
/// subole vachi atha touch panni name quantity purchase amount sales
/// amount thirishould ethu ellam voice command la sonna athu text ah fill
/// pannikkum ethula extra ethana add pannaumna ethapathina full details
/// analysis panni add pannikka" - one mic, speak the whole thing once,
/// analyze whatever was said and fill in whatever fields apply).
///
/// There's no cloud AI available for this (the app is offline-first
/// throughout - see WhatsAppSmsService/BackupService's own doc comments for
/// the same principle), so this is a plain keyword+number heuristic, not
/// true language understanding. It recognizes common English/Tanglish
/// words for quantity/purchase/selling/threshold sitting next to a number,
/// and treats whatever text is LEFT OVER once those recognized chunks are
/// removed as the product Name.
///
/// This is always meant to fill the visible on-screen fields for the shop
/// to glance over and correct before tapping Save - never to save blind.
/// Speech recognition and this heuristic can both misread a number or a
/// word, and the visible text fields are the review step.
class VoiceProductFields {
  String? name;
  double? quantity;
  double? purchasePrice;
  double? sellingPrice;
  double? threshold;
}

class _Range {
  final int start;
  final int end;
  _Range(this.start, this.end);

  bool overlaps(_Range other) => start < other.end && other.start < end;
}

class VoiceProductParser {
  static final RegExp _numberPattern = RegExp(r'\d+(?:\.\d+)?');

  // Longest/most specific phrases first so e.g. "selling price" matches
  // before a bare "price" would, and each list is checked in order.
  static const List<String> _purchaseWords = [
    'purchase price', 'purchase amount', 'purchase cost', 'buying price',
    'cost price', 'purchase', 'vaanga', 'vaangina', 'vangina',
  ];
  static const List<String> _sellingWords = [
    'selling price', 'sales price', 'sale price', 'selling amount',
    'sales amount', 'mrp', 'selling', 'sales', 'sale', 'vikra', 'vikkura', 'vikkum',
  ];
  static const List<String> _thresholdWords = [
    'low stock', 'threshold', 'alert', 'minimum',
  ];
  static const List<String> _quantityWords = [
    'quantity', 'qty', 'pieces', 'piece', 'pcs', 'units', 'unit', 'stock', 'yenikai', 'yennikkai',
  ];

  /// Finds the first occurrence of any keyword in [words] and the number
  /// nearest to it (checking just after the keyword first, since "quantity
  /// 30" is the far more natural order, then just before it for "30
  /// pieces"). Returns null if none of the keywords appear at all. Any
  /// match found also records the exact character range it consumed so the
  /// caller can strip it out of the leftover text used for the Name.
  static double? _extractNear(String text, List<String> words, List<_Range> consumed) {
    for (final w in words) {
      final wIdx = text.indexOf(w);
      if (wIdx == -1) continue;
      final afterStart = wIdx + w.length;
      final afterEnd = (afterStart + 20).clamp(0, text.length);
      final afterMatch = _numberPattern.firstMatch(text.substring(afterStart, afterEnd));
      if (afterMatch != null) {
        final range = _Range(wIdx, afterStart + afterMatch.end);
        if (consumed.any((r) => r.overlaps(range))) continue;
        consumed.add(range);
        return double.tryParse(afterMatch.group(0)!);
      }
      final beforeStart = (wIdx - 20).clamp(0, text.length);
      final beforeMatches = _numberPattern.allMatches(text.substring(beforeStart, wIdx)).toList();
      if (beforeMatches.isNotEmpty) {
        final m = beforeMatches.last;
        final range = _Range(beforeStart + m.start, afterStart);
        if (consumed.any((r) => r.overlaps(range))) continue;
        consumed.add(range);
        return double.tryParse(m.group(0)!);
      }
    }
    return null;
  }

  static VoiceProductFields parse(String heard) {
    final fields = VoiceProductFields();
    final text = ' ${heard.toLowerCase()} ';
    final consumed = <_Range>[];

    // Most-specific keyword groups first so a shared word like "price"
    // doesn't get claimed by the wrong field.
    fields.threshold = _extractNear(text, _thresholdWords, consumed);
    fields.sellingPrice = _extractNear(text, _sellingWords, consumed);
    fields.purchasePrice = _extractNear(text, _purchaseWords, consumed);
    fields.quantity = _extractNear(text, _quantityWords, consumed);

    // No explicit "quantity"/"pieces" word said (e.g. just "Boat headphone
    // 30") - fall back to the first number nobody else already claimed.
    if (fields.quantity == null) {
      for (final m in _numberPattern.allMatches(text)) {
        final range = _Range(m.start, m.end);
        if (consumed.any((r) => r.overlaps(range))) continue;
        fields.quantity = double.tryParse(m.group(0)!);
        consumed.add(range);
        break;
      }
    }

    // Remove every consumed range (highest offset first so earlier ranges'
    // indices don't shift), leaving whatever's left as the product name.
    consumed.sort((a, b) => b.start.compareTo(a.start));
    var nameText = text;
    for (final r in consumed) {
      nameText = nameText.replaceRange(r.start, r.end, ' ');
    }
    nameText = nameText.replaceAll(RegExp(r'\brupees?\b|\brs\.?\b|₹', caseSensitive: false), ' ');
    final cleaned = nameText.trim().replaceAll(RegExp(r'\s+'), ' ');
    fields.name = cleaned.isEmpty ? null : _titleCase(cleaned);
    return fields;
  }

  static String _titleCase(String s) => s
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
