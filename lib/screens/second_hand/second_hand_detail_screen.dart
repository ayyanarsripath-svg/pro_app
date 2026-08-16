import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/repositories/customer_repository.dart';
import '../../core/repositories/second_hand_repository.dart';
import '../../core/repositories/spare_part_repository.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/second_hand_phone.dart';
import '../../models/spare_part.dart';
import '../../widgets/section_card.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/status_badge.dart';

class SecondHandDetailScreen extends StatefulWidget {
  final String phoneId;
  const SecondHandDetailScreen({super.key, required this.phoneId});

  @override
  State<SecondHandDetailScreen> createState() => _SecondHandDetailScreenState();
}

class _SecondHandDetailScreenState extends State<SecondHandDetailScreen> {
  final _repo = SecondHandRepository();
  final _customerRepo = CustomerRepository();
  final _sparePartRepo = SparePartRepository();
  final _pdfService = PdfService();

  SecondHandPhone? _phone;
  List<SecondHandRepairItem> _repairs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final phone = await _repo.byId(widget.phoneId);
    final repairs = phone != null ? await _repo.repairItems(widget.phoneId) : <SecondHandRepairItem>[];
    setState(() {
      _phone = phone;
      _repairs = repairs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _phone == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final auth = context.watch<AuthService>();
    final phone = _phone!;

    return Scaffold(
      appBar: AppBar(title: Text('${phone.brand ?? ''} ${phone.model ?? ''}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Row(
              children: [
                Expanded(child: Text(phone.purchaseNo, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                StatusBadge(phone.status),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _actionChip('Add Repair Cost', Icons.build_rounded, _addRepairItem),
              _actionChip('Change Status', Icons.sync_alt_rounded, _changeStatus),
              if (phone.status != SecondHandStatus.sold) _actionChip('Sell Phone', Icons.sell_rounded, _sellPhone),
              if (phone.status == SecondHandStatus.sold) _actionChip('Print Sales Bill', Icons.print_rounded, _printSale),
              if (phone.status == SecondHandStatus.sold) _actionChip('Customer Return', Icons.assignment_return_rounded, _customerReturn),
            ]),
            const SizedBox(height: 14),
            SectionCard(title: 'Device Details', icon: Icons.phone_iphone_rounded, children: [
              _row('Brand', phone.brand),
              _row('Model', phone.model),
              _row('IMEI 1', phone.imei1),
              _row('IMEI 2', phone.imei2),
              _row('RAM / Storage', '${phone.ram ?? '-'} / ${phone.storage ?? '-'}'),
              _row('Colour', phone.colour),
            ]),
            SectionCard(title: 'Condition', icon: Icons.fact_check_rounded, children: [
              _row('Grade', phone.conditionGrade),
              _row('Battery Health', phone.batteryHealth),
              _row('Display', phone.displayCondition),
              _row('Body', phone.bodyCondition),
              _row('Accessories Received', phone.accessoriesReceived),
            ]),
            SectionCard(title: 'Seller', icon: Icons.person_rounded, children: [
              _row('Name', phone.sellerName),
              _row('Phone', phone.sellerPhone),
              _row('Purchase Date', formatDate(phone.purchaseDate)),
            ]),
            SectionCard(
              title: 'Repair / Investment',
              icon: Icons.handyman_rounded,
              children: [
                if (_repairs.isEmpty) const Text('No repair items added', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                ..._repairs.map((r) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.description),
                      trailing: Text(formatCurrency(r.cost)),
                    )),
              ],
            ),
            if (auth.canSeeCost)
              SectionCard(title: 'Investment Summary (Admin)', icon: Icons.lock_rounded, children: [
                _row('Purchase Price', formatCurrency(phone.purchasePrice)),
                _row('Repair Cost', formatCurrency(phone.repairCost)),
                _row('Spare Part Cost', formatCurrency(phone.sparePartCost)),
                _row('Other Cost', formatCurrency(phone.otherCost)),
                const Divider(),
                _row('Total Investment', formatCurrency(phone.totalInvestment)),
                _row('Expected Selling Price', formatCurrency(phone.expectedSellingPrice)),
                if (phone.status == SecondHandStatus.sold) ...[
                  _row('Actual Selling Price', formatCurrency(phone.actualSellingPrice ?? 0)),
                  Text(
                    formatProfitLoss(phone.realizedProfit),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: phone.realizedProfit < 0 ? AppColors.danger : AppColors.success,
                    ),
                  ),
                ] else
                  Text('Potential Profit: ${formatCurrency(phone.potentialProfit)}',
                      style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.textSecondary)),
              ]),
            if (phone.notes != null && phone.notes!.isNotEmpty)
              SectionCard(title: 'Notes', icon: Icons.notes_rounded, children: [Text(phone.notes!)]),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String? value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
            children: [
              TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: (value == null || value.isEmpty) ? '-' : value),
            ],
          ),
        ),
      );

  Widget _actionChip(String label, IconData icon, VoidCallback onTap) => ActionChip(
        avatar: Icon(icon, size: 16, color: AppColors.primaryBlue),
        label: Text(label),
        onPressed: onTap,
      );

  Future<void> _addRepairItem() async {
    final parts = await _sparePartRepo.all();
    SparePart? selected;
    final descCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    bool useInventory = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Add Repair Cost'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (parts.isNotEmpty)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use inventory spare part'),
                  value: useInventory,
                  onChanged: (v) => setLocalState(() => useInventory = v),
                ),
              if (useInventory)
                DropdownButtonFormField<SparePart>(
                  isExpanded: true,
                  items: parts.map((p) => DropdownMenuItem(value: p, child: Text(p.name))).toList(),
                  onChanged: (v) => setLocalState(() => selected = v),
                  decoration: const InputDecoration(labelText: 'Spare Part'),
                )
              else ...[
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description (e.g. Display Repair)')),
                TextField(controller: costCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cost (₹)')),
              ],
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
      if (useInventory && selected != null) {
        await _repo.addRepairItem(
          phoneId: widget.phoneId,
          description: selected!.name,
          sparePartId: selected!.id,
          cost: 0,
          date: DateTime.now(),
        );
      } else if (descCtrl.text.trim().isNotEmpty) {
        await _repo.addRepairItem(
          phoneId: widget.phoneId,
          description: descCtrl.text.trim(),
          cost: double.tryParse(costCtrl.text.trim()) ?? 0,
          date: DateTime.now(),
        );
      }
      _load();
    }
  }

  Future<void> _changeStatus() async {
    String status = _phone!.status;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Change Status'),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SecondHandStatus.all
                .map((st) => ChoiceChip(label: Text(st), selected: status == st, onSelected: (_) => setLocalState(() => status = st)))
                .toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Update')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _repo.updateStatus(widget.phoneId, status);
      _load();
    }
  }

  Future<void> _sellPhone() async {
    final phone = _phone!;
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: phone.expectedSellingPrice.toStringAsFixed(0));
    final paidCtrl = TextEditingController(text: phone.expectedSellingPrice.toStringAsFixed(0));
    bool warranty = phone.warranty;
    final warrantyPeriodCtrl = TextEditingController(text: phone.warrantyPeriod ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Sell Phone'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Customer Name')),
                TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Customer Phone')),
                TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sale Price (₹)')),
                TextField(controller: paidCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Paid (₹)')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Warranty'),
                  value: warranty,
                  onChanged: (v) => setLocalState(() => warranty = v),
                ),
                if (warranty) TextField(controller: warrantyPeriodCtrl, decoration: const InputDecoration(labelText: 'Warranty Period')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm Sale')),
          ],
        ),
      ),
    );

    if (ok == true) {
      final customer = await _customerRepo.findOrCreateByPhone(
        name: nameCtrl.text.trim().isEmpty ? 'Walk-in Customer' : nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
      );
      await _repo.recordSale(
        phoneId: widget.phoneId,
        customerId: customer.id,
        saleDate: DateTime.now(),
        salePrice: double.tryParse(priceCtrl.text.trim()) ?? 0,
        paymentMethod: 'Cash',
        paid: double.tryParse(paidCtrl.text.trim()) ?? 0,
        warranty: warranty,
        warrantyPeriod: warrantyPeriodCtrl.text.trim(),
      );
      _load();
    }
  }

  Future<void> _printSale() async {
    final phone = _phone!;
    final sale = await _repo.latestSaleForPhone(widget.phoneId);
    if (sale == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No sale record found for this phone')));
      }
      return;
    }
    final customer = sale.customerId != null ? await _customerRepo.byId(sale.customerId!) : null;
    final bytes = await _pdfService.buildSecondHandSalesBill(phone: phone, sale: sale, customer: customer);
    await Printing.layoutPdf(onLayout: (format) async => bytes);
  }

  Future<void> _customerReturn() async {
    final amountCtrl = TextEditingController(text: (_phone!.actualSellingPrice ?? 0).toStringAsFixed(0));
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Customer Return'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Refund Amount (₹)')),
            TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Process Return')),
        ],
      ),
    );
    if (ok == true) {
      final sale = await _repo.latestSaleForPhone(widget.phoneId);
      await _repo.recordReturn(
        phoneId: widget.phoneId,
        saleId: sale?.id ?? widget.phoneId,
        refundAmount: double.tryParse(amountCtrl.text.trim()) ?? 0,
        date: DateTime.now(),
        reason: reasonCtrl.text.trim(),
        restock: true,
      );
      _load();
    }
  }
}
