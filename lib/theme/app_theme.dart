import 'package:flutter/material.dart';

class AppTheme {
  static const _seedColor = Color(0xFFE8375A);

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final cs = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );
    return base.copyWith(
      colorScheme: cs,
      scaffoldBackgroundColor: const Color(0xFF0D0D0D),
      cardColor: const Color(0xFF1A1A1A),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF141414),
        indicatorColor: cs.primary.withOpacity(0.2),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF181818),
        modalBarrierColor: Colors.black54,
      ),
      dividerColor: Colors.white10,
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        activeTrackColor: cs.primary,
        inactiveTrackColor: Colors.white12,
        thumbColor: Colors.white,
        overlayShape: SliderComponentShape.noOverlay,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF2A2A2A),
        selectedColor: cs.primary.withOpacity(0.3),
        labelStyle: const TextStyle(fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
      ),
      textTheme: base.textTheme.copyWith(
        displayLarge: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        headlineMedium: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
        titleLarge: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          color: Colors.white.withOpacity(0.9),
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          color: Colors.white.withOpacity(0.6),
        ),
      ),
    );
  }

  static const gradientPrimary = LinearGradient(
    colors: [Color(0xFFE8375A), Color(0xFF8B1A3A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient playerGradient(Color dominantColor) {
    return LinearGradient(
      colors: [
        dominantColor.withOpacity(0.9),
        Colors.black,
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: const [0.0, 0.6],
    );
  }
}
