import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/repositories/customer_repository.dart';
import '../../core/repositories/service_repository.dart';
import '../../core/repositories/settings_repository.dart';
import 'package:pdf/pdf.dart';
import '../../core/repositories/spare_part_repository.dart';
import '../../core/repositories/warranty_repository.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/whatsapp_sms_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/id_gen.dart';
import '../../models/customer.dart';
import '../../models/service.dart';
import '../../models/spare_part.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_badge.dart';

/// The premium "mobile repair job card" screen (spec sections 19-25):
/// status header, quick-action row, big payment summary, delivery block,
/// and (admin-only) the internal cost/profit breakdown that never appears
/// on the printed customer bill.
class ServiceDetailScreen extends StatefulWidget {
  final String serviceId;
  const ServiceDetailScreen({super.key, required this.serviceId});

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  final _serviceRepo = ServiceRepository();
  final _customerRepo = CustomerRepository();
  final _sparePartRepo = SparePartRepository();
  final _settingsRepo = SettingsRepository();
  final _pdfService = PdfService();
  final _waService = WhatsAppSmsService();
  final _warrantyRepo = WarrantyRepository();

  ServiceJob? _service;
  Customer? _customer;
  List<ServiceSparePartUsage> _usages = [];
  List<ServiceOtherCost> _otherCosts = [];
  List<ServicePayment> _payments = [];
  List<ServicePhoto> _photos = [];
  ServiceProfitBreakdown? _profit;
  bool _loading = true; bool _warrantyClaimed = false;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Starts loading the bill's logo/font/terms-note assets right now, in
    // the background, so most of that work is already done by the time
    // the owner actually taps Print - see PdfService.warmUp's doc comment
    // (spec: "service bill print kudutha 5 to 7 second aaguthu ...
    // optimization panni 2 to 3 second la varamathiri panna mudiuma").
    _pdfService.warmUp();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = await _serviceRepo.byId(widget.serviceId);
    if (service == null) {
      setState(() => _loading = false);
      return;
    }
    final customer = await _customerRepo.byId(service.customerId);
    final usages = await _serviceRepo.sparePartUsages(service.id);
    final others = await _serviceRepo.otherCosts(service.id);
    final payments = await _serviceRepo.payments(service.id);
    final photos = await _serviceRepo.photos(service.id);
    final profit = await _serviceRepo.profitBreakdown(service.id); final claims = await _warrantyRepo.forReference(service.id);

    setState(() {
      _service = service;
      _customer = customer;
      _usages = usages;
      _otherCosts = others;
      _payments = payments;
      _photos = photos;
      _profit = profit; _warrantyClaimed = claims.isNotEmpty;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _service == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final auth = context.watch<AuthService>();
    final s = _service!;

    return Scaffold(
      appBar: AppBar(
        title: Text('SERVICE ${s.billNo}'),
        actions: [
          IconButton(
            icon: _printing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.print_rounded),
            tooltip: 'Print',
            onPressed: _printing ? null : _printBill,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Row(
              children: [
                Text('SERVICE ${s.billNo}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                const Spacer(),
                StatusBadge(s.status),
              ],
            ),
            const SizedBox(height: 12),
            _quickActions(auth),
            const SizedBox(height: 14),
            _paymentSummaryCard(s),
            const SizedBox(height: 14),
            SectionCard(title: 'Customer', icon: Icons.person_rounded, children: [
              Text(_customer?.name ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(_customer?.phone ?? '-'),
            ]),
            SectionCard(title: 'Device', icon: Icons.smartphone_rounded, children: [
              _row('Mobile', s.mobileName),
              _row('Model', s.model),
              _row('IMEI', s.imei),
            ]),
            SectionCard(
              title: 'Complaint',
              icon: Icons.report_problem_rounded,
              trailing: TextButton.icon(
                onPressed: _addComplaint,
                icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                label: const Text('Add Complaint'),
              ),
              children: [Text(s.complaint ?? '-')],
            ),
            SectionCard(title: 'Condition', icon: Icons.fact_check_rounded, children: [
              _row('Device Condition', s.deviceCondition),
              _row('Existing Damage', s.existingDamage),
            ]),
            SectionCard(title: 'Accessories Received', icon: Icons.cable_rounded, children: [
              Wrap(spacing: 10, children: [
                _tag('Charger', s.accCharger),
                _tag('Cable', s.accCable),
                _tag('SIM', s.accSim),
                _tag('Memory Card', s.accMemoryCard),
                if ((s.accOther ?? '').isNotEmpty) Chip(label: Text('Other: ${s.accOther}')),
              ]),
            ]),
            SectionCard(
              title: 'Repair',
              icon: Icons.handyman_rounded,
              trailing: TextButton.icon(
                onPressed: _addSparePart,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Part'),
              ),
              children: [
                _row('Technician', s.technician),
                _row('Status', s.status),
                const SizedBox(height: 6),
                if (_usages.isEmpty) Text('No spare parts used yet', style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12.5)),
                ..._usages.map((u) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(u.itemName),
                      subtitle: Text('Qty: ${u.quantity.toStringAsFixed(0)}'),
                      trailing: auth.canSeeCost ? Text(formatCurrency(u.totalCost)) : null,
                    )),
              ],
            ),
            SectionCard(title: 'Warranty', icon: Icons.verified_user_rounded, children: [
              _row('Warranty', s.warranty ? 'Yes' : 'No'),
              if (s.warranty) _row('Period', s.warrantyPeriod),
            ]),
            SectionCard(
              title: 'Photos',
              icon: Icons.photo_camera_rounded,
              trailing: TextButton.icon(onPressed: _addPhoto, icon: const Icon(Icons.add_a_photo_rounded, size: 16), label: const Text('Add')),
              children: [
                if (_photos.isEmpty)
                  Text('No photos added', style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12.5))
                else
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _photos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(_photos[i].photoPath), width: 84, height: 84, fit: BoxFit.cover),
                      ),
                    ),
                  ),
              ],
            ),
            _deliverySection(s),
            if (auth.canSeeCost || auth.canSeeProfit) _profitSection(auth),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String? value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: RichText(
          text: TextSpan(
            style: TextStyle(color: AppColors.textPrimaryOf(context), fontSize: 13.5),
            children: [
              TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: (value == null || value.isEmpty) ? '-' : value),
            ],
          ),
        ),
      );

  Widget _tag(String label, bool active) => Chip(
        avatar: Icon(active ? Icons.check_circle : Icons.circle_outlined, size: 16, color: active ? AppColors.success : AppColors.textSecondaryOf(context)),
        label: Text(label),
      );

  Widget _quickActions(AuthService auth) {
    final actions = <_QuickAction>[
      _QuickAction('Edit', Icons.edit_rounded, _editService),
      _QuickAction('Add Payment', Icons.payments_rounded, _addPayment),
      _QuickAction('Change Status', Icons.sync_alt_rounded, _changeStatus),
      _QuickAction('Print', Icons.print_rounded, _printBill),
      _QuickAction('Call', Icons.call_rounded, _callCustomer),
      _QuickAction('WhatsApp', Icons.chat_rounded, _sendWhatsApp),
      _QuickAction('SMS', Icons.sms_rounded, _sendSms),
      _QuickAction('Delivery', Icons.local_shipping_rounded, _markDelivery),
      if (!_warrantyClaimed) _QuickAction('Warranty Claim', Icons.assignment_return_rounded, _fileWarrantyClaim),
      if (auth.canDelete) _QuickAction('Delete', Icons.delete_rounded, _deleteService),
    ];
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final a = actions[i];
          return InkWell(
            onTap: a.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 74,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(a.icon, size: 20, color: a.label == 'Delete' ? AppColors.danger : AppColors.primaryBlue),
                  const SizedBox(height: 4),
                  Text(a.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _paymentSummaryCard(ServiceJob s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _amountBlock('FINAL AMOUNT', s.billTotal),
              _amountBlock('PAID', s.paid),
              _amountBlock('BALANCE', s.displayBalance),
            ],
          ),
          if (s.discount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
                child: Text('DISCOUNT APPLIED: ${formatCurrency(s.discount)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5)),
              ),
            ),
          if (s.displayBalance > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
                child: const Text('PAYMENT PENDING', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _amountBlock(String label, double value) => Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(formatCurrency(value), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
        ],
      );

  Widget _deliverySection(ServiceJob s) {
    return SectionCard(title: 'Delivery', icon: Icons.local_shipping_rounded, children: [
      _row('Expected Delivery', s.expectedDate != null ? formatDate(s.expectedDate!) : '-'),
      _row('Actual Delivery', s.actualDate != null ? formatDate(s.actualDate!) : '-'),
      _row('Delivery Person', s.deliveryPerson),
      const SizedBox(height: 6),
      StatusBadge(s.deliveryStatus),
    ]);
  }

  Widget _profitSection(AuthService auth) {
    final p = _profit!;
    return SectionCard(
      title: 'Internal Costing (Admin Only)',
      icon: Icons.lock_rounded,
      children: [
        _row('Service Revenue', formatCurrency(p.serviceRevenue)),
        if (auth.canSeeCost) _row('Spare Part Cost', formatCurrency(p.sparePartCost)),
        if (auth.canSeeCost) _row('Other Direct Cost', formatCurrency(p.otherDirectCost)),
        if (auth.canSeeCost) _row('Labour Cost', formatCurrency(p.labourCost)),
        if (auth.canSeeCost) _row('Total Direct Cost', formatCurrency(p.totalDirectCost)),
        if (auth.canSeeProfit) ...[
          const Divider(),
          _row('Gross Profit', formatCurrency(p.grossProfit)),
          _row('Additional Expense', formatCurrency(p.additionalExpense)),
          _row('Net Profit', formatCurrency(p.netProfit)),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------

  Future<void> _editService() async {
    final s = _service!;
    final finalCtrl = TextEditingController(text: s.finalAmount.toStringAsFixed(0));
    final labourCtrl = TextEditingController(text: s.labourCost.toStringAsFixed(0));
    final expenseCtrl = TextEditingController(text: s.additionalExpense.toStringAsFixed(0));
    final discountCtrl = TextEditingController(text: s.discount == 0 ? '' : s.discount.toStringAsFixed(0));
    final techCtrl = TextEditingController(text: s.technician ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Service'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: techCtrl, decoration: const InputDecoration(labelText: 'Technician')),
              const SizedBox(height: 10),
              TextField(controller: finalCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Final Amount (₹)')),
              const SizedBox(height: 10),
              TextField(controller: labourCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Labour Cost (₹) - Admin only')),
              const SizedBox(height: 10),
              TextField(controller: expenseCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Additional Expense (₹)')),
              const SizedBox(height: 10),
              // Bargain write-off: e.g. Final Amount 100, customer pays 90 -
              // enter 10 here and the balance auto-settles to 0 instead of
              // sitting as a pending due. Only printed on the bill when > 0.
              TextField(
                controller: discountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Discount (₹) - leave blank if none',
                  helperText: 'Bargained-off amount. Balance = Final − Paid − Discount.',
                  helperMaxLines: 2,
                ),
              ),
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
      final updated = ServiceJob(
        id: s.id,
        billNo: s.billNo,
        customerId: s.customerId,
        mobileName: s.mobileName,
        model: s.model,
        imei: s.imei,
        complaint: s.complaint,
        faultAmounts: s.faultAmounts,
        deviceCondition: s.deviceCondition,
        existingDamage: s.existingDamage,
        accCharger: s.accCharger,
        accCable: s.accCable,
        accSim: s.accSim,
        accMemoryCard: s.accMemoryCard,
        accOther: s.accOther,
        technician: techCtrl.text.trim(),
        status: s.status,
        labourCost: double.tryParse(labourCtrl.text.trim()) ?? s.labourCost,
        warranty: s.warranty,
        warrantyPeriod: s.warrantyPeriod,
        estimatedAmount: s.estimatedAmount,
        finalAmount: double.tryParse(finalCtrl.text.trim()) ?? s.finalAmount,
        discount: double.tryParse(discountCtrl.text.trim()) ?? 0,
        advance: s.advance,
        paid: s.paid,
        balance: s.balance,
        expectedDate: s.expectedDate,
        actualDate: s.actualDate,
        deliveryPerson: s.deliveryPerson,
        deliveryStatus: s.deliveryStatus,
        additionalExpense: double.tryParse(expenseCtrl.text.trim()) ?? s.additionalExpense,
        active: s.active,
        createdAt: s.createdAt,
        updatedAt: DateTime.now(),
      );
      await _serviceRepo.update(updated);
      _load();
    }
  }

  /// Lets the shop add a NEW fault/complaint found after intake (e.g. the
  /// technician discovers a second issue while checking) - either picked
  /// from the same quick-preset list used at intake or typed manually - and
  /// its charge is added straight into the bill amount, instead of the old
  /// "Edit" flow which just silently overwrote the complaint text with no
  /// way to bill for whatever was added.
  Future<void> _addComplaint() async {
    final s = _service!;
    final presets = await _settingsRepo.getComplaintPresets();
    String? selectedPreset;
    final manualCtrl = TextEditingController();
    final amountCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Add Complaint'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pick one, or write it manually below:', style: TextStyle(fontSize: 12.5)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: presets
                      .map((p) => FilterChip(
                            label: Text(p),
                            selected: selectedPreset == p,
                            onSelected: (v) => setLocalState(() => selectedPreset = v ? p : null),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: manualCtrl,
                  decoration: const InputDecoration(labelText: 'Or write manually'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount (₹) - added to the bill'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );

    final description = manualCtrl.text.trim().isNotEmpty ? manualCtrl.text.trim() : (selectedPreset ?? '');
    if (ok != true || description.isEmpty) return;

    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    final newComplaint = (s.complaint == null || s.complaint!.trim().isEmpty) ? description : '${s.complaint}, $description';
    final newFaultAmounts = (s.faultAmounts == null || s.faultAmounts!.trim().isEmpty)
        ? '$description:$amount'
        : '${s.faultAmounts}|$description:$amount';
    // The bill total tracks finalAmount once it's been set (post-checking),
    // otherwise it's still riding on estimatedAmount - add the new charge to
    // whichever one is currently live so the bill amount always reflects
    // this addition immediately (see ServiceJob.billTotal).
    final addToFinal = s.finalAmount > 0;

    final updated = ServiceJob(
      id: s.id,
      billNo: s.billNo,
      customerId: s.customerId,
      mobileName: s.mobileName,
      model: s.model,
      imei: s.imei,
      complaint: newComplaint,
      faultAmounts: newFaultAmounts,
      deviceCondition: s.deviceCondition,
      existingDamage: s.existingDamage,
      accCharger: s.accCharger,
      accCable: s.accCable,
      accSim: s.accSim,
      accMemoryCard: s.accMemoryCard,
      accOther: s.accOther,
      technician: s.technician,
      status: s.status,
      labourCost: s.labourCost,
      warranty: s.warranty,
      warrantyPeriod: s.warrantyPeriod,
      estimatedAmount: addToFinal ? s.estimatedAmount : s.estimatedAmount + amount,
      finalAmount: addToFinal ? s.finalAmount + amount : s.finalAmount,
      discount: s.discount,
      advance: s.advance,
      paid: s.paid,
      balance: s.balance,
      expectedDate: s.expectedDate,
      actualDate: s.actualDate,
      deliveryPerson: s.deliveryPerson,
      deliveryStatus: s.deliveryStatus,
      additionalExpense: s.additionalExpense,
      active: s.active,
      createdAt: s.createdAt,
      updatedAt: DateTime.now(),
    );
    await _serviceRepo.update(updated);
    _load();
  }

  Future<void> _addSparePart() async {
    final parts = await _sparePartRepo.all();
    SparePart? selected = parts.isNotEmpty ? parts.first : null;
    final qtyCtrl = TextEditingController(text: '1');
    final manualNameCtrl = TextEditingController();
    final manualCostCtrl = TextEditingController();
    bool manual = parts.isEmpty;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Add Spare Part Used'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Manual entry (not in inventory)'),
                value: manual,
                onChanged: (v) => setLocalState(() => manual = v),
              ),
              if (!manual) ...[
                DropdownButtonFormField<SparePart>(
                  value: selected,
                  isExpanded: true,
                  items: parts.map((p) => DropdownMenuItem(value: p, child: Text('${p.name} (stock: ${p.currentStock.toStringAsFixed(0)})'))).toList(),
                  onChanged: (v) => setLocalState(() => selected = v),
                ),
                TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
              ] else ...[
                TextField(controller: manualNameCtrl, decoration: const InputDecoration(labelText: 'Item Name')),
                TextField(controller: manualCostCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cost (₹)')),
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
      if (manual && manualNameCtrl.text.trim().isNotEmpty) {
        await _serviceRepo.addManualDirectCost(
          serviceId: widget.serviceId,
          itemName: manualNameCtrl.text.trim(),
          amount: double.tryParse(manualCostCtrl.text.trim()) ?? 0,
          date: DateTime.now(),
        );
      } else if (!manual && selected != null) {
        await _serviceRepo.addSparePartUsage(
          serviceId: widget.serviceId,
          sparePartId: selected!.id,
          itemName: selected!.name,
          quantity: double.tryParse(qtyCtrl.text.trim()) ?? 1,
          date: DateTime.now(),
        );
      }
      _load();
    }
  }

  Future<void> _addPayment() async {
    final s = _service!;
    final balanceDue = s.displayBalance > 0 ? s.displayBalance : 0.0;
    final amountCtrl = TextEditingController();
    String method = 'Cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Add Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Same "already paid / balance due" context as the Delivery
              // dialog (see _markDelivery) - this is what makes it clear
              // that an amount recorded here is a NEW payment on top of
              // what's already paid, not a replacement of it.
              Text(
                'Already paid: ${formatCurrency(s.paid)} • Balance due: ${formatCurrency(balanceDue)}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (₹)')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: method,
                items: ['Cash', 'UPI', 'Card', 'Bank Transfer'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => setLocalState(() => method = v ?? 'Cash'),
              ),
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
      final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
      if (amount > 0) {
        await _serviceRepo.recordPayment(serviceId: widget.serviceId, amount: amount, paymentMethod: method);
        _load();
      }
    }
  }

  Future<void> _changeStatus() async {
    String status = _service!.status;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Change Status'),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ServiceStatus.all
                .map((st) => ChoiceChip(
                      label: Text(st),
                      selected: status == st,
                      onSelected: (_) => setLocalState(() => status = st),
                    ))
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
      final wasReady = _service!.status == ServiceStatus.ready;
      await _serviceRepo.changeStatus(widget.serviceId, status);

      // "Mobile ready for delivery" WhatsApp notice (spec: send this the
      // moment status is set to Ready, using the shop's exact template) -
      // distinct from deliveryMessage, which fires later at actual pickup.
      // Only fires on the transition INTO Ready, not every time the
      // status dialog is re-opened while already Ready, and never blocks
      // the status change itself if WhatsApp isn't available.
      if (status == ServiceStatus.ready && !wasReady && _customer?.phone != null && _customer!.phone!.trim().isNotEmpty) {
        try {
          final s = _service!;
          final msg = await _waService.readyForDeliveryMessage(
            customerName: _customer!.name,
            mobileName: s.model?.trim().isNotEmpty == true ? s.model : s.mobileName,
            amount: s.billTotal,
            billNo: s.billNo,
            complaint: s.complaint,
            imei: s.imei,
            technician: s.technician,
            balance: s.displayBalance,
          );
          await _waService.sendWhatsApp(phone: _customer!.phone!, message: msg);
        } catch (_) {}
      }

      _load();
    }
  }

  /// Delivery action: previously this dialog only captured the delivery
  /// person's name (the amount had to be added separately via Add Payment,
  /// which was easy to forget before handing the device back). Now it also
  /// collects the final amount right here - filling it in and confirming
  /// records the payment, marks the job Delivered in one step, and pushes a
  /// WhatsApp "delivered" message to the customer.
  Future<void> _markDelivery() async {
    final s = _service!;
    final personCtrl = TextEditingController(text: s.deliveryPerson ?? '');
    // displayBalance already reflects every payment recorded so far
    // (Advance, Add Payment, any earlier Delivery Collection) - it's what
    // is ACTUALLY still owed right now, not just this dialog's own field.
    final balanceDue = s.displayBalance > 0 ? s.displayBalance : 0.0;
    final amountCtrl = TextEditingController(
      text: balanceDue > 0 ? balanceDue.toStringAsFixed(balanceDue == balanceDue.roundToDouble() ? 0 : 2) : '',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delivery'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Makes the current money state explicit before the shop types
            // anything here - this is what was missing before, and why
            // re-entering an amount already covered by Add Payment quietly
            // overpaid the bill (showed as balance going negative /
            // "extra"). Already paid comes from every payment recorded so
            // far (Advance + any Add Payment entries); Balance due is what
            // is genuinely still outstanding.
            Text(
              'Already paid: ${formatCurrency(s.paid)} • Balance due: ${formatCurrency(balanceDue)}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            TextField(controller: personCtrl, decoration: const InputDecoration(labelText: 'Delivery Person')),
            const SizedBox(height: 10),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount Collected Now (₹)',
                helperText: 'Only what you are collecting AT this delivery. Leave as 0 if the balance was '
                    'already fully paid earlier via Add Payment - this field always adds a NEW payment, '
                    'on top of anything already paid.',
                helperMaxLines: 4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('OK - Mark Delivered')),
        ],
      ),
    );
    if (ok == true) {
      final amountCollected = double.tryParse(amountCtrl.text.trim()) ?? 0;

      // Catches exactly the "already paid via Add Payment, then also
      // entered here" mistake before it silently overpays the bill - e.g.
      // balance was already ₹0 (fully paid) but the field still had a
      // suggested/typed amount left in it.
      if (amountCollected > balanceDue + 0.5) {
        final overBy = amountCollected - balanceDue;
        if (!mounted) return;
        final confirmOverpay = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('More Than the Balance Due?'),
            content: Text(
              'Balance due is only ${formatCurrency(balanceDue)}, but ${formatCurrency(amountCollected)} was entered here - '
              '${formatCurrency(overBy)} more than what is actually pending.\n\n'
              'If this amount was already recorded earlier via Add Payment, tap Cancel and change this field to 0. '
              'Only continue if the customer is genuinely paying ${formatCurrency(amountCollected)} extra right now.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Yes, Record It')),
            ],
          ),
        );
        if (confirmOverpay != true) return;
      }

      final updated = ServiceJob(
        id: s.id, billNo: s.billNo, customerId: s.customerId, mobileName: s.mobileName, model: s.model, imei: s.imei,
        complaint: s.complaint, faultAmounts: s.faultAmounts, deviceCondition: s.deviceCondition, existingDamage: s.existingDamage,
        accCharger: s.accCharger, accCable: s.accCable, accSim: s.accSim, accMemoryCard: s.accMemoryCard, accOther: s.accOther,
        technician: s.technician, status: ServiceStatus.delivered, labourCost: s.labourCost, warranty: s.warranty,
        warrantyPeriod: s.warrantyPeriod, estimatedAmount: s.estimatedAmount, finalAmount: s.finalAmount, advance: s.advance,
        paid: s.paid, balance: s.balance, expectedDate: s.expectedDate, actualDate: DateTime.now(),
        deliveryPerson: personCtrl.text.trim(), deliveryStatus: 'Delivered', additionalExpense: s.additionalExpense,
        active: s.active, createdAt: s.createdAt, updatedAt: DateTime.now(),
      );
      // Update delivery details first (paid/balance untouched here), then
      // record the collected amount as a real payment - so it shows in the
      // Payments history too, not just as a raw number overwrite.
      await _serviceRepo.update(updated);
      if (amountCollected > 0) {
        await _serviceRepo.recordPayment(serviceId: widget.serviceId, amount: amountCollected, paymentMethod: 'Delivery Collection');
      }
      await _serviceRepo.changeStatus(widget.serviceId, ServiceStatus.delivered);

      // Best-effort WhatsApp "delivered" notification - must never block the
      // delivery from being recorded if WhatsApp isn't available.
      if (_customer?.phone != null && _customer!.phone!.trim().isNotEmpty) {
        try {
          final freshTotal = s.billTotal;
          final freshPaid = s.paid + amountCollected;
          final msg = await _waService.deliveryMessage(
            customerName: _customer!.name,
            billNo: s.billNo,
            mobileName: s.mobileName,
            totalAmount: freshTotal,
            paidAmount: freshPaid,
            complaint: s.complaint,
            imei: s.imei,
            technician: s.technician,
            deliveryPerson: personCtrl.text.trim(),
          );
          await _waService.sendWhatsApp(phone: _customer!.phone!, message: msg);
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as Delivered')));
      }
      _load();
    }
  }

  /// Admin/permission-gated Delete (spec: small confirmation dialog, hides
  /// the record without losing its accounting/ledger history).
  Future<void> _deleteService() async {
    final s = _service!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Service?'),
        content: Text('SERVICE ${s.billNo} will be removed from lists. This cannot be undone from here.'),
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
      await _serviceRepo.delete(s.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Service deleted')));
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _addPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (picked == null) return;
    final docs = await getApplicationDocumentsDirectory();
    final photoDir = Directory(p.join(docs.path, 'service_photos'));
    if (!await photoDir.exists()) await photoDir.create(recursive: true);
    final dest = p.join(photoDir.path, '${newId()}${p.extension(picked.path)}');
    await File(picked.path).copy(dest);
    await _serviceRepo.addPhoto(widget.serviceId, dest);
    _load();
  }

  Future<void> _printBill() async {
    if (_customer == null || _service == null || _printing) return;
    // Spinner on the AppBar Print button while this runs (see the
    // _printing check above too, so a second tap - AppBar icon or this
    // same action from the horizontal Quick Actions row - can't start a
    // second overlapping build while one is already in flight).
    setState(() => _printing = true);
    try {
      final bytes = await _pdfService.buildServiceBill(service: _service!, customer: _customer!, partsUsed: _usages, warrantyClaimed: _warrantyClaimed);
      await Printing.layoutPdf(format: PdfPageFormat.a5, name: 'Service_${_service!.billNo}', onLayout: (format) async => bytes);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  /// Opens the phone's own dialer with the customer's saved number already
  /// filled in - a quick way to call and tell them the job is ready,
  /// without leaving the service screen to look the number up. Never
  /// throws into the UI: shows a plain snackbar instead if there's no
  /// saved number, or if the dialer can't be opened for any reason.
  Future<void> _callCustomer() async {
    final phone = _customer?.phone?.trim();
    if (phone == null || phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No phone number saved for this customer')),
        );
      }
      return;
    }
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the dialer')),
        );
      }
    }
  }

  Future<void> _sendWhatsApp() async {
    if (_customer?.phone == null) return;
    final msg = _waService.serviceStatusMessage(
      shopName: 'Professional Mobiles',
      billNo: _service!.billNo,
      status: _service!.status,
      mobileName: _service!.mobileName ?? 'Device',
    );
    await _waService.sendWhatsApp(phone: _customer!.phone!, message: msg);
  }

  Future<void> _sendSms() async {
    if (_customer?.phone == null) return;
    final msg = _waService.serviceStatusMessage(
      shopName: 'Professional Mobiles',
      billNo: _service!.billNo,
      status: _service!.status,
      mobileName: _service!.mobileName ?? 'Device',
    );
    await _waService.sendSms(phone: _customer!.phone!, message: msg);
  }

  Future<void> _fileWarrantyClaim() async {
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('File Warranty Claim'),
        content: TextField(
          controller: descCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Describe the issue'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('File Claim')),
        ],
      ),
    );
    if (ok == true && descCtrl.text.trim().isNotEmpty) {
      await _warrantyRepo.fileClaim(claimType: 'service', referenceId: widget.serviceId, description: descCtrl.text.trim());
      if (_customer?.phone != null && _customer!.phone!.trim().isNotEmpty) {
        // WhatsApp (Business by preference) first; SMS only as a fallback
        // when WhatsApp itself couldn't be launched - see the same fix in
        // ServiceFormScreen._submit for the full spec reference.
        final waMsg = _waService.warrantyClaimMessage(customerName: _customer!.name, referenceLabel: 'Service ${_service!.billNo}', description: descCtrl.text.trim());
        var waSent = false;
        try { waSent = await _waService.sendWhatsApp(phone: _customer!.phone!, message: waMsg); } catch (_) {}
        if (!waSent) {
          try { await _waService.sendSms(phone: _customer!.phone!, message: waMsg); } catch (_) {}
        }
      }
      await _serviceRepo.changeStatus(widget.serviceId, ServiceStatus.warranty, notes: descCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Warranty claim filed')));
      }
      _load();
    }
  }
}

class _QuickAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  _QuickAction(this.label, this.icon, this.onTap);
}
