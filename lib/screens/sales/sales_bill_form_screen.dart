import 'package:flutter/material.dart';

import '../../core/repositories/accessory_repository.dart';
import '../../core/repositories/customer_repository.dart';
import '../../core/repositories/sales_repository.dart';
import '../../core/utils/formatters.dart';
import '../../models/accessory.dart';
import '../../widgets/section_card.dart';

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

  final _customerNameCtrl = TextEditingController(text: 'Walk-in Customer');
  final _customerPhoneCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _paidCtrl = TextEditingController(text: '0');
  String _paymentMethod = 'Cash';

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
            TextField(controller: _customerNameCtrl, decoration: const InputDecoration(labelText: 'Customer Name')),
            const SizedBox(height: 10),
            TextField(controller: _customerPhoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (optional)')),
          ]),
          SectionCard(
            title: 'Products',
            icon: Icons.shopping_bag_rounded,
            trailing: TextButton.icon(onPressed: _addLine, icon: const Icon(Icons.add, size: 16), label: const Text('Add')),
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
      setState(() {
        _cart.add(_CartLine(selected, double.tryParse(qtyCtrl.text.trim()) ?? 1, double.tryParse(rateCtrl.text.trim()) ?? selected.sellingPrice));
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
    );

    if (mounted) Navigator.pop(context, true);
  }
}
