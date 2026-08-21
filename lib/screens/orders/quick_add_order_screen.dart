import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/repositories/daily_order_repository.dart';
import '../../core/services/daily_order_widget_service.dart';
import '../../core/services/widget_launch_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

/// Reached only by tapping "+ Add" on the Daily Orders home-screen widget
/// (see WidgetLaunchState / app.dart's _RootGate) - deliberately outside
/// the normal staff PIN gate, so noting down one part on the way past
/// never needs a login. Writes straight to the same table DailyOrderScreen
/// reads from, then refreshes the widget so the new item shows up there
/// immediately.
///
/// Closing this screen (via the back button, the X, or after saving)
/// always finishes the whole app back to the home screen, exactly like a
/// quick widget action - it never drops into the rest of the app, since
/// nothing past this point should be reachable without the real PIN login.
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

  void _closeToHomeScreen() {
    // Consumed - a normal app open after this goes through the regular
    // PIN gate again, same as before this screen was ever shown.
    WidgetLaunchState.quickAddRequested.value = false;
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
                  decoration: const InputDecoration(labelText: 'Phone (optional)', border: OutlineInputBorder()),
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
