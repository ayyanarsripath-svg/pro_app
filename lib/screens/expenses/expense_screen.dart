import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/repositories/expense_repository.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/expense.dart';
import '../../widgets/section_card.dart';

class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  final _repo = ExpenseRepository();
  List<Expense> _expenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _repo.all();
    setState(() {
      _expenses = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final total = _expenses.fold<double>(0, (s, e) => s + e.amount);
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.06), borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Expenses (All Time)', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text(formatCurrency(total), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.red)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (_expenses.isEmpty) const EmptyState(icon: Icons.money_off_rounded, message: 'No expenses recorded'),
                ..._expenses.map((e) => Card(
                      child: ListTile(
                        title: Text('${e.category}  •  ${formatCurrency(e.amount)}'),
                        subtitle: Text('${e.description ?? ''}\n${formatDate(e.expenseDate)}  •  ${e.paymentMethod ?? '-'}  •  ${_allocationLabel(e.allocation)}'),
                        isThreeLine: true,
                        trailing: auth.canDelete
                            ? IconButton(
                                icon: const Icon(Icons.delete_rounded, color: AppColors.danger),
                                tooltip: 'Delete expense',
                                onPressed: () => _delete(e),
                              )
                            : null,
                      ),
                    )),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExpense,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Expense'),
      ),
    );
  }

  /// Admin/permission-gated Delete (small confirmation dialog, same pattern
  /// used for accessories/spare parts). Also removes the matching P&L
  /// ledger row via ExpenseRepository.delete.
  Future<void> _delete(Expense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Expense?'),
        content: Text('${e.category} - ${formatCurrency(e.amount)} will be removed and its P&L entry reversed. This cannot be undone from here.'),
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
      await _repo.delete(e.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense deleted')));
      }
      _load();
    }
  }

  String _allocationLabel(String allocation) {
    switch (allocation) {
      case ExpenseAllocation.service:
        return 'Service Expense';
      case ExpenseAllocation.accessories:
        return 'Accessories Expense';
      case ExpenseAllocation.secondHand:
        return '2nd Hand Expense';
      case ExpenseAllocation.other:
        return 'Other';
      default:
        return 'General Business Expense';
    }
  }

  Future<void> _addExpense() async {
    String category = ExpenseCategory.defaults.first;
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String paymentMethod = 'Cash';
    String allocation = ExpenseAllocation.general;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Add Expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: category,
                  isExpanded: true,
                  items: ExpenseCategory.defaults.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setLocalState(() => category = v ?? category),
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                const SizedBox(height: 10),
                TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (₹)')),
                const SizedBox(height: 10),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: paymentMethod,
                  items: ['Cash', 'UPI', 'Card', 'Bank Transfer'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) => setLocalState(() => paymentMethod = v ?? paymentMethod),
                  decoration: const InputDecoration(labelText: 'Payment Method'),
                ),
                const SizedBox(height: 10),
                // "2nd Hand Business Expense" is deliberately NOT offered
                // here: a 2nd-hand phone's purchase cost already hits the
                // dashboard/P&L total the moment it's added to stock, so
                // logging it again here would double-count it. The enum
                // value/label are kept (see _allocationLabel) purely so
                // any already-recorded historical expenses still display
                // correctly.
                DropdownButtonFormField<String>(
                  value: allocation,
                  items: const [
                    DropdownMenuItem(value: ExpenseAllocation.general, child: Text('General Business Expense')),
                    DropdownMenuItem(value: ExpenseAllocation.service, child: Text('Service Expense')),
                    DropdownMenuItem(value: ExpenseAllocation.accessories, child: Text('Accessories Expense')),
                    DropdownMenuItem(value: ExpenseAllocation.other, child: Text('Other')),
                  ],
                  onChanged: (v) => setLocalState(() => allocation = v ?? allocation),
                  decoration: const InputDecoration(labelText: 'Allocation'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (ok == true) {
      final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
      if (amount > 0) {
        await _repo.create(
          expenseDate: DateTime.now(),
          category: category,
          amount: amount,
          paymentMethod: paymentMethod,
          description: descCtrl.text.trim(),
          allocation: allocation,
        );
        _load();
      }
    }
  }
}
