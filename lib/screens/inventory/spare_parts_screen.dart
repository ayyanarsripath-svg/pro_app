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
import '../../models/spare_part.dart';
import '../../widgets/multi_field_voice_button.dart';
import '../../widgets/section_card.dart';
import 'barcode_scanner_screen.dart';
import 'multi_unit_scan_screen.dart';
import 'product_detail_screen.dart';

class SparePartsScreen extends StatefulWidget {
  const SparePartsScreen({super.key});

  @override
  State<SparePartsScreen> createState() => _SparePartsScreenState();
}

class _SparePartsScreenState extends State<SparePartsScreen> {
  final _repo = SparePartRepository();
  final _accessoryRepo = AccessoryRepository();
  final _barcodeRepo = ProductBarcodeRepository();
  final _draftRepo = ProductDraftRepository();
  final _searchCtrl = TextEditingController();
  List<SparePart> _parts = [];
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
    final parts = await _repo.all();
    setState(() {
      _parts = parts;
      _loading = false;
    });
  }

  List<SparePart> get _filtered {
    if (_query.trim().isEmpty) return _parts;
    final q = _query.trim().toLowerCase();
    return _parts.where((p) => p.name.toLowerCase().contains(q) || (p.barcode?.toLowerCase().contains(q) ?? false)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final visible = _filtered;
    final stockValue = _parts.fold<double>(0, (s, p) => s + p.stockValue);
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
                          decoration: InputDecoration(
                            hintText: 'Search Product or Barcode',
                            prefixIcon: const Icon(Icons.search_rounded),
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
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${_parts.length} Spare Parts', style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('Stock Value: ₹${stockValue.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryBlue)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (visible.isEmpty) EmptyState(icon: Icons.memory_rounded, message: _parts.isEmpty ? 'No spare parts yet' : 'No match found'),
                  ...visible.map((part) => Card(
                        child: ListTile(
                          title: Text(part.name),
                          subtitle: Text(
                            '${part.category ?? ''} ${part.compatibleModel ?? ''}\nAvg Cost: ₹${part.avgPurchaseCost.toStringAsFixed(0)}'
                            '${part.barcode != null ? '\nBarcode: ${part.barcode}' : ''}',
                          ),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${part.currentStock.toStringAsFixed(0)} ${part.unit}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: part.isOutOfStock ? AppColors.danger : (part.isLowStock ? AppColors.warning : AppColors.textPrimaryOf(context)))),
                              if (part.isOutOfStock)
                                const Text('OUT OF STOCK', style: TextStyle(color: AppColors.danger, fontSize: 10, fontWeight: FontWeight.w700))
                              else if (part.isLowStock)
                                const Text('LOW STOCK', style: TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w700)),
                            ],
                          ),
                          onTap: () => _showActions(part, auth),
                        ),
                      )),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addPart(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Part'),
      ),
    );
  }

  /// Inventory Search + Scan (spec item 10): scanning a barcode from this
  /// screen looks it up across BOTH spare parts and accessories (barcodes
  /// are one shared identity space) and opens its Product Details page. A
  /// barcode that matches nothing offers to create a new spare part with
  /// that barcode pre-filled instead of a bare "not found" dead end.
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
        content: Text('No product is registered with barcode "$code" yet. Create a new spare part with this barcode?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    if (create == true) await _addPart(presetBarcode: code);
  }

  /// Fast Continuous Scanning restock (spec item 12): scan the same box of
  /// parts one after another - each repeated scan of the same barcode bumps
  /// its running count by 1 - then apply everything as Purchase (Stock In)
  /// transactions at each part's existing average cost once Done is
  /// tapped. A barcode that doesn't match any known spare part is skipped
  /// with a warning rather than silently dropped.
  Future<void> _quickRestockScan() async {
    final counts = <String, int>{};
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BarcodeScannerScreen(
          continuous: true,
          title: 'Quick Restock - Scan Each Part',
          onScan: (code) => counts[code] = (counts[code] ?? 0) + 1,
          describeCode: (code) async {
            final resolved = await _barcodeRepo.resolve(code);
            if (resolved == null || resolved.type != ProductTypes.sparePart) return null;
            final part = resolved.sparePart!;
            return '${part.name} (stock: ${part.currentStock.toStringAsFixed(0)})';
          },
        ),
      ),
    );
    if (counts.isEmpty || !mounted) return;

    int applied = 0;
    final notFound = <String>[];
    for (final entry in counts.entries) {
      final resolved = await _barcodeRepo.resolve(entry.key);
      if (resolved == null || resolved.type != ProductTypes.sparePart) {
        notFound.add(entry.key);
        continue;
      }
      final part = resolved.sparePart!;
      await _repo.recordPurchase(
        sparePartId: part.id,
        quantity: entry.value.toDouble(),
        unitCost: part.avgPurchaseCost,
        date: DateTime.now(),
      );
      applied++;
    }
    _load();
    if (!mounted) return;
    final message = StringBuffer('Restocked $applied part(s).');
    if (notFound.isNotEmpty) message.write(' ${notFound.length} barcode(s) not found in inventory: ${notFound.join(', ')}');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message.toString())));
  }

  Future<bool> _barcodeAvailable(String barcode, {String? excludingId}) async {
    final okHere = await _repo.isBarcodeAvailable(barcode, excludingId: excludingId);
    if (!okHere) return false;
    final okThere = await _accessoryRepo.isBarcodeAvailable(barcode);
    if (!okThere) return false;
    // Also checks every individually-scanned unit barcode from the
    // multi-scan Add Product flow (product_barcodes), not just the two
    // legacy single-barcode columns above. excludingId (when editing) may
    // legitimately already own this exact barcode as one of its own
    // multi-scanned unit codes.
    return _barcodeRepo.isAvailable(barcode, excludingProductType: ProductTypes.sparePart, excludingProductId: excludingId);
  }

  /// Applies whatever VoiceProductParser recognized straight onto the
  /// dialog's own TextEditingControllers - a TextField already redraws on
  /// its controller changing, no setState needed. Always shows what was
  /// heard so the shop can glance over (and correct) the fields before
  /// saving - voice recognition + this heuristic can both be wrong (spec:
  /// "ethula extra ethana add pannaumna ethapathina full details analysis
  /// panni add pannikka").
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
          'You have an unfinished Spare Part entry "${(name == null || name.isEmpty) ? '(unnamed)' : name}" '
          'with ${(draft.barcodes as List).length} barcode(s) already scanned. Resume it, or start a new one instead?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Start New')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Resume')),
        ],
      ),
    );
  }

  /// Step 2 of the multi-scan Add Product flow (spec: scan every physical
  /// unit's own barcode/QR, one product with quantity = however many were
  /// scanned) - see MultiUnitScanScreen's class doc comment for the full
  /// resumable-draft design.
  Future<void> _openMultiScan({required Map<String, String> details, required List<String> initialBarcodes}) async {
    await _draftRepo.save(productType: ProductTypes.sparePart, details: details, barcodes: initialBarcodes);
    if (!mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MultiUnitScanScreen(
          productType: ProductTypes.sparePart,
          details: details,
          initialBarcodes: initialBarcodes,
          title: 'Scan Units - ${details['name'] ?? ''}',
          onFinalize: (barcodes) async {
            final part = await _repo.create(
              name: details['name'] ?? '',
              category: details['category'],
              compatibleModel: details['compatibleModel'],
              lowStockThreshold: double.tryParse(details['threshold'] ?? '') ?? 2,
              barcode: barcodes.isNotEmpty ? barcodes.first : null,
            );
            await _repo.recordPurchase(
              sparePartId: part.id,
              quantity: barcodes.length.toDouble(),
              unitCost: double.tryParse(details['purchaseCost'] ?? '') ?? 0,
              date: DateTime.now(),
            );
            await _barcodeRepo.attachMany(productType: ProductTypes.sparePart, productId: part.id, barcodes: barcodes);
          },
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _addPart({String? presetBarcode}) async {
    // Resume-or-discard check first (spec: "naduvula back vantha entire
    // process cancel aagakudathu resume aaganum") - only offered when there
    // isn't already a presetBarcode flow in progress (that path always
    // starts a fresh entry, e.g. from Scan-to-Find's "Create" button).
    if (presetBarcode == null) {
      final existingDraft = await _draftRepo.load(ProductTypes.sparePart);
      if (existingDraft != null) {
        final resume = await _askResumeDraft(existingDraft);
        if (!mounted) return;
        if (resume == true) {
          await _openMultiScan(details: existingDraft.details, initialBarcodes: existingDraft.barcodes);
          return;
        }
        await _draftRepo.clear(ProductTypes.sparePart);
      }
    }

    final nameCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final thresholdCtrl = TextEditingController(text: '2');
    final quantityCtrl = TextEditingController(text: '0');
    final purchaseCtrl = TextEditingController(text: '0');
    final barcodeCtrl = TextEditingController(text: presetBarcode ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('Add Spare Part')),
            MultiFieldVoiceButton(
              onHeard: (heard) => _fillFromVoice(
                heard,
                nameCtrl: nameCtrl,
                quantityCtrl: quantityCtrl,
                purchaseCtrl: purchaseCtrl,
                thresholdCtrl: thresholdCtrl,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name (e.g. Samsung A15 Display)')),
              const SizedBox(height: 10),
              TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Category')),
              const SizedBox(height: 10),
              TextField(controller: modelCtrl, decoration: const InputDecoration(labelText: 'Compatible Model')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: TextField(controller: quantityCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: purchaseCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Purchase Cost (₹/unit)'))),
                ],
              ),
              const SizedBox(height: 10),
              TextField(controller: thresholdCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Low Stock Alert Threshold')),
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
        'compatibleModel': modelCtrl.text.trim(),
        'threshold': thresholdCtrl.text.trim(),
        'purchaseCost': purchaseCtrl.text.trim(),
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
      final part = await _repo.create(
        name: nameCtrl.text.trim(),
        category: categoryCtrl.text.trim(),
        compatibleModel: modelCtrl.text.trim(),
        lowStockThreshold: double.tryParse(thresholdCtrl.text.trim()) ?? 2,
        barcode: barcode.isEmpty ? null : barcode,
      );
      final qty = double.tryParse(quantityCtrl.text.trim()) ?? 0;
      if (qty > 0) {
        await _repo.recordPurchase(
          sparePartId: part.id,
          quantity: qty,
          unitCost: double.tryParse(purchaseCtrl.text.trim()) ?? 0,
          date: DateTime.now(),
        );
      }
      _load();
    }
  }

  /// A barcode text field with Scan + Generate buttons alongside it (spec
  /// items 4/5/16): scan saves an existing manufacturer barcode as-is;
  /// Generate calls [BarcodeGenerator] for a part that doesn't have one.
  /// Just a plain field otherwise - editable by hand too.
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

  void _showBarcodeTaken(String barcode) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Barcode "$barcode" is already assigned to another product.')));
  }

  Future<void> _showActions(SparePart part, AuthService auth) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.info_outline_rounded), title: const Text('View Details / Stock History'), onTap: () => Navigator.pop(context, 'details')),
          ListTile(leading: const Icon(Icons.add_box_rounded), title: const Text('Record Purchase (Stock In)'), onTap: () => Navigator.pop(context, 'purchase')),
          if (auth.isAdmin) ListTile(leading: const Icon(Icons.tune_rounded), title: const Text('Adjust Stock'), onTap: () => Navigator.pop(context, 'adjust')),
          ListTile(leading: const Icon(Icons.assignment_return_rounded), title: const Text('Return to Supplier'), onTap: () => Navigator.pop(context, 'return')),
          ListTile(leading: const Icon(Icons.edit_rounded), title: const Text('Edit'), onTap: () => Navigator.pop(context, 'edit')),
          if (auth.canDelete)
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: AppColors.danger),
              title: const Text('Delete', style: TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
        ]),
      ),
    );
    if (!mounted) return;
    if (action == 'details') await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(kind: ProductKind.sparePart, id: part.id)));
    if (action == 'purchase') await _recordPurchase(part);
    if (action == 'adjust') await _adjustStock(part);
    if (action == 'return') await _returnToSupplier(part);
    if (action == 'edit') await _editPart(part);
    if (action == 'delete') await _deletePart(part);
    _load();
  }

  /// Lets the shop edit an existing spare part's details/threshold.
  Future<void> _editPart(SparePart part) async {
    final nameCtrl = TextEditingController(text: part.name);
    final categoryCtrl = TextEditingController(text: part.category ?? '');
    final modelCtrl = TextEditingController(text: part.compatibleModel ?? '');
    final thresholdCtrl = TextEditingController(text: part.lowStockThreshold.toStringAsFixed(0));
    final barcodeCtrl = TextEditingController(text: part.barcode ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Spare Part'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Category')),
              const SizedBox(height: 10),
              TextField(controller: modelCtrl, decoration: const InputDecoration(labelText: 'Compatible Model')),
              const SizedBox(height: 10),
              TextField(controller: thresholdCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Low Stock Alert Threshold')),
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
      if (barcode.isNotEmpty && !await _barcodeAvailable(barcode, excludingId: part.id)) {
        if (mounted) _showBarcodeTaken(barcode);
        return;
      }
      await _repo.update(
        id: part.id,
        name: nameCtrl.text.trim().isEmpty ? part.name : nameCtrl.text.trim(),
        category: categoryCtrl.text.trim(),
        compatibleModel: modelCtrl.text.trim(),
        lowStockThreshold: double.tryParse(thresholdCtrl.text.trim()) ?? part.lowStockThreshold,
        barcode: barcode.isEmpty ? null : barcode,
      );
      _load();
    }
  }

  /// Admin/permission-gated Delete (spec: small confirmation dialog).
  Future<void> _deletePart(SparePart part) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Spare Part?'),
        content: Text('${part.name} will be removed from the list. This cannot be undone from here.'),
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
      await _repo.delete(part.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Spare part deleted')));
      }
      _load();
    }
  }

  Future<void> _returnToSupplier(SparePart part) async {
    final qtyCtrl = TextEditingController(text: '1');
    final notesCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Return to Supplier: ${part.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
            const SizedBox(height: 10),
            TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Reason')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Return')),
        ],
      ),
    );
    if (ok == true) {
      final qty = double.tryParse(qtyCtrl.text.trim()) ?? 0;
      if (qty > part.currentStock) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Only ${part.currentStock.toStringAsFixed(0)} ${part.unit} in stock.')));
        }
        return;
      }
      await _repo.returnToSupplier(
        sparePartId: part.id,
        quantity: qty,
        date: DateTime.now(),
        notes: notesCtrl.text.trim(),
      );
      _load();
    }
  }

  Future<void> _recordPurchase(SparePart part) async {
    final qtyCtrl = TextEditingController(text: '1');
    final costCtrl = TextEditingController(text: part.avgPurchaseCost.toStringAsFixed(0));
    final batchCtrl = TextEditingController();
    final invoiceCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Purchase: ${part.name}'),
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
        sparePartId: part.id,
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
  /// 7: Damaged / Lost / Used internally / Returned / Wrong stock entry /
  /// Physical stock correction) instead of only a free-text note - the
  /// chosen reason is stored as the transaction's notes so Stock History
  /// keeps showing exactly why the count changed.
  Future<void> _adjustStock(SparePart part) async {
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
          title: Text('Adjust Stock: ${part.name}'),
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
      if (part.currentStock + qty < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Stock cannot go below zero (only ${part.currentStock.toStringAsFixed(0)} ${part.unit} available).')));
        }
        return;
      }
      final note = notesCtrl.text.trim().isEmpty ? reason : '$reason - ${notesCtrl.text.trim()}';
      await _repo.adjustStock(
        sparePartId: part.id,
        quantity: qty,
        notes: note,
        date: DateTime.now(),
      );
      _load();
    }
  }
}
