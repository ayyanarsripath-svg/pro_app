import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/repositories/expense_repository.dart';
import '../../core/repositories/ledger_repository.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/section_card.dart';

/// Internal, screen-only combined row - a Quick Income entry (from the
/// ledger, referenceType 'quick_income') and a Quick Expense entry (from
/// the expenses table, source 'quick') have different underlying models,
/// but this screen only ever needs to show/delete them side by side.
class _QuickEntry {
  final String id;
  final bool isExpense;
  final double amount;
  final String label;
  final DateTime date;
  _QuickEntry({required this.id, required this.isExpense, required this.amount, required this.label, required this.date});
}

/// Dedicated Quick Income/Quick Expense history (spec: "quick expenses and
/// quick income ku thaniya oru history create pannikkalam expenses menu la
/// ella history create pannidalam" - Quick Expense entries were landing
/// mixed into the general Settings -> Expenses list with nothing marking
/// them apart from a manually-added shop expense, and Quick Income had no
/// history view anywhere). Both still feed the exact same underlying
/// tables the rest of the app already reads for Dashboard/P&L (see
/// QuickTransactionRepository's class doc comment) - this screen is purely
/// an additional, filtered view onto that same data, not a separate ledger.
class QuickHistoryScreen extends StatefulWidget {
  const QuickHistoryScreen({super.key});

  @override
  State<QuickHistoryScreen> createState() => _QuickHistoryScreenState();
}

class _QuickHistoryScreenState extends State<QuickHistoryScreen> {
  final _expenseRepo = ExpenseRepository();
  final _ledgerRepo = LedgerRepository();
  List<_QuickEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final incomes = await _ledgerRepo.byReferenceType('quick_income');
    final expenses = await _expenseRepo.quickOnly();
    final entries = <_QuickEntry>[
      ...incomes.map((t) => _QuickEntry(
            id: t.id,
            isExpense: false,
            amount: t.amount,
            label: (t.description == null || t.description!.trim().isEmpty) ? t.category : t.description!,
            date: t.txnDate,
          )),
      ...expenses.map((e) => _QuickEntry(
            id: e.id,
            isExpense: true,
            amount: e.amount,
            label: (e.description == null || e.description!.trim().isEmpty) ? e.category : '${e.category} - ${e.description}',
            date: e.expenseDate,
          )),
    ];
    entries.sort((a, b) => b.date.compareTo(a.date));
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _delete(_QuickEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry?'),
        content: Text('${entry.label} - ${formatCurrency(entry.amount)} will be removed and its P&L entry reversed. This cannot be undone from here.'),
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
    if (ok != true) return;
    // Expense.delete already reverses its own ledger row (see
    // ExpenseRepository.delete); a Quick Income row has no other place to
    // clean up - the ledger row itself IS the record.
    if (entry.isExpense) {
      await _expenseRepo.delete(entry.id);
    } else {
      await _ledgerRepo.delete(entry.id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry deleted')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final totalIncome = _entries.where((e) => !e.isExpense).fold<double>(0, (s, e) => s + e.amount);
    final totalExpense = _entries.where((e) => e.isExpense).fold<double>(0, (s, e) => s + e.amount);
    return Scaffold(
      appBar: AppBar(title: const Text('Quick Income & Expense History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: AppColors.success.withOpacity(0.08), borderRadius: BorderRadius.circular(14)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Quick Income', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(formatCurrency(totalIncome),
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.success, fontSize: 17)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.08), borderRadius: BorderRadius.circular(14)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Quick Expense', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(formatCurrency(totalExpense),
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.danger, fontSize: 17)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_entries.isEmpty) const EmptyState(icon: Icons.bolt_rounded, message: 'No Quick Income/Expense entries yet'),
                  ..._entries.map((e) => Card(
                        child: ListTile(
                          leading: Icon(
                            e.isExpense ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded,
                            color: e.isExpense ? AppColors.danger : AppColors.success,
                          ),
                          title: Text(e.label),
                          subtitle: Text(formatDateTime(e.date)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${e.isExpense ? '-' : '+'} ${formatCurrency(e.amount)}',
                                style: TextStyle(fontWeight: FontWeight.w800, color: e.isExpense ? AppColors.danger : AppColors.success),
                              ),
                              if (auth.canDelete)
                                IconButton(
                                  icon: const Icon(Icons.delete_rounded, color: AppColors.danger, size: 20),
                                  tooltip: 'Delete entry',
                                  onPressed: () => _delete(e),
                                ),
                            ],
                          ),
                        ),
                      )),
                ],
              ),
            ),
    );
  }
}
