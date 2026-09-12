import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/repositories/accessory_repository.dart';
import '../../core/repositories/spare_part_repository.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/barcode_generator.dart';
import '../../core/theme/app_theme.dart';
import '../../models/spare_part.dart';
import '../../widgets/section_card.dart';
import 'barcode_scanner_screen.dart';
import 'product_detail_screen.dart';

class SparePartsScreen extends StatefulWidget {
  const SparePartsScreen({super.key});

  @override
  State<SparePartsScreen> createState() => _SparePartsScreenState();
}

class _SparePartsScreenState extends State<SparePartsScreen> {
  final _repo = SparePartRepository();
  final _accessoryRepo = AccessoryRepository();
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

    final part = await _repo.findByBarcode(code);
    if (part != null) {
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(kind: ProductKind.sparePart, id: part.id)));
      _load();
      return;
    }
    final accessory = await _accessoryRepo.findByBarcode(code);
    if (accessory != null) {
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(kind: ProductKind.accessory, id: accessory.id)));
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

  Future<bool> _barcodeAvailable(String barcode, {String? excludingId}) async {
    final okHere = await _repo.isBarcodeAvailable(barcode, excludingId: excludingId);
    if (!okHere) return false;
    return _accessoryRepo.isBarcodeAvailable(barcode);
  }

  Future<void> _addPart({String? presetBarcode}) async {
    final nameCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final thresholdCtrl = TextEditingController(text: '2');
    final barcodeCtrl = TextEditingController(text: presetBarcode ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Spare Part'),
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
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final barcode = barcodeCtrl.text.trim();
      if (barcode.isNotEmpty && !await _barcodeAvailable(barcode)) {
        if (mounted) _showBarcodeTaken(barcode);
        return;
      }
      await _repo.create(
        name: nameCtrl.text.trim(),
        category: categoryCtrl.text.trim(),
        compatibleModel: modelCtrl.text.trim(),
        lowStockThreshold: double.tryParse(thresholdCtrl.text.trim()) ?? 2,
        barcode: barcode.isEmpty ? null : barcode,
      );
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
