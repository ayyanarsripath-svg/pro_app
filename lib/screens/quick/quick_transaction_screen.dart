import 'package:flutter/material.dart';

import '../../core/repositories/quick_transaction_repository.dart';
import '../../core/theme/app_theme.dart';

/// Fast Income/Expense entry (spec: "PRO SERVICE – Quick Income & Expense
/// Entry Feature", items 2 & 3 - "Minimum interaction-ல் transaction save
/// ஆக வேண்டும்"). Reached today from the Dashboard's Quick Income/Quick
/// Expense buttons. The persistent notification, home-screen widget, Quick
/// Settings tile and voice-entry pieces described in the same spec are
/// separate native-Android follow-ups; once built, each of them opens this
/// exact screen (or calls QuickTransactionRepository directly for the
/// notification's own inline buttons) - the save logic here does not
/// change when those arrive, only how this screen gets reached.
class QuickTransactionScreen extends StatefulWidget {
  final bool startAsExpense;
  const QuickTransactionScreen({super.key, this.startAsExpense = false});

  @override
  State<QuickTransactionScreen> createState() => _QuickTransactionScreenState();
}

class _QuickTransactionScreenState extends State<QuickTransactionScreen> {
  final _repo = QuickTransactionRepository();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _amountFocus = FocusNode();
  late bool _isExpense;
  late String _category;
  bool _saving = false;
  int _savedCount = 0;

  @override
  void initState() {
    super.initState();
    _isExpense = widget.startAsExpense;
    _category = _categories.first;
  }

  List<String> get _categories =>
      _isExpense ? QuickTransactionCategory.expenseCategories : QuickTransactionCategory.incomeCategories;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Future<void> _save({bool addAnother = false}) async {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter an amount')));
      return;
    }
    setState(() => _saving = true);
    try {
      final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
      if (_isExpense) {
        await _repo.recordExpense(amount: amount, category: _category, note: note);
      } else {
        await _repo.recordIncome(amount: amount, category: _category, note: note);
      }
      if (!mounted) return;
      _savedCount++;
      if (addAnother) {
        _amountCtrl.clear();
        _noteCtrl.clear();
        setState(() => _saving = false);
        // Cursor back to Amount so the next entry can be typed straight
        // away, same "no extra tap" convenience as Quick Add Order.
        FocusScope.of(context).requestFocus(_amountFocus);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_isExpense ? 'Expense' : 'Income'} of ₹${amount.toStringAsFixed(0)} saved')),
        );
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _isExpense ? AppColors.danger : AppColors.success;
    return Scaffold(
      appBar: AppBar(
        title: Text(_savedCount == 0
            ? (_isExpense ? 'Quick Expense' : 'Quick Income')
            : '${_isExpense ? 'Quick Expense' : 'Quick Income'} ($_savedCount saved)'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Income/Expense toggle - switching resets the category to
              // the new list's first entry so a stale Expense category
              // (e.g. "Shop Rent") can never get silently saved as Income,
              // or vice versa.
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Income'), icon: Icon(Icons.add_circle_outline_rounded)),
                  ButtonSegment(value: true, label: Text('Expense'), icon: Icon(Icons.remove_circle_outline_rounded)),
                ],
                selected: {_isExpense},
                onSelectionChanged: (s) => setState(() {
                  _isExpense = s.first;
                  _category = _categories.first;
                }),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _amountCtrl,
                focusNode: _amountFocus,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
                decoration: const InputDecoration(labelText: 'Amount (₹) *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _noteCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
                  onPressed: _saving ? null : () => _save(),
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
    );
  }
}
