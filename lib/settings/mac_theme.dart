import 'package:flutter/material.dart';

/// macOS-flavoured design tokens for Orthant's config window.
///
/// Hand-rolled rather than pulling in `macos_ui`: the spec keeps dependencies
/// lean, and window-owning packages fight over `MainFlutterWindow` (§5). These
/// values approximate AppKit's semantic colors closely enough that the window
/// reads as a system preferences pane rather than a Material app.
@immutable
class MacTokens extends ThemeExtension<MacTokens> {
  const MacTokens({
    required this.windowBackground,
    required this.contentBackground,
    required this.rowHighlight,
    required this.separator,
    required this.labelPrimary,
    required this.labelSecondary,
    required this.labelTertiary,
    required this.accent,
    required this.keycapFill,
    required this.keycapBorder,
    required this.keycapShadow,
    required this.glyphOutline,
    required this.warning,
  });

  final Color windowBackground;
  final Color contentBackground;
  final Color rowHighlight;
  final Color separator;
  final Color labelPrimary;
  final Color labelSecondary;
  final Color labelTertiary;
  final Color accent;
  final Color keycapFill;
  final Color keycapBorder;
  final Color keycapShadow;
  final Color glyphOutline;

  /// System orange. Reserved for a control that looks configured but isn't
  /// working — nothing in this pane is destructive enough to warrant red.
  final Color warning;

  /// SF Mono isn't guaranteed installed; Menlo ships with every macOS.
  static const String monoFamily = 'Menlo';

  static const light = MacTokens(
    windowBackground: Color(0xFFECECEE),
    contentBackground: Color(0xFFFFFFFF),
    rowHighlight: Color(0x0A000000),
    separator: Color(0x14000000),
    labelPrimary: Color(0xE6000000),
    labelSecondary: Color(0x8C000000),
    labelTertiary: Color(0x59000000),
    accent: Color(0xFF007AFF),
    keycapFill: Color(0xFFFDFDFD),
    keycapBorder: Color(0x24000000),
    keycapShadow: Color(0x14000000),
    glyphOutline: Color(0x40000000),
    warning: Color(0xFFC93400),
  );

  static const dark = MacTokens(
    windowBackground: Color(0xFF1E1E1F),
    contentBackground: Color(0xFF2C2C2E),
    rowHighlight: Color(0x14FFFFFF),
    separator: Color(0x1AFFFFFF),
    labelPrimary: Color(0xE6FFFFFF),
    labelSecondary: Color(0x8CFFFFFF),
    labelTertiary: Color(0x59FFFFFF),
    accent: Color(0xFF0A84FF),
    keycapFill: Color(0xFF3A3A3C),
    keycapBorder: Color(0x33FFFFFF),
    keycapShadow: Color(0x33000000),
    glyphOutline: Color(0x59FFFFFF),
    warning: Color(0xFFFF9F0A),
  );

  @override
  MacTokens copyWith({
    Color? windowBackground,
    Color? contentBackground,
    Color? rowHighlight,
    Color? separator,
    Color? labelPrimary,
    Color? labelSecondary,
    Color? labelTertiary,
    Color? accent,
    Color? keycapFill,
    Color? keycapBorder,
    Color? keycapShadow,
    Color? glyphOutline,
    Color? warning,
  }) {
    return MacTokens(
      windowBackground: windowBackground ?? this.windowBackground,
      contentBackground: contentBackground ?? this.contentBackground,
      rowHighlight: rowHighlight ?? this.rowHighlight,
      separator: separator ?? this.separator,
      labelPrimary: labelPrimary ?? this.labelPrimary,
      labelSecondary: labelSecondary ?? this.labelSecondary,
      labelTertiary: labelTertiary ?? this.labelTertiary,
      accent: accent ?? this.accent,
      keycapFill: keycapFill ?? this.keycapFill,
      keycapBorder: keycapBorder ?? this.keycapBorder,
      keycapShadow: keycapShadow ?? this.keycapShadow,
      glyphOutline: glyphOutline ?? this.glyphOutline,
      warning: warning ?? this.warning,
    );
  }

  @override
  MacTokens lerp(MacTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return MacTokens(
      windowBackground: c(windowBackground, other.windowBackground),
      contentBackground: c(contentBackground, other.contentBackground),
      rowHighlight: c(rowHighlight, other.rowHighlight),
      separator: c(separator, other.separator),
      labelPrimary: c(labelPrimary, other.labelPrimary),
      labelSecondary: c(labelSecondary, other.labelSecondary),
      labelTertiary: c(labelTertiary, other.labelTertiary),
      accent: c(accent, other.accent),
      keycapFill: c(keycapFill, other.keycapFill),
      keycapBorder: c(keycapBorder, other.keycapBorder),
      keycapShadow: c(keycapShadow, other.keycapShadow),
      glyphOutline: c(glyphOutline, other.glyphOutline),
      warning: c(warning, other.warning),
    );
  }
}

/// Convenience: `context.mac` instead of a nested `Theme.of` lookup.
extension MacThemeContext on BuildContext {
  MacTokens get mac =>
      Theme.of(this).extension<MacTokens>() ?? MacTokens.light;
}

ThemeData macTheme(Brightness brightness) {
  final t = brightness == Brightness.dark ? MacTokens.dark : MacTokens.light;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: t.windowBackground,
    canvasColor: t.windowBackground,
    colorScheme: base.colorScheme.copyWith(primary: t.accent),
    extensions: [t],
    // Tighter, quieter text than Material's defaults — closer to AppKit metrics.
    textTheme: base.textTheme.apply(
      bodyColor: t.labelPrimary,
      displayColor: t.labelPrimary,
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      behavior: SnackBarBehavior.floating,
      backgroundColor: brightness == Brightness.dark
          ? const Color(0xFF3A3A3C)
          : const Color(0xFF323234),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 12.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}
