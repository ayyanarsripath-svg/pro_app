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

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.icon,
    this.isCurrency = true,
    this.suffixText,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primaryBlue;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
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
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isCurrency ? formatCurrency(value) : '${value.toStringAsFixed(0)}${suffixText ?? ''}',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
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
