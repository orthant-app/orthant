import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/l10n/strings.dart';
import 'package:orthant/permission/ready_screen.dart';
import 'package:orthant/settings/platform_theme.dart';
import 'package:orthant/settings/region_glyph.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

import 'support/carbon_terms.dart';
import 'support/locales.dart';
import 'support/localized_host.dart';
import 'support/no_english.dart';

void main() {
  Widget host(
    List<Binding> bindings, {
    VoidCallback? onDone,
    VoidCallback? onOpenShortcuts,
    Set<CommandRef> unavailable = const {},
  }) =>
      MaterialApp(
        theme: orthantTheme(Brightness.light),
        home: SizedBox(
          width: 560,
          height: 430,
          child: ReadyScreen(
            bindings: bindings,
            unavailable: unavailable,
            onDone: onDone ?? () {},
            onOpenShortcuts: onOpenShortcuts ?? () {},
          ),
        ),
      );

  testWidgets('shows both tiers, so the grid is discoverable at all',
      (tester) async {
    await tester.pumpWidget(host(macDefaults));
    expect(find.text('Orthant is ready'), findsOneWidget);
    // The summon, and a region shortcut beside it.
    expect(find.text('O'), findsOneWidget);
    expect(find.text('←'), findsOneWidget);
    expect(find.text('→'), findsOneWidget);
  });

  testWidgets('renders the live binding, not a hardcoded chord', (tester) async {
    // Rebinding before the first launch must not make onboarding lie. This is
    // the reason the screen takes bindings at all.
    final rebound = withRebind(macDefaults,
        Binding(BuiltIn(ShortcutCommand.showGrid), carbon(17 /* T */, kCmdKey | kShiftKey)));
    await tester.pumpWidget(host(rebound));

    expect(find.text('T'), findsOneWidget);
    expect(find.text('⌘'), findsOneWidget);
    expect(find.text('⇧'), findsOneWidget);
    expect(find.text('O'), findsNothing);
  });

  testWidgets('an unset summon says so rather than showing nothing',
      (tester) async {
    // Silence would read as "the grid has no shortcut and never did", which is
    // exactly the state a user needs pointing at.
    final cleared = withRebind(
        macDefaults, Binding.unbound(BuiltIn(ShortcutCommand.showGrid)));
    await tester.pumpWidget(host(cleared));
    expect(find.text('No shortcut set'), findsOneWidget);
  });

  testWidgets('a chord macOS refused is marked, not taught', (tester) async {
    // The screen already took `bindings` so it could not show a stale combo.
    // It did not take the refusals, so it could still show one that is stored,
    // displayed and never delivered — on the one screen whose reader has no
    // experience of the app to contradict it. Marked the same way the settings
    // list and the General pane mark it, with the "Change these shortcuts…"
    // link already on screen.
    await tester.pumpWidget(host(macDefaults));
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

    await tester.pumpWidget(
        host(macDefaults, unavailable: {const BuiltIn(ShortcutCommand.showGrid)}));
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.text('O'), findsOneWidget,
        reason: 'still shown — the user has to know which one to change');
  });

  testWidgets('a refused region shortcut is marked too', (tester) async {
    await tester.pumpWidget(host(macDefaults, unavailable: {
      const BuiltIn(ShortcutCommand.leftHalf),
      const BuiltIn(ShortcutCommand.rightHalf),
    }));
    expect(find.byIcon(Icons.warning_amber_rounded), findsNWidgets(2));
  });

  testWidgets('an unset command is not also marked as refused', (tester) async {
    // "No shortcut set" already says everything there is to say; a warning
    // beside it would claim macOS had refused something never registered.
    final cleared = withRebind(
        macDefaults, Binding.unbound(BuiltIn(ShortcutCommand.showGrid)));
    await tester.pumpWidget(
        host(cleared, unavailable: {const BuiltIn(ShortcutCommand.showGrid)}));
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('Done and the shortcuts link each report once', (tester) async {
    var dones = 0;
    var opens = 0;
    await tester.pumpWidget(host(macDefaults,
        onDone: () => dones++, onOpenShortcuts: () => opens++));

    await tester.tap(find.text('Change these shortcuts…'));
    await tester.pumpAndSettle();
    expect((dones, opens), (0, 1));

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect((dones, opens), (1, 1));
  });

  testWidgets('the direct-shortcuts card shows a shape the eleven cannot make',
      (tester) async {
    // Four glyphs: the grid lattice, left half, right half, and a two-thirds
    // example. Onboarding is the one place a new user is told regions of their
    // own exist, and a picture survives being skim-read where a clause does not.
    await tester.pumpWidget(host(macDefaults));
    expect(find.byType(RegionGlyph), findsNWidgets(4));
  });

  group('in the app\'s language', () {
    // The English the screen has always shown, word for word. The captions name
    // the key that extends and the key that places, so they differ by platform.
    const direct = 'Snaps straight to a half, a quarter, or full screen. No '
        'aiming, and you can add shapes of your own, like the third one.';

    String grid(String shift, String place) => 'Opens the grid. Drag across it '
        'to pick any block: thirds, two-thirds, anything. Or use the arrow '
        'keys, $shift to extend, $place to place.';

    testWidgets('English on macOS is exactly what it was', (tester) async {
      await tester.pumpWidget(host(macDefaults));
      expect(find.text('Orthant is ready'), findsOneWidget);
      expect(find.text('Two ways to put a window where you want it.'),
          findsOneWidget);
      expect(find.text(grid('⇧', '↩')), findsOneWidget);
      expect(find.text(direct), findsOneWidget);
      expect(find.text('Change these shortcuts…'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('English on Windows is exactly what it was', (tester) async {
      await tester.pumpWidget(
          host(defaultBindings(platform: TargetPlatform.windows)));
      expect(find.text(grid('Shift', 'Enter')), findsOneWidget);
      expect(find.text(direct), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('English unset labels and the refusal tooltip are unchanged',
        (tester) async {
      final cleared = withRebind(
          withRebind(macDefaults,
              Binding.unbound(const BuiltIn(ShortcutCommand.showGrid))),
          Binding.unbound(const BuiltIn(ShortcutCommand.leftHalf)));
      await tester.pumpWidget(host(cleared));
      expect(find.text('No shortcut set'), findsOneWidget);
      expect(find.text('Not set'), findsOneWidget);

      await tester.pumpWidget(host(macDefaults,
          unavailable: {const BuiltIn(ShortcutCommand.showGrid)}));
      expect(
          tester.widget<Tooltip>(find.byType(Tooltip)).message,
          'macOS or another app already uses this combination, so it never '
          'reaches Orthant.\nPick a different one below.');
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('English tooltip names Windows on Windows', (tester) async {
      final bindings = defaultBindings(platform: TargetPlatform.windows);
      await tester.pumpWidget(host(bindings,
          unavailable: {const BuiltIn(ShortcutCommand.showGrid)}));
      expect(
          tester.widget<Tooltip>(find.byType(Tooltip)).message,
          'Windows or another app already uses this combination, so it never '
          'reaches Orthant.\nPick a different one below.');
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    for (final locale in [kSimplified, kTraditional, kHongKong]) {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
        testWidgets(
            '${locale.toLanguageTag()} on ${platform.name}: no English is '
            'left, semantics included', (tester) async {
          // The platform is the test's `variant`, which is the only thing that
          // puts it back before the framework checks it was.
          setAppStrings(locale);
          addTearDown(() => setAppStrings(kEnglish));
          final bindings = defaultBindings(platform: platform);

          Widget screen(List<Binding> b, Set<CommandRef> unavailable) =>
              localizedApp(
                locale,
                SizedBox(
                  width: 560,
                  height: 430,
                  child: ReadyScreen(
                    bindings: b,
                    unavailable: unavailable,
                    onDone: () {},
                    onOpenShortcuts: () {},
                  ),
                ),
              );

          // Every shortcut set, the grid's and a region's refused: the
          // warning tooltip is on screen.
          await tester.pumpWidget(screen(bindings, {
            const BuiltIn(ShortcutCommand.showGrid),
            const BuiltIn(ShortcutCommand.leftHalf),
          }));
          expect(find.byType(Tooltip), findsNWidgets(2));
          expectNoEnglish(tester);

          // Then both unset labels.
          await tester.pumpWidget(screen(
              withRebind(
                  withRebind(bindings,
                      Binding.unbound(const BuiltIn(ShortcutCommand.showGrid))),
                  Binding.unbound(const BuiltIn(ShortcutCommand.leftHalf))),
              const {}));
          expectNoEnglish(tester);
        }, variant: TargetPlatformVariant.only(platform));
      }
    }

    testWidgets('Chinese says what it means: the captions, the buttons, the '
        'refusal and the unset labels', (tester) async {
      setAppStrings(kSimplified);
      addTearDown(() => setAppStrings(kEnglish));
      final bindings = defaultBindings(platform: TargetPlatform.windows);
      await tester.pumpWidget(localizedApp(
        kSimplified,
        SizedBox(
          width: 560,
          height: 430,
          child: ReadyScreen(
            bindings: withRebind(bindings,
                Binding.unbound(const BuiltIn(ShortcutCommand.showGrid))),
            unavailable: {const BuiltIn(ShortcutCommand.leftHalf)},
            onDone: () {},
            onOpenShortcuts: () {},
          ),
        ),
      ));
      expect(find.text('Orthant 已就绪'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('更改这些快捷键…'), findsOneWidget);
      expect(find.text('未设置快捷键'), findsOneWidget);
      // The keys that extend and place are the Windows legends, English in
      // every language, inside the Chinese sentence.
      expect(find.textContaining('Shift 加方向键扩展，Enter 放置'),
          findsOneWidget);
      expect(
          tester.widget<Tooltip>(find.byType(Tooltip)).message,
          startsWith('Windows 或其他应用已使用此组合键'));
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });
}
