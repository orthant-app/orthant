import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../core/window_controller.dart' show AccentColors;

/// How a focused control is outlined, which each platform does its own way.
enum FocusRingStyle {
  /// macOS: the accent at half strength, 3 pt wide, just outside the control.
  halo,

  /// Windows (WinUI's focus visual): a 2 px outer stroke in
  /// [PlatformTokens.focusOuter] and a 1 px inner one in
  /// [PlatformTokens.focusInner], filling a 3 px band (`FocusRingPainter`
  /// says where: just outside the control at the usual inset of 3).
  doubleStroke,
}

/// Orthant's design tokens for its config window, one design on both
/// platforms.
///
/// Hand-rolled rather than pulling in `macos_ui` or `fluent_ui`: the spec
/// keeps dependencies lean, and window-owning packages fight over the
/// runner's window. The palette, radii and spacing are the macOS window's,
/// shared by Windows. What differs by platform is only what the OS owns: the
/// accent (the user's, through `WindowController.accentColor`), what is drawn
/// on it, the link colour, the focus ring, and the keycaps' font. Key names and
/// glyphs are `KeyWords`', and the UI font is Flutter's own per-platform
/// `Typography`.
@immutable
class PlatformTokens extends ThemeExtension<PlatformTokens> {
  const PlatformTokens({
    required this.windowBackground,
    required this.contentBackground,
    required this.rowHighlight,
    required this.separator,
    required this.labelPrimary,
    required this.labelSecondary,
    required this.labelTertiary,
    required this.accent,
    required this.onAccent,
    required this.link,
    required this.keycapFill,
    required this.keycapBorder,
    required this.keycapShadow,
    required this.glyphOutline,
    required this.warning,
    required this.focusRing,
    required this.focusOuter,
    required this.focusInner,
    required this.keycapFamily,
  });

  final Color windowBackground;
  final Color contentBackground;
  final Color rowHighlight;
  final Color separator;
  final Color labelPrimary;
  final Color labelSecondary;
  final Color labelTertiary;
  final Color accent;

  /// Text and glyphs drawn on an [accent] fill: white on macOS; on Windows
  /// white in its light theme and black in its dark one, whose accent fill is
  /// a light shade.
  final Color onAccent;

  /// Text and glyphs that act as links. macOS draws them in its link colour
  /// (`NSColor.linkColor`), which does not follow the accent and reads better
  /// than it in dark mode; Windows in WinUI's link text, one shade of the
  /// accent past its fill (`AccentColors.linkLight`, `linkDark`), at least
  /// 4.5:1 on the window and on a card ([PlatformTokens.of]).
  final Color link;

  final Color keycapFill;
  final Color keycapBorder;
  final Color keycapShadow;
  final Color glyphOutline;

  /// System orange. Reserved for a control that looks configured but isn't
  /// working — nothing in this pane is destructive enough to warrant red.
  final Color warning;

  final FocusRingStyle focusRing;

  /// The [FocusRingStyle.doubleStroke] ring's two colours. The halo draws in
  /// the accent and leaves these transparent.
  final Color focusOuter;
  final Color focusInner;

  /// The keycaps' font. SF Mono isn't guaranteed installed on macOS; Menlo
  /// ships with every macOS. Windows names its keys in words (Win, Ctrl), set
  /// in its UI font, as its own shortcut editors do.
  final String keycapFamily;

  static const macLight = PlatformTokens(
    windowBackground: Color(0xFFECECEE),
    contentBackground: Color(0xFFFFFFFF),
    rowHighlight: Color(0x0A000000),
    separator: Color(0x14000000),
    labelPrimary: Color(0xE6000000),
    labelSecondary: Color(0x8C000000),
    labelTertiary: Color(0x59000000),
    accent: Color(0xFF007AFF),
    onAccent: Color(0xFFFFFFFF),
    link: Color(0xFF0068DA),
    keycapFill: Color(0xFFFDFDFD),
    keycapBorder: Color(0x24000000),
    keycapShadow: Color(0x14000000),
    glyphOutline: Color(0x40000000),
    warning: Color(0xFFC93400),
    focusRing: FocusRingStyle.halo,
    focusOuter: Color(0x00000000),
    focusInner: Color(0x00000000),
    keycapFamily: 'Menlo',
  );

  static const macDark = PlatformTokens(
    windowBackground: Color(0xFF1E1E1F),
    contentBackground: Color(0xFF2C2C2E),
    rowHighlight: Color(0x14FFFFFF),
    separator: Color(0x1AFFFFFF),
    labelPrimary: Color(0xE6FFFFFF),
    labelSecondary: Color(0x8CFFFFFF),
    labelTertiary: Color(0x59FFFFFF),
    accent: Color(0xFF0A84FF),
    onAccent: Color(0xFFFFFFFF),
    link: Color(0xFF419CFF),
    keycapFill: Color(0xFF3A3A3C),
    keycapBorder: Color(0x33FFFFFF),
    keycapShadow: Color(0x33000000),
    glyphOutline: Color(0x59FFFFFF),
    warning: Color(0xFFFF9F0A),
    focusRing: FocusRingStyle.halo,
    focusOuter: Color(0x00000000),
    focusInner: Color(0x00000000),
    keycapFamily: 'Menlo',
  );

  /// macOS's palette, with Windows' own accent (the default blue's shades,
  /// until the user's is read), what it draws on it, its links (WinUI's link
  /// text in that blue), its focus ring and its UI font for the keycaps. The
  /// focus colours are WinUI's `FocusStrokeColorOuter` and
  /// `FocusStrokeColorInner`.
  static final windowsLight = macLight.copyWith(
    accent: const Color(0xFF0067C0),
    onAccent: const Color(0xFFFFFFFF),
    link: const Color(0xFF003E92),
    focusRing: FocusRingStyle.doubleStroke,
    focusOuter: const Color(0xE4000000),
    focusInner: const Color(0xB3FFFFFF),
    keycapFamily: 'Segoe UI',
  );

  static final windowsDark = macDark.copyWith(
    accent: const Color(0xFF4CC2FF),
    onAccent: const Color(0xFF000000),
    link: const Color(0xFF99EBFF),
    focusRing: FocusRingStyle.doubleStroke,
    focusOuter: const Color(0xFFFFFFFF),
    focusInner: const Color(0xB3000000),
    keycapFamily: 'Segoe UI',
  );

  /// The tokens for [platform] in [brightness], with the user's [accent] when
  /// the OS gave one. The app runs on macOS and Windows only; anything else
  /// (a test host) reads as macOS, where it began.
  static PlatformTokens of(
    TargetPlatform platform,
    Brightness brightness, {
    AccentColors? accent,
  }) {
    final dark = brightness == Brightness.dark;
    final base = platform == TargetPlatform.windows
        ? (dark ? windowsDark : windowsLight)
        : (dark ? macDark : macLight);
    if (accent == null) return base;
    final shade = Color(dark ? accent.dark : accent.light);
    // A link follows the accent on Windows and never does on macOS.
    if (platform != TargetPlatform.windows) return base.copyWith(accent: shade);
    final link = dark ? accent.linkDark : accent.linkLight;
    return base.copyWith(
      accent: shade,
      link: _readable(link == null ? shade : Color(link),
          [base.windowBackground, base.contentBackground]),
    );
  }

  /// [color], or as little darker (or lighter, on dark grounds) as reads at
  /// 4.5:1 on every one of [grounds]. WinUI's link text is chosen against
  /// WinUI's own backgrounds, and this window's are a shade further: yellow
  /// gold's #9B5D00 reads 4.78:1 on WinUI's #F3F3F3 and 4.495:1 on #ECECEE
  /// (measured palettes; every other one passes as it is).
  static Color _readable(Color color, List<Color> grounds) {
    double ratio(Color a, Color b) {
      final (x, y) = (a.computeLuminance(), b.computeLuminance());
      return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
    }

    bool reads(Color c) => grounds.every((g) => ratio(c, g) >= 4.5);
    final towards = grounds.first.computeLuminance() > 0.5
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
    var c = color;
    for (var step = 1; step <= 50 && !reads(c); step++) {
      c = Color.lerp(color, towards, step / 50)!;
    }
    return c;
  }

  @override
  PlatformTokens copyWith({
    Color? windowBackground,
    Color? contentBackground,
    Color? rowHighlight,
    Color? separator,
    Color? labelPrimary,
    Color? labelSecondary,
    Color? labelTertiary,
    Color? accent,
    Color? onAccent,
    Color? link,
    Color? keycapFill,
    Color? keycapBorder,
    Color? keycapShadow,
    Color? glyphOutline,
    Color? warning,
    FocusRingStyle? focusRing,
    Color? focusOuter,
    Color? focusInner,
    String? keycapFamily,
  }) {
    return PlatformTokens(
      windowBackground: windowBackground ?? this.windowBackground,
      contentBackground: contentBackground ?? this.contentBackground,
      rowHighlight: rowHighlight ?? this.rowHighlight,
      separator: separator ?? this.separator,
      labelPrimary: labelPrimary ?? this.labelPrimary,
      labelSecondary: labelSecondary ?? this.labelSecondary,
      labelTertiary: labelTertiary ?? this.labelTertiary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      link: link ?? this.link,
      keycapFill: keycapFill ?? this.keycapFill,
      keycapBorder: keycapBorder ?? this.keycapBorder,
      keycapShadow: keycapShadow ?? this.keycapShadow,
      glyphOutline: glyphOutline ?? this.glyphOutline,
      warning: warning ?? this.warning,
      focusRing: focusRing ?? this.focusRing,
      focusOuter: focusOuter ?? this.focusOuter,
      focusInner: focusInner ?? this.focusInner,
      keycapFamily: keycapFamily ?? this.keycapFamily,
    );
  }

  @override
  PlatformTokens lerp(PlatformTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    // A style and a font cannot be blended; each switches at the midpoint.
    final near = t < 0.5 ? this : other;
    // The accent is not blended at all: a new one is drawn from the first
    // frame. Blended, the window's first open of a session faded from the
    // default blue to the user's accent over the theme's animation, as did
    // every open after an accent change. A link follows the accent on Windows,
    // so it snaps with it; on macOS it snaps too, switching with the appearance
    // where the colours around it blend.
    return PlatformTokens(
      windowBackground: c(windowBackground, other.windowBackground),
      contentBackground: c(contentBackground, other.contentBackground),
      rowHighlight: c(rowHighlight, other.rowHighlight),
      separator: c(separator, other.separator),
      labelPrimary: c(labelPrimary, other.labelPrimary),
      labelSecondary: c(labelSecondary, other.labelSecondary),
      labelTertiary: c(labelTertiary, other.labelTertiary),
      accent: other.accent,
      onAccent: c(onAccent, other.onAccent),
      link: other.link,
      keycapFill: c(keycapFill, other.keycapFill),
      keycapBorder: c(keycapBorder, other.keycapBorder),
      keycapShadow: c(keycapShadow, other.keycapShadow),
      glyphOutline: c(glyphOutline, other.glyphOutline),
      warning: c(warning, other.warning),
      focusRing: near.focusRing,
      focusOuter: c(focusOuter, other.focusOuter),
      focusInner: c(focusInner, other.focusInner),
      keycapFamily: near.keycapFamily,
    );
  }

  /// By value. The theme is rebuilt each time the app notifies, and the
  /// accent makes a new [PlatformTokens] each time; without this, every
  /// rebuild compared unequal and replayed the theme's 200 ms animation.
  @override
  bool operator ==(Object other) =>
      other is PlatformTokens &&
      other.windowBackground == windowBackground &&
      other.contentBackground == contentBackground &&
      other.rowHighlight == rowHighlight &&
      other.separator == separator &&
      other.labelPrimary == labelPrimary &&
      other.labelSecondary == labelSecondary &&
      other.labelTertiary == labelTertiary &&
      other.accent == accent &&
      other.onAccent == onAccent &&
      other.link == link &&
      other.keycapFill == keycapFill &&
      other.keycapBorder == keycapBorder &&
      other.keycapShadow == keycapShadow &&
      other.glyphOutline == glyphOutline &&
      other.warning == warning &&
      other.focusRing == focusRing &&
      other.focusOuter == focusOuter &&
      other.focusInner == focusInner &&
      other.keycapFamily == keycapFamily;

  @override
  int get hashCode => Object.hash(
        windowBackground,
        contentBackground,
        rowHighlight,
        separator,
        labelPrimary,
        labelSecondary,
        labelTertiary,
        accent,
        onAccent,
        link,
        keycapFill,
        keycapBorder,
        keycapShadow,
        glyphOutline,
        warning,
        focusRing,
        focusOuter,
        focusInner,
        keycapFamily,
      );
}

/// Convenience: `context.tokens` instead of a nested `Theme.of` lookup.
extension PlatformThemeContext on BuildContext {
  PlatformTokens get tokens =>
      Theme.of(this).extension<PlatformTokens>() ?? PlatformTokens.macLight;
}

/// The config window's theme for [brightness] on [platform] (the running
/// one unless a test names another), in the user's [accent] when the OS gave
/// one.
ThemeData orthantTheme(
  Brightness brightness, {
  TargetPlatform? platform,
  AccentColors? accent,
}) {
  final on = platform ?? defaultTargetPlatform;
  final t = PlatformTokens.of(on, brightness, accent: accent);
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: t.windowBackground,
    canvasColor: t.windowBackground,
    // Material draws a checkbox's tick in onPrimary: what the platform draws
    // on the accent (white on macOS, as its own checkboxes do).
    colorScheme:
        base.colorScheme.copyWith(primary: t.accent, onPrimary: t.onAccent),
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
