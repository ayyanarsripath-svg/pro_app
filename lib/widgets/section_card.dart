import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// A boxed section used on the premium Service Job Card screen and various
/// forms - mirrors the printed A5 bill's "boxed sections" look on-screen.
class SectionCard extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<Widget> children;
  final Widget? trailing;

  const SectionCard({
    super.key,
    required this.title,
    this.icon,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              if (icon != null) Icon(icon, size: 16, color: AppColors.primaryBlue),
              if (icon != null) const SizedBox(width: 6),
              Expanded(
                child: Text(title.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.textSecondary)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const EmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(icon, size: 46, color: AppColors.textSecondary.withOpacity(0.4)),
          const SizedBox(height: 10),
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
