import 'package:flutter/material.dart';

/// Centralised PETORA design tokens (see docs/DESIGN_SYSTEM.md).
class PColor {
  PColor._();
  // forest green
  static const primary50 = Color(0xFFEDF7F0);
  static const primary100 = Color(0xFFD3EBDA);
  static const primary200 = Color(0xFFA9D6B8);
  static const primary300 = Color(0xFF78BC93);
  static const primary400 = Color(0xFF46A06F);
  static const primary500 = Color(0xFF2A8656);
  static const primary600 = Color(0xFF1E6B44);
  static const primary700 = Color(0xFF17563A);
  static const primary800 = Color(0xFF124530);
  static const primary900 = Color(0xFF0C3223);
  // deep teal
  static const secondary50 = Color(0xFFE6F6F4);
  static const secondary100 = Color(0xFFC2E8E3);
  static const secondary500 = Color(0xFF0F766E);
  static const secondary600 = Color(0xFF0D5F59);
  static const secondary700 = Color(0xFF0B4B47);
  // muted coral
  static const accent400 = Color(0xFFF08A6B);
  static const accent500 = Color(0xFFE8704F);
  static const accent600 = Color(0xFFD2593A);
}

/// Semantic colours that differ between light and dark.
@immutable
class PetoraColors extends ThemeExtension<PetoraColors> {
  const PetoraColors({
    required this.bgWarm,
    required this.surface,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.accent,
    required this.secondary,
    required this.successBg,
    required this.warningBg,
    required this.dangerBg,
    required this.infoBg,
  });

  final Color bgWarm, surface, border, text, textMuted, success, warning, danger, info, accent, secondary;
  final Color successBg, warningBg, dangerBg, infoBg;

  static const light = PetoraColors(
    bgWarm: Color(0xFFFAF7F2),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE8E2D8),
    text: Color(0xFF1C2A24),
    textMuted: Color(0xFF5E6B64),
    success: Color(0xFF1E8E5A),
    warning: Color(0xFFB97A00),
    danger: Color(0xFFC8402F),
    info: Color(0xFF2B6CB0),
    accent: PColor.accent500,
    secondary: PColor.secondary600,
    successBg: Color(0xFFE5F5EC),
    warningBg: Color(0xFFFFF3D9),
    dangerBg: Color(0xFFFCE8E5),
    infoBg: Color(0xFFE6F0FA),
  );

  static const dark = PetoraColors(
    bgWarm: Color(0xFF131E19),
    surface: Color(0xFF16211C),
    border: Color(0xFF26342D),
    text: Color(0xFFE8F0EB),
    textMuted: Color(0xFF9DB0A5),
    success: Color(0xFF52C48C),
    warning: Color(0xFFE8B13A),
    danger: Color(0xFFF0867A),
    info: Color(0xFF7DB3EA),
    accent: PColor.accent400,
    secondary: Color(0xFF3DB6AB),
    successBg: Color(0xFF173626),
    warningBg: Color(0xFF3A2F12),
    dangerBg: Color(0xFF3F1F1B),
    infoBg: Color(0xFF16293F),
  );

  @override
  PetoraColors copyWith() => this;

  @override
  PetoraColors lerp(ThemeExtension<PetoraColors>? other, double t) => t < 0.5 ? this : (other as PetoraColors? ?? this);
}

extension PetoraContext on BuildContext {
  PetoraColors get pc => Theme.of(this).extension<PetoraColors>() ?? PetoraColors.light;
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
}

class PSpace {
  PSpace._();
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32;
  static const double gutter = 16;
}

class PRadius {
  PRadius._();
  static const double chip = 8, field = 10, card = 14, sheet = 20;
  static const BorderRadius chipR = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius fieldR = BorderRadius.all(Radius.circular(field));
  static const BorderRadius cardR = BorderRadius.all(Radius.circular(card));
  static const BorderRadius sheetR = BorderRadius.vertical(top: Radius.circular(sheet));
}

class PElevation {
  PElevation._();
  static const card = [BoxShadow(color: Color(0x0F101814), blurRadius: 2, offset: Offset(0, 1))];
  static const raised = [BoxShadow(color: Color(0x1A101814), blurRadius: 14, offset: Offset(0, 4))];
}

class PIcon {
  PIcon._();
  static const double sm = 16, md = 20, lg = 24;
}

class PType {
  PType._();
  static const fontFamily = 'Inter';

  static TextTheme textTheme(Color text) => TextTheme(
    displayLarge: _s(28, FontWeight.w700, text),
    headlineMedium: _s(22, FontWeight.w700, text),
    titleLarge: _s(18, FontWeight.w600, text),
    titleMedium: _s(16, FontWeight.w600, text),
    titleSmall: _s(14, FontWeight.w600, text),
    bodyLarge: _s(14, FontWeight.w400, text, 1.45),
    bodyMedium: _s(14, FontWeight.w400, text, 1.45),
    bodySmall: _s(12, FontWeight.w400, text, 1.35),
    labelLarge: _s(14, FontWeight.w600, text),
    labelMedium: _s(12, FontWeight.w600, text),
    labelSmall: _s(11, FontWeight.w600, text),
  );

  static TextStyle _s(double size, FontWeight w, Color c, [double h = 1.35]) =>
      TextStyle(fontFamily: fontFamily, fontSize: size, fontWeight: w, color: c, height: h);

  /// Tabular numerals for prices.
  static const price = TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
