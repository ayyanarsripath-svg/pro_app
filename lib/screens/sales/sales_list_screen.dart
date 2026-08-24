import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:provider/provider.dart';

import '../../core/repositories/customer_repository.dart';
import '../../core/repositories/sales_repository.dart';
import '../../core/repositories/warranty_repository.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/whatsapp_sms_service.dart';
import '../../core/theme/app_theme.dart';
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
  final _warrantyRepo = WarrantyRepository();
  final _waService = WhatsAppSmsService();
  List<SalesBill> _bills = [];
  Set<String> _claimedBillIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final bills = await _repo.all();
    final claims = await _warrantyRepo.all();
    setState(() {
      _bills = bills;
      _claimedBillIds = claims.where((c) => c.claimType == 'accessory').map((c) => c.referenceId).toSet();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
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
            final claimed = _claimedBillIds.contains(b.id);
            return Card(
              child: ListTile(
                title: Text('${b.billNo} • ${formatCurrency(b.total)}'),
                subtitle: Text('${formatDate(b.saleDate)} • ${b.paymentMethod ?? '-'}${b.balance > 0 ? ' • Balance: ${formatCurrency(b.balance)}' : ''}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!claimed)
                    IconButton(icon: const Icon(Icons.verified_user_rounded), tooltip: 'Warranty Claim', onPressed: () => _fileWarrantyClaim(b)),
                    IconButton(icon: const Icon(Icons.print_rounded), onPressed: () => _print(b)),
                    // Delete moved behind a "more" overflow menu instead of
                    // sitting as its own icon right next to Print (spec:
                    // print/delete pakkathula erukku, accident ah delete
                    // touch pannita) - a stray tap now just opens a small
                    // menu instead of immediately landing on Delete, and
                    // the existing confirm dialog is still a second guard
                    // after that.
                    if (auth.canDelete)
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      onSelected: (v) {
                        if (v == 'delete') _deleteBill(b);
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.delete_rounded, color: AppColors.danger),
                            title: Text('Delete'),
                          ),
                        ),
                      ],
                    ),
                    ],
                  ),
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
    final bytes = await _pdfService.buildSalesBill(bill: bill, items: items, customer: customer, warrantyClaimed: _claimedBillIds.contains(bill.id));
    await Printing.layoutPdf(format: PdfPageFormat.a5, name: 'Sales_${bill.billNo}', onLayout: (format) async => bytes);
  }

  /// Admin/permission-gated Delete (soft-delete: sets active=0 and clears
  /// its ledger entries, matching the pattern used for services/2nd-hand).
  Future<void> _deleteBill(SalesBill bill) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Sales Bill?'),
        content: Text('${bill.billNo} (${formatCurrency(bill.total)}) will be removed from lists. This cannot be undone from here.'),
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
      await _repo.delete(bill.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sales bill deleted')));
      }
      _load();
    }
  }

  Future<void> _fileWarrantyClaim(SalesBill bill) async {
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('File Warranty Claim'),
        content: TextField(controller: descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Describe the issue')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('File Claim')),
          ],
        ),
      );
    if (ok == true && descCtrl.text.trim().isNotEmpty) {
      await _warrantyRepo.fileClaim(claimType: 'accessory', referenceId: bill.id, description: descCtrl.text.trim());
      final customer = bill.customerId != null ? await _customerRepo.byId(bill.customerId!) : null;
      if (customer?.phone != null && customer!.phone!.trim().isNotEmpty) {
        final waMsg = _waService.warrantyClaimMessage(customerName: customer.name, referenceLabel: 'Sales ${bill.billNo}', description: descCtrl.text.trim());
        try { await _waService.sendWhatsApp(phone: customer.phone!, message: waMsg); } catch (_) {}
        try { await _waService.sendSms(phone: customer.phone!, message: waMsg); } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Warranty claim filed')));
      }
      _load();
    }
  }
}
