import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/settings/mac_theme.dart';
import 'package:orthant/settings/recording_field.dart';
import 'package:orthant/settings/region_glyph.dart';
import 'package:orthant/settings/shortcuts_screen.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/settings/region_picker_sheet.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/custom_region.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

Widget _host(Widget child) =>
    MaterialApp(theme: macTheme(Brightness.light), home: child);

void main() {
  testWidgets('lists every command with a region glyph and its combo keycaps',
      (tester) async {
    await tester.pumpWidget(_host(
      ShortcutsScreen(bindings: kDefaultBindings, onRebound: (_) {}),
    ));

    expect(find.text('Left half'), findsOneWidget);
    expect(find.text('Maximize'), findsOneWidget);
    // One diagram per command.
    expect(find.byType(RegionGlyph),
        findsNWidgets(ShortcutCommand.values.length));
    // Combos render as separate keycaps: every default is on ⌃⌥.
    expect(find.text('⌃'), findsNWidgets(ShortcutCommand.values.length));
    expect(find.text('←'), findsOneWidget); // leftHalf
    expect(find.text('↩'), findsOneWidget); // maximize
  });

  testWidgets('a notice does not cover the Reset Shortcuts button',
      (tester) async {
    // Reported from real use: the message bar sat at the bottom of the window
    // and hid "Reset Shortcuts". A bar that obscures a control is worse than no
    // bar. Asserted by *pressing* the button while a notice is up — its
    // presence in the tree proves nothing, since a SnackBar covered it without
    // removing it.
    // Room for twelve rows plus the footer; the default 800x600 surface would
    // leave the custom row outside the viewport and unhittable.
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var resets = 0;
    const region = CustomRegion(
      id: 'r1', name: 'Left ⅔', cols: 3, rows: 1, c0: 0, c1: 1, r0: 0, r1: 0,
    );
    await tester.pumpWidget(_host(SizedBox(
      width: 500,
      height: 900,
      child: ShortcutsScreen(
        bindings: kDefaultBindings,
        regions: const [region],
        onRebound: (_) {},
        onRegionSaved: (_) {},
        onRegionDeleted: (_) {},
        onResetBindings: () => resets++,
      ),
    )));

    // Raise a notice with an action — the tallest kind.
    await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('region-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Left ⅔ deleted.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Reset Shortcuts'));
    await tester.pumpAndSettle();

    expect(resets, 1, reason: 'the notice was sitting on top of the button');
  });

  testWidgets('Reset Shortcuts offers the previous set straight back',
      (tester) async {
    // One click rewrote eleven-plus bindings with no way back, while deleting a
    // *single* region has had an Undo since M9 — the larger change was the less
    // recoverable one.
    //
    // A **live** host, and that is load-bearing: with a fixed `bindings:` prop
    // the pane never rebuilds, so "the set before the change" and "the set now"
    // are the same object and an Undo that handed back the *damage* would pass.
    // In production `main.dart` wraps the window in a `ListenableBuilder` on the
    // coordinator, so `widget.bindings` really is the post-reset list while the
    // notice is up.
    var live = withRebind(kDefaultBindings,
        const Binding(BuiltIn(ShortcutCommand.center), 6, kControlOption));
    var resets = 0;
    List<Binding>? restored;
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (context, setInner) => ShortcutsScreen(
        bindings: live,
        onRebound: (_) {},
        onResetBindings: () => setInner(() {
          resets++;
          live = [...kDefaultBindings];
        }),
        onRestoreBindings: (b) => restored = b,
      ),
    )));

    await tester.tap(find.text('Reset Shortcuts'));
    await tester.pumpAndSettle();
    expect(resets, 1);
    expect(find.textContaining('reset to their defaults'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notice-action')));
    await tester.pumpAndSettle();

    expect(restored, isNotNull);
    final center = restored!
        .firstWhere((b) => b.command == const BuiltIn(ShortcutCommand.center));
    expect(center.keyCode, 6, reason: 'the rebind the reset wiped, back again');
  });

  testWidgets('Reset offers back only the rows it actually changed',
      (tester) async {
    // A row already sitting at its default is not part of the reset — the reset
    // left it exactly as it found it. Carrying it in the snapshot anyway means
    // that editing it afterwards and then clicking Undo reverts an edit this
    // operation never made, which is silent data loss dressed as a way back.
    var live = withRebind(kDefaultBindings,
        const Binding(BuiltIn(ShortcutCommand.center), 6, kControlOption));
    List<Binding>? restored;
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (context, setInner) => ShortcutsScreen(
        bindings: live,
        onRebound: (_) {},
        onResetBindings: () => setInner(() => live = [...kDefaultBindings]),
        onRestoreBindings: (b) => restored = b,
      ),
    )));

    await tester.tap(find.text('Reset Shortcuts'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notice-action')));
    await tester.pumpAndSettle();

    // Center was rebound, so the reset changed it and Undo owns it.
    expect(restored!.map((b) => b.command),
        contains(const BuiltIn(ShortcutCommand.center)));
    // Left half was untouched at ⌃⌥←, so it is none of this operation's
    // business. Asserted on a *specific* row rather than on the length: a
    // count passes for any ten of the eleven.
    expect(
      restored!.map((b) => b.command),
      isNot(contains(const BuiltIn(ShortcutCommand.leftHalf))),
      reason: 'a row the reset did not change was still claimed by its Undo',
    );
  });

  testWidgets('Reset says nothing about undo when there is no way back',
      (tester) async {
    await tester.pumpWidget(_host(ShortcutsScreen(
      bindings: kDefaultBindings,
      onRebound: (_) {},
      onResetBindings: () {},
    )));
    await tester.tap(find.text('Reset Shortcuts'));
    await tester.pumpAndSettle();
    expect(find.textContaining('reset to their defaults'), findsOneWidget);
    expect(find.byKey(const ValueKey('notice-action')), findsNothing,
        reason: 'an Undo button that cannot undo');
  });

  testWidgets('the footer keeps its height, whatever it is saying',
      (tester) async {
    // This window measures its content to size itself, so anything that changes
    // the footer's height moves the whole window. Measured against the real app
    // before it was pinned: the pane oscillated **752 ↔ 755 pt** — a twitch when
    // a notice appeared, and *another* six seconds later when it expired. The
    // second is the worse one: the window moves while the user is doing nothing.
    //
    // The viewport is the proxy, because it is exactly what the window-sizing
    // arithmetic subtracts: `chrome = view height - viewport height`.
    double viewport() => tester
        .renderObject<RenderBox>(find.byType(SingleChildScrollView))
        .size
        .height;

    await tester.pumpWidget(_host(ShortcutsScreen(
      bindings: kDefaultBindings,
      onRebound: (_) {},
      onRestoreBindings: (_) {},
      onResetBindings: () {},
    )));
    final hint = viewport();

    // Recording: Reset Shortcuts hides itself, so the tallest control goes.
    await tester.tap(find.text('Left half'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordingField), findsOneWidget);
    expect(viewport(), hint, reason: 'Reset hides while recording');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // A notice, with an action button beside it.
    await tester.tap(find.text('Reset Shortcuts'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notice-action')), findsOneWidget);
    expect(viewport(), hint, reason: 'a notice with an Undo button');

    // And back to the hint when it expires — the unprompted half.
    await tester.pump(const Duration(seconds: 11));
    expect(find.byKey(const ValueKey('notice-action')), findsNothing);
    expect(viewport(), hint);
  });

  group('a combination another command owns', () {
    // The history, because it explains why this is neither of the two obvious
    // answers. Recording ⌃⌥← on "Open grid" originally took it from "Left
    // half", which silently became unset. That was reported twice from real
    // use, so it was made to *refuse* — and refusing turned out to be a dead
    // end: the row stopped listening, and putting ⌃⌥← on Open grid then meant
    // clearing Left half ten rows away and starting over. Six interactions for
    // one intent.
    //
    // It now asks. Two commands still cannot share a chord; the difference is
    // that the person typing decides which one gives, and can undo it.

    /// Record ⌃⌥← — which belongs to Left half — on [on].
    Future<void> pressTakenCombo(WidgetTester tester, {String on = 'Open grid'}) async {
      await tester.tap(find.text(on));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('is not taken on the first press, and the row keeps listening',
        (tester) async {
      final changes = <Binding>[];
      await tester.pumpWidget(_host(ShortcutsScreen(
        bindings: kDefaultBindings,
        onRebound: changes.add,
      )));

      await pressTakenCombo(tester);

      expect(changes, isEmpty, reason: 'the combo was taken from its owner');
      expect(find.textContaining('is used by Left half'), findsOneWidget);
      // The dead end that refusal created: a rejected press used to end the
      // recording, so even "try another one" cost a further click.
      expect(find.byType(RecordingField), findsOneWidget,
          reason: 'the row stopped listening, so there is nothing to press');
    });

    testWidgets('is taken when the same combination is pressed again',
        (tester) async {
      final changes = <Binding>[];
      await tester.pumpWidget(_host(ShortcutsScreen(
        bindings: kDefaultBindings,
        onRebound: changes.add,
      )));

      await pressTakenCombo(tester);
      expect(changes, isEmpty);
      await pressTakenCombo(tester);

      expect(changes.single.command, const BuiltIn(ShortcutCommand.showGrid));
      expect(changes.single.keyCode, 123);
      expect(changes.single.modifiers, kControlOption);
    });

    testWidgets('is taken by the footer button as well', (tester) async {
      // Both routes exist because RecordingField answers every key with
      // `handled`, so Tab cannot reach this button — a mouse-only affordance
      // would be a keyboard dead end, and a key-only one a mouse dead end.
      final changes = <Binding>[];
      await tester.pumpWidget(_host(ShortcutsScreen(
        bindings: kDefaultBindings,
        onRebound: changes.add,
      )));

      await pressTakenCombo(tester);
      await tester.tap(find.byKey(const ValueKey('notice-action')));
      await tester.pumpAndSettle();

      expect(changes.single.command, const BuiltIn(ShortcutCommand.showGrid));
      expect(changes.single.keyCode, 123);
    });

    testWidgets('reports what it cost, and hands back the way there',
        (tester) async {
      // The undo is what makes offering the take safe at all: without it this
      // is the silent theft that was reported twice.
      //
      // A **live** host: with a fixed `bindings:` prop the pane never rebuilds,
      // so the snapshot and a live read are indistinguishable — and an Undo
      // that handed back the damage instead of the way back would pass. In
      // production the window rebuilds on every coordinator change.
      var live = [...kDefaultBindings];
      List<Binding>? restored;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (context, setInner) => ShortcutsScreen(
          bindings: live,
          onRebound: (b) => setInner(() => live = withRebind(live, b)),
          onRestoreBindings: (b) => restored = b,
        ),
      )));

      await pressTakenCombo(tester);
      await pressTakenCombo(tester);

      // The take really landed, so the pane is now showing the damage.
      expect(
          live
              .firstWhere(
                  (b) => b.command == const BuiltIn(ShortcutCommand.leftHalf))
              .isBound,
          isFalse);

      expect(find.textContaining('Left half lost ⌃⌥←'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notice-action')));
      await tester.pumpAndSettle();

      // Both rows the take touched, and **only** those two: Left half gets its
      // combination back *and* Open grid gives up what it took. The second half
      // is what distinguishes the snapshot from a live read; the exact command
      // set is what keeps an Undo from reaching rows this operation never
      // changed. Asserted as a set rather than a length — a count passes for
      // any two bindings, including the wrong two.
      expect(restored, isNotNull);
      expect(
        restored!.map((b) => b.command).toSet(),
        {
          const BuiltIn(ShortcutCommand.showGrid),
          const BuiltIn(ShortcutCommand.leftHalf),
        },
      );
      final leftHalf = restored!.firstWhere(
          (b) => b.command == const BuiltIn(ShortcutCommand.leftHalf));
      expect(leftHalf.keyCode, 123);
      expect(leftHalf.modifiers, kControlOption);
      final showGrid = restored!.firstWhere(
          (b) => b.command == const BuiltIn(ShortcutCommand.showGrid));
      expect(showGrid.keyCode, 31,
          reason: 'Open grid must go back to ⌃⌥O, not keep what it took');
    });

    testWidgets('undo reaches only the rows it changed, not later edits',
        (tester) async {
      // The notice lasts ten seconds and nothing cancels it — a conflict-free
      // rebind raises no pending question, so `_startRecording`'s cleanup does
      // not apply. With a whole-set snapshot the two facts combined into silent
      // data loss: take a chord, rebind a third command, click the Undo that is
      // still sitting there, and the third command went back to a binding the
      // user had already replaced. Nothing said it had.
      var live = [...kDefaultBindings];
      List<Binding>? restored;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (context, setInner) => ShortcutsScreen(
          bindings: live,
          onRebound: (b) => setInner(() => live = withRebind(live, b)),
          onRestoreBindings: (b) => restored = b,
        ),
      )));

      await pressTakenCombo(tester);
      await pressTakenCombo(tester);

      // A second, unrelated change while the Undo is still up. ⌃⌥Z is free, so
      // this displaces nothing and raises no notice of its own.
      await tester.tap(find.text('Center'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
          live
              .firstWhere(
                  (b) => b.command == const BuiltIn(ShortcutCommand.center))
              .keyCode,
          6,
          reason: 'the second edit must have landed for this to test anything');

      // The first change's Undo is still on screen — which is the point. It
      // may still be offered; it may not carry an unrelated row with it.
      expect(find.textContaining('Left half lost ⌃⌥←'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notice-action')));
      await tester.pumpAndSettle();

      expect(restored, isNotNull);
      expect(
        restored!.map((b) => b.command),
        isNot(contains(const BuiltIn(ShortcutCommand.center))),
        reason: 'undoing the take rewrote a row the take never touched',
      );
      // And it still does its own job.
      expect(
          restored!
              .firstWhere(
                  (b) => b.command == const BuiltIn(ShortcutCommand.leftHalf))
              .keyCode,
          123);
    });

    testWidgets('points at the row it cost, not only at the sentence',
        (tester) async {
      // "Left half lost ⌃⌥←" names a row that can be anywhere in a list of
      // twelve, and the footer is at the bottom of the window. The message and
      // the thing it describes were disconnected — which is most of what made
      // the silent theft this replaced so confusing to begin with.
      var live = [...kDefaultBindings];
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (context, setInner) => ShortcutsScreen(
          bindings: live,
          onRebound: (b) => setInner(() => live = withRebind(live, b)),
          onRestoreBindings: (_) {},
        ),
      )));

      Finder tinted() => find.ancestor(
            of: find.text('Left half'),
            matching: find.byWidgetPredicate(
                (w) => w is ColoredBox && w.color.a > 0 && w.color.a < 1),
          );
      expect(tinted(), findsNothing);

      await pressTakenCombo(tester);
      // The confirming press is pumped by hand: `pumpAndSettle` would run the
      // 900 ms tween to its end before looking, so the tint would always be
      // gone and this would pass with the flash deleted. (It did, first draft.)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tinted(), findsOneWidget,
          reason: 'the row that lost its combination was not pointed out');

      await tester.pump(const Duration(milliseconds: 1200));
      expect(tinted(), findsNothing, reason: 'a tint that never fades is state');
    });

    testWidgets('is dropped by esc, leaving the question behind it',
        (tester) async {
      final changes = <Binding>[];
      await tester.pumpWidget(_host(ShortcutsScreen(
        bindings: kDefaultBindings,
        onRebound: changes.add,
      )));

      await pressTakenCombo(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(changes, isEmpty);
      // The question's notice is sticky — it has no timer — so if esc did not
      // take it down, nothing ever would.
      expect(find.textContaining('is used by'), findsNothing);
      expect(find.byType(RecordingField), findsNothing);
    });

    testWidgets('gives way to a free combination pressed instead',
        (tester) async {
      final changes = <Binding>[];
      await tester.pumpWidget(_host(ShortcutsScreen(
        bindings: kDefaultBindings,
        onRebound: changes.add,
      )));

      await pressTakenCombo(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(changes.single.keyCode, 6, reason: '⌃⌥Z, not the taken ⌃⌥←');
      expect(find.textContaining('is used by'), findsNothing);
    });

    testWidgets('is not confirmed by a *different* occupied combination',
        (tester) async {
      // The confirmation is "press it again", so it has to be the same chord.
      // Pressing ⌃⌥← and then ⌃⌥→ is two questions, not a question and an
      // answer — and answering the second with the first would take a
      // combination the user had been shown nothing about.
      final changes = <Binding>[];
      await tester.pumpWidget(_host(ShortcutsScreen(
        bindings: kDefaultBindings,
        onRebound: changes.add,
      )));

      await pressTakenCombo(tester);
      expect(find.textContaining('is used by Left half'), findsOneWidget);

      // ⌃⌥→ belongs to Right half.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(changes, isEmpty, reason: 'taken without ever being asked');
      expect(find.textContaining('is used by Right half'), findsOneWidget);
    });

    testWidgets('is put to a screen reader, not only to the footer',
        (tester) async {
      // The footer is a plain Text with no live region, the warning-coloured
      // pill is excluded from semantics, and RecordingField answers every key
      // with `handled` so Tab cannot reach "Use it here". Without this the
      // question is silence, and the only way out is esc — the dead end this
      // whole change exists to remove, restored for one class of user.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(ShortcutsScreen(
        bindings: kDefaultBindings,
        onRebound: (_) {},
      )));

      await pressTakenCombo(tester);

      expect(
          tester.getSemantics(find.bySemanticsLabel(RegExp(
              r'Open grid, ⌃⌥← is used by Left half\. '
              r'Press it again to use it here'))),
          isNotNull);
      handle.dispose();
    });

    testWidgets('undoing it does not put the hotkeys back mid-capture',
        (tester) async {
      // A notice outlives the moment that raised it: six seconds is long enough
      // to click another row. Undo re-registers the *whole* set, so firing it
      // while a row listens means the next chord is swallowed by its own
      // registration and moves a window instead of being recorded.
      //
      // `_ResetButton` beside it is simply hidden while recording, for exactly
      // this reason — the gate was on one of the two buttons in that row.
      final events = <String>[];
      await tester.pumpWidget(_host(ShortcutsScreen(
        bindings: kDefaultBindings,
        onRebound: (_) {},
        onRestoreBindings: (_) => events.add('restore'),
        onCaptureStart: () async => events.add('suspend'),
        onCaptureEnd: () async => events.add('resume'),
      )));

      await pressTakenCombo(tester);
      await pressTakenCombo(tester); // taken; Undo now up for six seconds
      expect(find.byKey(const ValueKey('notice-action')), findsOneWidget);

      await tester.tap(find.text('Maximize')); // start recording elsewhere
      await tester.pumpAndSettle();
      expect(find.byType(RecordingField), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('notice-action')));
      await tester.pumpAndSettle();

      expect(events.last, 'restore');
      expect(events.sublist(events.length - 2), ['resume', 'restore'],
          reason: 'the hotkeys came back while the row was still listening');
      expect(find.byType(RecordingField), findsNothing);
    });

    testWidgets('survives a hotkey resume that fails on the way out',
        (tester) async {
      // Undo now ends the recording first (so it cannot re-register the chords
      // mid-capture), and that stop awaits a method-channel call that can
      // reject. Letting the rejection through would lose the only way back from
      // a multi-row change, silently — the same "a failed resume must not eat
      // the click" rule this pane already applies when opening the picker.
      var restored = false;
      await tester.pumpWidget(_host(ShortcutsScreen(
        bindings: kDefaultBindings,
        onRebound: (_) {},
        onRestoreBindings: (_) => restored = true,
        onCaptureEnd: () async => throw StateError('channel gone'),
      )));

      await pressTakenCombo(tester);
      await pressTakenCombo(tester); // taken; Undo up
      await tester.tap(find.text('Maximize')); // recording elsewhere
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('notice-action')));
      await tester.pumpAndSettle();

      expect(restored, isTrue, reason: 'the Undo was eaten by a failed resume');
    });

    testWidgets('is committed even when the hotkey resume fails',
        (tester) async {
      // The same rule on the ordinary path: `_commit` stops the recording and
      // then rebinds, so a rejection between the two loses the rebind outright.
      final changes = <Binding>[];
      await tester.pumpWidget(_host(ShortcutsScreen(
        bindings: kDefaultBindings,
        onRebound: changes.add,
        onCaptureEnd: () async => throw StateError('channel gone'),
      )));

      await tester.tap(find.text('Open grid'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(changes.single.keyCode, 6, reason: 'the rebind was lost');
    });

    testWidgets('does not follow the recording to another row', (tester) async {
      // Clicking a second row while one is recording starts recording there,
      // without stopping the first. The pending question must not survive that:
      // its footer button rebinds the row it was raised for, so pressing the
      // same chord on the new row would otherwise take it with no question at
      // all — for the wrong row.
      final changes = <Binding>[];
      await tester.pumpWidget(_host(ShortcutsScreen(
        bindings: kDefaultBindings,
        onRebound: changes.add,
      )));

      await pressTakenCombo(tester);
      expect(find.textContaining('is used by'), findsOneWidget);

      await tester.tap(find.text('Maximize'));
      await tester.pumpAndSettle();
      expect(find.textContaining('is used by'), findsNothing,
          reason: 'the question is about a row that is no longer recording');

      await pressTakenCombo(tester, on: 'Maximize');
      expect(changes, isEmpty, reason: 'taken without ever being asked');
    });
  });

  testWidgets('a free combo is still accepted', (tester) async {
    // The counterpart, so the refusal cannot be a blanket "nothing commits".
    final changes = <Binding>[];
    await tester.pumpWidget(_host(ShortcutsScreen(
      bindings: kDefaultBindings,
      onRebound: changes.add,
    )));

    await tester.tap(find.text('Open grid'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(changes.single.isBound, isTrue);
  });

  testWidgets('an unbound command offers a button, not a status', (tester) async {
    final bindings = withRebind(kDefaultBindings,
        const Binding(BuiltIn(ShortcutCommand.leftHalf), 124, kControlOption));
    await tester.pumpWidget(_host(
      ShortcutsScreen(bindings: bindings, onRebound: (_) {}),
    ));
    // rightHalf was displaced by leftHalf taking ⌃⌥→.
    expect(find.text('Click to set'), findsOneWidget);
    expect(find.text('Not set'), findsNothing,
        reason: 'grey status text on a row whose whole purpose is a click');
  });

  testWidgets('recording starts without waiting on the hotkey suspend',
      (tester) async {
    // Entering recording mode used to be gated behind the suspend, which is a
    // method-channel call: `await onCaptureStart()` came *before* the setState
    // that shows the recorder. So if that call was slow or failed, the click
    // did nothing at all — no pill, no error, a row that simply refused to be
    // clicked, with nothing on screen to say why because nothing had changed.
    //
    // A blocked completer is the faithful shape. It covers the likelier real
    // failure too: not a throw, just a round trip that has not come back yet.
    final blocked = Completer<void>();
    await tester.pumpWidget(_host(ShortcutsScreen(
      bindings: kDefaultBindings,
      onRebound: (_) {},
      onCaptureStart: () => blocked.future,
    )));

    await tester.tap(find.text('Left half'));
    await tester.pump();

    expect(find.text('Press keys…'), findsOneWidget,
        reason: 'the click waited on a channel call that had not returned');

    blocked.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('an unset row says it can be set, on reach', (tester) async {
    // "Not set" is a status, and on a row whose whole purpose is to be clicked
    // it read as a dead end — a user whose shortcut had been displaced
    // concluded the row could not be set at all. It always could; nothing said
    // so. Asserted for the pointer *and* the keyboard, because the row is
    // reachable both ways and the affordance has to be too.
    final bindings = withRebind(kDefaultBindings,
        const Binding(BuiltIn(ShortcutCommand.leftHalf), 124, kControlOption));
    final changes = <Binding>[];
    await tester.pumpWidget(_host(
      ShortcutsScreen(bindings: bindings, onRebound: changes.add),
    ));
    // A button, present at rest — not status text that only becomes an
    // invitation once the pointer is already there.
    expect(find.text('Click to set'), findsOneWidget);
    expect(find.text('Not set'), findsNothing);

    // And the invitation is true: the row records and commits.
    await tester.tap(find.text('Click to set'));
    await tester.pumpAndSettle();
    expect(find.text('Press keys…'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(changes.single.isBound, isTrue,
        reason: 'the row said it could be set and then could not');
  });

  testWidgets('marks combos the OS refused to register', (tester) async {
    // The row is the only place this can surface: a refused chord is stored and
    // rendered exactly like a working one, and simply never fires.
    await tester.pumpWidget(_host(ShortcutsScreen(
      bindings: kDefaultBindings,
      unavailable: {const BuiltIn(ShortcutCommand.center)},
      onRebound: (_) {},
    )));
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('an unbound command is never marked unavailable', (tester) async {
    // "Not set" already says the shortcut does nothing; a warning beside it
    // would claim a conflict that does not exist.
    final bindings = withRebind(kDefaultBindings,
        const Binding(BuiltIn(ShortcutCommand.leftHalf), 124, kControlOption));
    await tester.pumpWidget(_host(ShortcutsScreen(
      bindings: bindings,
      unavailable: {const BuiltIn(ShortcutCommand.rightHalf)},
      onRebound: (_) {},
    )));
    expect(find.text('Click to set'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('suspends global hotkeys while recording, resumes on esc',
      (tester) async {
    final events = <String>[];
    await tester.pumpWidget(_host(ShortcutsScreen(
      bindings: kDefaultBindings,
      onRebound: (_) {},
      onCaptureStart: () async => events.add('suspend'),
      onCaptureEnd: () async => events.add('resume'),
    )));

    await tester.tap(find.text('Left half'));
    await tester.pumpAndSettle();
    expect(events, ['suspend'], reason: 'hotkeys must be off while recording');
    expect(find.text('Press keys…'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(events, ['suspend', 'resume']);
    expect(find.text('Press keys…'), findsNothing);
  });

  testWidgets('clearing a shortcut reports an unbound binding', (tester) async {
    final changes = <Binding>[];
    await tester.pumpWidget(_host(ShortcutsScreen(
      bindings: kDefaultBindings,
      onRebound: changes.add,
    )));

    // The clear affordance is resident for every bound row — a screen reader
    // has to be able to reach it without hovering — and only *shown* on hover,
    // so it is addressed by which shortcut it removes rather than by its icon.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('Maximize')));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Remove Maximize shortcut'));
    await tester.pumpAndSettle();

    expect(changes.single.command, const BuiltIn(ShortcutCommand.maximize));
    expect(changes.single.isBound, isFalse);
  });

  group('custom rows', () {
    // `host` lays the pane out at 900 pt, and the default 800×600 surface clips
    // everything below the fold: `find` still succeeds down there, but a tap
    // computes a location outside the view and silently lands on nothing. The
    // real window sizes itself to its content, so this is the production
    // geometry rather than a concession to the test.
    //
    // Set on the view rather than through `setSurfaceSize`, which asserts
    // `inTest` and so cannot run from `setUp` at all.
    TestFlutterView view() => TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    setUp(() => view().physicalSize =
        const Size(700, 1100) * view().devicePixelRatio);
    tearDown(() => view().resetPhysicalSize());

    const region = CustomRegion(
      id: 'r1',
      name: 'Left ⅔',
      cols: 3,
      rows: 1,
      c0: 0,
      c1: 1,
      r0: 0,
      r1: 0,
    );

    Widget host({
      List<Binding>? bindings,
      List<CustomRegion> regions = const [region],
      void Function(Binding)? onRebound,
      void Function(RegionDraft)? onRegionSaved,
      void Function(String)? onRegionDeleted,
      CustomRegion? pendingRegion,
      VoidCallback? onPendingConsumed,
      Future<void> Function()? onCaptureStart,
      Future<void> Function()? onCaptureEnd,
    }) =>
        _host(SizedBox(
          width: 500,
          height: 900,
          child: ShortcutsScreen(
            bindings: bindings ??
                [
                  ...kDefaultBindings,
                  const Binding(
                      Custom('r1'), 123, kControlOption | kShiftKey),
                ],
            regions: regions,
            onRebound: onRebound ?? (_) {},
            onRegionSaved: onRegionSaved ?? (_) {},
            onRegionDeleted: onRegionDeleted,
            pendingRegion: pendingRegion,
            onPendingConsumed: onPendingConsumed,
            onCaptureStart: onCaptureStart,
            onCaptureEnd: onCaptureEnd,
          ),
        ));

    /// Wraps the app so `animating: false` reproduces a hidden window: the
    /// clock runs, animations do not. Present in *every* pump with only the
    /// flag changing — introducing the wrapper later rebuilds the MaterialApp
    /// beneath it, recreating the messenger and navigator, and the test then
    /// passes having proved nothing.
    Widget staged(Widget app, {required bool animating}) =>
        TickerMode(enabled: animating, child: app);

    testWidgets('a region renders as a row with its own name', (tester) async {
      await tester.pumpWidget(host());
      expect(find.text('Left ⅔'), findsOneWidget);
      expect(find.byType(RegionGlyph),
          findsNWidgets(ShortcutCommand.values.length + 1));
    });

    testWidgets('opening the picker ends a recording left running',
        (tester) async {
      // Found by driving the real app: clicking a row and then "Add region…"
      // left the row listening *underneath the modal* — pill and all, with the
      // footer still saying "Listening…".
      //
      // And worse than it looks. The row's recording holds a hotkey suspension
      // that only _stopRecording hands back, while the route's endCapture is a
      // no-op unless the *sheet* recorded something. Cancelling the picker
      // therefore left every shortcut dead until the user pressed esc on a row
      // they had stopped looking at.
      var suspends = 0;
      var resumes = 0;
      await tester.pumpWidget(host(
        onCaptureStart: () async => suspends++,
        onCaptureEnd: () async => resumes++,
      ));

      await tester.tap(find.text('Left half'));
      await tester.pumpAndSettle();
      expect(find.byType(RecordingField), findsOneWidget);
      expect(suspends, 1);
      expect(resumes, 0);

      await tester.tap(find.byKey(const ValueKey('add-region')));
      await tester.pumpAndSettle();

      expect(find.byType(RegionPickerSheet), findsOneWidget);
      expect(find.byType(RecordingField), findsNothing,
          reason: 'a row still listening behind a modal');
      expect(find.textContaining('Listening…'), findsNothing);
      expect(resumes, 1, reason: 'the row never handed its suspension back');

      // And it stays handed back through a cancel, which is the path that
      // stranded it: the sheet never recorded, so its own endCapture does
      // nothing at all.
      await tester.tap(find.byKey(const ValueKey('region-cancel')));
      await tester.pumpAndSettle();
      expect(resumes, 1);
      expect(suspends, 1, reason: 'nothing should have re-suspended');
    });

    testWidgets('going away mid-recording hands the hotkeys back',
        (tester) async {
      // SettingsWindow swaps panes with a `switch` on the tab, so clicking
      // General *disposes* this one. A recording live at that moment left every
      // global shortcut suspended for as long as the window stayed open, with
      // nothing on screen to say so — the only backstop being the window close.
      final events = <String>[];
      await tester.pumpWidget(host(
        onCaptureStart: () async => events.add('suspend'),
        onCaptureEnd: () async => events.add('resume'),
      ));

      await tester.tap(find.text('Left half'));
      await tester.pumpAndSettle();
      expect(events, ['suspend']);

      // Whatever replaces the pane — the other tab, or the window going away.
      await tester.pumpWidget(_host(const SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(events, ['suspend', 'resume']);
    });

    testWidgets('a failing hotkey resume does not eat the picker',
        (tester) async {
      // `_stopRecording` awaits onCaptureEnd, a method-channel call that can
      // reject. Letting that throw escape did two things at once: it stranded
      // `_presenting`, after which "Add region…" and every region's edit
      // control silently did nothing for the rest of the session; and it
      // swallowed the click that started it. No error surfaced either time,
      // because these callbacks are VoidCallbacks and the future is unobserved.
      var fail = true;
      await tester.pumpWidget(host(
        onCaptureEnd: () async {
          if (fail) throw StateError('channel gone');
        },
      ));

      await tester.tap(find.text('Left half'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-region')));
      await tester.pumpAndSettle();

      expect(find.byType(RegionPickerSheet), findsOneWidget,
          reason: 'a failed hotkey resume swallowed the click');
      expect(find.byType(RecordingField), findsNothing,
          reason: 'the recording state is cleared before the channel call');

      // And the slot comes back, or the pane is read-only until relaunch.
      fail = false;
      await tester.tap(find.byKey(const ValueKey('region-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-region')));
      await tester.pumpAndSettle();
      expect(find.byType(RegionPickerSheet), findsOneWidget);
    });

    testWidgets('clearing a row while another records ends the recording',
        (tester) async {
      // The clear button is revealed by plain hover, on *any* row, so it is
      // reachable while a different row is listening — and `onRebound`
      // re-registers the whole hotkey set. That put every chord back live under
      // a recorder that was still showing "Press keys…", so the next
      // combination fired a window move instead of being recorded.
      //
      // `_ResetButton` is hidden while recording, the notice action and the
      // picker both end the recording first. This was the one control left.
      final events = <String>[];
      await tester.pumpWidget(host(
        onRebound: (b) => events.add('rebind'),
        onCaptureStart: () async => events.add('suspend'),
        onCaptureEnd: () async => events.add('resume'),
      ));

      await tester.tap(find.text('Open grid'));
      await tester.pumpAndSettle();
      expect(events, ['suspend']);

      // Hover another row to reveal its clear button, then press it.
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
          pointer.hover(tester.getCenter(find.text('Left half'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clear-leftHalf')));
      await tester.pumpAndSettle();

      expect(events, ['suspend', 'resume', 'rebind'],
          reason: 'the chords came back under a row that was still listening');
      expect(find.byType(RecordingField), findsNothing);
    });

    testWidgets('a queued ⌘S shape survives a failed resume', (tester) async {
      // The drain used to sit *after* the try/finally, so a throw out of the
      // body released the slot but skipped the queue — silently dropping the
      // shape ⌘S was pressed to keep, which is the exact loss the queue exists
      // to prevent, one level down. `endCapture()` inside `Future.wait` is the
      // reachable throw: the sheet recorded, and its resume failed.
      const handed = CustomRegion(
        id: 'r9', name: 'Handed over',
        cols: 3, rows: 1, c0: 2, c1: 2, r0: 0, r1: 0,
      );
      var fail = false;
      Widget h({CustomRegion? pending}) => host(
            pendingRegion: pending,
            onCaptureEnd: () async {
              if (fail) throw StateError('channel gone');
            },
          );

      await tester.pumpWidget(h());
      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      expect(find.byType(RegionPickerSheet), findsOneWidget);

      // ⌘S lands while the sheet is up, so it queues.
      await tester.pumpWidget(h(pending: handed));
      await tester.pumpAndSettle();

      // Start recording *in the sheet* and then dismiss by the barrier, so the
      // route's own `endCapture` is the one that runs — Cancel would have gone
      // through the sheet's `_stopRecording` first, and `endCapture` is
      // idempotent, so that path leaves nothing to reject.
      await tester.tap(find.byKey(const ValueKey('region-record')));
      await tester.pumpAndSettle();
      fail = true;
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      expect(find.byType(RegionPickerSheet), findsOneWidget,
          reason: 'the queued ⌘S shape was dropped');
      expect(find.text('Handed over'), findsOneWidget);
    });

    testWidgets('the picker reports what a save cost, and hands it back',
        (tester) async {
      // The **third** caller of the onRestoreBindings seam, and the one that
      // had no coverage at all: the sheet's "Use it here" displaces exactly as
      // a row does, and `onSubmit` raises the same notice. Gating that notice
      // off left the whole suite green — i.e. this would have shipped as the
      // silent theft reported twice from real use, on the one path nothing
      // looked at.
      //
      // A live host, for the same reason as the two list cases: a fixed
      // `bindings:` prop makes the snapshot and a live read indistinguishable.
      var live = [
        ...kDefaultBindings,
        const Binding.unbound(Custom('r1')),
      ];
      List<Binding>? restored;
      await tester.pumpWidget(_host(SizedBox(
        width: 500,
        height: 900,
        child: StatefulBuilder(
          builder: (context, setInner) => ShortcutsScreen(
            bindings: live,
            regions: const [region],
            onRebound: (_) {},
            onRestoreBindings: (b) => restored = b,
            onRegionSaved: (d) => setInner(() => live = withRebind(
                live, Binding(Custom(d.region.id), d.keyCode, d.modifiers))),
            onRegionDeleted: (_) {},
          ),
        ),
      )));

      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();

      // ⌃⌥←, which Left half owns.
      await tester.tap(find.byKey(const ValueKey('region-record')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('region-take-anyway')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Left half lost ⌃⌥←'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notice-action')));
      await tester.pumpAndSettle();

      expect(restored, isNotNull);
      expect(
          restored!
              .firstWhere(
                  (b) => b.command == const BuiltIn(ShortcutCommand.leftHalf))
              .keyCode,
          123);
      // And the region gives back what it took — the half a live read fails.
      expect(
          restored!.firstWhere((b) => b.command == const Custom('r1')).isBound,
          isFalse);
    });

    testWidgets('the list is grouped, so regions read as a feature',
        (tester) async {
      // Custom regions were rows appended to the eleven built-ins and styled
      // identically, so the feature was invisible to anyone who had not already
      // found it.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      expect(find.text('BUILT-IN'), findsOneWidget);
      expect(find.text('YOUR REGIONS'), findsOneWidget);

      // Real headings, not just bold small text: without the flag a screen
      // reader's heading rotor cannot find either group, so the structure this
      // exists to create is visible only to people who can see it.
      for (final title in ['BUILT-IN', 'YOUR REGIONS']) {
        expect(
            tester
                .getSemantics(find.text(title))
                .getSemanticsData()
                .flagsCollection
                .isHeader,
            isTrue,
            reason: '$title is not a heading');
      }
      handle.dispose();
    });

    testWidgets('the regions hint teaches the grid route, and stays',
        (tester) async {
      // This hint used to vanish once a region existed — "explaining a
      // feature to somebody already using it". But the grid's own ⌘S caption
      // retires at the same moment (saveHint is regions.isEmpty), so after
      // the first region nothing anywhere said the grid can mint shortcuts.
      // "Add region…" is a labelled button and documents itself; ⌘S is
      // invisible unless told, so the hint now carries it and stays.
      await tester.pumpWidget(host(regions: const []));
      expect(find.textContaining('press ⌘S'), findsOneWidget);

      await tester.pumpWidget(host());
      expect(find.textContaining('press ⌘S'), findsOneWidget,
          reason: 'the ⌘S route is untaught anywhere else once a region exists');
    });

    testWidgets('a read-only pane with no regions has no regions group',
        (tester) async {
      // A header over an empty box would announce a feature this pane has no
      // way to reach.
      await tester.pumpWidget(_host(SizedBox(
        width: 500,
        height: 900,
        child: ShortcutsScreen(
          bindings: kDefaultBindings,
          onRebound: (_) {},
        ),
      )));
      expect(find.text('YOUR REGIONS'), findsNothing);
      expect(find.text('BUILT-IN'), findsOneWidget);
    });

    testWidgets('a saved region is pointed out, then left alone',
        (tester) async {
      // The sheet closing used to append a row to the foot of a twelve-row list
      // with nothing to mark it: did that work?
      //
      // Anchored to the row rather than to any tinted box on screen — the
      // dialog's own fading barrier is one of those, which is how the first
      // draft of this test passed while asserting nothing.
      Finder tinted() => find.ancestor(
            of: find.text('Left ⅔'),
            matching: find.byWidgetPredicate(
                (w) => w is ColoredBox && w.color.a > 0 && w.color.a < 1),
          );

      RegionDraft? saved;
      await tester
          .pumpWidget(host(regions: const [], onRegionSaved: (d) => saved = d));
      await tester.tap(find.byKey(const ValueKey('add-region')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('region-grid')));
      await tester.enterText(find.byType(TextField), 'Left ⅔');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-submit')));
      await tester.pump();
      expect(saved, isNotNull);

      // The row only exists once the pane is rebuilt with it, which the real
      // coordinator does after persisting — a frame or more after the save.
      await tester.pumpWidget(
          host(regions: [saved!.region], onRegionSaved: (_) {}));
      // Not settled: the tint is an animation, and pumpAndSettle would run it
      // to its end before looking.
      await tester.pump();
      expect(tinted(), findsOneWidget,
          reason: 'the new row was not pointed out');

      await tester.pump(const Duration(milliseconds: 1200));
      expect(tinted(), findsNothing,
          reason: 'a tint that never fades is a state, not a signal');
    });

    testWidgets('the add row opens the picker', (tester) async {
      await tester.pumpWidget(host(regions: const []));
      await tester.tap(find.byKey(const ValueKey('add-region')));
      await tester.pumpAndSettle();
      expect(find.byType(RegionPickerSheet), findsOneWidget);
      expect(find.text('New region'), findsOneWidget);
    });

    testWidgets('tapping a custom row opens the picker on that region',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      expect(find.byType(RegionPickerSheet), findsOneWidget);
      expect(find.text('Edit region'), findsOneWidget);
    });

    testWidgets('a custom row carries a tap action, not just a name',
        (tester) async {
      // Assert the ACTION. A control is not accessible because a screen reader
      // can say its name — this app shipped exactly that defect with fifteen
      // keyboard tests passing, because Tab and Space never go through the
      // semantics tree.
      await tester.pumpWidget(host());
      final node =
          tester.getSemantics(find.byKey(const ValueKey('edit-custom:r1')));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(node.label, contains('Left ⅔'));
    });

    testWidgets('the add row carries a tap action too', (tester) async {
      await tester.pumpWidget(host(regions: const []));
      final node = tester.getSemantics(find.byKey(const ValueKey('add-region')));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(node.label, 'Add region');
    });

    testWidgets('a custom row can be cleared like a built-in', (tester) async {
      Binding? rebound;
      await tester.pumpWidget(host(onRebound: (b) => rebound = b));

      await tester.tap(find.bySemanticsLabel('Remove Left ⅔ shortcut'),
          warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(rebound?.command, const Custom('r1'));
      expect(rebound?.isBound, isFalse);
    });

    testWidgets('deleting from the sheet reports the region id',
        (tester) async {
      String? deleted;
      await tester.pumpWidget(host(onRegionDeleted: (id) => deleted = id));

      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-delete')));
      await tester.pumpAndSettle();

      expect(deleted, 'r1');
      expect(find.byType(RegionPickerSheet), findsNothing);
    });

    testWidgets('submitting the sheet reports a draft and closes it',
        (tester) async {
      RegionDraft? saved;
      await tester.pumpWidget(host(onRegionSaved: (d) => saved = d));

      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-submit')));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.region.id, 'r1');
      expect(saved!.keyCode, 123, reason: 'the existing combo is carried in');
      expect(find.byType(RegionPickerSheet), findsNothing);
    });


    testWidgets('the recorder inside the dialog actually receives keys',
        (tester) async {
      // The sheet is presented with showDialog, which brings its own FocusScope
      // and its own Esc handling. Driving the real app, a chord pressed at the
      // "Press keys…" pill never registered and Esc closed the whole sheet --
      // both symptoms of the recording field not holding focus.
      RegionDraft? saved;
      await tester.pumpWidget(host(onRegionSaved: (d) => saved = d));
      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('region-record')));
      await tester.pumpAndSettle();
      expect(find.text('Press keys…'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.text('Press keys…'), findsNothing,
          reason: 'the chord should have been captured and recording ended');

      await tester.tap(find.byKey(const ValueKey('region-submit')));
      await tester.pumpAndSettle();
      expect(saved!.keyCode, 5, reason: 'Carbon code for G');
    });

    testWidgets('esc cancels the recording without closing the sheet',
        (tester) async {
      // One keystroke must not discard a shape the user just drew.
      await tester.pumpWidget(host());
      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-record')));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(RegionPickerSheet), findsOneWidget,
          reason: 'esc cancels the recording, not the whole sheet');
      expect(find.text('Press keys…'), findsNothing);
    });


    testWidgets('deleting offers an undo that brings the region back',
        (tester) async {
      // A drawn shape is minutes of attention and deletion is one click.
      String? deleted;
      RegionDraft? restored;
      await tester.pumpWidget(host(
        onRegionDeleted: (id) => deleted = id,
        onRegionSaved: (d) => restored = d,
      ));

      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-delete')));
      await tester.pumpAndSettle();

      expect(deleted, 'r1');
      expect(find.text('Left ⅔ deleted.'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(restored, isNotNull);
      expect(restored!.region, region, reason: 'the same shape, id and name');
      expect(restored!.keyCode, 123, reason: 'and the combo it had');
    });

    testWidgets('the deleted notice goes away even when nothing can animate',
        (tester) async {
      // Reported from the real app: "Full screen deleted." survived closing and
      // reopening Settings.
      //
      // Flutter arms a snackbar's dismissal timer inside ScaffoldMessenger's
      // *build*, and only once the 250 ms entrance animation has **completed**.
      // That animation needs frames, and this window is hidden with `orderOut`
      // while the engine stays alive — so the bar froze mid-entrance with no
      // timer ever created. Not a long timeout: none at all. The queue lives on
      // the app-level messenger, above `home`, so it was still there on the next
      // open.
      //
      // `TickerMode(enabled: false)` is precisely that state: the clock runs,
      // animations do not.
      // TickerMode is present in *both* pumps with only its flag changing, so
      // the MaterialApp below it keeps its element and the messenger — which
      // owns the snackbar queue — survives. Introducing the wrapper on the
      // second pump instead rebuilds the app and drops the queue, and the test
      // passes having proved nothing. (It did, until the mutation caught it.)
      Widget frame({required bool animating}) => TickerMode(
            enabled: animating,
            child: host(onRegionDeleted: (_) {}),
          );

      await tester.pumpWidget(frame(animating: true));

      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-delete')));
      // One frame only: the bar is inserted and *still animating in*, which is
      // the state that used to strand it. Settling here would complete the
      // entrance and arm Flutter's timer, and the test would prove nothing.
      await tester.pump();
      expect(find.text('Left ⅔ deleted.'), findsOneWidget);

      // The window is hidden: frames stop, so the entrance can never finish.
      await tester.pumpWidget(frame(animating: false));
      await tester.pump(const Duration(seconds: 11));
      await tester.pump();

      expect(find.text('Left ⅔ deleted.'), findsNothing,
          reason: 'a bar that cannot animate must still be taken down');
    });

    testWidgets('the picker does not outlive the pane either', (tester) async {
      // A route lives on the *root navigator* — above `home`, outside this
      // subtree, exactly as the snackbar queue is. Closing the settings window
      // therefore left the sheet pushed, and the next open showed a modal over
      // a window the user had only just asked for. Found by asking where else
      // the snackbar's "state above home" applies.
      //
      // Frozen from the close onward, and that is the point: a *popped*
      // TransitionRoute keeps its overlay entries until the reverse transition
      // finishes, so with `pumpAndSettle` supplying the frames a pop looks like
      // a removal. It is not — under `orderOut` the sheet would have stayed
      // fully rendered and faded out over the next open.
      await tester.pumpWidget(staged(host(), animating: true));
      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      expect(find.byType(RegionPickerSheet), findsOneWidget);

      // Close, then reopen, never settling the exit. TickerMode is in both
      // pumps with only its flag changing, so the MaterialApp below keeps its
      // element and the navigator holding the route survives.
      await tester.pumpWidget(
          staged(_host(const SizedBox.shrink()), animating: false));
      await tester.pump();
      await tester.pumpWidget(staged(host(), animating: false));
      await tester.pump();

      expect(find.byType(RegionPickerSheet), findsNothing,
          reason: 'a stale modal greeted the next open');
    });

    testWidgets('an undoable notice outlasts one that only reports',
        (tester) async {
      // Ten seconds, not six. Six is enough to *read* "Left ⅔ deleted."; it is
      // not enough to read it, look up at what changed, decide, and come back —
      // and the way back is the last thing that should expire under someone
      // still thinking about it. Measured from real use: driving this pane by
      // hand, the six-second Undo was missed twice.
      //
      // The two pumps below bracket the old duration, so a regression to six
      // fails here rather than merely reading differently.
      await tester.pumpWidget(host(onRegionDeleted: (_) {}));
      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-delete')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // entrance
      expect(find.text('Left ⅔ deleted.'), findsOneWidget);

      // Explicit pumps, because `pumpAndSettle` burns an unknown amount of
      // clock and the whole point is *when* it goes.
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('Left ⅔ deleted.'), findsOneWidget,
          reason: 'an undoable notice expired at the plain-message duration');

      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Left ⅔ deleted.'), findsNothing,
          reason: 'the stated duration was never honoured');
    });

    testWidgets('replacing a notice does not strand the replacement',
        (tester) async {
      // `clearSnackBars` hides the current bar by *animation* and queues the
      // new one behind it. With frames stopped mid-reverse the old bar stays at
      // the head of the queue, so the fallback timer removed *it* and
      // `removeCurrentSnackBar` synchronously promoted the replacement — which
      // by then had no timer of its own. The original bug wearing the
      // successor's face.
      // The host is 900 tall; the default 800x600 surface squeezes the Scaffold
      // so its snackbar lands *on top of* the custom rows and swallows the tap
      // that opens the second picker. Give it room.
      await tester.binding.setSurfaceSize(const Size(600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const second = CustomRegion(
        id: 'r2', name: 'Right ⅓', cols: 3, rows: 1, c0: 2, c1: 2, r0: 0, r1: 0,
      );
      Widget app({required bool animating}) => staged(
            host(regions: const [region, second], onRegionDeleted: (_) {}),
            animating: animating,
          );

      await tester.pumpWidget(app(animating: true));
      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Left ⅔ deleted.'), findsOneWidget);

      // The second notice replaces the first.
      await tester.tap(find.byKey(const ValueKey('edit-custom:r2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-delete')));
      await tester.pump();
      expect(find.text('Right ⅓ deleted.'), findsOneWidget);

      // Frames stop while the first notice would still be reversing.
      await tester.pumpWidget(app(animating: false));
      await tester.pump(const Duration(seconds: 11));
      await tester.pump();

      expect(find.text('Right ⅓ deleted.'), findsNothing,
          reason: 'the replacement was promoted and left with no timer');
      expect(find.text('Left ⅔ deleted.'), findsNothing);
    });

    testWidgets('a picker closing when the window does is not left frozen',
        (tester) async {
      // The gap the retained handle used to have. `push`'s future completes in
      // `Route.didPop` — the instant Cancel is pressed — while the 150 ms
      // reverse transition and the overlay removal happen afterwards. Releasing
      // ownership there left the sheet rendered and unowned, so a close landing
      // inside that window froze it on screen for the next open.
      await tester.pumpWidget(staged(host(), animating: true));
      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      expect(find.byType(RegionPickerSheet), findsOneWidget);

      // Cancel, then exactly one frame — mid-transition, sheet still rendered.
      await tester.tap(find.byKey(const ValueKey('region-cancel')));
      await tester.pump();
      expect(find.byType(RegionPickerSheet), findsOneWidget,
          reason: 'the reverse transition has not finished; this is the gap');

      await tester.pumpWidget(
          staged(_host(const SizedBox.shrink()), animating: false));
      await tester.pump();
      await tester.pumpWidget(staged(host(), animating: false));
      await tester.pump();

      expect(find.byType(RegionPickerSheet), findsNothing,
          reason: 'a half-dismissed sheet was frozen into the next open');
    });

    testWidgets('a pending region while a picker is open does not stack',
        (tester) async {
      // ⌘S can hand over a shape at any moment — the overlay is summonable with
      // Settings open. A second push stacked two modals *and* overwrote the one
      // retained route handle, so a later close tore down only the newer and the
      // first survived into the next open.
      const handed = CustomRegion(
        id: 'r9', name: 'Handed over',
        cols: 3, rows: 1, c0: 2, c1: 2, r0: 0, r1: 0,
      );
      await tester.pumpWidget(host());
      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      expect(find.byType(RegionPickerSheet), findsOneWidget);

      // ⌘S lands while the first sheet is up.
      await tester.pumpWidget(host(pendingRegion: handed));
      await tester.pumpAndSettle();
      expect(find.byType(RegionPickerSheet), findsOneWidget,
          reason: 'two sheets were stacked');
      expect(find.text('Edit region'), findsOneWidget,
          reason: 'the edit in progress was replaced');

      // A *second* handoff while the first is still queued. One slot silently
      // discarded everything but the last.
      const alsoHanded = CustomRegion(
        id: 'r8', name: 'Also handed over',
        cols: 4, rows: 1, c0: 0, c1: 0, r0: 0, r1: 0,
      );
      await tester.pumpWidget(host(pendingRegion: alsoHanded));
      await tester.pumpAndSettle();
      expect(find.byType(RegionPickerSheet), findsOneWidget);

      // Queued, not dropped, and in order. Asserted by *name*, not by the
      // sheet's title: "New region" would pass for either shape, or for a blank
      // one, which is what a lost handoff looks like.
      await tester.tap(find.byKey(const ValueKey('region-cancel')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Handed over'), findsOneWidget,
          reason: 'the first handed-over shape was lost');

      await tester.tap(find.byKey(const ValueKey('region-cancel')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Also handed over'), findsOneWidget,
          reason: 'the second handoff was overwritten by a single slot');
    });

    testWidgets('a transition finishing on the close frame is not finalized twice',
        (tester) async {
      // Flutter removes a route from `_history` and *then* defers
      // `Route.dispose` to a microtask, so `route.navigator != null` is not
      // "still in history". Completing Cancel's 150 ms exit on the very frame
      // that disposes the pane lands squarely in that window, and the teardown
      // called `finalizeRoute` on a route already out of history.
      // Driven through a toggle above the pane, so a *single* `pump(duration)`
      // both advances past the exit and rebuilds without the pane.
      // `pumpWidget(..., duration:)` splits those into two frames, and the
      // deferred disposal then drains in between — which is how the first
      // version of this test passed against the mutation.
      var showPane = true;
      late StateSetter setOuter;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (context, setState) {
          setOuter = setState;
          return showPane
              ? SizedBox(
                  width: 500,
                  height: 900,
                  child: ShortcutsScreen(
                    bindings: const [
                      ...kDefaultBindings,
                      Binding(Custom('r1'), 123, kControlOption | kShiftKey),
                    ],
                    regions: const [region],
                    onRebound: (_) {},
                    onRegionSaved: (_) {},
                  ),
                )
              : const SizedBox.shrink();
        },
      )));

      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-cancel')));

      showPane = false;
      setOuter(() {});
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'the teardown finalized a route already out of history');
    });

    testWidgets('a handoff during a slow restore does not overtake the queue',
        (tester) async {
      // `_pickerRouteRef` is released the moment the route is *gone*, which is
      // before the hotkey restore finishes. Using it as the admission gate let a
      // request arriving in that window open straight away, ahead of everything
      // already queued.
      final blocked = Completer<void>();
      const first = CustomRegion(
        id: 'r8', name: 'First handoff',
        cols: 3, rows: 1, c0: 0, c1: 0, r0: 0, r1: 0,
      );
      const second = CustomRegion(
        id: 'r9', name: 'Second handoff',
        cols: 3, rows: 1, c0: 1, c1: 1, r0: 0, r1: 0,
      );
      Widget app({CustomRegion? pending}) => host(
            pendingRegion: pending,
            onCaptureStart: () async {},
            onCaptureEnd: () => blocked.future,
          );

      await tester.pumpWidget(app());
      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-record')));
      await tester.pumpAndSettle();

      // Queued behind the open sheet.
      await tester.pumpWidget(app(pending: first));
      await tester.pumpAndSettle();

      // The sheet closes; the restore is still outstanding.
      await tester.tap(find.byKey(const ValueKey('region-cancel')));
      await tester.pumpAndSettle();

      // A second handoff arrives inside that window.
      await tester.pumpWidget(app(pending: second));
      await tester.pumpAndSettle();

      blocked.complete();
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'First handoff'), findsOneWidget,
          reason: 'the later handoff overtook the queue');
    });

    testWidgets('a slow hotkey restore does not strand a dead route handle',
        (tester) async {
      // Ownership used to end at `max(resumed, gone)`, because the restore was
      // awaited *before* `route.completed`. A restore slower than the 150 ms
      // exit therefore left the handle pointing at a route already out of the
      // navigator's history — and a close in that window sent the teardown to
      // `finalizeRoute` on it, which asserts in debug and indexes an invalid
      // history entry in release.
      final blocked = Completer<void>();
      await tester.pumpWidget(host(
        onCaptureStart: () async {},
        onCaptureEnd: () => blocked.future,
      ));
      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-record')));
      await tester.pumpAndSettle();

      // Cancel, and let the exit transition finish. The route is *gone*; the
      // restore is still outstanding.
      await tester.tap(find.byKey(const ValueKey('region-cancel')));
      await tester.pumpAndSettle();

      // Settings closes while the old code would still have held the handle.
      await tester.pumpWidget(_host(const SizedBox.shrink()));
      await tester.pumpAndSettle();

      blocked.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'the teardown reached a route that had already been disposed');
    });

    testWidgets('a frame-starved close still revives the hotkeys',
        (tester) async {
      // The resume used to sit behind `route.completed`, and Flutter defers a
      // route's disposal until its overlay subtree unmounts — another frame,
      // which is exactly what a window hidden with `orderOut` stops producing.
      // So a close mid-recording left every shortcut suspended until the next
      // open. The coordinator's own close backstop hid it; the guarantee this
      // route owns did not hold.
      final events = <String>[];
      await tester.pumpWidget(staged(
        host(
          onCaptureStart: () async => events.add('suspend'),
          onCaptureEnd: () async => events.add('resume'),
        ),
        animating: true,
      ));
      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-record')));
      await tester.pumpAndSettle();
      expect(events, ['suspend']);

      // Frames stop, then the window closes. Asserted on **this frame alone**:
      // the close frame runs dispose's callback, which removes the route and
      // completes `push`'s future. Allowing even one more pump lets the route's
      // deferred disposal land too, and the test stops being able to tell the
      // two orderings apart — which is exactly how it first passed against the
      // mutation.
      await tester.pumpWidget(
          staged(_host(const SizedBox.shrink()), animating: false));

      expect(events, ['suspend', 'resume'],
          reason: 'the hotkeys were left suspended by a frozen close');
    });

    testWidgets('closing the window under the picker revives the hotkeys',
        (tester) async {
      // Popping the route completes showDialog's future, so the suspend/resume
      // the route owns finishes its half. Without it the app is left with no
      // working shortcuts — the M5 defect this pane has now had twice.
      final events = <String>[];
      await tester.pumpWidget(host(
        onCaptureStart: () async => events.add('suspend'),
        onCaptureEnd: () async => events.add('resume'),
      ));
      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-record')));
      await tester.pumpAndSettle();
      expect(events, ['suspend']);

      await tester.pumpWidget(_host(const SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(events, ['suspend', 'resume']);
    });

    testWidgets('the deleted notice does not outlive the pane', (tester) async {
      // The other half of the same fix, and the reason it is two halves: the
      // timer is cancelled when this pane is disposed, so without an explicit
      // take-down here a bar raised moments before the window closed would stay
      // queued on the app-level messenger — above `home`, outside this subtree
      // — and be rendered again by the next Scaffold to mount.
      await tester.pumpWidget(host(onRegionDeleted: (_) {}));
      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Left ⅔ deleted.'), findsOneWidget);

      // Close, then reopen — the reported scenario, and the only shape that can
      // see this. Asserting straight after the close would pass for the wrong
      // reason: it removes the Scaffold that *renders* the bar while the entry
      // is still queued on the messenger, so `findsNothing` holds either way.
      // `_host` keeps the MaterialApp, and with it the messenger that owns the
      // queue.
      await tester.pumpWidget(_host(const SizedBox.shrink()));
      await tester.pump();
      await tester.pumpWidget(host(onRegionDeleted: (_) {}));
      await tester.pump();

      expect(find.text('Left ⅔ deleted.'), findsNothing,
          reason: 'a stale undo offer greeted the next open');
    });

    testWidgets('the picker is told which command a combo would displace',
        (tester) async {
      // The row path can only report a theft afterwards; the sheet warns first.
      await tester.pumpWidget(host(
        bindings: [
          ...kDefaultBindings,
          const Binding(Custom('r1'), 123, kControlOption | kShiftKey),
        ],
      ));
      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();

      final sheet =
          tester.widget<RegionPickerSheet>(find.byType(RegionPickerSheet));
      // ⌃⌥← is Left half's default.
      expect(sheet.conflictName!(123, kControlOption), 'Left half');
      // Its own combo is not a clash with itself.
      expect(sheet.conflictName!(123, kControlOption | kShiftKey), isNull);
      // A free chord is free.
      expect(sheet.conflictName!(17, kControlOption | kShiftKey), isNull);
    });


    testWidgets('a shape from ⌘S opens the picker pre-filled and is consumed',
        (tester) async {
      var consumed = 0;
      await tester.pumpWidget(host(
        regions: const [],
        pendingRegion: region,
        onPendingConsumed: () => consumed++,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(RegionPickerSheet), findsOneWidget);
      expect(find.text('Left ⅔'), findsOneWidget);
      expect(find.text('New region'), findsOneWidget,
          reason: 'it has no row yet, so it is an add rather than an edit');
      expect(find.byKey(const ValueKey('region-delete')), findsNothing);
      expect(consumed, 1,
          reason: 'consumed before the sheet shows, so a rebuild cannot '
              'open a second one behind it');
    });


    testWidgets('cancelling mid-recording still revives the global hotkeys',
        (tester) async {
      // Recording suspends every hotkey. Cancel, Save, Delete, Esc and a
      // barrier tap all pop the route without going through _stopRecording, so
      // this left the app with NO working shortcuts at all. The settings window
      // had the same defect fixed once already (M5).
      var started = 0;
      var ended = 0;
      await tester.pumpWidget(host(
        onCaptureStart: () async => started++,
        onCaptureEnd: () async => ended++,
      ));

      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-record')));
      await tester.pumpAndSettle();
      expect(started, 1);

      await tester.tap(find.byKey(const ValueKey('region-cancel')));
      await tester.pumpAndSettle();

      expect(ended, 1, reason: 'the route owns the resume, not the sheet');
    });

    testWidgets('esc mid-recording revives them too', (tester) async {
      var ended = 0;
      await tester.pumpWidget(host(
        onCaptureStart: () async {},
        onCaptureEnd: () async => ended++,
      ));

      await tester.tap(find.byKey(const ValueKey('edit-custom:r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('region-record')));
      await tester.pumpAndSettle();

      // Esc reaches the recorder first, which stops it; a second Esc pops the
      // route. Either way the count must land on exactly one.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(ended, 1, reason: 'resumed exactly once, never twice');
    });

    testWidgets('the glyph opens the editor, as the name does', (tester) async {
      // It used to inherit the row's action and start *recording* instead.
      await tester.pumpWidget(host());
      final edit = find.byKey(const ValueKey('edit-custom:r1'));
      expect(
        find.descendant(of: edit, matching: find.byType(RegionGlyph)),
        findsOneWidget,
      );
    });

    /// Open the picker and report the transition the route declared.
    ///
    /// One case per test rather than both in one: `pumpWidget` with the same
    /// widget type reuses the element tree, so the `Navigator` keeps its route
    /// stack and the *first* sheet is still up when the second case taps — the
    /// tap then lands on that sheet's own Material and the failure reads as a
    /// layout problem.
    Future<Duration> pickerTransition(
      WidgetTester tester, {
      required bool reduceMotion,
    }) async {
      await tester.pumpWidget(MaterialApp(
        theme: macTheme(Brightness.light),
        // `copyWith`, never a fresh `MediaQueryData`: a bare one carries
        // `Size.zero`, which lays the pane out at nothing and leaves every row
        // findable but unhittable — the same fold problem this group's `setUp`
        // exists to avoid, arriving by a different door.
        home: Builder(
          builder: (context) => MediaQuery(
            data:
                MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
            child: SizedBox(
              width: 500,
              height: 900,
              child: ShortcutsScreen(
                bindings: kDefaultBindings,
                regions: const [region],
                onRebound: (_) {},
                onRegionSaved: (_) {},
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('add-region')));
      await tester.pumpAndSettle();
      // Read the route rather than timing frames: the claim is about the
      // duration the sheet *declares*, and a frame-counting version would be
      // measuring the test harness's clock instead.
      return ModalRoute.of(tester.element(find.byType(RegionPickerSheet)))!
          .transitionDuration;
    }

    testWidgets('the picker opens faster than the Material default',
        (tester) async {
      // Nothing loads behind this sheet — no persistence, no hotkey call, no
      // native call on the way in — so the entire gap between *Add region…* and
      // a usable grid *is* the transition. Material's 150 ms read as weight the
      // app does not have; 100 ms is the overlay's own entrance.
      expect(await pickerTransition(tester, reduceMotion: false),
          const Duration(milliseconds: 100));
    });

    testWidgets('the picker does not animate under reduced motion',
        (tester) async {
      expect(await pickerTransition(tester, reduceMotion: true), Duration.zero,
          reason: 'reduced motion must reach the sheet, not only the theme');
    });

    testWidgets('hovering a region row shows that its name is editable',
        (tester) async {
      // A custom row has two actions — its glyph and name edit the region,
      // everything right of them records a shortcut — and nothing said so. The
      // hint appears on hover, which is also when the clear button appears, so
      // the row reveals both of its halves at the same moment.
      await tester.pumpWidget(host());
      final edit = find.byKey(const ValueKey('edit-custom:r1'));
      final hint = find.descendant(of: edit, matching: find.byType(Opacity));

      expect(tester.widget<Opacity>(hint).opacity, 0,
          reason: 'a row nobody is pointing at should be quiet');
      final restingSize = tester.getSize(edit);

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(edit));
      await tester.pumpAndSettle();

      expect(tester.widget<Opacity>(hint).opacity, 1);
      // Faded, never inserted. This pane's measured height sizes the *window*,
      // so a row whose metrics move under the pointer would resize it — the
      // twitch the fixed-height footer was introduced to stop, on a control the
      // user is by definition pointing at.
      expect(tester.getSize(edit), restingSize);
    });

    testWidgets('the add row is hidden when regions are not editable',
        (tester) async {
      await tester.pumpWidget(_host(SizedBox(
        width: 500,
        height: 900,
        child: ShortcutsScreen(
          bindings: kDefaultBindings,
          regions: const [region],
          onRebound: (_) {},
        ),
      )));
      expect(find.byKey(const ValueKey('add-region')), findsNothing);
      expect(find.text('Left ⅔'), findsOneWidget,
          reason: 'the row still shows; only editing is withheld');
    });
  });
}
