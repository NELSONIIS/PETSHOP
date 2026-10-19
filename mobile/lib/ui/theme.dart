import 'package:flutter/material.dart';

import 'tokens.dart';

class PetoraTheme {
  PetoraTheme._();

  static ThemeData light() => _build(
    const ColorScheme(
      brightness: Brightness.light,
      primary: PColor.primary600,
      onPrimary: Colors.white,
      primaryContainer: PColor.primary100,
      onPrimaryContainer: PColor.primary900,
      secondary: PColor.secondary600,
      onSecondary: Colors.white,
      secondaryContainer: PColor.secondary100,
      onSecondaryContainer: PColor.secondary700,
      tertiary: PColor.accent500,
      onTertiary: Colors.white,
      error: Color(0xFFC8402F),
      onError: Colors.white,
      surface: Colors.white,
      onSurface: Color(0xFF1C2A24),
      onSurfaceVariant: Color(0xFF5E6B64),
      outline: Color(0xFFE8E2D8),
      outlineVariant: Color(0xFFEFE9DE),
      surfaceContainerHighest: Color(0xFFF3EFE7),
    ),
    PetoraColors.light,
  );

  static ThemeData dark() => _build(
    const ColorScheme(
      brightness: Brightness.dark,
      primary: PColor.primary400,
      onPrimary: PColor.primary900,
      primaryContainer: PColor.primary800,
      onPrimaryContainer: PColor.primary100,
      secondary: Color(0xFF3DB6AB),
      onSecondary: Color(0xFF00201E),
      secondaryContainer: PColor.secondary700,
      onSecondaryContainer: PColor.secondary100,
      tertiary: PColor.accent400,
      onTertiary: Color(0xFF3B1306),
      error: Color(0xFFF0867A),
      onError: Color(0xFF410C05),
      surface: Color(0xFF0F1714),
      onSurface: Color(0xFFE8F0EB),
      onSurfaceVariant: Color(0xFF9DB0A5),
      outline: Color(0xFF26342D),
      outlineVariant: Color(0xFF1E2B25),
      surfaceContainerHighest: Color(0xFF1B2822),
    ),
    PetoraColors.dark,
  );

  static ThemeData _build(ColorScheme cs, PetoraColors pc) {
    final text = PType.textTheme(cs.onSurface);
    final border = OutlineInputBorder(
      borderRadius: PRadius.fieldR,
      borderSide: BorderSide(color: pc.border),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      brightness: cs.brightness,
      fontFamily: PType.fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: cs.surface,
      extensions: [pc],
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleMedium,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: pc.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: PRadius.cardR,
          side: BorderSide(color: pc.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: pc.border, space: 1, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.brightness == Brightness.light ? pc.bgWarm : pc.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(borderSide: BorderSide(color: cs.primary, width: 1.6)),
        errorBorder: border.copyWith(borderSide: BorderSide(color: cs.error)),
        focusedErrorBorder: border.copyWith(borderSide: BorderSide(color: cs.error, width: 1.6)),
        labelStyle: text.bodyMedium?.copyWith(color: pc.textMuted),
        hintStyle: text.bodyMedium?.copyWith(color: pc.textMuted),
        errorStyle: text.bodySmall?.copyWith(color: cs.error),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: const RoundedRectangleBorder(borderRadius: PRadius.fieldR),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          side: BorderSide(color: pc.border),
          foregroundColor: cs.onSurface,
          shape: const RoundedRectangleBorder(borderRadius: PRadius.fieldR),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48), textStyle: text.labelLarge),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: pc.surface,
        selectedColor: cs.primaryContainer,
        side: BorderSide(color: pc.border),
        shape: const RoundedRectangleBorder(borderRadius: PRadius.chipR),
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: pc.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: cs.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(text.labelSmall),
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: PRadius.fieldR),
        backgroundColor: cs.brightness == Brightness.light ? const Color(0xFF1C2A24) : const Color(0xFFE8F0EB),
        contentTextStyle: text.bodyMedium?.copyWith(
          color: cs.brightness == Brightness.light ? Colors.white : const Color(0xFF1C2A24),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: pc.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: PRadius.sheetR),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: pc.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PRadius.sheet)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.tertiary,
        foregroundColor: cs.onTertiary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 4,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: cs.primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? cs.onPrimary : pc.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? cs.primary : pc.border),
      ),
    );
  }
}
