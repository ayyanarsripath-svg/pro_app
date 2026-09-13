import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';

/// An in-progress "Add Product" session: whatever was typed in Step 1
/// (Name/Category/etc) plus every barcode scanned so far in Step 2.
class ProductDraft {
  final String productType;
  final Map<String, String> details;
  final List<String> barcodes;
  final DateTime updatedAt;

  ProductDraft({
    required this.productType,
    required this.details,
    required this.barcodes,
    required this.updatedAt,
  });
}

/// Persists an in-progress "Add Product" session to the database itself,
/// not just in-memory widget state - so it survives the shop's phone Back
/// button, the app being swiped from Recents, or even a full close/reopen
/// while they're partway through scanning many units' worth of barcodes for
/// one new product (spec: "naduvula back vantha entire process cancel
/// aagakudathu resume aaganum chinna thappu pannalum aprom first la erunthu
/// pannanum" - interrupting mid-way, or making one small mistake, must
/// never force starting the whole entry over).
///
/// Exactly one draft is kept per product type at a time (`product_type` is
/// the primary key) - simple by design: starting a second brand-new "Add
/// Part" while one is already mid-scan resumes that same in-progress entry
/// instead of stacking a separate draft (see SparePartsScreen/
/// AccessoriesScreen's resume prompt).
class ProductDraftRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<ProductDraft?> load(String productType) async {
    final db = await _dbHelper.database;
    final rows = await db.query('product_add_drafts', where: 'product_type = ?', whereArgs: [productType]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return ProductDraft(
      productType: productType,
      details: Map<String, String>.from(jsonDecode(row['details_json'] as String) as Map),
      barcodes: List<String>.from(jsonDecode(row['barcodes_json'] as String) as List),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  Future<void> save({
    required String productType,
    required Map<String, String> details,
    required List<String> barcodes,
  }) async {
    final db = await _dbHelper.database;
    await db.insert(
      'product_add_drafts',
      {
        'product_type': productType,
        'details_json': jsonEncode(details),
        'barcodes_json': jsonEncode(barcodes),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clear(String productType) async {
    final db = await _dbHelper.database;
    await db.delete('product_add_drafts', where: 'product_type = ?', whereArgs: [productType]);
  }
}
