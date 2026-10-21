import 'package:flutter/material.dart';

/// PulseMesh palette: midnight slate + electric indigo.
class C {
  static const bg = Color(0xFF0F172A);
  static const surface = Color(0xFF172036);
  static const surface2 = Color(0xFF1F2A44);
  static const line = Color(0xFF2A3656);
  static const indigo = Color(0xFF6366F1);
  static const indigoSoft = Color(0xFFA5B4FC);
  static const online = Color(0xFF22C55E);
  static const text = Color(0xFFE6EBF5);
  static const muted = Color(0xFF8D9BB8);
  static const avatars = <Color>[
    Color(0xFF6366F1), Color(0xFF14B8A6), Color(0xFFF59E0B), Color(0xFFEC4899),
    Color(0xFF0EA5E9), Color(0xFF84CC16), Color(0xFFF97316), Color(0xFF8B5CF6),
  ];
  static Color avatar(int i) => avatars[i.abs() % avatars.length];
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(
      primary: C.indigo, secondary: C.indigoSoft, surface: C.surface, onSurface: C.text,
    ),
    appBarTheme: const AppBarTheme(backgroundColor: C.bg, elevation: 0, scrolledUnderElevation: 0),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.surface,
      indicatorColor: C.indigo.withOpacity(.28),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerColor: C.line,
  );
}
