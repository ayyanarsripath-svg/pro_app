import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/repositories/customer_repository.dart';
import '../../core/repositories/sales_repository.dart';
import '../../core/services/pdf_service.dart';
import '../../core/utils/formatters.dart';
import '../../models/sales_bill.dart';
import '../../widgets/section_card.dart';
import 'sales_bill_form_screen.dart';

class SalesListScreen extends StatefulWidget {
  const SalesListScreen({super.key});

  @override
  State<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends State<SalesListScreen> {
  final _repo = SalesRepository();
  final _customerRepo = CustomerRepository();
  final _pdfService = PdfService();
  List<SalesBill> _bills = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final bills = await _repo.all();
    setState(() {
      _bills = bills;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _bills.isEmpty
              ? const EmptyState(icon: Icons.receipt_long_rounded, message: 'No sales bills yet')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: _bills.length,
                    itemBuilder: (context, i) {
                      final b = _bills[i];
                      return Card(
                        child: ListTile(
                          title: Text('${b.billNo}  •  ${formatCurrency(b.total)}'),
                          subtitle: Text('${formatDate(b.saleDate)}  •  ${b.paymentMethod ?? '-'}${b.balance > 0 ? '  •  Balance: ${formatCurrency(b.balance)}' : ''}'),
                          trailing: IconButton(icon: const Icon(Icons.print_rounded), onPressed: () => _print(b)),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const SalesBillFormScreen()));
          if (created == true) _load();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Sale'),
      ),
    );
  }

  Future<void> _print(SalesBill bill) async {
    final items = await _repo.itemsFor(bill.id);
    final customer = bill.customerId != null ? await _customerRepo.byId(bill.customerId!) : null;
    final bytes = await _pdfService.buildSalesBill(bill: bill, items: items, customer: customer);
    await Printing.layoutPdf(format: PdfPageFormat.a5, onLayout: (format) async => bytes);
  }
}
