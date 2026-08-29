import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/permission/ready_screen.dart';
import 'package:orthant/settings/mac_theme.dart';
import 'package:orthant/settings/region_glyph.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

void main() {
  Widget host(
    List<Binding> bindings, {
    VoidCallback? onDone,
    VoidCallback? onOpenShortcuts,
    Set<CommandRef> unavailable = const {},
  }) =>
      MaterialApp(
        theme: macTheme(Brightness.light),
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
    await tester.pumpWidget(host(kDefaultBindings));
    expect(find.text('Orthant is ready'), findsOneWidget);
    // The summon, and a region shortcut beside it.
    expect(find.text('O'), findsOneWidget);
    expect(find.text('←'), findsOneWidget);
    expect(find.text('→'), findsOneWidget);
  });

  testWidgets('renders the live binding, not a hardcoded chord', (tester) async {
    // Rebinding before the first launch must not make onboarding lie. This is
    // the reason the screen takes bindings at all.
    final rebound = withRebind(kDefaultBindings,
        const Binding(BuiltIn(ShortcutCommand.showGrid), 17 /* T */, kCmdKey | kShiftKey));
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
        kDefaultBindings, Binding.unbound(BuiltIn(ShortcutCommand.showGrid)));
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
    await tester.pumpWidget(host(kDefaultBindings));
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

    await tester.pumpWidget(
        host(kDefaultBindings, unavailable: {const BuiltIn(ShortcutCommand.showGrid)}));
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.text('O'), findsOneWidget,
        reason: 'still shown — the user has to know which one to change');
  });

  testWidgets('a refused region shortcut is marked too', (tester) async {
    await tester.pumpWidget(host(kDefaultBindings, unavailable: {
      const BuiltIn(ShortcutCommand.leftHalf),
      const BuiltIn(ShortcutCommand.rightHalf),
    }));
    expect(find.byIcon(Icons.warning_amber_rounded), findsNWidgets(2));
  });

  testWidgets('an unset command is not also marked as refused', (tester) async {
    // "No shortcut set" already says everything there is to say; a warning
    // beside it would claim macOS had refused something never registered.
    final cleared = withRebind(
        kDefaultBindings, Binding.unbound(BuiltIn(ShortcutCommand.showGrid)));
    await tester.pumpWidget(
        host(cleared, unavailable: {const BuiltIn(ShortcutCommand.showGrid)}));
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('Done and the shortcuts link each report once', (tester) async {
    var dones = 0;
    var opens = 0;
    await tester.pumpWidget(host(kDefaultBindings,
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
    await tester.pumpWidget(host(kDefaultBindings));
    expect(find.byType(RegionGlyph), findsNWidgets(4));
  });
}
