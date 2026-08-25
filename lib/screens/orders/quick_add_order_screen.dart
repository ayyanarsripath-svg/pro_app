import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/repositories/daily_order_repository.dart';
import '../../core/services/daily_order_widget_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

/// Reached ONLY via the Daily Orders home-screen widget's "+ Add"/card tap
/// - see main.dart's quickAddMain() entry point and QuickAddActivity.kt
/// (injected into android/ by the CI build script). That tap launches a
/// completely separate Android Activity running a separate, minimal
/// Flutter engine that shows nothing but this screen - the main app
/// (MainActivity, the staff PIN gate, the dashboard) is never started, so
/// this genuinely never "opens pro_app" the way the app normally opens.
/// Writes straight to the same table DailyOrderScreen reads from, then
/// refreshes the widget so the new item shows up there immediately.
///
/// Closing this screen (via the back button, the X, or after saving)
/// finishes this whole separate Activity/task straight back to the home
/// screen - there is no "rest of the app" to drop into from here, since
/// this runs in its own isolated engine.
class QuickAddOrderScreen extends StatefulWidget {
  const QuickAddOrderScreen({super.key});

  @override
  State<QuickAddOrderScreen> createState() => _QuickAddOrderScreenState();
}

class _QuickAddOrderScreenState extends State<QuickAddOrderScreen> {
  final _repo = DailyOrderRepository();
  final _widgetService = DailyOrderWidgetService();

  final _partCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _saving = false;
  int _addedCount = 0;

  @override
  void dispose() {
    _partCtrl.dispose();
    _typeCtrl.dispose();
    _qtyCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _callPhone(String phone) async {
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {}
  }

  void _closeToHomeScreen() {
    // This screen runs in its own separate Activity/task (see the class
    // doc comment) - popping it finishes that whole task straight back to
    // the home screen, without ever having touched the main app.
    SystemNavigator.pop();
  }

  Future<void> _save({required bool addAnother}) async {
    final part = _partCtrl.text.trim();
    final qty = _qtyCtrl.text.trim();
    if (part.isEmpty || qty.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Part/Accessory name and Quantity are required')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final today = isoDateFormat.format(DateTime.now());
      await _repo.create(
        orderDate: today,
        partName: part,
        typeModel: _typeCtrl.text.trim().isEmpty ? null : _typeCtrl.text.trim(),
        quantity: qty,
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      );
      await _widgetService.refresh();
      _addedCount++;

      if (!mounted) return;
      if (addAnother) {
        _partCtrl.clear();
        _typeCtrl.clear();
        _qtyCtrl.clear();
        _phoneCtrl.clear();
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added "$part". Note the next item...')),
        );
      } else {
        // BUG FIX: this used to call _closeToHomeScreen() immediately after
        // awaiting refresh() - but refresh() awaiting the Dart-side
        // saveWidgetData/updateWidget calls only guarantees THIS engine
        // issued those platform-channel calls, not that Android's
        // SharedPreferences write has actually reached disk and the home
        // screen's widget host has actually redrawn before
        // SystemNavigator.pop() tears this whole separate Activity/engine
        // down (spec: "once order enter pannathukku aporom preview
        // therithu but konja neram kazhichi marubadi order enter panna
        // antha preview katta mattangithu" - worked at first, then
        // intermittently stopped reflecting the newest item). A short
        // pause here gives that native work time to actually land before
        // the process that triggered it disappears - cheap insurance
        // against a race that otherwise only shows up "sometimes".
        await Future.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        _closeToHomeScreen();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add item: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeToHomeScreen();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_addedCount == 0 ? 'Quick Add Order' : 'Quick Add Order ($_addedCount added)'),
          leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: _closeToHomeScreen),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primaryBlue.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt_rounded, color: AppColors.primaryBlue, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "From the widget - straight to today's order note, no login needed.",
                          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondaryOf(context)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _partCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Part / Accessory Name *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _typeCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Type / Model', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone (optional)',
                    border: const OutlineInputBorder(),
                    // Same "call right from here" convenience as the full
                    // Daily Orders screen's Add/Edit Item dialogs (spec:
                    // "phone number note pannathukku aprom call panra
                    // option ella call panni inform panrathukku option
                    // kudu") - useful since this quick-add screen is
                    // reached straight from the home-screen widget, with
                    // no easy way back to the full item list to find the
                    // same call button there.
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.call_rounded),
                      tooltip: 'Call this number',
                      onPressed: () {
                        final phone = _phoneCtrl.text.trim();
                        if (phone.isNotEmpty) _callPhone(phone);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : () => _save(addAnother: false),
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded),
                    label: const Text('Save & Close'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _save(addAnother: true),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Save & Add Another'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
