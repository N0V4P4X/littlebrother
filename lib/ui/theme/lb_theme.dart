import 'package:flutter/material.dart';

class LBColors {
  LBColors._();

  static const background  = Color(0xFF0A0A0A);
  static const surface     = Color(0xFF141414);
  static const surfaceHigh = Color(0xFF1E1E1E);
  static const border      = Color(0xFF2A2A2A);
  static const dimText     = Color(0xFF6B6B6B);
  static const bodyText    = Color(0xFFC8C8C8);
  static const white       = Color(0xFFF0F0F0);
  static const blue        = Color(0xFF3B82F6);
  static const blueDim     = Color(0xFF1E3A5F);
  static const cyan        = Color(0xFF00D4FF);
  static const green       = Color(0xFF00FF88);
  static const yellow      = Color(0xFFFFD700);
  static const red         = Color(0xFFFF4444);
  static const orange      = Color(0xFFFF8C00);

  // Signal type colors
  static const wifi        = Color(0xFF3B82F6);  // blue
  static const ble         = Color(0xFF8B5CF6);  // purple
  static const cell        = Color(0xFF00D4FF);  // cyan
  static const threat      = Color(0xFFFF4444);  // red

  // Severity colors
  static Color severity(int s) => switch (s) {
    1 => blue,
    2 => yellow,
    3 => orange,
    4 => red,
    5 => const Color(0xFFFF0000),
    _ => dimText,
  };

  // Risk score gradient: 0=green, 50=yellow, 100=red
  static Color riskColor(int score) {
    if (score < 30) return green;
    if (score < 60) return yellow;
    if (score < 80) return orange;
    return red;
  }

  // Radar blip color by signal type + threat flag
  static Color blipColor(String signalType, int threatFlag) {
    if (threatFlag == 2) return red;
    if (threatFlag == 1) return orange;
    return switch (signalType) {
      'wifi'          => wifi,
      'ble'           => ble,
      'cell'          => cyan,
      'cell_neighbor' => cyan.withOpacity(0.5),
      _               => dimText,
    };
  }
}

class LBTextStyles {
  LBTextStyles._();

  static const _mono = 'Courier New';

  static const displayLarge = TextStyle(
    fontFamily: _mono,
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: LBColors.white,
    letterSpacing: 2,
  );

  static const displayMedium = TextStyle(
    fontFamily: _mono,
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: LBColors.white,
    letterSpacing: 1.5,
  );

  static const heading = TextStyle(
    fontFamily: _mono,
    fontSize: 14,
    fontWeight: FontWeight.bold,
    color: LBColors.cyan,
    letterSpacing: 1.2,
  );

  static const body = TextStyle(
    fontFamily: _mono,
    fontSize: 13,
    color: LBColors.bodyText,
    letterSpacing: 0.3,
  );

  static const label = TextStyle(
    fontFamily: _mono,
    fontSize: 11,
    color: LBColors.dimText,
    letterSpacing: 0.8,
  );

  static const value = TextStyle(
    fontFamily: _mono,
    fontSize: 13,
    color: LBColors.cyan,
    letterSpacing: 0.3,
  );

  static const threat = TextStyle(
    fontFamily: _mono,
    fontSize: 12,
    fontWeight: FontWeight.bold,
    color: LBColors.red,
    letterSpacing: 1,
  );

  static const mono = TextStyle(
    fontFamily: _mono,
    fontSize: 12,
    color: LBColors.bodyText,
  );
}

ThemeData buildLBTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: LBColors.background,
    colorScheme: const ColorScheme.dark(
      surface:          LBColors.surface,
      primary:          LBColors.blue,
      secondary:        LBColors.cyan,
      error:            LBColors.red,
      onSurface:        LBColors.bodyText,
      onPrimary:        LBColors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: LBColors.background,
      foregroundColor: LBColors.white,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'Courier New',
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: LBColors.white,
        letterSpacing: 2,
      ),
      iconTheme: IconThemeData(color: LBColors.blue),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: LBColors.surface,
      selectedItemColor: LBColors.cyan,
      unselectedItemColor: LBColors.dimText,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: TextStyle(
        fontFamily: 'Courier New', fontSize: 10, letterSpacing: 1,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamily: 'Courier New', fontSize: 10, letterSpacing: 1,
      ),
    ),
    cardTheme: CardTheme(
      color: LBColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: LBColors.border, width: 1),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    dividerTheme: const DividerThemeData(
      color: LBColors.border,
      thickness: 1,
      space: 1,
    ),
    iconTheme: const IconThemeData(color: LBColors.dimText, size: 16),
    textTheme: const TextTheme(
      displayLarge:  LBTextStyles.displayLarge,
      displayMedium: LBTextStyles.displayMedium,
      headlineMedium: LBTextStyles.heading,
      bodyMedium:    LBTextStyles.body,
      labelSmall:    LBTextStyles.label,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LBColors.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: LBColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: LBColors.blue, width: 1),
      ),
      labelStyle: LBTextStyles.label,
      hintStyle: LBTextStyles.label,
    ),
  );
}
