import 'package:flutter/material.dart';

class Appthemes {
  static final ThemeData purpleForest = _buildTheme(
    seed: const Color(0xFF8B5CF6),
    brightness: Brightness.dark,
    scaffold: const Color(0xFF090812),
    surface: const Color(0xFF15121F),
  );

  static final ThemeData deepOcean = _buildTheme(
    seed: const Color(0xFF38BDF8),
    brightness: Brightness.dark,
    scaffold: const Color(0xFF071018),
    surface: const Color(0xFF101C27),
  );

  static final ThemeData redRiver = _buildTheme(
    seed: const Color(0xFFFB7185),
    brightness: Brightness.dark,
    scaffold: const Color(0xFF13090C),
    surface: const Color(0xFF211216),
  );

  static final ThemeData grayCity = _buildTheme(
    seed: const Color(0xFFA8B1C2),
    brightness: Brightness.dark,
    scaffold: const Color(0xFF0C0E12),
    surface: const Color(0xFF171A20),
  );

  static final ThemeData heavensDay = _buildTheme(
    seed: const Color(0xFF2563EB),
    brightness: Brightness.light,
    scaffold: const Color(0xFFF5F8FF),
    surface: Colors.white,
  );

  static final ThemeData sunsLight = _buildTheme(
    seed: const Color(0xFFD97706),
    brightness: Brightness.light,
    scaffold: const Color(0xFFFFFBEB),
    surface: const Color(0xFFFFFEF8),
  );

  static final ThemeData frozenLake = _buildTheme(
    seed: const Color(0xFF0891B2),
    brightness: Brightness.light,
    scaffold: const Color(0xFFF0FAFC),
    surface: const Color(0xFFFAFEFF),
  );

  static ThemeData _buildTheme({
    required Color seed,
    required Brightness brightness,
    required Color scaffold,
    required Color surface,
  }) {
    final isDark = brightness == Brightness.dark;
    final baseScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final scheme = baseScheme.copyWith(
      primary: seed,
      onPrimary: isDark ? Colors.white : const Color(0xFF07111F),
      surface: surface,
      surfaceContainerLowest: scaffold,
      surfaceContainerLow: Color.lerp(scaffold, surface, 0.55),
      surfaceContainer: surface,
      surfaceContainerHigh: Color.lerp(
        surface,
        isDark ? Colors.white : Colors.black,
        isDark ? 0.07 : 0.04,
      ),
      outline: isDark ? const Color(0xFF4B4659) : const Color(0xFFC5CBD6),
      outlineVariant:
          isDark ? const Color(0xFF302C3A) : const Color(0xFFE1E5EC),
    );

    final baseTextTheme = ThemeData(
      brightness: brightness,
      useMaterial3: true,
    ).textTheme;
    final textTheme = baseTextTheme.copyWith(
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      // Kept as the app accent for compatibility with the existing screens.
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(color: scheme.onSurface),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(color: scheme.onSurface),
      bodySmall:
          baseTextTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: scheme,
      primaryColor: scheme.primary,
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      visualDensity: VisualDensity.standard,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
            size: 25,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          );
        }),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: scheme.primary,
        collapsedIconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        collapsedTextColor: scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        collapsedShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  static ThemeData getThemeByName(String themeName) {
    return switch (themeName) {
      'deepOcean' => deepOcean,
      'redRiver' => redRiver,
      'grayCity' => grayCity,
      'heavensDay' => heavensDay,
      'sunsLight' => sunsLight,
      'frozenLake' => frozenLake,
      _ => purpleForest,
    };
  }

  static String getThemeName(ThemeData theme) {
    if (identical(theme, deepOcean)) return 'deepOcean';
    if (identical(theme, redRiver)) return 'redRiver';
    if (identical(theme, grayCity)) return 'grayCity';
    if (identical(theme, heavensDay)) return 'heavensDay';
    if (identical(theme, sunsLight)) return 'sunsLight';
    if (identical(theme, frozenLake)) return 'frozenLake';
    return 'purpleForest';
  }
}
