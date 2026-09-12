import 'dart:typed_data';

import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/theme/app_theme.dart';

/// Barcode Generation label (spec item 5): Display/Print/Share a label for a
/// product's barcode showing Product Name, Model, Barcode, and (optionally)
/// Selling Price. Works for BOTH kinds of barcode the spec describes - an
/// existing manufacturer barcode saved as-is (System A) or one this app
/// generated internally (System B, see BarcodeGenerator) - the label itself
/// doesn't care which.
class BarcodeLabelScreen extends StatelessWidget {
  final String productName;
  final String? model;
  final String barcode;
  final double? sellingPrice;

  const BarcodeLabelScreen({
    super.key,
    required this.productName,
    this.model,
    required this.barcode,
    this.sellingPrice,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Barcode Label')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderOf(context)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(productName, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 16)),
                    if (model != null && model!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(model!, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                      ),
                    const SizedBox(height: 10),
                    bw.BarcodeWidget(
                      barcode: bw.Barcode.code128(),
                      data: barcode,
                      width: 240,
                      height: 90,
                      drawText: true,
                      style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (sellingPrice != null) ...[
                      const SizedBox(height: 8),
                      Text('₹${sellingPrice!.toStringAsFixed(0)}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 16)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _print(context),
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('Print'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _share(context),
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Share'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _buildPdf() async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(226, 141, marginAll: 10), // ~80mm x 50mm label
        build: (context) => pw.Center(
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(productName, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              if (model != null && model!.trim().isNotEmpty)
                pw.Text(model!, style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 6),
              pw.BarcodeWidget(
                data: barcode,
                barcode: pw.Barcode.code128(),
                width: 190,
                height: 60,
                drawText: true,
                textStyle: const pw.TextStyle(fontSize: 9),
              ),
              if (sellingPrice != null) ...[
                pw.SizedBox(height: 4),
                pw.Text('Rs. ${sellingPrice!.toStringAsFixed(0)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
    return doc.save();
  }

  Future<void> _print(BuildContext context) async {
    try {
      final bytes = await _buildPdf();
      await Printing.layoutPdf(name: 'Barcode_$barcode', onLayout: (format) async => bytes);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not print label: $e')));
      }
    }
  }

  Future<void> _share(BuildContext context) async {
    try {
      final bytes = await _buildPdf();
      await Printing.sharePdf(bytes: bytes, filename: 'Barcode_$barcode.pdf');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not share label: $e')));
      }
    }
  }
}
