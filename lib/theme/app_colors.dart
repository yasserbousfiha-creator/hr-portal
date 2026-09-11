import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color bgDark = Color(0xFF061A22);
  static const Color surface = Color(0xFF0D2731);
  static const Color surfaceHi = Color(0xFF123540);

  static const Color primary = Color(0xFF06B6D4);
  static const Color primaryLight = Color(0xFF22D3EE);
  static const Color primaryDeep = Color(0xFF0E7490);

  static const Color secondary = Color(0xFF0EA5E9);
  static const Color secondaryDeep = Color(0xFF1E3A5F);

  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFF87171);
  static const Color info = Color(0xFF60A5FA);

  static const LinearGradient mainGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
