import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/repositories/accessory_repository.dart';
import '../../core/repositories/spare_part_repository.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/barcode_generator.dart';
import '../../core/theme/app_theme.dart';
import '../../models/accessory.dart';
import '../../widgets/section_card.dart';
import 'barcode_scanner_screen.dart';
import 'product_detail_screen.dart';

class AccessoriesScreen extends StatefulWidget {
  const AccessoriesScreen({super.key});

  @override
  State<AccessoriesScreen> createState() => _AccessoriesScreenState();
}

class _AccessoriesScreenState extends State<AccessoriesScreen> {
  final _repo = AccessoryRepository();
  final _sparePartRepo = SparePartRepository();
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

    final accessory = await _repo.findByBarcode(code);
    if (accessory != null) {
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(kind: ProductKind.accessory, id: accessory.id)));
      _load();
      return;
    }
    final part = await _sparePartRepo.findByBarcode(code);
    if (part != null) {
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(kind: ProductKind.sparePart, id: part.id)));
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

  Future<bool> _barcodeAvailable(String barcode, {String? excludingId}) async {
    final okHere = await _repo.isBarcodeAvailable(barcode, excludingId: excludingId);
    if (!okHere) return false;
    return _sparePartRepo.isBarcodeAvailable(barcode);
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

  Future<void> _addAccessory({String? presetBarcode}) async {
    final nameCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final brandCtrl = TextEditingController();
    final purchaseCtrl = TextEditingController();
    final sellCtrl = TextEditingController();
    final thresholdCtrl = TextEditingController(text: '3');
    final barcodeCtrl = TextEditingController(text: presetBarcode ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Accessory'),
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
              TextField(controller: purchaseCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Purchase Price (₹)')),
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

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final barcode = barcodeCtrl.text.trim();
      if (barcode.isNotEmpty && !await _barcodeAvailable(barcode)) {
        if (mounted) _showBarcodeTaken(barcode);
        return;
      }
      await _repo.create(
        name: nameCtrl.text.trim(),
        category: categoryCtrl.text.trim(),
        brand: brandCtrl.text.trim(),
        purchasePrice: double.tryParse(purchaseCtrl.text.trim()) ?? 0,
        sellingPrice: double.tryParse(sellCtrl.text.trim()) ?? 0,
        lowStockThreshold: double.tryParse(thresholdCtrl.text.trim()) ?? 3,
        barcode: barcode.isEmpty ? null : barcode,
      );
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
