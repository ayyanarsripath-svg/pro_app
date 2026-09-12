import 'package:flutter/material.dart';

import '../../core/repositories/accessory_repository.dart';
import '../../core/repositories/customer_repository.dart';
import '../../core/repositories/sales_repository.dart';
import '../../core/utils/formatters.dart';
import '../../models/accessory.dart';
import '../../widgets/section_card.dart';
import '../inventory/barcode_scanner_screen.dart';

class _CartLine {
  final Accessory accessory;
  double quantity;
  double rate;
  _CartLine(this.accessory, this.quantity, this.rate);
  double get total => quantity * rate;
}

class SalesBillFormScreen extends StatefulWidget {
  const SalesBillFormScreen({super.key});

  @override
  State<SalesBillFormScreen> createState() => _SalesBillFormScreenState();
}

class _SalesBillFormScreenState extends State<SalesBillFormScreen> {
  final _accessoryRepo = AccessoryRepository();
  final _customerRepo = CustomerRepository();
  final _salesRepo = SalesRepository();

  final _customerNameCtrl = TextEditingController();
  final _customerPhoneCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _paidCtrl = TextEditingController(text: '0');
  String _paymentMethod = 'Cash';
  // Warranty toggle + period (spec: "warranty option ... warranty period in
  // days ... on pannalana Nil nu mention pannu") - prints the period on
  // the bill when on, "Nil" when off (see PdfService.buildSalesBill).
  bool _warranty = false;
  final _warrantyPeriodCtrl = TextEditingController();

  List<Accessory> _accessories = [];
  final List<_CartLine> _cart = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _accessoryRepo.all().then((v) => setState(() => _accessories = v));
  }

  double get _subtotal => _cart.fold(0, (s, l) => s + l.total);
  double get _discount => double.tryParse(_discountCtrl.text.trim()) ?? 0;
  double get _total => (_subtotal - _discount).clamp(0, double.infinity);
  double get _paid => double.tryParse(_paidCtrl.text.trim()) ?? 0;
  double get _balance => _total - _paid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Sales Bill')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          SectionCard(title: 'Customer', icon: Icons.person_rounded, children: [
            TextField(controller: _customerNameCtrl, decoration: const InputDecoration(labelText: 'Customer Name', hintText: 'Walk-in Customer')),
            const SizedBox(height: 10),
            TextField(controller: _customerPhoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional)')),
          ]),
          SectionCard(
            title: 'Products',
            icon: Icons.shopping_bag_rounded,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _scanAndAddLine,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                  tooltip: 'Scan Barcode',
                  visualDensity: VisualDensity.compact,
                ),
                TextButton.icon(onPressed: _addLine, icon: const Icon(Icons.add, size: 16), label: const Text('Add')),
              ],
            ),
            children: [
              if (_cart.isEmpty) const Text('No products added', style: TextStyle(color: Colors.grey)),
              ..._cart.map((line) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(line.accessory.name),
                    subtitle: Text('${line.quantity.toStringAsFixed(0)} x ${formatCurrency(line.rate)}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(formatCurrency(line.total)),
                        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _cart.remove(line))),
                      ],
                    ),
                  )),
            ],
          ),
          SectionCard(title: 'Bill Summary', icon: Icons.receipt_rounded, children: [
            _summaryRow('Subtotal', _subtotal),
            TextField(controller: _discountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Discount (₹)'), onChanged: (_) => setState(() {})),
            _summaryRow('Total', _total, bold: true),
            const SizedBox(height: 10),
            TextField(controller: _paidCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Paid (₹)'), onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _paymentMethod,
              items: ['Cash', 'UPI', 'Card', 'Bank Transfer'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (v) => setState(() => _paymentMethod = v ?? 'Cash'),
              decoration: const InputDecoration(labelText: 'Payment Method'),
            ),
            const SizedBox(height: 6),
            _summaryRow('Balance', _balance, bold: true),
          ]),
          SectionCard(title: 'Warranty', icon: Icons.verified_user_rounded, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Warranty'),
              subtitle: Text(_warranty ? 'Warranty period will print on the bill' : 'Bill will print "Nil" for warranty'),
              value: _warranty,
              onChanged: (v) => setState(() => _warranty = v),
            ),
            if (_warranty) ...[
              const SizedBox(height: 4),
              TextField(
                controller: _warrantyPeriodCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Warranty Period (in days)'),
              ),
            ],
          ]),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: (_cart.isEmpty || _saving) ? null : _submit,
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Create Sales Bill'),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, double value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
            Text(formatCurrency(value), style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          ],
        ),
      );

  /// Sales Bill "Scan Barcode" (spec item 6): scans an accessory's barcode
  /// and auto-adds it to the cart, updating stock the same way a manual Add
  /// does once the bill is saved. Re-scanning an item already in the cart
  /// bumps its quantity by 1 instead of adding a second line for it.
  Future<void> _scanAndAddLine() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const BarcodeScannerScreen(title: 'Scan Product Barcode')));
    if (code == null || code.isEmpty || !mounted) return;

    final accessory = await _accessoryRepo.findByBarcode(code);
    if (!mounted) return;
    if (accessory == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No accessory found with barcode "$code".')));
      return;
    }
    if (accessory.isOutOfStock) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${accessory.name} is out of stock.')));
      return;
    }

    final existing = _cart.where((l) => l.accessory.id == accessory.id).toList();
    if (existing.isNotEmpty) {
      final line = existing.first;
      if (line.quantity + 1 > accessory.currentStock) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Only ${accessory.currentStock.toStringAsFixed(0)} ${accessory.name} available.')));
        return;
      }
      setState(() => line.quantity += 1);
    } else {
      setState(() => _cart.add(_CartLine(accessory, 1, accessory.sellingPrice)));
    }
    if (!_accessories.any((a) => a.id == accessory.id)) {
      setState(() => _accessories = [..._accessories, accessory]);
    }
  }

  Future<void> _addLine() async {
    if (_accessories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add accessories to inventory first')));
      return;
    }
    Accessory selected = _accessories.first;
    final qtyCtrl = TextEditingController(text: '1');
    final rateCtrl = TextEditingController(text: selected.sellingPrice.toStringAsFixed(0));

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Add Product'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Accessory>(
                value: selected,
                isExpanded: true,
                items: _accessories.map((a) => DropdownMenuItem(value: a, child: Text('${a.name} (stock: ${a.currentStock.toStringAsFixed(0)})'))).toList(),
                onChanged: (v) {
                  setLocalState(() {
                    selected = v!;
                    rateCtrl.text = selected.sellingPrice.toStringAsFixed(0);
                  });
                },
              ),
              TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
              TextField(controller: rateCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rate (₹)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );

    if (ok == true) {
      // Out of Stock Protection (spec item 13): never let a line push the
      // total quantity of one accessory across the cart above what's
      // actually in stock right now - clamp it and say so clearly instead
      // of silently accepting (or worse, letting stock go negative).
      final alreadyInCart = _cart.where((l) => l.accessory.id == selected.id).fold<double>(0, (s, l) => s + l.quantity);
      final requested = double.tryParse(qtyCtrl.text.trim()) ?? 1;
      final available = selected.currentStock - alreadyInCart;
      if (selected.isOutOfStock || available <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${selected.name} is out of stock.')));
        return;
      }
      final quantity = requested > available ? available : requested;
      if (requested > available) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Only ${available.toStringAsFixed(0)} ${selected.name} available - added $quantity.')));
      }
      setState(() {
        _cart.add(_CartLine(selected, quantity, double.tryParse(rateCtrl.text.trim()) ?? selected.sellingPrice));
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    final customer = await _customerRepo.findOrCreateByPhone(
      name: _customerNameCtrl.text.trim().isEmpty ? 'Walk-in Customer' : _customerNameCtrl.text.trim(),
      phone: _customerPhoneCtrl.text.trim().isEmpty ? null : _customerPhoneCtrl.text.trim(),
    );

    await _salesRepo.create(
      customerId: customer.id,
      saleDate: DateTime.now(),
      items: _cart
          .map((l) => SaleLineInput(accessoryId: l.accessory.id, itemName: l.accessory.name, quantity: l.quantity, rate: l.rate, cost: l.accessory.purchasePrice))
          .toList(),
      discount: _discount,
      paid: _paid,
      paymentMethod: _paymentMethod,
      warranty: _warranty,
      warrantyPeriodDays: _warranty ? int.tryParse(_warrantyPeriodCtrl.text.trim()) : null,
    );

    if (mounted) Navigator.pop(context, true);
  }
}
