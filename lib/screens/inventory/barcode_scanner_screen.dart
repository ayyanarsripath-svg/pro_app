import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_theme.dart';

/// Professional phone-camera barcode/QR scanner (spec item 1 & item 11):
/// full camera preview, a center scanning box, flash on/off, auto focus,
/// scan sound + vibration on every accepted scan, a Cancel button, and a
/// manual-barcode-entry fallback for a barcode that won't scan (damaged
/// label, bad lighting, etc).
///
/// Two modes:
///  - Single-shot (default, [continuous] = false): the FIRST accepted scan
///    immediately closes the screen and returns the code via
///    `Navigator.pop(context, code)` - used for "Scan Barcode" buttons on
///    Sales Bill / Service Bill / Purchase / Add Part-Accessory dialogs
///    ("Scan once + Enter Quantity" - spec item 12's second option; the
///    quantity dialog is shown by the caller right after this pops).
///  - Continuous ([continuous] = true): keeps the camera running and calls
///    [onScan] for every newly-accepted code without closing, showing a
///    small "recently scanned" strip at the bottom (spec item 11's "recent
///    scanned product display", item 12's "Fast Continuous Scanning mode -
///    repeated scans increment quantity"). The same barcode scanned again
///    after being out of frame for a moment is treated as a fresh, deliberate
///    re-scan (so repeated scans really can increment a running quantity);
///    only rapid-fire duplicate frames of the same still-in-view barcode
///    within [duplicateWindow] are suppressed (spec item 1's "duplicate scan
///    protection"). The shop closes this mode themselves via the Done button.
class BarcodeScannerScreen extends StatefulWidget {
  final bool continuous;
  final String title;

  /// Called once per newly-accepted scan. In single-shot mode this is
  /// optional (the screen just pops with the code); in continuous mode this
  /// is how the caller finds out about each scan.
  final void Function(String code)? onScan;

  /// Optional: resolve a scanned code to a human-readable line (e.g. the
  /// matching product's name + stock) shown in the "recently scanned" strip
  /// in continuous mode. Returning null shows "Not found in inventory".
  final Future<String?> Function(String code)? describeCode;

  final Duration duplicateWindow;

  const BarcodeScannerScreen({
    super.key,
    this.continuous = false,
    this.title = 'Scan Barcode',
    this.onScan,
    this.describeCode,
    this.duplicateWindow = const Duration(milliseconds: 1200),
  });

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _RecentScan {
  final String code;
  String description;
  int count;
  _RecentScan(this.code, this.description, this.count);
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  late final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
    detectionSpeed: DetectionSpeed.normal,
  );

  String? _lastCode;
  DateTime? _lastScanAt;
  final List<_RecentScan> _recent = [];
  bool _handledFirstScan = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!widget.continuous && _handledFirstScan) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code == null || code.trim().isEmpty) continue;
      _accept(code.trim());
      if (!widget.continuous) break;
    }
  }

  Future<void> _accept(String code) async {
    final now = DateTime.now();
    if (_lastCode == code && _lastScanAt != null && now.difference(_lastScanAt!) < widget.duplicateWindow) {
      // Same barcode still sitting in front of the camera from the scan we
      // already accepted a moment ago - ignore this repeat frame instead of
      // double-counting one physical scan (spec item 1: duplicate-scan
      // protection).
      return;
    }
    _lastCode = code;
    _lastScanAt = now;

    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);

    if (!widget.continuous) {
      if (_handledFirstScan) return;
      _handledFirstScan = true;
      if (mounted) Navigator.pop(context, code);
      return;
    }

    widget.onScan?.call(code);

    if (!mounted) return;
    setState(() {
      final existing = _recent.firstWhere((r) => r.code == code, orElse: () {
        final fresh = _RecentScan(code, 'Looking up…', 0);
        _recent.insert(0, fresh);
        return fresh;
      });
      existing.count += 1;
    });

    if (widget.describeCode != null) {
      final desc = await widget.describeCode!(code);
      if (!mounted) return;
      setState(() {
        final entry = _recent.firstWhere((r) => r.code == code, orElse: () => _RecentScan(code, '', 0));
        entry.description = desc ?? 'Not found in inventory';
      });
    }
  }

  Future<void> _manualEntry() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Barcode Manually'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Barcode / Code'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    if (code != null && code.isNotEmpty) {
      await _accept(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, child) => IconButton(
              icon: Icon(state.torchState == TorchState.on ? Icons.flash_on_rounded : Icons.flash_off_rounded),
              tooltip: 'Flash',
              onPressed: () => _controller.toggleTorch(),
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off_rounded, color: Colors.white70, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _cameraErrorMessage(error),
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _manualEntry,
                      icon: const Icon(Icons.keyboard_rounded),
                      label: const Text('Enter Barcode Manually'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _ScanWindowPainter(),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: widget.continuous && _recent.isNotEmpty ? 170 : 90,
            child: Center(
              child: Text(
                widget.continuous ? 'Point the camera at each barcode' : 'Align barcode inside the box',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (widget.continuous && _recent.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 70,
              height: 90,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                scrollDirection: Axis.horizontal,
                itemCount: _recent.length,
                itemBuilder: (context, i) {
                  final r = _recent[i];
                  return Container(
                    width: 190,
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(r.code, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(r.description, style: const TextStyle(color: Colors.white70, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (r.count > 1)
                          Text('x${r.count}', style: const TextStyle(color: AppColors.flameOrange, fontWeight: FontWeight.w800, fontSize: 12)),
                      ],
                    ),
                  );
                },
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: _manualEntry,
                  icon: const Icon(Icons.keyboard_rounded),
                  label: const Text('Enter Manually'),
                ),
                if (widget.continuous) ...[
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _cameraErrorMessage(MobileScannerException error) {
    if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
      return 'Camera permission was denied.\nPlease allow Camera access in phone Settings to scan barcodes.';
    }
    return 'Camera is unavailable right now.\nYou can still type the barcode below.';
  }
}

/// Draws a dark overlay over the whole preview with a clear, bordered
/// rectangle cut out in the center (spec item 11: "center scanning box").
class _ScanWindowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final boxWidth = size.width * 0.72;
    final boxHeight = boxWidth * 0.62;
    final rect = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2.4), width: boxWidth, height: boxHeight);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    final overlayPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
      Path()..addRRect(rrect),
    );
    canvas.drawPath(overlayPath, Paint()..color = Colors.black.withOpacity(0.55));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
