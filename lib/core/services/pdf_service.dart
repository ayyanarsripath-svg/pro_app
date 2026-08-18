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

/// Builds the three premium A5 bills (Service Job Card, Sales Bill, 2nd Hand
/// Sales Bill) described in spec sections 24-27. Every bill:
/// - prints the shop logo in a black & white friendly form so it looks
/// right on a plain B/W printer (per the shop owner's explicit request),
/// - embeds a Tamil-capable Unicode font so the ₹ symbol and Tamil text
/// always print correctly instead of falling back to a broken glyph box,
/// - NEVER prints internal purchase cost / spare part cost / profit /
/// margin (spec section 28) - only the customer-facing fields below are
/// ever laid out here.
class PdfService {
        final _settings = SettingsRepository();
        Uint8List? _logoBytes;
        Uint8List? _termsNoteBytes;
        pw.Font? _fontRegular;

        Future<Uint8List> _logo() async {
                  _logoBytes ??= (await rootBundle.load('assets/images/logo_bw.png')).buffer.asUint8List();
                  return _logoBytes!;
        }

        /// The 7-point Tamil return/repair policy note, pre-rendered as a crisp
        /// black & white image (exact wording, correctly shaped Tamil script)
        /// instead of drawn as live PDF text - the PDF text engine does not
        /// reorder/ligature Tamil vowel signs correctly, which made the note
        /// look garbled even with a Tamil font loaded. The image guarantees it
        /// prints exactly as written.
        Future<Uint8List> _termsNoteImage() async {
                  _termsNoteBytes ??= (await rootBundle.load('assets/images/terms_note.png')).buffer.asUint8List();
                  return _termsNoteBytes!;
        }

        Future<pw.Font> _regularFont() async {
                  _fontRegular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansTamil-Regular.ttf'));
                  return _fontRegular!;
        }

        /// Shared document theme. Using a Tamil-capable Unicode font as the base
        /// font (instead of the PDF package's default Helvetica, which has no
        /// glyph for ₹ or Tamil script) fixes the broken "x" box that used to
        /// print in place of the rupee sign in every amount, and makes the Tamil
        /// notes on the service bill render properly. The same font is used for
        /// bold text too (Noto Sans Tamil has no separate bold file bundled here)
        /// so headings simply print at regular weight - a small cosmetic trade
        /// for keeping the app's font assets tiny.
        Future<pw.ThemeData> _theme() async {
                  final font = await _regularFont();
                  return pw.ThemeData.withFont(base: font, bold: font, italic: font, boldItalic: font);
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
                                                                                                  width: 38,
                                                                                                  height: 38,
                                                                                                  margin: const pw.EdgeInsets.only(right: 8),
                                                                                                  child: pw.Image(pw.MemoryImage(logo)),
                                                                                                ),
                                                                              pw.Column(
                                                                                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                                                                                  children: [
                                                                                                                        pw.Text(shop['name']!,
                                                                                                                                                    style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, letterSpacing: 1)),
                                                                                                                        pw.Text(shop['tagline']!, style: const pw.TextStyle(fontSize: 8.5)),
                                                                                                                      ],
                                                                                                ),
                                                                            ],
                                                          ),
                                            pw.SizedBox(height: 2),
                                            pw.Text('${shop['address']} | Cell: ${shop['phone']}', style: const pw.TextStyle(fontSize: 8)),
                                            pw.SizedBox(height: 4),
                                            pw.Container(height: 1.2, width: 260, color: PdfColors.grey700),
                                            pw.SizedBox(height: 4),
                                            pw.Text(docTitle, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                                          ],
                            );
        }

        pw.Widget _box(String title, List<pw.Widget> children) {
                  return pw.Container(
                              width: double.infinity,
                              margin: const pw.EdgeInsets.only(bottom: 4),
                              padding: const pw.EdgeInsets.all(4),
                              decoration: pw.BoxDecoration(
                                            border: pw.Border.all(color: PdfColors.grey600, width: 0.7),
                                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                                          ),
                              child: pw.Column(
                                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                                            children: [
                                                            pw.Text(title,
                                                                                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
                                                            pw.SizedBox(height: 2),
                                                            ...children,
                                                          ],
                                          ),
                            );
        }

        /// Boxed Tamil terms & conditions note, printed from a pre-rendered image
        /// (see [_termsNoteImage]) so the exact wording and correct Tamil script
        /// shaping is guaranteed regardless of the PDF text engine's limits.
        Future<pw.Widget> _termsBox() async {
                  final bytes = await _termsNoteImage();
                  return pw.Container(
                              width: double.infinity,
                              padding: const pw.EdgeInsets.all(4),
                              decoration: pw.BoxDecoration(
                                            border: pw.Border.all(color: PdfColors.grey600, width: 0.7),
                                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                                          ),
                              child: pw.Image(pw.MemoryImage(bytes), width: 344, height: 107.3, fit: pw.BoxFit.fitWidth),
                            );
        }

        pw.Widget _kv(String k, String? v) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 1.5),
                      child: _kvText(k, v),
                    );

        /// Two key/value fields sharing a single row - keeps the right half of
        /// the A5 sheet from sitting empty when both fields are short, and cuts
        /// the number of printed lines (and therefore the page count) roughly
        /// in half versus stacking every field on its own line.
        pw.Widget _kv2(String k1, String? v1, String k2, String? v2) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 1.5),
                      child: pw.Row(
                                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                                      children: [
                                                        pw.Expanded(child: _kvText(k1, v1)),
                                                        pw.SizedBox(width: 6),
                                                        pw.Expanded(child: _kvText(k2, v2)),
                                                      ],
                                    ),
                    );

        pw.Widget _kvText(String k, String? v) => pw.RichText(
                      text: pw.TextSpan(
                                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.black),
                                      children: [
                                                        pw.TextSpan(text: '$k: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                                                        pw.TextSpan(text: v?.isNotEmpty == true ? v : '-'),
                                                      ],
                                    ),
                    );

        pw.Widget _signatures() {
                  return pw.Padding(
                              padding: const pw.EdgeInsets.only(top: 6),
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
                                                            _amountBlock('TOTAL AMOUNT', finalAmount),
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

        /// Service Job Card payment summary: TOTAL AMOUNT minus ADVANCE AMOUNT
        /// equals BALANCE AMOUNT, laid out as a centered subtraction so the
        /// customer can see exactly how the balance was worked out at a glance
        /// (e.g. Total 1200 - Advance 500 = Balance 700).
        pw.Widget _serviceAmountSummary({
                  required double totalAmount,
                  required double advanceAmount,
                  required double balanceAmount,
        }) {
                  return pw.Center(
                              child: pw.Container(
                                            width: 230,
                                            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: pw.BoxDecoration(
                                                          color: PdfColors.grey200,
                                                          border: pw.Border.all(color: PdfColors.grey700, width: 0.7),
                                                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                                                        ),
                                            child: pw.Column(
                                                          children: [
                                                                        _amountLine('TOTAL AMOUNT', totalAmount),
                                                                        _amountLine('- ADVANCE AMOUNT', advanceAmount),
                                                                        pw.Container(
                                                                                      margin: const pw.EdgeInsets.symmetric(vertical: 2.5),
                                                                                      height: 0.7,
                                                                                      color: PdfColors.grey700,
                                                                                    ),
                                                                        _amountLine(
                                                                                      balanceAmount > 0 ? 'BALANCE AMOUNT (PENDING)' : 'BALANCE AMOUNT',
                                                                                      balanceAmount,
                                                                                      emphasize: true,
                                                                                    ),
                                                                      ],
                                                        ),
                                          ),
                            );
        }

        pw.Widget _amountLine(String label, double amount, {bool emphasize = false}) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 1),
                      child: pw.Row(
                                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                      children: [
                                                        pw.Text(label,
                                                                          style: pw.TextStyle(fontSize: emphasize ? 9 : 8, fontWeight: pw.FontWeight.bold)),
                                                        pw.Text(formatCurrency(amount),
                                                                          style: pw.TextStyle(fontSize: emphasize ? 11 : 9, fontWeight: pw.FontWeight.bold)),
                                                      ],
                                    ),
                    );

        // -----------------------------------------------------------------
        // SERVICE JOB CARD (spec sections 19-25)
        // -----------------------------------------------------------------
        Future<Uint8List> buildServiceBill({
                  required ServiceJob service,
                  required Customer customer,
        }) async {
                  final shop = await _shopInfo();
                  final logo = await _logo();
                  final termsWidget = await _termsBox();
                  final doc = pw.Document(theme: await _theme());

                  doc.addPage(
                              pw.MultiPage(
                                            pageFormat: PdfPageFormat.a5,
                                            margin: const pw.EdgeInsets.all(14),
                                            build: (context) => [
                                                            _header(shop, logo, 'SERVICE JOB CARD'),
                                                            pw.SizedBox(height: 3),
                                                            pw.Row(
                                                                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                                                              children: [
                                                                                                  pw.Text('Bill No: ${service.billNo}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                                                                                                  pw.Text('Date: ${formatDate(service.createdAt)}'),
                                                                                                ],
                                                                            ),
                                                            pw.SizedBox(height: 4),
                                                            // Customer + device details share one box, two fields per row -
                                                            // this alone removes an entire box's border/title/padding
                                                            // overhead and uses the empty right half of the sheet, which
                                                            // is most of what was pushing the card onto a second page.
                                                            _box('CUSTOMER & DEVICE DETAILS', [
                                                                              _kv2('Name', customer.name, 'Phone', customer.phone),
                                                                              _kv2('Mobile', service.mobileName, 'Model', service.model),
                                                                              _kv('IMEI', service.imei),
                                                                            ]),
                                                            _box('ISSUE DETAILS', [
                                                                              _kv('Fault / Complaint', service.complaint),
                                                                              _kv2('Condition', service.deviceCondition, 'Existing Damage', service.existingDamage),
                                                                            ]),
                                                            _box('ACCESSORIES & WARRANTY', [
                                                                              pw.Wrap(spacing: 10, children: [
                                                                                                  _checkText('Charger', service.accCharger),
                                                                                                  _checkText('Cable', service.accCable),
                                                                                                  _checkText('SIM', service.accSim),
                                                                                                  _checkText('Memory Card', service.accMemoryCard),
                                                                                                  if ((service.accOther ?? '').isNotEmpty) pw.Text('Other: ${service.accOther}', style: const pw.TextStyle(fontSize: 9)),
                                                                                                ]),
                                                                              pw.SizedBox(height: 1),
                                                                              service.warranty
                                                                                                  ? _kv2('Warranty', 'Yes', 'Period', service.warrantyPeriod)
                                                                                                  : _kv('Warranty', 'No'),
                                                                            ]),
                                                  pw.SizedBox(height: 3),
                                                  // TOTAL AMOUNT - ADVANCE AMOUNT = BALANCE AMOUNT, centered so the
                                                  // customer can see the working at a glance.
                                                  _serviceAmountSummary(
                                                        totalAmount: service.finalAmount,
                                                        advanceAmount: service.paid,
                                                        balanceAmount: service.balance,
                                                        ),
                                                  pw.SizedBox(height: 3),
                                                  _box('DELIVERY', [
                                                        _kv2(
                                                              'Expected Delivery',
                                                              service.expectedDate != null ? formatDate(service.expectedDate!) : '-',
                                                              'Status',
                                                              service.deliveryStatus,
                                                              ),
                                                        ]),
                                                  pw.SizedBox(height: 2),
                                                  termsWidget,
                                                  _signatures(),
                                                  ],
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
            final doc = pw.Document(theme: await _theme());

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
                                          pw.Text('Customer: ${customer?.name ?? 'Walk-in Customer'} ${customer?.phone ?? ''}',
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
            final doc = pw.Document(theme: await _theme());

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
            final doc = pw.Document(theme: await _theme());

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
