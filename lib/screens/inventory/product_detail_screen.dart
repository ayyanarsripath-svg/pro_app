import 'package:flutter/material.dart';

import '../../core/repositories/accessory_repository.dart';
import '../../core/repositories/spare_part_repository.dart';
import '../../core/services/barcode_generator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/accessory.dart';
import '../../models/spare_part.dart';
import '../../widgets/section_card.dart';
import 'barcode_label_screen.dart';
import 'barcode_scanner_screen.dart';

enum ProductKind { sparePart, accessory }

/// Product Details page (spec item 10): Name, Brand, Model, Category,
/// Barcode, Purchase Price, Selling Price, Current Stock, Minimum Stock,
/// Total Purchased, Total Sold, Total Used in Service, and the full Stock
/// History table - opened from the Inventory Search/Scan screen, or by
/// tapping a spare part / accessory directly. Works for both product types
/// since they share almost every one of these fields.
class ProductDetailScreen extends StatefulWidget {
  final ProductKind kind;
  final String id;

  const ProductDetailScreen({super.key, required this.kind, required this.id});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _StockRow {
  final DateTime date;
  final String type;
  final double qty;
  final double balance;
  _StockRow(this.date, this.type, this.qty, this.balance);
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _sparePartRepo = SparePartRepository();
  final _accessoryRepo = AccessoryRepository();

  bool _loading = true;
  SparePart? _part;
  Accessory? _accessory;
  List<_StockRow> _history = [];
  double _totalPurchased = 0;
  double _totalSold = 0; // accessories: 'sale'; spare parts: service+2nd-hand usage
  double _totalOther = 0; // adjustments / returns, net

  bool get _isSparePart => widget.kind == ProductKind.sparePart;
  String? get _barcode => _isSparePart ? _part?.barcode : _accessory?.barcode;
  String get _name => _isSparePart ? (_part?.name ?? '') : (_accessory?.name ?? '');
  double get _sellingPrice => _isSparePart ? (_part?.avgPurchaseCost ?? 0) : (_accessory?.sellingPrice ?? 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (_isSparePart) {
      final part = await _sparePartRepo.byId(widget.id);
      final txns = await _sparePartRepo.transactionsFor(widget.id);
      _buildHistory(txns.map((t) => (t.txnDate, t.txnType, t.quantity)).toList());
      _totalPurchased = txns.where((t) => t.txnType == 'purchase').fold(0, (s, t) => s + t.quantity);
      _totalSold = txns
          .where((t) => t.txnType == 'service_usage' || t.txnType == 'second_hand_usage')
          .fold(0, (s, t) => s + t.quantity.abs());
      _totalOther = txns.where((t) => t.txnType == 'adjustment' || t.txnType == 'supplier_return').fold(0, (s, t) => s + t.quantity);
      setState(() {
        _part = part;
        _loading = false;
      });
    } else {
      final acc = await _accessoryRepo.byId(widget.id);
      final txns = await _accessoryRepo.transactionsFor(widget.id);
      _buildHistory(txns.map((t) => (t.txnDate, t.txnType, t.quantity)).toList());
      _totalPurchased = txns.where((t) => t.txnType == 'purchase').fold(0, (s, t) => s + t.quantity);
      _totalSold = txns.where((t) => t.txnType == 'sale').fold(0, (s, t) => s + t.quantity.abs());
      _totalOther = txns.where((t) => t.txnType == 'adjustment' || t.txnType == 'sales_return' || t.txnType == 'stock_return').fold(0, (s, t) => s + t.quantity);
      setState(() {
        _accessory = acc;
        _loading = false;
      });
    }
  }

  void _buildHistory(List<(DateTime, String, double)> txns) {
    double running = 0;
    final rows = <_StockRow>[];
    for (final t in txns) {
      running += t.$3;
      rows.add(_StockRow(t.$1, _labelFor(t.$2), t.$3, running));
    }
    _history = rows.reversed.toList();
  }

  String _labelFor(String txnType) {
    switch (txnType) {
      case 'purchase':
        return 'Purchase';
      case 'sale':
        return 'Sale';
      case 'service_usage':
        return 'Used in Service';
      case 'second_hand_usage':
        return 'Used (2nd Hand Repair)';
      case 'adjustment':
        return 'Adjustment';
      case 'supplier_return':
        return 'Return to Supplier';
      case 'sales_return':
        return 'Sales Return';
      case 'stock_return':
        return 'Stock Return';
      default:
        return txnType;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_part == null && _accessory == null) {
      return const Scaffold(body: Center(child: Text('Product not found')));
    }

    final currentStock = _isSparePart ? _part!.currentStock : _accessory!.currentStock;
    final minStock = _isSparePart ? _part!.lowStockThreshold : _accessory!.lowStockThreshold;
    final isLow = _isSparePart ? _part!.isLowStock : _accessory!.isLowStock;
    final isOut = _isSparePart ? _part!.isOutOfStock : _accessory!.isOutOfStock;
    final category = _isSparePart ? _part!.category : _accessory!.category;
    final modelOrBrand = _isSparePart ? _part!.compatibleModel : _accessory!.brand;
    final purchasePrice = _isSparePart ? _part!.avgPurchaseCost : _accessory!.purchasePrice;

    return Scaffold(
      appBar: AppBar(title: Text(_name)),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          SectionCard(title: 'Product Details', icon: Icons.inventory_2_rounded, children: [
            _row('Name', _name),
            if (category != null && category.isNotEmpty) _row('Category', category),
            if (modelOrBrand != null && modelOrBrand.isNotEmpty) _row(_isSparePart ? 'Compatible Model' : 'Brand', modelOrBrand),
            _row('Barcode', _barcode ?? 'Not assigned'),
            _row('Purchase Price', formatCurrency(purchasePrice)),
            if (!_isSparePart) _row('Selling Price', formatCurrency(_sellingPrice)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Current Stock', style: TextStyle(color: AppColors.textSecondaryOf(context))),
                Text(
                  '${currentStock.toStringAsFixed(0)} ${_isSparePart ? _part!.unit : _accessory!.unit}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: isOut ? AppColors.danger : (isLow ? AppColors.warning : AppColors.textPrimaryOf(context))),
                ),
              ],
            ),
            if (isOut) const Padding(padding: EdgeInsets.only(top: 4), child: Text('OUT OF STOCK', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800, fontSize: 12)))
            else if (isLow) const Padding(padding: EdgeInsets.only(top: 4), child: Text('LOW STOCK', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w800, fontSize: 12))),
            _row('Minimum Stock Level', minStock.toStringAsFixed(0)),
          ]),
          SectionCard(title: 'Usage Summary', icon: Icons.bar_chart_rounded, children: [
            _row('Total Purchased', _totalPurchased.toStringAsFixed(0)),
            _row(_isSparePart ? 'Total Used in Service' : 'Total Sold', _totalSold.toStringAsFixed(0)),
            _row('Other Movements (Adjustments/Returns)', _totalOther.toStringAsFixed(0)),
          ]),
          SectionCard(
            title: 'Barcode',
            icon: Icons.qr_code_rounded,
            trailing: TextButton(onPressed: _assignBarcode, child: Text(_barcode == null ? 'Assign' : 'Change')),
            children: [
              if (_barcode != null)
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BarcodeLabelScreen(productName: _name, model: modelOrBrand, barcode: _barcode!, sellingPrice: _isSparePart ? null : _sellingPrice),
                    ),
                  ),
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('View / Print Label'),
                )
              else
                Text('No barcode assigned yet.', style: TextStyle(color: AppColors.textSecondaryOf(context))),
            ],
          ),
          SectionCard(title: 'Stock History', icon: Icons.history_rounded, children: [
            if (_history.isEmpty) Text('No stock movements yet.', style: TextStyle(color: AppColors.textSecondaryOf(context))),
            if (_history.isNotEmpty)
              Table(
                columnWidths: const {0: FlexColumnWidth(1.3), 1: FlexColumnWidth(1.4), 2: FlexColumnWidth(0.8), 3: FlexColumnWidth(0.9)},
                children: [
                  TableRow(children: [
                    _th('Date'),
                    _th('Type'),
                    _th('Qty'),
                    _th('Balance'),
                  ]),
                  ..._history.map((r) => TableRow(children: [
                        _td(formatDate(r.date)),
                        _td(r.type),
                        _td('${r.qty > 0 ? '+' : ''}${r.qty.toStringAsFixed(0)}', color: r.qty < 0 ? AppColors.danger : AppColors.success),
                        _td(r.balance.toStringAsFixed(0)),
                      ])),
                ],
              ),
          ]),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: AppColors.textSecondaryOf(context))),
            Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );

  Widget _th(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.textSecondaryOf(context))),
      );

  Widget _td(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      );

  Future<void> _assignBarcode() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.qr_code_scanner_rounded), title: const Text('Scan Existing Barcode'), onTap: () => Navigator.pop(context, 'scan')),
          ListTile(leading: const Icon(Icons.auto_awesome_rounded), title: const Text('Generate New Barcode'), onTap: () => Navigator.pop(context, 'generate')),
        ]),
      ),
    );
    if (!mounted || choice == null) return;

    String? code;
    if (choice == 'scan') {
      code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const BarcodeScannerScreen(title: 'Scan Product Barcode')));
    } else {
      code = await BarcodeGenerator.generate(_name);
    }
    if (code == null || code.isEmpty) return;
    if (!mounted) return;

    final available = _isSparePart
        ? await _sparePartRepo.isBarcodeAvailable(code, excludingId: widget.id) && await _accessoryRepo.isBarcodeAvailable(code)
        : await _accessoryRepo.isBarcodeAvailable(code, excludingId: widget.id) && await _sparePartRepo.isBarcodeAvailable(code);
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Barcode "$code" is already used by another product.')));
      }
      return;
    }
    if (_isSparePart) {
      await _sparePartRepo.setBarcode(widget.id, code);
    } else {
      await _accessoryRepo.setBarcode(widget.id, code);
    }
    _load();
  }
}
