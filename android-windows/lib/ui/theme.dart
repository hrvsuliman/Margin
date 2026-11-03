import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Margin's colours (Margin/DesignSystem/Palette.swift): paper and ink, with
/// the red margin line as the only accent. Light and dark follow the system.
@immutable
class MarginColors extends ThemeExtension<MarginColors> {
  const MarginColors({
    required this.paper,
    required this.sheet,
    required this.ink,
    required this.secondaryInk,
    required this.faintInk,
    required this.ruling,
    required this.marginRed,
  });

  final Color paper;
  final Color sheet;
  final Color ink;
  final Color secondaryInk;
  final Color faintInk;
  final Color ruling;
  final Color marginRed;

  static const light = MarginColors(
    paper: Color(0xFFF6F3EC),
    sheet: Color(0xFFFFFDF8),
    ink: Color(0xFF1C1B1F),
    secondaryInk: Color(0xFF6B6862),
    faintInk: Color(0xFFA9A59D),
    ruling: Color(0xFFD3DCE6),
    marginRed: Color(0xFFD4513B),
  );

  static const dark = MarginColors(
    paper: Color(0xFF131315),
    sheet: Color(0xFF1D1D20),
    ink: Color(0xFFECE9E2),
    secondaryInk: Color(0xFF9C988F),
    faintInk: Color(0xFF5E5B55),
    ruling: Color(0xFF262C35),
    marginRed: Color(0xFFE8664F),
  );

  @override
  MarginColors copyWith() => this;

  @override
  MarginColors lerp(MarginColors? other, double t) {
    if (other == null) return this;
    return MarginColors(
      paper: Color.lerp(paper, other.paper, t)!,
      sheet: Color.lerp(sheet, other.sheet, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      secondaryInk: Color.lerp(secondaryInk, other.secondaryInk, t)!,
      faintInk: Color.lerp(faintInk, other.faintInk, t)!,
      ruling: Color.lerp(ruling, other.ruling, t)!,
      marginRed: Color.lerp(marginRed, other.marginRed, t)!,
    );
  }
}

extension MarginContext on BuildContext {
  MarginColors get colors => Theme.of(this).extension<MarginColors>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Serif heading, as on a page of notes.
  TextStyle get serifTitle => TextStyle(
        fontFamily: serifFamily,
        fontFamilyFallback: serifFallback,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: colors.ink,
      );
}

final serifFamily = Platform.isWindows ? 'Georgia' : 'serif';
const serifFallback = ['Georgia', 'Noto Serif', 'serif', 'Times New Roman'];

/// Subject colours, muted so a full timetable doesn't look like a rainbow.
const subjectColors = <String, (String, int, int)>{
  'red': ('Rot', 0xC2463A, 0xE0675A),
  'coral': ('Koralle', 0xDE7A5F, 0xEB8D73),
  'orange': ('Orange', 0xD98A2B, 0xEBA048),
  'mustard': ('Senf', 0xC09A1E, 0xD9B43C),
  'olive': ('Oliv', 0x7F8F45, 0x9DAE5E),
  'green': ('Grün', 0x3F8F5E, 0x5BB07B),
  'teal': ('Petrol', 0x2F8487, 0x4BA5A8),
  'blue': ('Blau', 0x3672B9, 0x5B93D6),
  'indigo': ('Indigo', 0x5260AE, 0x7683CC),
  'violet': ('Violett', 0x8460AB, 0xA283C6),
  'pink': ('Rosa', 0xBD5F8E, 0xD67FA9),
  'brown': ('Braun', 0x8E6248, 0xB08166),
  'gray': ('Grau', 0x737A84, 0x959CA6),
};

Color subjectColor(BuildContext context, String? key) {
  final entry = subjectColors[key] ?? subjectColors['gray']!;
  return Color(0xFF000000 | (context.isDark ? entry.$3 : entry.$2));
}

/// Pen colours of notes (PenColor in HandwritingModels.swift).
const penColors = <String, (String, int)>{
  'royalBlue': ('Königsblau', 0x1F3FA0),
  'black': ('Schwarz', 0x1E1E22),
  'navy': ('Dunkelblau', 0x17264F),
  'green': ('Grün', 0x1F6B45),
  'red': ('Rot', 0xB3261E),
  'violet': ('Lila', 0x5B3A8C),
};

/// A pen colour key or "#RRGGBB" → colour. Dark ink is lightened on dark paper.
Color penColor(String key, {bool dark = false}) {
  Color color;
  if (key.startsWith('#') && key.length == 7) {
    color = Color(0xFF000000 | (int.tryParse(key.substring(1), radix: 16) ?? 0x1F3FA0));
  } else {
    color = Color(0xFF000000 | (penColors[key]?.$2 ?? 0x1F3FA0));
  }
  if (!dark) return color;
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness(math.min(0.85, hsl.lightness + 0.45)).toColor();
}

ThemeData marginTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? MarginColors.dark : MarginColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.ink,
    onPrimary: c.paper,
    secondary: c.marginRed,
    onSecondary: Colors.white,
    error: c.marginRed,
    onError: Colors.white,
    surface: c.paper,
    onSurface: c.ink,
    surfaceContainerLowest: c.sheet,
    surfaceContainerLow: c.sheet,
    surfaceContainer: c.sheet,
    surfaceContainerHigh: c.sheet,
    surfaceContainerHighest: c.ruling,
    onSurfaceVariant: c.secondaryInk,
    outline: c.faintInk,
    outlineVariant: c.ruling,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  final serif = TextStyle(fontFamily: serifFamily, fontFamilyFallback: serifFallback, color: c.ink);
  return base.copyWith(
    scaffoldBackgroundColor: c.paper,
    extensions: [c],
    textTheme: base.textTheme.copyWith(
      headlineMedium: serif.copyWith(fontSize: 28, fontWeight: FontWeight.w600),
      headlineSmall: serif.copyWith(fontSize: 24, fontWeight: FontWeight.w600),
      titleLarge: serif.copyWith(fontSize: 21, fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.paper,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      titleTextStyle: serif.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: c.sheet,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: c.ruling, thickness: 1, space: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.sheet,
      indicatorColor: c.ruling,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12, color: c.ink)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.sheet,
      indicatorColor: c.ruling,
      selectedLabelTextStyle: TextStyle(color: c.ink, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: TextStyle(color: c.secondaryInk),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.ink,
      foregroundColor: c.paper,
      elevation: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: c.ink, foregroundColor: c.paper),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.sheet,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.ruling)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.ruling)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? c.ink : null),
      checkColor: WidgetStatePropertyAll(c.paper),
    ),
    dialogTheme: DialogThemeData(backgroundColor: c.sheet, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.paper, surfaceTintColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(backgroundColor: c.ink, contentTextStyle: TextStyle(color: c.paper)),
  );
}
