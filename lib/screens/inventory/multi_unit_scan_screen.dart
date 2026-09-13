import 'package:flutter/material.dart';

import '../../core/repositories/product_barcode_repository.dart';
import '../../core/repositories/product_draft_repository.dart';
import '../../core/theme/app_theme.dart';
import 'barcode_scanner_screen.dart';

/// Step 2 of the multi-scan "Add Product" flow (spec: "boat headphone
/// enkitta 30 pcs erukku inventory la add pannumpothu 30 pcs ku thani
/// thaniya text enter pannittu erukka mudiyathu oru text multi scan after
/// save" - enter the product's details once, then scan every physical
/// unit's own barcode/QR one after another, each accepted scan counting as
/// one more unit of that same new product).
///
/// Every accepted scan is written straight to [ProductDraftRepository] so
/// the whole session survives the shop's phone Back button, the app being
/// swiped from Recents, or a full close/reopen (spec: "naduvula back
/// vantha entire process cancel aagakudathu resume aaganum") - reopening
/// "Add Part"/"Add Accessory" later detects the unfinished draft and offers
/// to resume it right back into this same screen with everything already
/// scanned still there. A wrongly-scanned code can be removed individually
/// from the list below without discarding the rest of the session (spec:
/// "chinna thappu pannalum aprom first la erunthu pannanum" - one small
/// mistake shouldn't mean starting over).
class MultiUnitScanScreen extends StatefulWidget {
  final String productType; // ProductTypes.sparePart | ProductTypes.accessory
  final Map<String, String> details;
  final List<String> initialBarcodes;
  final String title;

  /// Creates the actual product (+ initial stock/purchase transaction) once
  /// the shop taps Save - the caller knows exactly which repository/fields
  /// apply for its product type. This screen only owns the scanning/review
  /// UI and the draft persistence, never the product schema itself.
  final Future<void> Function(List<String> barcodes) onFinalize;

  const MultiUnitScanScreen({
    super.key,
    required this.productType,
    required this.details,
    required this.initialBarcodes,
    required this.title,
    required this.onFinalize,
  });

  @override
  State<MultiUnitScanScreen> createState() => _MultiUnitScanScreenState();
}

class _MultiUnitScanScreenState extends State<MultiUnitScanScreen> {
  final _barcodeRepo = ProductBarcodeRepository();
  final _draftRepo = ProductDraftRepository();
  late final List<String> _scanned = List.of(widget.initialBarcodes);
  bool _saving = false;

  Future<void> _scanMore() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BarcodeScannerScreen(
          continuous: true,
          title: 'Scan Each Unit',
          // All the accept/reject logic lives here (not in onScan) so it
          // runs sequentially, awaited, with no race against the strip's
          // own display update - see this screen's class doc comment.
          describeCode: (code) async {
            if (_scanned.contains(code)) return 'Already scanned in this session';
            final available = await _barcodeRepo.isAvailable(code);
            if (!available) {
              final resolved = await _barcodeRepo.resolve(code);
              return 'Already used by ${resolved?.name ?? 'another product'} - skipped';
            }
            if (mounted) setState(() => _scanned.add(code));
            await _draftRepo.save(productType: widget.productType, details: widget.details, barcodes: _scanned);
            return 'Unit #${_scanned.length} added';
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _removeAt(int i) {
    setState(() => _scanned.removeAt(i));
    _draftRepo.save(productType: widget.productType, details: widget.details, barcodes: _scanned);
  }

  Future<void> _save() async {
    if (_scanned.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scan at least one barcode first.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onFinalize(List.of(_scanned));
      await _draftRepo.clear(widget.productType);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: AppColors.primaryBlue.withOpacity(0.08),
            child: Text(
              '${_scanned.length} unit(s) scanned so far - each barcode/QR counts as 1 quantity. '
              'Closing this screen keeps your progress; come back any time to continue.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: _scanned.isEmpty
                ? const Center(child: Text('No barcodes scanned yet'))
                : ListView.builder(
                    itemCount: _scanned.length,
                    itemBuilder: (context, i) => ListTile(
                      leading: CircleAvatar(child: Text('${i + 1}')),
                      title: Text(_scanned[i]),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppColors.danger),
                        tooltip: 'Remove this scan',
                        onPressed: () => _removeAt(i),
                      ),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _scanMore,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('Scan More'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(_saving ? 'Saving...' : 'Save Product'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
