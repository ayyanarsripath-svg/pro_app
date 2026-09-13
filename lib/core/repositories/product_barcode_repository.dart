import '../db/database_helper.dart';
import '../utils/id_gen.dart';
import '../../models/spare_part.dart';
import '../../models/accessory.dart';
import 'spare_part_repository.dart';
import 'accessory_repository.dart';

class ProductTypes {
  static const sparePart = 'spare_part';
  static const accessory = 'accessory';
}

/// One physical unit's barcode/QR resolved back to whichever product owns
/// it - a [SparePart] XOR an [Accessory], never both (barcodes are one
/// shared identity space across both, same as the original single-barcode
/// design).
class ResolvedProduct {
  final String type; // ProductTypes.sparePart | ProductTypes.accessory
  final SparePart? sparePart;
  final Accessory? accessory;

  ResolvedProduct.sparePart(SparePart part)
      : type = ProductTypes.sparePart,
        sparePart = part,
        accessory = null;

  ResolvedProduct.accessory(Accessory acc)
      : type = ProductTypes.accessory,
        accessory = acc,
        sparePart = null;

  String get id => (sparePart?.id ?? accessory?.id)!;
  String get name => sparePart?.name ?? accessory?.name ?? '';
}

/// Backs the "scan every physical unit's own barcode/QR" flow (spec: "oru
/// product name and details add pannumpothu ... multiple barcode or qr
/// code la scann panramathiri options need" - e.g. 30 physically distinct
/// Boat Headphone units, each with its OWN sticker, all counting as one
/// product with quantity 30, "ella barcode um scann pannikkanum ... save
/// pannikkanum" - every single one of them must be remembered).
///
/// Before this, the schema was strictly "ONE PRODUCT -> ONE BARCODE" (a
/// single `barcode` column on spare_parts/accessories) - correct for the
/// original spec item 18, but it meant only ONE of many identical units'
/// stickers could ever be remembered; scanning any of the other 29 later
/// (at sale time, a supplier return, Service Bill "Add Part -> Scan
/// Barcode", Inventory Search+Scan, etc) would never resolve back to the
/// product at all. This repository adds a proper one-product-to-many-
/// barcodes relationship via the `product_barcodes` table without
/// disturbing that original column, which stays exactly as-is (and keeps
/// working via the legacy fallback in [resolve]) for every product created
/// the old, single-barcode way.
class ProductBarcodeRepository {
  final _dbHelper = DatabaseHelper.instance;
  final _spareParts = SparePartRepository();
  final _accessories = AccessoryRepository();

  /// True only when [barcode] isn't already registered anywhere - this
  /// table (any product, any type) OR either legacy single-barcode column -
  /// so one physical sticker can never end up pointing at two different
  /// products. Pass [excludingProductType]/[excludingProductId] when
  /// checking during an EDIT of a product that may already legitimately own
  /// this exact barcode itself (e.g. its legacy `barcode` column mirrors
  /// one of its own multi-scanned unit codes - see
  /// SparePartsScreen/AccessoriesScreen._barcodeAvailable) so it doesn't
  /// collide with itself. Omit both when scanning new units for a
  /// brand-new product (nothing to exclude yet).
  Future<bool> isAvailable(String barcode, {String? excludingProductType, String? excludingProductId}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'product_barcodes',
      where: excludingProductId != null
          ? 'barcode = ? AND NOT (product_type = ? AND product_id = ?)'
          : 'barcode = ?',
      whereArgs: excludingProductId != null ? [barcode, excludingProductType, excludingProductId] : [barcode],
      limit: 1,
    );
    if (rows.isNotEmpty) return false;
    final okSparePart = await _spareParts.isBarcodeAvailable(
      barcode,
      excludingId: excludingProductType == ProductTypes.sparePart ? excludingProductId : null,
    );
    if (!okSparePart) return false;
    return _accessories.isBarcodeAvailable(
      barcode,
      excludingId: excludingProductType == ProductTypes.accessory ? excludingProductId : null,
    );
  }

  /// Resolves any scanned barcode back to its product: checks every
  /// individually-registered unit barcode first, then falls back to each
  /// product's own single legacy `barcode` column (older products, created
  /// before this feature existed, are unaffected and still resolve
  /// correctly here).
  Future<ResolvedProduct?> resolve(String barcode) async {
    final db = await _dbHelper.database;
    final rows = await db.query('product_barcodes', where: 'barcode = ?', whereArgs: [barcode], limit: 1);
    if (rows.isNotEmpty) {
      final type = rows.first['product_type'] as String;
      final productId = rows.first['product_id'] as String;
      if (type == ProductTypes.sparePart) {
        final part = await _spareParts.byId(productId);
        if (part != null) return ResolvedProduct.sparePart(part);
      } else {
        final acc = await _accessories.byId(productId);
        if (acc != null) return ResolvedProduct.accessory(acc);
      }
    }
    final part = await _spareParts.findByBarcode(barcode);
    if (part != null) return ResolvedProduct.sparePart(part);
    final acc = await _accessories.findByBarcode(barcode);
    if (acc != null) return ResolvedProduct.accessory(acc);
    return null;
  }

  /// Registers every scanned unit barcode against a product in one go -
  /// called once, right after SparePartRepository.create/
  /// AccessoryRepository.create, when the shop finishes a multi-scan Add
  /// Product session. Silently skips a code already registered to this
  /// exact same product (safe to call more than once with an overlapping
  /// list) and blank entries.
  Future<void> attachMany({required String productType, required String productId, required List<String> barcodes}) async {
    if (barcodes.isEmpty) return;
    final db = await _dbHelper.database;
    final existing = (await barcodesFor(productType: productType, productId: productId)).toSet();
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final code in barcodes) {
      final trimmed = code.trim();
      if (trimmed.isEmpty || existing.contains(trimmed)) continue;
      batch.insert('product_barcodes', {
        'id': newId(),
        'product_type': productType,
        'product_id': productId,
        'barcode': trimmed,
        'created_at': now,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<String>> barcodesFor({required String productType, required String productId}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'product_barcodes',
      where: 'product_type = ? AND product_id = ?',
      whereArgs: [productType, productId],
      orderBy: 'created_at ASC',
    );
    return rows.map((r) => r['barcode'] as String).toList();
  }

  /// How many individually-scanned unit barcodes a product has on record -
  /// shown on Product Details so the shop can tell this product was set up
  /// with a full unit-by-unit scan, not just the old single barcode.
  Future<int> countFor({required String productType, required String productId}) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) as c FROM product_barcodes WHERE product_type = ? AND product_id = ?',
      [productType, productId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }
}
