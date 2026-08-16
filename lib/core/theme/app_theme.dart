import 'package:flutter/material.dart';

/// Brand palette pulled from the "Professional Mobiles & Laptop Service"
/// phoenix logo: deep blue wing, orange/red flame wing, purple accents.
class AppColors {
  AppColors._();

  static const Color primaryBlue = Color(0xFF1E3AAE);
  static const Color deepBlue = Color(0xFF0F2470);
  static const Color flameOrange = Color(0xFFFF6A1A);
  static const Color flameRed = Color(0xFFE21B4D);
  static const Color accentPurple = Color(0xFF7C3AED);

  static const Color bg = Color(0xFFF4F6FB);
  static const Color card = Colors.white;
  static const Color border = Color(0xFFE3E7F1);

  static const Color textPrimary = Color(0xFF1A1F36);
  static const Color textSecondary = Color(0xFF6B7290);

  static const Color success = Color(0xFF16A34A);
  static const Color danger = Color(0xFFDC2626);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF2563EB);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [deepBlue, primaryBlue, accentPurple, flameOrange],
  );

  /// Status colours used across Service / 2nd Hand / Delivery pipelines.
  static Color statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'RECEIVED':
        return const Color(0xFF64748B);
      case 'CHECKING':
        return const Color(0xFF0EA5E9);
      case 'REPAIRING':
      case 'REPAIR':
        return flameOrange;
      case 'PART PENDING':
      case 'PART_PENDING':
        return warning;
      case 'READY':
      case 'READY FOR SALE':
      case 'READY_FOR_SALE':
      case 'READY FOR DELIVERY':
        return const Color(0xFF0891B2);
      case 'DELIVERED':
      case 'SOLD':
        return success;
      case 'WARRANTY':
        return accentPurple;
      case 'CANCELLED':
      case 'RETURNED':
        return danger;
      case 'PURCHASED':
        return info;
      case 'RESERVED':
        return const Color(0xFF9333EA);
      default:
        return const Color(0xFF64748B);
    }
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryBlue,
        primary: AppColors.primaryBlue,
        secondary: AppColors.flameOrange,
        tertiary: AppColors.accentPurple,
        error: AppColors.danger,
        surface: AppColors.card,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      fontFamily: 'Roboto',
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.deepBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryBlue,
          side: const BorderSide(color: AppColors.primaryBlue),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.bg,
        shape: StadiumBorder(side: BorderSide(color: AppColors.border)),
      ),
    );
  }
}
