import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/repositories/accessory_repository.dart';
import '../../core/repositories/product_barcode_repository.dart';
import '../../core/repositories/product_draft_repository.dart';
import '../../core/repositories/spare_part_repository.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/barcode_generator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/voice_product_parser.dart';
import '../../models/accessory.dart';
import '../../widgets/multi_field_voice_button.dart';
import '../../widgets/section_card.dart';
import 'barcode_scanner_screen.dart';
import 'multi_unit_scan_screen.dart';
import 'product_detail_screen.dart';

class AccessoriesScreen extends StatefulWidget {
  const AccessoriesScreen({super.key});

  @override
  State<AccessoriesScreen> createState() => _AccessoriesScreenState();
}

class _AccessoriesScreenState extends State<AccessoriesScreen> {
  final _repo = AccessoryRepository();
  final _sparePartRepo = SparePartRepository();
  final _barcodeRepo = ProductBarcodeRepository();
  final _draftRepo = ProductDraftRepository();
  final _searchCtrl = TextEditingController();
  List<Accessory> _items = [];
  bool _loading = true;
  String _query = '';

  static const _adjustReasons = [
    'Damaged',
    'Lost',
    'Used internally',
    'Returned',
    'Wrong stock entry',
    'Physical stock correction',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _repo.all();
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  List<Accessory> get _filtered {
    if (_query.trim().isEmpty) return _items;
    final q = _query.trim().toLowerCase();
    return _items.where((a) => a.name.toLowerCase().contains(q) || (a.barcode?.toLowerCase().contains(q) ?? false)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final visible = _filtered;
    final stockValue = _items.fold<double>(0, (s, a) => s + a.stockValue);
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Search Product or Barcode',
                            prefixIcon: Icon(Icons.search_rounded),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        tooltip: 'Scan Barcode',
                        onPressed: _scanToFind,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _quickRestockScan,
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Quick Restock (Continuous Scan)'),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.flameOrange.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${_items.length} Accessories', style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('Stock Value: ₹${stockValue.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.flameOrange)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (visible.isEmpty) EmptyState(icon: Icons.headset_rounded, message: _items.isEmpty ? 'No accessories yet' : 'No match found'),
                  ...visible.map((a) => Card(
                        child: ListTile(
                          title: Text(a.name),
                          subtitle: Text(
                            '${a.category ?? ''} ${a.brand ?? ''}\nBuy ₹${a.purchasePrice.toStringAsFixed(0)}  →  Sell ₹${a.sellingPrice.toStringAsFixed(0)}  (Profit ₹${a.unitProfit.toStringAsFixed(0)}/unit)'
                            '${a.barcode != null ? '\nBarcode: ${a.barcode}' : ''}',
                          ),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${a.currentStock.toStringAsFixed(0)} ${a.unit}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: a.isOutOfStock ? AppColors.danger : (a.isLowStock ? AppColors.warning : AppColors.textPrimaryOf(context)))),
                              if (a.isOutOfStock)
                                const Text('OUT OF STOCK', style: TextStyle(color: AppColors.danger, fontSize: 10, fontWeight: FontWeight.w700))
                              else if (a.isLowStock)
                                const Text('LOW STOCK', style: TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w700)),
                            ],
                          ),
                          onTap: () => _showActions(a, auth),
                        ),
                      )),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addAccessory(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Accessory'),
      ),
    );
  }

  /// Inventory Search + Scan (spec item 10) - see SparePartsScreen's
  /// _scanToFind for the shared-barcode-space reasoning; this is the
  /// accessory-first mirror of the same flow.
  Future<void> _scanToFind() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const BarcodeScannerScreen(title: 'Scan to Find Product')));
    if (code == null || code.isEmpty || !mounted) return;

    // Resolves via product_barcodes FIRST (any individually-scanned unit
    // barcode from the multi-scan Add Product flow) before falling back to
    // each product's own legacy single barcode column - see
    // ProductBarcodeRepository.resolve's doc comment.
    final resolved = await _barcodeRepo.resolve(code);
    if (resolved != null) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(
            kind: resolved.type == ProductTypes.sparePart ? ProductKind.sparePart : ProductKind.accessory,
            id: resolved.id,
          ),
        ),
      );
      _load();
      return;
    }

    if (!mounted) return;
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Product Not Found'),
        content: Text('No product is registered with barcode "$code" yet. Create a new accessory with this barcode?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    if (create == true) await _addAccessory(presetBarcode: code);
  }

  /// Fast Continuous Scanning restock (spec item 12) - see
  /// SparePartsScreen._quickRestockScan for the same flow on the spare-parts
  /// side; this is the accessory mirror of it.
  Future<void> _quickRestockScan() async {
    final counts = <String, int>{};
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BarcodeScannerScreen(
          continuous: true,
          title: 'Quick Restock - Scan Each Item',
          onScan: (code) => counts[code] = (counts[code] ?? 0) + 1,
          describeCode: (code) async {
            final resolved = await _barcodeRepo.resolve(code);
            if (resolved == null || resolved.type != ProductTypes.accessory) return null;
            final acc = resolved.accessory!;
            return '${acc.name} (stock: ${acc.currentStock.toStringAsFixed(0)})';
          },
        ),
      ),
    );
    if (counts.isEmpty || !mounted) return;

    int applied = 0;
    final notFound = <String>[];
    for (final entry in counts.entries) {
      final resolved = await _barcodeRepo.resolve(entry.key);
      if (resolved == null || resolved.type != ProductTypes.accessory) {
        notFound.add(entry.key);
        continue;
      }
      final acc = resolved.accessory!;
      await _repo.recordPurchase(
        accessoryId: acc.id,
        quantity: entry.value.toDouble(),
        unitCost: acc.purchasePrice,
        date: DateTime.now(),
      );
      applied++;
    }
    _load();
    if (!mounted) return;
    final message = StringBuffer('Restocked $applied item(s).');
    if (notFound.isNotEmpty) message.write(' ${notFound.length} barcode(s) not found in inventory: ${notFound.join(', ')}');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message.toString())));
  }

  Future<bool> _barcodeAvailable(String barcode, {String? excludingId}) async {
    final okHere = await _repo.isBarcodeAvailable(barcode, excludingId: excludingId);
    if (!okHere) return false;
    final okThere = await _sparePartRepo.isBarcodeAvailable(barcode);
    if (!okThere) return false;
    // Also checks every individually-scanned unit barcode from the
    // multi-scan Add Product flow (product_barcodes), not just the two
    // legacy single-barcode columns above. excludingId (when editing) may
    // legitimately already own this exact barcode as one of its own
    // multi-scanned unit codes.
    return _barcodeRepo.isAvailable(barcode, excludingProductType: ProductTypes.accessory, excludingProductId: excludingId);
  }

  void _showBarcodeTaken(String barcode) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Barcode "$barcode" is already assigned to another product.')));
  }

  /// A barcode text field with Scan + Generate buttons (see
  /// SparePartsScreen._barcodeField for the same widget on the spare-parts
  /// side - kept as separate small copies rather than a shared widget file
  /// so each screen's dialogs stay self-contained).
  Widget _barcodeField(TextEditingController barcodeCtrl, TextEditingController nameCtrl) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: TextField(controller: barcodeCtrl, decoration: const InputDecoration(labelText: 'Barcode (optional)'))),
        IconButton(
          tooltip: 'Scan Barcode',
          icon: const Icon(Icons.qr_code_scanner_rounded),
          onPressed: () async {
            final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
            if (code != null) barcodeCtrl.text = code;
          },
        ),
        IconButton(
          tooltip: 'Generate Barcode',
          icon: const Icon(Icons.auto_awesome_rounded),
          onPressed: () async {
            final code = await BarcodeGenerator.generate(nameCtrl.text.trim().isEmpty ? 'Item' : nameCtrl.text.trim());
            barcodeCtrl.text = code;
          },
        ),
      ],
    );
  }

  /// Applies whatever VoiceProductParser recognized straight onto the
  /// dialog's own TextEditingControllers - see SparePartsScreen's identical
  /// helper for why no setState is needed here.
  void _fillFromVoice(
    String heard, {
    required TextEditingController nameCtrl,
    TextEditingController? quantityCtrl,
    TextEditingController? purchaseCtrl,
    TextEditingController? sellCtrl,
    TextEditingController? thresholdCtrl,
  }) {
    final f = VoiceProductParser.parse(heard);
    if (f.name != null) nameCtrl.text = f.name!;
    if (f.quantity != null) quantityCtrl?.text = f.quantity!.toStringAsFixed(f.quantity! % 1 == 0 ? 0 : 2);
    if (f.purchasePrice != null) purchaseCtrl?.text = f.purchasePrice!.toStringAsFixed(0);
    if (f.sellingPrice != null) sellCtrl?.text = f.sellingPrice!.toStringAsFixed(0);
    if (f.threshold != null) thresholdCtrl?.text = f.threshold!.toStringAsFixed(0);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Heard: "$heard" - please check the fields below before saving.')));
    }
  }

  Future<bool?> _askResumeDraft(dynamic draft) async {
    final name = (draft.details['name'] as String?)?.trim();
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Resume Unfinished Entry?'),
        content: Text(
          'You have an unfinished Accessory entry "${(name == null || name.isEmpty) ? '(unnamed)' : name}" '
          'with ${(draft.barcodes as List).length} barcode(s) already scanned. Resume it, or start a new one instead?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Start New')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Resume')),
        ],
      ),
    );
  }

  /// Step 2 of the multi-scan Add Product flow - see
  /// MultiUnitScanScreen/SparePartsScreen._openMultiScan for the full
  /// resumable-draft design; this is the accessory-side mirror.
  Future<void> _openMultiScan({required Map<String, String> details, required List<String> initialBarcodes}) async {
    await _draftRepo.save(productType: ProductTypes.accessory, details: details, barcodes: initialBarcodes);
    if (!mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MultiUnitScanScreen(
          productType: ProductTypes.accessory,
          details: details,
          initialBarcodes: initialBarcodes,
          title: 'Scan Units - ${details['name'] ?? ''}',
          onFinalize: (barcodes) async {
            final acc = await _repo.create(
              name: details['name'] ?? '',
              category: details['category'],
              brand: details['brand'],
              sellingPrice: double.tryParse(details['sellingPrice'] ?? '') ?? 0,
              lowStockThreshold: double.tryParse(details['threshold'] ?? '') ?? 3,
              barcode: barcodes.isNotEmpty ? barcodes.first : null,
            );
            await _repo.recordPurchase(
              accessoryId: acc.id,
              quantity: barcodes.length.toDouble(),
              unitCost: double.tryParse(details['purchaseCost'] ?? '') ?? 0,
              date: DateTime.now(),
            );
            await _barcodeRepo.attachMany(productType: ProductTypes.accessory, productId: acc.id, barcodes: barcodes);
          },
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _addAccessory({String? presetBarcode}) async {
    if (presetBarcode == null) {
      final existingDraft = await _draftRepo.load(ProductTypes.accessory);
      if (existingDraft != null) {
        final resume = await _askResumeDraft(existingDraft);
        if (!mounted) return;
        if (resume == true) {
          await _openMultiScan(details: existingDraft.details, initialBarcodes: existingDraft.barcodes);
          return;
        }
        await _draftRepo.clear(ProductTypes.accessory);
      }
    }

    final nameCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final brandCtrl = TextEditingController();
    final quantityCtrl = TextEditingController(text: '0');
    final purchaseCtrl = TextEditingController();
    final sellCtrl = TextEditingController();
    final thresholdCtrl = TextEditingController(text: '3');
    final barcodeCtrl = TextEditingController(text: presetBarcode ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('Add Accessory')),
            MultiFieldVoiceButton(
              onHeard: (heard) => _fillFromVoice(
                heard,
                nameCtrl: nameCtrl,
                quantityCtrl: quantityCtrl,
                purchaseCtrl: purchaseCtrl,
                sellCtrl: sellCtrl,
                thresholdCtrl: thresholdCtrl,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name (e.g. Headphone)')),
              const SizedBox(height: 10),
              TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Category')),
              const SizedBox(height: 10),
              TextField(controller: brandCtrl, decoration: const InputDecoration(labelText: 'Brand')),
              const SizedBox(height: 10),
              TextField(controller: quantityCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
              const SizedBox(height: 10),
              TextField(controller: purchaseCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Purchase Price (₹)')),
              const SizedBox(height: 10),
              TextField(controller: sellCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Selling Price (₹)')),
              const SizedBox(height: 10),
              TextField(controller: thresholdCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Low Stock Threshold')),
              const SizedBox(height: 10),
              _barcodeField(barcodeCtrl, nameCtrl),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a Name first.')));
                      return;
                    }
                    Navigator.pop(context, 'scan_multi');
                  },
                  icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: const Text('Scan Barcode for Each Unit (many pcs, many codes)'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save')),
        ],
      ),
    );

    if (result == 'scan_multi') {
      final details = <String, String>{
        'name': nameCtrl.text.trim(),
        'category': categoryCtrl.text.trim(),
        'brand': brandCtrl.text.trim(),
        'threshold': thresholdCtrl.text.trim(),
        'purchaseCost': purchaseCtrl.text.trim(),
        'sellingPrice': sellCtrl.text.trim(),
      };
      await _openMultiScan(details: details, initialBarcodes: const []);
      return;
    }

    if (result == 'save' && nameCtrl.text.trim().isNotEmpty) {
      final barcode = barcodeCtrl.text.trim();
      if (barcode.isNotEmpty && !await _barcodeAvailable(barcode)) {
        if (mounted) _showBarcodeTaken(barcode);
        return;
      }
      final acc = await _repo.create(
        name: nameCtrl.text.trim(),
        category: categoryCtrl.text.trim(),
        brand: brandCtrl.text.trim(),
        purchasePrice: double.tryParse(purchaseCtrl.text.trim()) ?? 0,
        sellingPrice: double.tryParse(sellCtrl.text.trim()) ?? 0,
        lowStockThreshold: double.tryParse(thresholdCtrl.text.trim()) ?? 3,
        barcode: barcode.isEmpty ? null : barcode,
      );
      final qty = double.tryParse(quantityCtrl.text.trim()) ?? 0;
      if (qty > 0) {
        await _repo.recordPurchase(
          accessoryId: acc.id,
          quantity: qty,
          unitCost: double.tryParse(purchaseCtrl.text.trim()) ?? 0,
          date: DateTime.now(),
        );
      }
      _load();
    }
  }

  /// Restock / Adjust / Edit / Delete menu for a single accessory (Edit is
  /// how the low-stock threshold - and other details - can now be changed
  /// after creation, which previously wasn't possible).
  Future<void> _showActions(Accessory a, AuthService auth) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('View Details / Stock History'),
              onTap: () => Navigator.pop(context, 'details'),
            ),
            ListTile(
              leading: const Icon(Icons.add_shopping_cart_rounded),
              title: const Text('Record Purchase'),
              onTap: () => Navigator.pop(context, 'purchase'),
            ),
            if (auth.isAdmin)
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Adjust Stock'),
                onTap: () => Navigator.pop(context, 'adjust'),
              ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            if (auth.canDelete)
              ListTile(
                leading: const Icon(Icons.delete_rounded, color: AppColors.danger),
                title: const Text('Delete', style: TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'details') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(kind: ProductKind.accessory, id: a.id)));
      _load();
    } else if (action == 'purchase') {
      await _recordPurchase(a);
    } else if (action == 'adjust') {
      await _adjustStock(a);
    } else if (action == 'edit') {
      await _editAccessory(a);
    } else if (action == 'delete') {
      await _deleteAccessory(a);
    }
  }

  /// Lets the shop edit an already-created accessory - most importantly the
  /// low-stock threshold, which previously could only be set at creation.
  Future<void> _editAccessory(Accessory a) async {
    final nameCtrl = TextEditingController(text: a.name);
    final categoryCtrl = TextEditingController(text: a.category ?? '');
    final brandCtrl = TextEditingController(text: a.brand ?? '');
    final sellCtrl = TextEditingController(text: a.sellingPrice.toStringAsFixed(0));
    final thresholdCtrl = TextEditingController(text: a.lowStockThreshold.toStringAsFixed(0));
    final barcodeCtrl = TextEditingController(text: a.barcode ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Accessory'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Category')),
              const SizedBox(height: 10),
              TextField(controller: brandCtrl, decoration: const InputDecoration(labelText: 'Brand')),
              const SizedBox(height: 10),
              TextField(controller: sellCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Selling Price (₹)')),
              const SizedBox(height: 10),
              TextField(controller: thresholdCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Low Stock Threshold')),
              const SizedBox(height: 10),
              _barcodeField(barcodeCtrl, nameCtrl),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok == true) {
      final barcode = barcodeCtrl.text.trim();
      if (barcode.isNotEmpty && !await _barcodeAvailable(barcode, excludingId: a.id)) {
        if (mounted) _showBarcodeTaken(barcode);
        return;
      }
      await _repo.update(
        id: a.id,
        name: nameCtrl.text.trim().isEmpty ? a.name : nameCtrl.text.trim(),
        category: categoryCtrl.text.trim(),
        brand: brandCtrl.text.trim(),
        sellingPrice: double.tryParse(sellCtrl.text.trim()) ?? a.sellingPrice,
        lowStockThreshold: double.tryParse(thresholdCtrl.text.trim()) ?? a.lowStockThreshold,
        barcode: barcode.isEmpty ? null : barcode,
      );
      _load();
    }
  }

  /// Admin/permission-gated Delete (spec: small confirmation dialog).
  Future<void> _deleteAccessory(Accessory a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Accessory?'),
        content: Text('${a.name} will be removed from the list. This cannot be undone from here.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _repo.delete(a.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Accessory deleted')));
      }
      _load();
    }
  }

  Future<void> _recordPurchase(Accessory a) async {
    final qtyCtrl = TextEditingController(text: '1');
    final costCtrl = TextEditingController(text: a.purchasePrice.toStringAsFixed(0));
    final batchCtrl = TextEditingController();
    final invoiceCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Purchase: ${a.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
              const SizedBox(height: 10),
              TextField(controller: costCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Unit Cost (₹)')),
              const SizedBox(height: 10),
              TextField(controller: batchCtrl, decoration: const InputDecoration(labelText: 'Batch Number (optional)')),
              const SizedBox(height: 10),
              TextField(controller: invoiceCtrl, decoration: const InputDecoration(labelText: 'Invoice Number (optional)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add Stock')),
        ],
      ),
    );
    if (ok == true) {
      await _repo.recordPurchase(
        accessoryId: a.id,
        quantity: double.tryParse(qtyCtrl.text.trim()) ?? 0,
        unitCost: double.tryParse(costCtrl.text.trim()) ?? 0,
        date: DateTime.now(),
        batchNumber: batchCtrl.text.trim().isEmpty ? null : batchCtrl.text.trim(),
        invoiceNumber: invoiceCtrl.text.trim().isEmpty ? null : invoiceCtrl.text.trim(),
      );
      _load();
    }
  }

  /// Admin-only Stock Adjustment with a specific-reason dropdown (spec item
  /// 7) - accessories previously had no adjustment flow at all.
  Future<void> _adjustStock(Accessory a) async {
    final qtyCtrl = TextEditingController(text: '0');
    final notesCtrl = TextEditingController();
    String reason = _adjustReasons.first;

    void bump(void Function(void Function()) setLocalState, int delta) {
      final current = double.tryParse(qtyCtrl.text.trim()) ?? 0;
      setLocalState(() => qtyCtrl.text = (current + delta).toStringAsFixed(current % 1 == 0 ? 0 : 2));
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text('Adjust Stock: ${a.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: reason,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: _adjustReasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) => setLocalState(() => reason = v ?? reason),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded, size: 32, color: AppColors.danger),
                      tooltip: 'Decrease',
                      onPressed: () => bump(setLocalState, -1),
                    ),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: qtyCtrl,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                        decoration: const InputDecoration(labelText: 'Quantity (+ / -)'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 32, color: AppColors.success),
                      tooltip: 'Increase',
                      onPressed: () => bump(setLocalState, 1),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (ok == true) {
      final qty = double.tryParse(qtyCtrl.text.trim()) ?? 0;
      if (a.currentStock + qty < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Stock cannot go below zero (only ${a.currentStock.toStringAsFixed(0)} ${a.unit} available).')));
        }
        return;
      }
      final note = notesCtrl.text.trim().isEmpty ? reason : '$reason - ${notesCtrl.text.trim()}';
      await _repo.adjustStock(
        accessoryId: a.id,
        quantity: qty,
        notes: note,
        date: DateTime.now(),
      );
      _load();
    }
  }
}
