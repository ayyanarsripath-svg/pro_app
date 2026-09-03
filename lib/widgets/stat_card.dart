import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';

class StatCard extends StatelessWidget {
  final String label;
  final double value;
  final Color? color;
  final IconData? icon;
  final bool isCurrency;
  final String? suffixText;

  /// Optional short explanation shown in a popup when the (i) icon next to
  /// [label] is tapped (spec item 4: "dash board la gross profit and net
  /// profit enakku konjam confusion ah erukku" - Gross vs Net Profit reads
  /// as two similar numbers with no visible difference between them). Kept
  /// as an on-demand dialog rather than a permanently-shown subtitle so
  /// every other, already-self-explanatory StatCard on screen doesn't get
  /// visually busier just to support these two.
  final String? infoText;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.icon,
    this.isCurrency = true,
    this.suffixText,
    this.infoText,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primaryBlue;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 16, color: c),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondaryOf(context), fontWeight: FontWeight.w600)),
              ),
              if (infoText != null)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(label),
                      content: Text(infoText!),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.info_outline_rounded, size: 14, color: AppColors.textSecondaryOf(context)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isCurrency ? formatCurrency(value) : '${value.toStringAsFixed(0)}${suffixText ?? ''}',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimaryOf(context)),
          ),
        ],
      ),
    );
  }
}

class ProfitLossPill extends StatelessWidget {
  final double value;
  const ProfitLossPill(this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final isLoss = value < 0;
    final color = isLoss ? AppColors.danger : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        formatProfitLoss(value),
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5),
      ),
    );
  }
}
