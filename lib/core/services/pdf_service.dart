import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../repositories/settings_repository.dart';
import '../utils/formatters.dart';
import '../../models/customer.dart';
import '../../models/second_hand_phone.dart';
import '../../models/sales_bill.dart';
import '../../models/service.dart';
import 'pnl_service.dart';

const _tamilFooterNote =
    'குறிப்பு : பழுது பார்க்க குடுத்த செல்போன் 21 நாள்களுக்குள் திரும்ப பெறவில்லை '
    'எனில் நிர்வாகம் பொறுப்பில்லை. நீங்கள் மாற்றும் வாரன்டி இல்லாத உதிரி பாகங்கள் '
    'அல்லது பொருட்களுக்கு உத்திரவாதம் கிடையாது';

/// Builds the three premium A5 bills (Service Job Card, Sales Bill, 2nd Hand
/// Sales Bill) described in spec sections 24-27. Every bill:
///  - prints the shop logo in a black & white friendly form so it looks
///    right on a plain B/W printer (per the shop owner's explicit request),
///  - NEVER prints internal purchase cost / spare part cost / profit /
///    margin (spec section 28) - only the customer-facing fields below are
///    ever laid out here.
class PdfService {
  final _settings = SettingsRepository();
  Uint8List? _logoBytes;

  Future<Uint8List> _logo() async {
    _logoBytes ??= (await rootBundle.load('assets/images/logo_bw.png')).buffer.asUint8List();
    return _logoBytes!;
  }

  Future<Map<String, String>> _shopInfo() async {
    final all = await _settings.getAll();
    return {
      'name': all[SettingsRepository.shopName] ?? 'PROFESSIONAL MOBILES',
      'tagline': all[SettingsRepository.shopTagline] ?? 'SERVICE & 2ND HAND SALES',
      'address': all[SettingsRepository.shopAddress] ?? 'Mainroad, Ma.Kunnathur',
      'phone': all[SettingsRepository.shopPhone] ?? '7806938306',
    };
  }

  pw.Widget _header(Map<String, String> shop, Uint8List logo, String docTitle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 46,
              height: 46,
              margin: const pw.EdgeInsets.only(right: 10),
              child: pw.Image(pw.MemoryImage(logo)),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(shop['name']!,
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, letterSpacing: 1)),
                pw.Text(shop['tagline']!, style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 3),
        pw.Text('${shop['address']}   |   Cell: ${shop['phone']}', style: const pw.TextStyle(fontSize: 8.5)),
        pw.SizedBox(height: 6),
        pw.Container(height: 1.2, width: 260, color: PdfColors.grey700),
        pw.SizedBox(height: 6),
        pw.Text(docTitle, style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  pw.Widget _box(String title, List<pw.Widget> children) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey600, width: 0.7),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
          pw.SizedBox(height: 3),
          ...children,
        ],
      ),
    );
  }

  pw.Widget _kv(String k, String? v) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 1.5),
        child: pw.RichText(
          text: pw.TextSpan(
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.black),
            children: [
              pw.TextSpan(text: '$k: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.TextSpan(text: v?.isNotEmpty == true ? v : '-'),
            ],
          ),
        ),
      );

  pw.Widget _signatures() {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 22),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(children: [
            pw.Container(width: 140, height: 0.7, color: PdfColors.black),
            pw.SizedBox(height: 3),
            pw.Text('Customer Signature', style: const pw.TextStyle(fontSize: 8)),
          ]),
          pw.Column(children: [
            pw.Container(width: 140, height: 0.7, color: PdfColors.black),
            pw.SizedBox(height: 3),
            pw.Text('Admin Signature', style: const pw.TextStyle(fontSize: 8)),
          ]),
        ],
      ),
    );
  }

  pw.Widget _paymentSummary({
    required double finalAmount,
    required double paid,
    required double balance,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        border: pw.Border.all(color: PdfColors.grey700, width: 0.7),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _amountBlock('FINAL AMOUNT', finalAmount),
          _amountBlock('PAID', paid),
          _amountBlock(balance > 0 ? 'BALANCE (PENDING)' : 'BALANCE', balance),
        ],
      ),
    );
  }

  pw.Widget _amountBlock(String label, double amount) => pw.Column(children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text(formatCurrency(amount), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      ]);

  // -----------------------------------------------------------------
  // SERVICE JOB CARD (spec sections 19-25)
  // -----------------------------------------------------------------
  Future<Uint8List> buildServiceBill({
    required ServiceJob service,
    required Customer customer,
  }) async {
    final shop = await _shopInfo();
    final logo = await _logo();
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(18),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _header(shop, logo, 'SERVICE JOB CARD'),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Bill No: ${service.billNo}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('Date: ${formatDate(service.createdAt)}'),
                ],
              ),
              pw.SizedBox(height: 6),
              _box('CUSTOMER DETAILS', [
                _kv('Name', customer.name),
                _kv('Phone', customer.phone),
              ]),
              _box('DEVICE DETAILS', [
                _kv('Mobile', service.mobileName),
                _kv('Model', service.model),
                _kv('IMEI', service.imei),
              ]),
              _box('FAULT / COMPLAINT', [pw.Text(service.complaint ?? '-', style: const pw.TextStyle(fontSize: 9))]),
              _box('DEVICE CONDITION', [pw.Text(service.deviceCondition ?? '-', style: const pw.TextStyle(fontSize: 9))]),
              _box('EXISTING DAMAGE', [pw.Text(service.existingDamage ?? '-', style: const pw.TextStyle(fontSize: 9))]),
              _box('ACCESSORIES RECEIVED', [
                pw.Wrap(spacing: 10, children: [
                  _checkText('Charger', service.accCharger),
                  _checkText('Cable', service.accCable),
                  _checkText('SIM', service.accSim),
                  _checkText('Memory Card', service.accMemoryCard),
                  if ((service.accOther ?? '').isNotEmpty) pw.Text('Other: ${service.accOther}', style: const pw.TextStyle(fontSize: 9)),
                ]),
              ]),
              _box('WARRANTY', [
                _kv('Warranty', service.warranty ? 'Yes' : 'No'),
                if (service.warranty) _kv('Period', service.warrantyPeriod),
              ]),
              pw.SizedBox(height: 4),
              _paymentSummary(finalAmount: service.finalAmount, paid: service.paid, balance: service.balance),
              pw.SizedBox(height: 4),
              _box('DELIVERY', [
                _kv('Expected Delivery', service.expectedDate != null ? formatDate(service.expectedDate!) : '-'),
                _kv('Status', service.deliveryStatus),
              ]),
              pw.Spacer(),
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(
                  _tamilFooterNote,
                  style: const pw.TextStyle(fontSize: 7.2),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              _signatures(),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  pw.Widget _checkText(String label, bool checked) => pw.Text(
        '${checked ? '[x]' : '[ ]'} $label',
        style: const pw.TextStyle(fontSize: 9),
      );

  // -----------------------------------------------------------------
  // SALES BILL (accessories / general sales - spec section 26)
  // -----------------------------------------------------------------
  Future<Uint8List> buildSalesBill({
    required SalesBill bill,
    required List<SalesBillItem> items,
    Customer? customer,
  }) async {
    final shop = await _shopInfo();
    final logo = await _logo();
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(18),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _header(shop, logo, 'SALES BILL'),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Bill No: ${bill.billNo}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('Date: ${formatDate(bill.saleDate)}'),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Text('Customer: ${customer?.name ?? 'Walk-in Customer'}   ${customer?.phone ?? ''}',
                  style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.6),
                columnWidths: const {
                  0: pw.FlexColumnWidth(4),
                  1: pw.FlexColumnWidth(1.3),
                  2: pw.FlexColumnWidth(1.7),
                  3: pw.FlexColumnWidth(1.7),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      _th('Product'),
                      _th('Qty'),
                      _th('Rate'),
                      _th('Total'),
                    ],
                  ),
                  for (final item in items)
                    pw.TableRow(children: [
                      _td(item.itemName),
                      _td(item.quantity.toStringAsFixed(item.quantity == item.quantity.roundToDouble() ? 0 : 2)),
                      _td(formatCurrency(item.rate)),
                      _td(formatCurrency(item.total)),
                    ]),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Subtotal: ${formatCurrency(bill.subtotal)}', style: const pw.TextStyle(fontSize: 9)),
                    if (bill.discount > 0)
                      pw.Text('Discount: -${formatCurrency(bill.discount)}', style: const pw.TextStyle(fontSize: 9)),
                    pw.Text('Total: ${formatCurrency(bill.total)}',
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),
              _paymentSummary(finalAmount: bill.total, paid: bill.paid, balance: bill.balance),
              pw.SizedBox(height: 4),
              pw.Text('Payment Method: ${bill.paymentMethod ?? '-'}', style: const pw.TextStyle(fontSize: 9)),
              pw.Spacer(),
              _signatures(),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  // -----------------------------------------------------------------
  // 2ND HAND SALES BILL (spec section 27) - never shows shop purchase
  // price or profit.
  // -----------------------------------------------------------------
  Future<Uint8List> buildSecondHandSalesBill({
    required SecondHandPhone phone,
    required SecondHandSale sale,
    Customer? customer,
  }) async {
    final shop = await _shopInfo();
    final logo = await _logo();
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(18),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _header(shop, logo, '2ND HAND MOBILE - SALES BILL'),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Sales Bill No: ${sale.billNo}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('Date: ${formatDate(sale.saleDate)}'),
                ],
              ),
              pw.SizedBox(height: 6),
              _box('CUSTOMER', [
                _kv('Name', customer?.name ?? 'Walk-in Customer'),
                _kv('Phone', customer?.phone),
              ]),
              _box('DEVICE', [
                _kv('Brand', phone.brand),
                _kv('Model', phone.model),
                _kv('IMEI', phone.imei1),
                _kv('RAM / Storage', '${phone.ram ?? '-'} / ${phone.storage ?? '-'}'),
                _kv('Condition', phone.conditionGrade),
                _kv('Battery Health', phone.batteryHealth),
              ]),
              _box('WARRANTY', [
                _kv('Warranty', sale.warranty ? 'Yes' : 'No'),
                if (sale.warranty) _kv('Period', sale.warrantyPeriod),
              ]),
              pw.SizedBox(height: 4),
              _paymentSummary(finalAmount: sale.salePrice, paid: sale.paid, balance: sale.balance),
              pw.SizedBox(height: 4),
              pw.Text('Payment Method: ${sale.paymentMethod ?? '-'}', style: const pw.TextStyle(fontSize: 9)),
              pw.Spacer(),
              _signatures(),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  // -----------------------------------------------------------------
  // PROFIT & LOSS report (spec sections 15 & 32) - A4, admin-only export.
  // -----------------------------------------------------------------
  Future<Uint8List> buildPnlReport({
    required String periodLabel,
    required BusinessTotals totals,
  }) async {
    final shop = await _shopInfo();
    final logo = await _logo();
    final doc = pw.Document();

    pw.TableRow row(String label, CategorySummary c) => pw.TableRow(children: [
          _td(label),
          _td(formatCurrency(c.revenue)),
          _td(formatCurrency(c.cost)),
          _td(formatCurrency(c.grossProfit)),
          _td(formatCurrency(c.expenses)),
          _td(formatCurrency(c.netProfit)),
        ]);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _header(shop, logo, 'PROFIT & LOSS REPORT'),
              pw.SizedBox(height: 4),
              pw.Center(child: pw.Text(periodLabel, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 14),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.6),
                columnWidths: const {
                  0: pw.FlexColumnWidth(2.2),
                  1: pw.FlexColumnWidth(1.4),
                  2: pw.FlexColumnWidth(1.4),
                  3: pw.FlexColumnWidth(1.4),
                  4: pw.FlexColumnWidth(1.4),
                  5: pw.FlexColumnWidth(1.4),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                    children: [_th('Category'), _th('Revenue'), _th('Cost'), _th('Gross Profit'), _th('Expenses'), _th('Net Profit')],
                  ),
                  row('Service', totals.service),
                  row('Accessories', totals.accessories),
                  row('2nd Hand', totals.secondHand),
                  row('Other Sales', totals.other),
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _td('TOTAL', bold: true),
                      _td(formatCurrency(totals.totalRevenue), bold: true),
                      _td(formatCurrency(totals.totalDirectCost), bold: true),
                      _td(formatCurrency(totals.grossProfit), bold: true),
                      _td(formatCurrency(totals.categoryExpenses + totals.generalExpenses), bold: true),
                      _td(formatCurrency(totals.netProfit), bold: true),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Text('General Business Expenses: ${formatCurrency(totals.generalExpenses)}', style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 4),
              pw.Text('Gross Profit = Total Revenue - Total Direct Cost', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              pw.Text('Net Profit = Gross Profit - Operating Expenses', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  pw.Widget _th(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(text, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _td(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );
}
