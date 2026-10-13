import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/key_chord.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/permission/ready_screen.dart';
import 'package:orthant/settings/general_pane.dart';
import 'package:orthant/settings/keycap.dart';
import 'package:orthant/settings/mac_control.dart';
import 'package:orthant/settings/platform_theme.dart';
import 'package:orthant/settings/recording_field.dart';
import 'package:orthant/settings/region_picker_sheet.dart';
import 'package:orthant/settings/settings.dart';
import 'package:orthant/settings/shortcuts_screen.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/custom_region.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

/// One design on both platforms: macOS's palette, radii and spacing, shared.
/// What differs is what the OS owns: the accent, what is drawn on it, the link
/// colour, the focus ring and the keycaps' font. macOS's values are pinned
/// exactly.
void main() {
  final both = TargetPlatformVariant(
      {TargetPlatform.macOS, TargetPlatform.windows});

  /// Every colour the two platforms share, by name.
  Map<String, Color> palette(PlatformTokens t) => {
        'windowBackground': t.windowBackground,
        'contentBackground': t.contentBackground,
        'rowHighlight': t.rowHighlight,
        'separator': t.separator,
        'labelPrimary': t.labelPrimary,
        'labelSecondary': t.labelSecondary,
        'labelTertiary': t.labelTertiary,
        'keycapFill': t.keycapFill,
        'keycapBorder': t.keycapBorder,
        'keycapShadow': t.keycapShadow,
        'glyphOutline': t.glyphOutline,
        'warning': t.warning,
      };

  test('macOS draws exactly what 1.0.x drew', () {
    // The values the shipped window had before tokens took platform names.
    expect(palette(PlatformTokens.macLight), {
      'windowBackground': const Color(0xFFECECEE),
      'contentBackground': const Color(0xFFFFFFFF),
      'rowHighlight': const Color(0x0A000000),
      'separator': const Color(0x14000000),
      'labelPrimary': const Color(0xE6000000),
      'labelSecondary': const Color(0x8C000000),
      'labelTertiary': const Color(0x59000000),
      'keycapFill': const Color(0xFFFDFDFD),
      'keycapBorder': const Color(0x24000000),
      'keycapShadow': const Color(0x14000000),
      'glyphOutline': const Color(0x40000000),
      'warning': const Color(0xFFC93400),
    });
    expect(palette(PlatformTokens.macDark), {
      'windowBackground': const Color(0xFF1E1E1F),
      'contentBackground': const Color(0xFF2C2C2E),
      'rowHighlight': const Color(0x14FFFFFF),
      'separator': const Color(0x1AFFFFFF),
      'labelPrimary': const Color(0xE6FFFFFF),
      'labelSecondary': const Color(0x8CFFFFFF),
      'labelTertiary': const Color(0x59FFFFFF),
      'keycapFill': const Color(0xFF3A3A3C),
      'keycapBorder': const Color(0x33FFFFFF),
      'keycapShadow': const Color(0x33000000),
      'glyphOutline': const Color(0x59FFFFFF),
      'warning': const Color(0xFFFF9F0A),
    });
    for (final (t, accent) in [
      (PlatformTokens.macLight, const Color(0xFF007AFF)),
      (PlatformTokens.macDark, const Color(0xFF0A84FF)),
    ]) {
      expect(t.accent, accent, reason: 'the default when macOS gives none');
      expect(t.onAccent, const Color(0xFFFFFFFF));
      expect(t.focusRing, FocusRingStyle.halo);
      expect(t.keycapFamily, 'Menlo');
    }
  });

  test('Windows shares the palette and keeps what its OS owns', () {
    expect(palette(PlatformTokens.windowsLight),
        palette(PlatformTokens.macLight));
    expect(palette(PlatformTokens.windowsDark),
        palette(PlatformTokens.macDark));
    // The default blue's shades, as Windows 11 fills its own controls.
    expect(PlatformTokens.windowsLight.accent, const Color(0xFF0067C0));
    expect(PlatformTokens.windowsDark.accent, const Color(0xFF4CC2FF));
    expect(PlatformTokens.windowsLight.onAccent, const Color(0xFFFFFFFF));
    expect(PlatformTokens.windowsDark.onAccent, const Color(0xFF000000),
        reason: 'a dark theme\'s accent fill is a light shade');
    for (final t in [PlatformTokens.windowsLight, PlatformTokens.windowsDark]) {
      expect(t.focusRing, FocusRingStyle.doubleStroke);
      expect(t.keycapFamily, 'Segoe UI');
    }
    expect(PlatformTokens.windowsLight.focusOuter, const Color(0xE4000000));
    expect(PlatformTokens.windowsLight.focusInner, const Color(0xB3FFFFFF));
    expect(PlatformTokens.windowsDark.focusOuter, const Color(0xFFFFFFFF));
    expect(PlatformTokens.windowsDark.focusInner, const Color(0xB3000000));
  });

  test('of picks the platform and the appearance, and the user\'s accent', () {
    const accent = AccentColors(light: 0xFF953D96, dark: 0xFFA550A7);
    expect(PlatformTokens.of(TargetPlatform.macOS, Brightness.light),
        same(PlatformTokens.macLight));
    expect(PlatformTokens.of(TargetPlatform.windows, Brightness.dark),
        same(PlatformTokens.windowsDark));
    for (final p in TargetPlatform.values) {
      if (p == TargetPlatform.windows) continue;
      expect(PlatformTokens.of(p, Brightness.dark), same(PlatformTokens.macDark),
          reason: '$p reads as macOS');
    }
    final macDark = PlatformTokens.of(TargetPlatform.macOS, Brightness.dark,
        accent: accent);
    expect(macDark.accent, const Color(0xFFA550A7));
    expect(palette(macDark), palette(PlatformTokens.macDark),
        reason: 'the accent replaces the accent and nothing else');
    final winLight = PlatformTokens.of(TargetPlatform.windows, Brightness.light,
        accent: accent);
    expect(winLight.accent, const Color(0xFF953D96));
    expect(winLight.onAccent, PlatformTokens.windowsLight.onAccent);
    expect(winLight.focusRing, FocusRingStyle.doubleStroke);
  });

  test('a link is macOS\'s link colour, which does not follow the accent, and '
      'on Windows the accent', () {
    // NSColor.linkColor, measured under the blue, purple and graphite accents
    // alike.
    expect(PlatformTokens.macLight.link, const Color(0xFF0068DA));
    expect(PlatformTokens.macDark.link, const Color(0xFF419CFF));
    const purple = AccentColors(light: 0xFF953D96, dark: 0xFFA550A7);
    expect(
        PlatformTokens.of(TargetPlatform.macOS, Brightness.light,
                accent: purple)
            .link,
        const Color(0xFF0068DA));
    expect(
        PlatformTokens.of(TargetPlatform.macOS, Brightness.dark,
                accent: purple)
            .link,
        const Color(0xFF419CFF));
    for (final t in [PlatformTokens.windowsLight, PlatformTokens.windowsDark]) {
      expect(t.link, t.accent, reason: 'the default palette');
    }
    for (final (b, shade) in [
      (Brightness.light, const Color(0xFF953D96)),
      (Brightness.dark, const Color(0xFFA550A7)),
    ]) {
      final t = PlatformTokens.of(TargetPlatform.windows, b, accent: purple);
      expect(t.accent, shade);
      expect(t.link, shade, reason: 'a custom palette, $b');
    }
  });

  test('the theme carries the tokens and makes the accent Material\'s primary',
      () {
    const accent = AccentColors(light: 0xFFE0383E, dark: 0xFFFF5257);
    final theme = orthantTheme(Brightness.dark,
        platform: TargetPlatform.windows, accent: accent);
    final t = theme.extension<PlatformTokens>()!;
    expect(t.accent, const Color(0xFFFF5257));
    expect(t.keycapFamily, 'Segoe UI');
    expect(theme.colorScheme.primary, const Color(0xFFFF5257));
    expect(orthantTheme(Brightness.light).extension<PlatformTokens>(),
        same(PlatformTokens.macLight),
        reason: 'the test host reads as macOS, with no accent read');
  });

  test('a checkbox\'s tick is what each platform draws on the accent: white on '
      'macOS in both appearances, Windows\' own on Windows', () {
    for (final b in Brightness.values) {
      expect(orthantTheme(b, platform: TargetPlatform.macOS).colorScheme.onPrimary,
          const Color(0xFFFFFFFF), reason: 'macOS, $b');
      expect(
          orthantTheme(b, platform: TargetPlatform.windows).colorScheme.onPrimary,
          b == Brightness.dark
              ? const Color(0xFF000000)
              : const Color(0xFFFFFFFF),
          reason: 'Windows, $b');
    }
  });

  test('a blend blends the colours, switches the style and the font at its '
      'midpoint, and draws the new accent and link from their start', () {
    final a = PlatformTokens.macLight;
    final b = PlatformTokens.windowsDark;
    expect(a.lerp(b, 0.4).focusRing, FocusRingStyle.halo);
    expect(a.lerp(b, 0.6).focusRing, FocusRingStyle.doubleStroke);
    expect(a.lerp(b, 0.4).keycapFamily, 'Menlo');
    expect(a.lerp(b, 0.6).keycapFamily, 'Segoe UI');
    final mid = a.lerp(b, 0.5);
    expect(mid.onAccent, Color.lerp(a.onAccent, b.onAccent, 0.5));
    expect(mid.focusOuter, Color.lerp(a.focusOuter, b.focusOuter, 0.5));
    expect(mid.focusInner, Color.lerp(a.focusInner, b.focusInner, 0.5));
    expect(mid.windowBackground,
        Color.lerp(a.windowBackground, b.windowBackground, 0.5));
    for (final t in [0.0, 0.5, 1.0]) {
      expect(a.lerp(b, t).accent, b.accent, reason: 'at $t');
      // On Windows a link is the accent, so it snaps with it.
      expect(a.lerp(b, t).link, b.link, reason: 'at $t');
    }
  });

  test('tokens and themes are equal by value', () {
    const purple = AccentColors(light: 0xFF953D96, dark: 0xFFA550A7);
    const red = AccentColors(light: 0xFFE0383E, dark: 0xFFFF5257);
    PlatformTokens tokens(AccentColors accent) =>
        PlatformTokens.of(TargetPlatform.windows, Brightness.dark,
            accent: accent);
    expect(tokens(purple), tokens(purple));
    expect(tokens(purple).hashCode, tokens(purple).hashCode);
    expect(tokens(purple), isNot(tokens(red)));
    expect(
        orthantTheme(Brightness.light,
            platform: TargetPlatform.macOS, accent: purple),
        orthantTheme(Brightness.light,
            platform: TargetPlatform.macOS, accent: purple));
  });

  test('tokens differing only in the link colour are unequal', () {
    PlatformTokens withLink(int argb) =>
        PlatformTokens.macLight.copyWith(link: Color(argb));
    expect(withLink(0xFF0068DA), withLink(0xFF0068DA));
    expect(withLink(0xFF0068DA).hashCode, withLink(0xFF0068DA).hashCode);
    expect(withLink(0xFF0068DA), isNot(withLink(0xFF419CFF)));
    expect(withLink(0xFF0068DA).hashCode, isNot(withLink(0xFF419CFF).hashCode));
  });

  group('the theme in the app', () {
    const purple = AccentColors(light: 0xFF953D96, dark: 0xFFA550A7);
    const red = AccentColors(light: 0xFFE0383E, dark: 0xFFFF5257);
    Color? drawn;
    Widget app(AccentColors accent) => MaterialApp(
          theme: orthantTheme(Brightness.light, accent: accent),
          home: Builder(builder: (context) {
            drawn = context.tokens.accent;
            return const SizedBox();
          }),
        );

    testWidgets('a rebuild in the same accent animates nothing',
        (tester) async {
      await tester.pumpWidget(app(purple));
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(purple));
      expect(tester.hasRunningAnimations, isFalse,
          reason: 'every notify would replay the theme\'s animation');
    });

    testWidgets('a new accent is drawn whole, never faded in', (tester) async {
      await tester.pumpWidget(app(purple));
      await tester.pumpAndSettle();
      expect(drawn, const Color(0xFF953D96));
      // The frame that takes the new theme still draws the old one: the
      // theme's tween returns its start at t = 0 without blending. Every frame
      // after it draws the new accent whole, where a blend would draw a mix
      // of the two for 200 ms. (Launch reads the accent too, so the window's
      // first open does not change it at all: the coordinator's tests.)
      await tester.pumpWidget(app(red));
      await tester.pump(const Duration(milliseconds: 16));
      expect(drawn, const Color(0xFFE0383E));
    });
  });

  group('the focus ring', () {
    Future<void> paintRing(WidgetTester tester, PlatformTokens t) =>
        tester.pumpWidget(Center(
          child: CustomPaint(
            size: const Size(100, 20),
            foregroundPainter: FocusRingPainter(tokens: t, radius: 6, inset: 3),
          ),
        ));

    testWidgets('macOS draws one halo in the accent, 3 pt out',
        (tester) async {
      await paintRing(tester, PlatformTokens.macLight);
      expect(
        find.byType(CustomPaint),
        paints
          ..rrect(
            rrect: RRect.fromRectAndRadius(
                const Rect.fromLTWH(-3, -3, 106, 26), const Radius.circular(9)),
            style: PaintingStyle.stroke,
            strokeWidth: 3,
            color: const Color(0xFF007AFF).withValues(alpha: 0.5),
          ),
      );
    });

    testWidgets('Windows draws WinUI\'s two strokes in the band outside',
        (tester) async {
      await paintRing(tester, PlatformTokens.windowsLight);
      expect(
        find.byType(CustomPaint),
        paints
          ..rrect(
            rrect: RRect.fromRectAndRadius(
                const Rect.fromLTWH(-2, -2, 104, 24), const Radius.circular(8)),
            style: PaintingStyle.stroke,
            strokeWidth: 2,
            color: const Color(0xE4000000),
          )
          ..rrect(
            rrect: RRect.fromRectAndRadius(
                const Rect.fromLTWH(-0.5, -0.5, 101, 21),
                const Radius.circular(6.5)),
            style: PaintingStyle.stroke,
            strokeWidth: 1,
            color: const Color(0xB3FFFFFF),
          ),
      );
    });

    testWidgets('a focused control draws its platform\'s ring', (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic);
      await tester.pumpWidget(MaterialApp(
        theme: orthantTheme(Brightness.light),
        home: Center(
          child: MacControl(
            autofocus: true,
            onPressed: () {},
            child: const SizedBox(width: 60, height: 20),
          ),
        ),
      ));
      await tester.pump();
      final ring = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.foregroundPainter)
          .whereType<FocusRingPainter>()
          .single;
      expect(ring.tokens.focusRing,
          debugDefaultTargetPlatformOverride == TargetPlatform.windows
              ? FocusRingStyle.doubleStroke
              : FocusRingStyle.halo);
      expect((ring.radius, ring.inset), (7.0, 3.0),
          reason: 'MacControl\'s own radius and inset, as before');
    }, variant: both);

    testWidgets('on macOS the region picker\'s grid draws the ring it always '
        'did: the accent at half strength, 3 pt wide, 3 pt out, radius 6',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: orthantTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 700,
            child: RegionPickerSheet(
                gridCols: 6, gridRows: 6, onSubmit: (_) {}, onCancel: () {}),
          ),
        ),
      ));
      final grid = find.byKey(const ValueKey('region-grid'));
      await tester.tapAt(tester.getRect(grid).topLeft + const Offset(5, 5));
      await tester.pumpAndSettle();
      final ring = tester
          .widget<CustomPaint>(
              find.descendant(of: grid, matching: find.byType(CustomPaint)))
          .foregroundPainter! as FocusRingPainter;
      // With the halo's own test above, this is the ring 1.0.x drew: the
      // control's 3 pt radius, 3 pt out, so a 6 pt corner.
      expect((ring.tokens.focusRing, ring.radius, ring.inset),
          (FocusRingStyle.halo, 3.0, 3.0));
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });

  group('keycaps and the recorder', () {
    Future<void> pumpIn(WidgetTester tester, Brightness b, Widget child) =>
        tester.pumpWidget(MaterialApp(
          theme: orthantTheme(b),
          home: Scaffold(body: Center(child: child)),
        ));

    testWidgets('a keycap is set in the platform\'s keycap font',
        (tester) async {
      await pumpIn(tester, Brightness.light, const Keycap('Ctrl'));
      expect(tester.widget<Text>(find.text('Ctrl')).style!.fontFamily,
          debugDefaultTargetPlatformOverride == TargetPlatform.windows
              ? 'Segoe UI'
              : 'Menlo');
    }, variant: both);

    testWidgets('the recorder draws on the accent in the platform\'s colour',
        (tester) async {
      await pumpIn(tester, Brightness.dark,
          RecordingField(onCombo: (_) {}, onCancel: () {}));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      final label = tester.widget<Text>(find.text('Ctrl'));
      expect(label.style!.color, const Color(0xFF000000),
          reason: 'black on Windows\' light accent shade in its dark theme');
      expect(label.style!.fontFamily, 'Segoe UI');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('a pending chord stays white on the warning colour, even on '
        'Windows\' dark theme', (tester) async {
      await pumpIn(
          tester,
          Brightness.dark,
          RecordingField(
            onCombo: (_) {},
            onCancel: () {},
            pending: KeyChord(
              physical: PhysicalKeyboardKey.keyU.usbHidUsage,
              logical: LogicalKeyboardKey.keyU.keyId,
              modifiers: Modifiers.ctrl,
            ),
          ));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text('Ctrl+U')).style!.color,
          const Color(0xFFFFFFFF));
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('the ready screen\'s and the picker\'s buttons draw on the '
        'accent in the platform\'s colour', (tester) async {
      final windows = debugDefaultTargetPlatformOverride == TargetPlatform.windows;
      final want = windows ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
      await pumpIn(
          tester,
          Brightness.dark,
          SizedBox(
            width: 760,
            height: 700,
            child: ReadyScreen(
              bindings: runningDefaults(),
              unavailable: const {},
              onDone: () {},
              onOpenShortcuts: () {},
            ),
          ));
      final done = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(done.style!.foregroundColor!.resolve({}), want, reason: 'Done');
      await pumpIn(
          tester,
          Brightness.dark,
          SizedBox(
            width: 600,
            height: 700,
            child: RegionPickerSheet(
              initial: const CustomRegion(
                  id: 'r', name: 'Left', cols: 2, rows: 1, c0: 0, c1: 0,
                  r0: 0, r1: 0),
              gridCols: 6,
              gridRows: 6,
              onSubmit: (_) {},
              onCancel: () {},
            ),
          ));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text('Save')).style!.color, want,
          reason: 'the picker\'s Save');
    }, variant: both);

    testWidgets('on macOS the recorder stays white on the accent',
        (tester) async {
      await pumpIn(tester, Brightness.dark,
          RecordingField(onCombo: (_) {}, onCancel: () {}));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(tester.widget<Text>(find.text('⌃')).style!.color,
          const Color(0xFFFFFFFF));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });

  // Text that acts as a link is drawn in the platform's link colour: on macOS
  // that is not the accent (a purple one here, so the two cannot be mistaken),
  // and on Windows it is the accent.
  group('links', () {
    const purple = AccentColors(light: 0xFF953D96, dark: 0xFFA550A7);
    const macLink = Color(0xFF419CFF);
    const windowsLink = Color(0xFFA550A7);

    Future<void> pumpIn(
        WidgetTester tester, TargetPlatform platform, Widget child) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: orthantTheme(Brightness.dark,
            platform: platform, accent: purple),
        home: Scaffold(body: SizedBox(width: 760, height: 900, child: child)),
      ));
      await tester.pumpAndSettle();
    }

    Color? textColor(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text)).style!.color;

    Widget general() => GeneralPane(
          settings: const Settings(),
          onSettingsChanged: (_) {},
          permissionGranted: true,
          loginStatus: LoginItemStatus.disabled,
          bindings: runningDefaults(),
        );

    Widget ready() => ReadyScreen(
          bindings: runningDefaults(),
          onDone: () {},
          onOpenShortcuts: () {},
        );

    testWidgets('General\'s Change… is the link colour on macOS',
        (tester) async {
      await pumpIn(tester, TargetPlatform.macOS, general());
      expect(textColor(tester, 'Change…'), macLink);
    });

    testWidgets('General\'s Change… is the accent on Windows', (tester) async {
      await pumpIn(tester, TargetPlatform.windows, general());
      expect(textColor(tester, 'Change…'), windowsLink);
    });

    testWidgets('the ready screen\'s link is the link colour on macOS',
        (tester) async {
      await pumpIn(tester, TargetPlatform.macOS, ready());
      expect(textColor(tester, 'Change these shortcuts…'), macLink);
    });

    testWidgets('the picker\'s Use it here is the link colour on macOS',
        (tester) async {
      await pumpIn(
          tester,
          TargetPlatform.macOS,
          RegionPickerSheet(
            initialChord: runningDefaults()
                .firstWhere(
                    (b) => b.command == const BuiltIn(ShortcutCommand.leftHalf))
                .chord,
            gridCols: 6,
            gridRows: 6,
            onSubmit: (_) {},
            onCancel: () {},
            conflictName: (_) => 'Left half',
          ));
      expect(textColor(tester, 'Use it here'), macLink);
    });

    testWidgets('the shortcuts pane\'s links are the link colour on macOS',
        (tester) async {
      await pumpIn(
          tester,
          TargetPlatform.macOS,
          ShortcutsScreen(
            bindings: runningDefaults(),
            onRebound: (_) {},
            onResetBindings: () {},
            onRestoreBindings: (_) {},
            onRegionSaved: (_) {},
            permissionGranted: false,
          ));
      expect(textColor(tester, 'Open Accessibility Settings…'), macLink);
      expect(textColor(tester, 'Add region…'), macLink);
      expect(tester.widget<Icon>(find.byIcon(Icons.add)).color, macLink);
      await tester.tap(find.text('Reset Shortcuts'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.descendant(
                  of: find.byKey(const ValueKey('notice-action')),
                  matching: find.byType(Text)))
              .style!
              .color,
          macLink,
          reason: 'the notice\'s action');
    });

    testWidgets('the shortcuts pane\'s links are the accent on Windows',
        (tester) async {
      await pumpIn(
          tester,
          TargetPlatform.windows,
          ShortcutsScreen(
            bindings: runningDefaults(),
            onRebound: (_) {},
            onRegionSaved: (_) {},
          ));
      expect(textColor(tester, 'Add region…'), windowsLink);
      expect(tester.widget<Icon>(find.byIcon(Icons.add)).color, windowsLink);
    });
  });
}
