import 'package:flutter/material.dart';

import '../../core/repositories/spare_part_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/spare_part_usage.dart';
import '../../widgets/section_card.dart';

/// Spare Parts usage log (spec item 2 - see SparePartRepository
/// .serviceUsageLog's doc comment for exactly what this reads). Kept as a
/// body-only widget (no Scaffold/AppBar of its own) so it can be embedded
/// directly as one of Expenses' three tabs (spec item 3 - see
/// ExpenseScreen), same "reusable body" pattern as QuickHistoryBody.
class SparePartsUsageBody extends StatefulWidget {
  const SparePartsUsageBody({super.key});

  @override
  State<SparePartsUsageBody> createState() => _SparePartsUsageBodyState();
}

class _SparePartsUsageBodyState extends State<SparePartsUsageBody> {
  final _repo = SparePartRepository();
  List<SparePartUsage> _usage = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final usage = await _repo.serviceUsageLog();
    if (!mounted) return;
    setState(() {
      _usage = usage;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final total = _usage.fold<double>(0, (s, u) => s + u.totalCost);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.08), borderRadius: BorderRadius.circular(14)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Spare Parts Cost', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('${_usage.length} part${_usage.length == 1 ? '' : 's'} used across Service Bills',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondaryOf(context))),
                  ],
                ),
                Text(formatCurrency(total), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.warning, fontSize: 17)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Every spare part chosen under "Add Part" on a Service Bill, at the cost it was counted for in Profit & Loss - this is exactly what feeds "Today\'s Cost" for spare parts.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondaryOf(context)),
            ),
          ),
          if (_usage.isEmpty) const EmptyState(icon: Icons.memory_rounded, message: 'No spare parts used on a Service Bill yet'),
          ..._usage.map((u) => Card(
                child: ListTile(
                  title: Text('${u.partName}${(u.category ?? '').isNotEmpty ? ' (${u.category})' : ''}'),
                  subtitle: Text(
                    'Bill: ${u.billNo}  •  ${u.mobileName ?? ''}${(u.model ?? '').isNotEmpty ? ' (${u.model})' : ''}\n'
                    'Qty ${u.quantity.toStringAsFixed(u.quantity == u.quantity.roundToDouble() ? 0 : 2)} × ${formatCurrency(u.unitCost)}  •  ${formatDate(u.date)}',
                  ),
                  isThreeLine: true,
                  trailing: Text(formatCurrency(u.totalCost), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.warning)),
                ),
              )),
        ],
      ),
    );
  }
}
