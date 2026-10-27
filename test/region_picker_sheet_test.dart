import 'dart:async';
import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/core/key_chord.dart';
import 'package:orthant/l10n/strings.dart';
import 'package:orthant/settings/keycap.dart';
import 'package:orthant/settings/mac_control.dart';
import 'package:orthant/settings/platform_theme.dart';
import 'package:orthant/settings/recording_field.dart';
import 'package:orthant/settings/region_picker_sheet.dart';
import 'package:orthant/shortcuts/custom_region.dart';

import 'support/carbon_terms.dart';
import 'support/localized_host.dart';
import 'support/locales.dart';
import 'support/no_english.dart';

const _leftTwoThirds = CustomRegion(
  id: 'r1',
  name: 'Left ⅔',
  cols: 3,
  rows: 1,
  c0: 0,
  c1: 1,
  r0: 0,
  r1: 0,
);

Widget _host(Widget child) => MaterialApp(
      theme: orthantTheme(Brightness.light),
      home: Scaffold(body: SizedBox(width: 600, height: 700, child: child)),
    );

/// Drag from the centre of cell (c0,r0) to the centre of cell (c1,r1).
Future<void> _dragCells(
  WidgetTester tester, {
  required int cols,
  required int rows,
  required int c0,
  required int r0,
  required int c1,
  required int r1,
}) async {
  final grid = tester.getRect(find.byKey(const ValueKey('region-grid')));
  final cw = grid.width / cols;
  final ch = grid.height / rows;
  Offset centre(int c, int r) =>
      grid.topLeft + Offset(cw * (c + 0.5), ch * (r + 0.5));
  final gesture = await tester.startGesture(centre(c0, r0));
  await tester.pump();
  await gesture.moveTo(centre(c1, r1));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a drag across cells produces the block drawn', (tester) async {
    RegionDraft? submitted;
    await tester.pumpWidget(_host(RegionPickerSheet(
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => submitted = d,
      onCancel: () {},
    )));

    // Columns 0..3 of 6, all six rows — left two-thirds.
    await _dragCells(tester, cols: 6, rows: 6, c0: 0, r0: 0, c1: 3, r1: 5);
    await tester.tap(find.byKey(const ValueKey('region-submit')));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.region.cols, 6);
    expect(submitted!.region.rows, 6);
    expect(submitted!.region.c0, 0);
    expect(submitted!.region.c1, 3);
    expect(submitted!.region.r0, 0);
    expect(submitted!.region.r1, 5);
  });

  testWidgets('a mouse click after a drag collapses the range to one cell',
      (tester) async {
    RegionDraft? submitted;
    await tester.pumpWidget(_host(RegionPickerSheet(
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => submitted = d,
      onCancel: () {},
    )));

    final grid = tester.getRect(find.byKey(const ValueKey('region-grid')));
    final cellWidth = grid.width / 6;
    final cellHeight = grid.height / 6;
    Offset centre(int col, int row) => grid.topLeft +
        Offset(cellWidth * (col + 0.5), cellHeight * (row + 0.5));

    // One persistent mouse pointer, matching macOS: drag, release, then click
    // again without removing and re-adding the device between gestures.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: centre(0, 0));
    addTearDown(mouse.removePointer);
    await mouse.down(centre(0, 0));
    await tester.pump();
    await mouse.moveTo(centre(3, 5));
    await tester.pump();
    await mouse.up();
    await tester.pump();

    // The second cell is deliberately inside the old range. A picker that only
    // reacts when the new press falls outside the highlight still fails the
    // ordinary "change my mind within this range" interaction.
    await mouse.down(centre(2, 2));
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('region-submit')));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.region.c0, 2);
    expect(submitted!.region.c1, 2);
    expect(submitted!.region.r0, 2);
    expect(submitted!.region.r1, 2);
  });

  testWidgets('a pointer move inside one cell rebuilds nothing',
      (tester) async {
    // `onPanUpdate` fires on **every pointer move** — well over a hundred a
    // second on a trackpad — while the cell under the pointer changes a handful
    // of times in a whole drag. Unguarded, every one of those moves ran
    // `setState` and rebuilt the sheet: the grid, its painter, the name field
    // and the buttons, for a selection that had not changed.
    //
    // Asserted on the painter's **identity**, because that is what actually
    // differs. Counting writes to the name controller does not: assigning the
    // same text pushes an equal `TextEditingValue`, and `ValueNotifier` drops
    // those, so the redundant work is invisible from there. (It was — this test
    // passed against both mutations before it was rewritten.)
    await tester.pumpWidget(_host(RegionPickerSheet(
      gridCols: 6,
      gridRows: 6,
      onSubmit: (_) {},
      onCancel: () {},
    )));

    CustomPaint painter() => tester.widget<CustomPaint>(find.descendant(
          of: find.byKey(const ValueKey('region-grid')),
          matching: find.byType(CustomPaint),
        ));

    final grid = tester.getRect(find.byKey(const ValueKey('region-grid')));
    final cw = grid.width / 6;
    final ch = grid.height / 6;
    Offset centre(int c, int r) =>
        grid.topLeft + Offset(cw * (c + 0.5), ch * (r + 0.5));

    final gesture = await tester.startGesture(centre(0, 0));
    await tester.pump();
    final atPress = painter();

    // Three moves that all stay inside cell (0,0).
    for (final dx in [-2.0, 1.0, 3.0]) {
      await gesture.moveTo(centre(0, 0) + Offset(dx, 0));
      await tester.pump();
    }
    expect(identical(painter(), atPress), isTrue,
        reason: 'the sheet rebuilt for a move that changed no cell');

    // And it still redraws the moment the cell genuinely changes.
    await gesture.moveTo(centre(3, 0));
    await tester.pump();
    expect(identical(painter(), atPress), isFalse);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a backwards drag normalises, as blockFrom does', (tester) async {
    RegionDraft? submitted;
    await tester.pumpWidget(_host(RegionPickerSheet(
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => submitted = d,
      onCancel: () {},
    )));

    await _dragCells(tester, cols: 6, rows: 6, c0: 3, r0: 5, c1: 0, r1: 0);
    await tester.tap(find.byKey(const ValueKey('region-submit')));
    await tester.pumpAndSettle();

    expect(submitted!.region.c0, 0);
    expect(submitted!.region.c1, 3);
  });

  group('which pointer draws', () {
    // The press anchors for any button and any pointer, as it did before the
    // grid learned to scroll. The drawing that follows is the pan's old rule:
    // the pressing pointer, with its primary button or contact.
    Offset centre(WidgetTester tester, int c, int r) {
      final grid = tester.getRect(find.byKey(const ValueKey('region-grid')));
      return grid.topLeft +
          Offset(grid.width / 6 * (c + 0.5), grid.height / 6 * (r + 0.5));
    }

    testWidgets('a right-button drag selects the pressed cell and no more',
        (tester) async {
      RegionDraft? submitted;
      await tester.pumpWidget(_host(RegionPickerSheet(
        gridCols: 6,
        gridRows: 6,
        onSubmit: (d) => submitted = d,
        onCancel: () {},
      )));

      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.addPointer(location: centre(tester, 1, 1));
      addTearDown(mouse.removePointer);
      await mouse.down(centre(tester, 1, 1));
      await tester.pump();
      await mouse.moveTo(centre(tester, 3, 1));
      await tester.pump();
      await mouse.moveTo(centre(tester, 4, 4));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('region-submit')));
      await tester.pumpAndSettle();

      expect(submitted, isNotNull);
      expect(submitted!.region.c0, 1);
      expect(submitted!.region.c1, 1);
      expect(submitted!.region.r0, 1);
      expect(submitted!.region.r1, 1);
    });

    testWidgets('only the pointer that pressed last draws', (tester) async {
      RegionDraft? submitted;
      await tester.pumpWidget(_host(RegionPickerSheet(
        gridCols: 6,
        gridRows: 6,
        onSubmit: (d) => submitted = d,
        onCancel: () {},
      )));

      // The sheet stays open on submit here, so the selection can be read
      // while both fingers are still down.
      Future<RegionDraft> selection() async {
        submitted = null;
        await tester.tap(find.byKey(const ValueKey('region-submit')));
        await tester.pump();
        return submitted!;
      }

      final first = await tester.startGesture(centre(tester, 1, 1));
      await tester.pump();
      final second = await tester.startGesture(centre(tester, 4, 4));
      await tester.pump();

      // The second press re-anchors, as any press does. The first finger,
      // moving on, no longer draws.
      await first.moveTo(centre(tester, 2, 3));
      await tester.pump();
      var s = (await selection()).region;
      expect([s.c0, s.c1, s.r0, s.r1], [4, 4, 4, 4]);

      // The second finger is the one that pressed last: it draws.
      await second.moveTo(centre(tester, 2, 3));
      await tester.pump();
      s = (await selection()).region;
      expect([s.c0, s.c1, s.r0, s.r1], [2, 4, 3, 4]);

      await first.up();
      await second.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a primary-button mouse drag still draws', (tester) async {
      RegionDraft? submitted;
      await tester.pumpWidget(_host(RegionPickerSheet(
        gridCols: 6,
        gridRows: 6,
        onSubmit: (d) => submitted = d,
        onCancel: () {},
      )));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: centre(tester, 1, 2));
      addTearDown(mouse.removePointer);
      await mouse.down(centre(tester, 1, 2));
      await tester.pump();
      await mouse.moveTo(centre(tester, 3, 2));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('region-submit')));
      await tester.pumpAndSettle();

      expect(submitted, isNotNull);
      expect(submitted!.region.c0, 1);
      expect(submitted!.region.c1, 3);
      expect(submitted!.region.r0, 2);
      expect(submitted!.region.r1, 2);
    });
  });

  testWidgets('the name fills in from the shape drawn', (tester) async {
    await tester.pumpWidget(_host(RegionPickerSheet(
      gridCols: 6,
      gridRows: 6,
      onSubmit: (_) {},
      onCancel: () {},
    )));

    await _dragCells(tester, cols: 6, rows: 6, c0: 0, r0: 0, c1: 3, r1: 5);
    expect(find.text('Left ⅔'), findsOneWidget);
  });

  testWidgets('a typed name is not overwritten by a later drag',
      (tester) async {
    RegionDraft? submitted;
    await tester.pumpWidget(_host(RegionPickerSheet(
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => submitted = d,
      onCancel: () {},
    )));

    await _dragCells(tester, cols: 6, rows: 6, c0: 0, r0: 0, c1: 3, r1: 5);
    await tester.enterText(find.byType(TextField), 'Reading pane');
    await _dragCells(tester, cols: 6, rows: 6, c0: 0, r0: 0, c1: 2, r1: 5);
    await tester.tap(find.byKey(const ValueKey('region-submit')));
    await tester.pumpAndSettle();

    expect(submitted!.region.name, 'Reading pane');
  });

  testWidgets('submit is disabled until a shape exists', (tester) async {
    await tester.pumpWidget(_host(RegionPickerSheet(
      gridCols: 6,
      gridRows: 6,
      onSubmit: (_) {},
      onCancel: () {},
    )));

    // Assert the flag, not the colour: an enabled-looking disabled control is
    // exactly the defect this app shipped with launch-at-login.
    final before =
        tester.getSemantics(find.byKey(const ValueKey('region-submit')));
    expect(before.flagsCollection.isEnabled, Tristate.isFalse);

    await _dragCells(tester, cols: 6, rows: 6, c0: 0, r0: 0, c1: 3, r1: 5);

    final after =
        tester.getSemantics(find.byKey(const ValueKey('region-submit')));
    expect(after.flagsCollection.isEnabled, Tristate.isTrue);
    expect(after.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  });

  testWidgets('arrows move the selection and shift extends it', (tester) async {
    RegionDraft? submitted;
    await tester.pumpWidget(_host(RegionPickerSheet(
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => submitted = d,
      onCancel: () {},
    )));

    // Tap once to take focus; that also selects cell (0,0).
    await tester.tapAt(
        tester.getRect(find.byKey(const ValueKey('region-grid'))).topLeft +
            const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('region-submit')));
    await tester.pumpAndSettle();

    expect(submitted!.region.c0, 0);
    expect(submitted!.region.c1, 1);
  });


  testWidgets('an existing region opens with its shape, name and combo',
      (tester) async {
    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: _leftTwoThirds,
      initialChord: carbon(123, kControlOption | kShiftKey),
      gridCols: 6,
      gridRows: 6,
      onSubmit: (_) {},
      onCancel: () {},
      onDelete: () {},
    )));

    expect(find.text('Left ⅔'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    // Its denominators are no longer shown — there is no control for them.
    // That they are *used* is covered by 'editing keeps the region own
    // denominators, not the live grid'.
  });

  testWidgets('editing keeps the region id', (tester) async {
    RegionDraft? submitted;
    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: _leftTwoThirds,
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => submitted = d,
      onCancel: () {},
      onDelete: () {},
    )));

    await tester.enterText(find.byType(TextField), 'Reading pane');
    await tester.tap(find.byKey(const ValueKey('region-submit')));
    await tester.pumpAndSettle();

    expect(submitted!.region.id, 'r1',
        reason: 'a rename must not make a different region');
    expect(submitted!.region.name, 'Reading pane');
  });

  testWidgets('delete is offered only when editing', (tester) async {
    var deleted = false;
    await tester.pumpWidget(_host(RegionPickerSheet(
      gridCols: 6,
      gridRows: 6,
      onSubmit: (_) {},
      onCancel: () {},
    )));
    expect(find.byKey(const ValueKey('region-delete')), findsNothing);

    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: _leftTwoThirds,
      gridCols: 6,
      gridRows: 6,
      onSubmit: (_) {},
      onCancel: () {},
      onDelete: () => deleted = true,
    )));
    await tester.tap(find.byKey(const ValueKey('region-delete')));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });

  testWidgets('recording a combo suspends the global hotkeys', (tester) async {
    // Without this the combination being recorded also fires, so a window
    // jumps mid-capture.
    var started = 0;
    var ended = 0;
    RegionDraft? submitted;
    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: _leftTwoThirds,
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => submitted = d,
      onCancel: () {},
      onCaptureStart: () async => started++,
      onCaptureEnd: () async => ended++,
    )));

    await tester.tap(find.byKey(const ValueKey('region-record')));
    await tester.pumpAndSettle();
    expect(started, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(ended, 1);

    await tester.tap(find.byKey(const ValueKey('region-submit')));
    await tester.pumpAndSettle();
    expect(submitted!.keyCode, 17, reason: 'Carbon code for T');
    expect(submitted!.modifiers & kControlOption, kControlOption);
  });

  testWidgets('a Save landing during a slow resume carries the new combination',
      (tester) async {
    // The combination used to be assigned *after* `onCaptureEnd` was awaited,
    // so for the length of a hotkey resume the sheet was no longer recording
    // and still held the old shortcut — with Save live. Saving in that window
    // persisted the combination the user had just replaced, and said nothing.
    final resume = Completer<void>();
    RegionDraft? submitted;
    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: _leftTwoThirds,
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => submitted = d,
      onCancel: () {},
      initialChord: carbon(8, kControlOption), // ⌃⌥C, the combination being replaced
      onCaptureStart: () async {},
      onCaptureEnd: () => resume.future,
    )));

    await tester.tap(find.byKey(const ValueKey('region-record')));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    // The resume has not answered, so the sheet is mid-transition — exactly
    // where the defect lived.
    expect(resume.isCompleted, isFalse);
    await tester.tap(find.byKey(const ValueKey('region-submit')));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull,
        reason: 'Save is live here, so it must save the right thing');
    expect(submitted!.keyCode, 17, reason: 'Carbon code for T, not C');
    resume.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a resume that rejects does not take the combination with it',
      (tester) async {
    // `RecordingField` calls this from a synchronous key handler, so nothing
    // catches the future it returns: a rejected resume both dropped the new
    // combination and surfaced as an uncaught async error. The hotkeys are the
    // coordinator's to recover on its next apply; what the user just typed is
    // not recoverable at all.
    RegionDraft? submitted;
    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: _leftTwoThirds,
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => submitted = d,
      onCancel: () {},
      onCaptureStart: () async {},
      onCaptureEnd: () async => throw StateError('channel rejected'),
    )));

    await tester.tap(find.byKey(const ValueKey('region-record')));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'a failed resume must not escape a synchronous key handler');
    await tester.tap(find.byKey(const ValueKey('region-submit')));
    await tester.pumpAndSettle();
    expect(submitted!.keyCode, 17);
  });

  testWidgets('Save is refused while a combination is being recorded',
      (tester) async {
    // Return has always refused mid-recording — the shortcut on screen is not
    // the one being typed. The button did not, so the mouse and the keyboard
    // disagreed in the pane whose subject is the keyboard.
    RegionDraft? submitted;
    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: _leftTwoThirds,
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => submitted = d,
      onCancel: () {},
      onCaptureStart: () async {},
      onCaptureEnd: () async {},
    )));

    await tester.tap(find.byKey(const ValueKey('region-record')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('region-submit')));
    await tester.pumpAndSettle();

    expect(submitted, isNull);
    expect(find.byType(RecordingField), findsOneWidget,
        reason: 'and the recording is still running, not silently cancelled');
  });

  testWidgets('cancel reports without submitting', (tester) async {
    var cancelled = false;
    RegionDraft? submitted;
    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: _leftTwoThirds,
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => submitted = d,
      onCancel: () => cancelled = true,
    )));

    await tester.tap(find.byKey(const ValueKey('region-cancel')));
    await tester.pumpAndSettle();

    expect(cancelled, isTrue);
    expect(submitted, isNull);
  });

  testWidgets('reshaping re-suggests a name that was never authored',
      (tester) async {
    // A region called "Left ⅔" that then places a third is a row lying about
    // what it does. The stored name still equalling the suggestion is what
    // marks it as generated rather than chosen.
    RegionDraft? submitted;
    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: _leftTwoThirds,
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => submitted = d,
      onCancel: () {},
    )));

    // 3x1, columns 0..0 — one third.
    // A 3x1 region is now edited on 6x6 (refineForEditing), so a third is
    // columns 0..1 of six rather than column 0 of three.
    await _dragCells(tester, cols: 6, rows: 6, c0: 0, r0: 0, c1: 1, r1: 5);
    await tester.tap(find.byKey(const ValueKey('region-submit')));
    await tester.pumpAndSettle();

    expect(submitted!.region.name, 'Left ⅓');
  });

  testWidgets('reshaping preserves a name the user typed', (tester) async {
    RegionDraft? submitted;
    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: _leftTwoThirds.copyWith(name: 'Reading pane'),
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => submitted = d,
      onCancel: () {},
    )));

    await _dragCells(tester, cols: 6, rows: 6, c0: 0, r0: 0, c1: 1, r1: 5);
    await tester.tap(find.byKey(const ValueKey('region-submit')));
    await tester.pumpAndSettle();

    expect(submitted!.region.name, 'Reading pane');
  });

  testWidgets('a taken combo is called out before it is committed',
      (tester) async {
    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: _leftTwoThirds,
      initialChord: carbon(123, kControlOption),
      gridCols: 6,
      gridRows: 6,
      onSubmit: (_) {},
      onCancel: () {},
      conflictName: (c) =>
          (c.keyCode == 123 && c.carbonMask == kControlOption) ? 'Left half' : null,
    )));

    expect(find.textContaining('Left half already uses this combination'),
        findsOneWidget);

    // Held, not merely announced: Save is disabled until the user says to take
    // it. The sheet used to warn and then take it silently, leaving the other
    // command unset with no notice anyone would still be reading.
    final save = tester.widget<MacControl>(
        find.byKey(const ValueKey('region-submit')));
    expect(save.onPressed, isNull,
        reason: 'the sheet would still have taken a combo in use');
  });

  testWidgets('a taken combo can be taken, once that is asked for',
      (tester) async {
    // Refusing outright is the worse of the two wrong answers *here*: this
    // sheet is modal over the very list the user would have to go and clear,
    // so it is a dead end that covers its own way out.
    RegionDraft? saved;
    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: _leftTwoThirds,
      initialChord: carbon(123, kControlOption),
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => saved = d,
      onCancel: () {},
      conflictName: (c) =>
          (c.keyCode == 123 && c.carbonMask == kControlOption) ? 'Left half' : null,
    )));

    await tester.tap(find.byKey(const ValueKey('region-take-anyway')));
    await tester.pumpAndSettle();

    // The warning stays — it is still true — but now says what will happen.
    expect(find.textContaining('Left half will lose this combination'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('region-take-anyway')), findsNothing,
        reason: 'an accepted collision cannot be accepted twice');

    await tester.tap(find.byKey(const ValueKey('region-submit')));
    await tester.pumpAndSettle();
    expect(saved?.keyCode, 123);
    expect(saved?.modifiers, kControlOption);
  });

  testWidgets('accepting one collision does not cover the next',
      (tester) async {
    // A new combination is a new question. Carrying the acceptance over would
    // displace a command the user was never asked about — they said "use it
    // here" of Left half's chord and would silently take Right half's.
    //
    // The list side of this has its own test ("is not confirmed by a
    // *different* occupied combination"); that hole survived a first mutation
    // round there, which is why this one exists.
    RegionDraft? saved;
    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: _leftTwoThirds,
      initialChord: carbon(123, kControlOption),
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => saved = d,
      onCancel: () {},
      conflictName: (c) => switch (c.keyCode) {
        123 when c.carbonMask == kControlOption => 'Left half',
        124 when c.carbonMask == kControlOption => 'Right half',
        _ => null,
      },
    )));

    await tester.tap(find.byKey(const ValueKey('region-take-anyway')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<MacControl>(find.byKey(const ValueKey('region-submit')))
            .onPressed,
        isNotNull);

    // Now record a *different* occupied combination: ⌃⌥→, Right half's.
    await tester.tap(find.byKey(const ValueKey('region-record')));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.textContaining('Right half already uses this combination'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('region-take-anyway')), findsOneWidget,
        reason: 'a fresh collision has to be asked about afresh');
    expect(
        tester
            .widget<MacControl>(find.byKey(const ValueKey('region-submit')))
            .onPressed,
        isNull,
        reason: 'Right half would be displaced without ever being named');
    expect(saved, isNull);
  });

  testWidgets('an unset shortcut is a button, not a status', (tester) async {
    // The list learned this twice over, from real use: on a field whose entire
    // purpose is to be clicked, plain grey status text reads as a verdict —
    // reported as "I still can't set it". This sheet had the same field still
    // wearing the older face, so the two said the same thing two ways.
    await tester.pumpWidget(_host(RegionPickerSheet(
      gridCols: 6,
      gridRows: 6,
      onSubmit: (_) {},
      onCancel: () {},
    )));

    expect(find.byType(SetShortcutPill), findsOneWidget);
    expect(find.text('Click to record'), findsOneWidget);

    // And it is not drawn in the *disabled* weight, which is the same mistake
    // one layer down: tertiary is what macOS greys an unavailable control with
    // — 2.4:1 against this pane — so an invitation wearing it still reads as a
    // verdict, however button-shaped the box around it is.
    final t = PlatformTokens.macLight;
    final label = tester.widget<Text>(find.text('Click to record'));
    expect(label.style!.color, isNot(t.labelTertiary));
    expect(label.style!.color, t.labelSecondary);
  });

  testWidgets('a free combo says nothing', (tester) async {
    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: _leftTwoThirds,
      initialChord: carbon(123, kControlOption | kShiftKey),
      gridCols: 6,
      gridRows: 6,
      onSubmit: (_) {},
      onCancel: () {},
      conflictName: (_) => null,
    )));
    expect(find.textContaining('uses this combination'), findsNothing);
  });


  testWidgets('return submits, but not while recording', (tester) async {
    // ⌃⌥↩ is Maximize's default, so Return must stay recordable.
    var submits = 0;
    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: _leftTwoThirds,
      gridCols: 6,
      gridRows: 6,
      onSubmit: (_) => submits++,
      onCancel: () {},
    )));

    await tester.tap(find.byKey(const ValueKey('region-record')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(submits, 0, reason: 'Return belongs to the recorder while it listens');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(submits, 1);
  });

  testWidgets('return does nothing when there is nothing to submit',
      (tester) async {
    var submits = 0;
    await tester.pumpWidget(_host(RegionPickerSheet(
      gridCols: 6, gridRows: 6, onSubmit: (_) => submits++, onCancel: () {},
    )));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(submits, 0);
  });

  testWidgets('the region keeps its own denominators, with no way to change them',
      (tester) async {
    // One grid concept, set in one place. A second pair of Columns/Rows
    // steppers here read as a copy of the General pane; the region still
    // *stores* its denominators, which is what makes a saved shape survive a
    // later grid change.
    await tester.pumpWidget(_host(RegionPickerSheet(
      gridCols: 4,
      gridRows: 4,
      onSubmit: (_) {},
      onCancel: () {},
    )));
    expect(find.text('Columns'), findsNothing);
    expect(find.text('Rows'), findsNothing);
  });

  testWidgets('a new region is drawn on the live grid', (tester) async {
    RegionDraft? submitted;
    await tester.pumpWidget(_host(RegionPickerSheet(
      gridCols: 4,
      gridRows: 4,
      onSubmit: (d) => submitted = d,
      onCancel: () {},
    )));

    await _dragCells(tester, cols: 4, rows: 4, c0: 0, r0: 0, c1: 1, r1: 3);
    await tester.tap(find.byKey(const ValueKey('region-submit')));
    await tester.pumpAndSettle();

    expect(submitted!.region.cols, 4);
    expect(submitted!.region.rows, 4);
    expect(submitted!.region.name, 'Left ½');
  });

  testWidgets('editing keeps the region own denominators, not the live grid',
      (tester) async {
    // Reinterpreting a 3x1 region on a 6x6 grid would change its shape under
    // the user.
    RegionDraft? submitted;
    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: _leftTwoThirds, // 3 x 1
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => submitted = d,
      onCancel: () {},
    )));

    await tester.tap(find.byKey(const ValueKey('region-submit')));
    await tester.pumpAndSettle();

    expect(submitted!.region.cols, 3);
    expect(submitted!.region.rows, 1);
  });

  testWidgets('a coarse region is edited on a finer grid, unmoved',
      (tester) async {
    // 3 x 1 has one row, so it cannot be reshaped vertically at all. Opened
    // against a 6 x 6 live grid it is edited as 6 x 6 — the same rectangle,
    // now with rows to work in.
    RegionDraft? submitted;
    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: _leftTwoThirds.copyWith(cols: 3, rows: 1, c0: 0, c1: 1, r0: 0, r1: 0),
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => submitted = d,
      onCancel: () {},
    )));

    // Reshape to the top half of that two-thirds — impossible on one row.
    await _dragCells(tester, cols: 6, rows: 6, c0: 0, r0: 0, c1: 3, r1: 2);
    await tester.tap(find.byKey(const ValueKey('region-submit')));
    await tester.pumpAndSettle();

    final r = submitted!.region;
    // Stored on the grid it was edited on. That is the grid its row glyph
    // paints, and it no longer decides *where the window goes* —
    // `gapForPlacement` measures the block, so 6 x 6 and its reduction to
    // 3 x 2 place identically.
    expect(r.cols, 6);
    expect(r.rows, 6);
    expect(r.r1, 2, reason: 'a vertical reshape is now possible');
    // And the numbers mean what they should: the top half of the left
    // two-thirds. Asserting the rectangle rather than only the indices is what
    // makes this test notice a refinement that reshapes *and* moves.
    expect(
      gridBlock(const WinRect(0, 0, 1200, 900),
          cols: r.cols, rows: r.rows, c0: r.c0, c1: r.c1, r0: r.r0, r1: r.r1),
      const WinRect(0, 0, 800, 450),
    );
  });

  testWidgets('renaming leaves a coarse region stored exactly as it was',
      (tester) async {
    // The refined grid is an editing convenience, not a migration: an edit that
    // never touches the geometry must not rewrite how the shape is stored.
    const coarse = CustomRegion(
      id: 'r1', name: 'Left ⅔', cols: 3, rows: 1, c0: 0, c1: 1, r0: 0, r1: 0,
    );
    RegionDraft? submitted;
    await tester.pumpWidget(_host(RegionPickerSheet(
      initial: coarse,
      gridCols: 6,
      gridRows: 6,
      onSubmit: (d) => submitted = d,
      onCancel: () {},
    )));

    await tester.enterText(find.byType(TextField), 'Reading pane');
    await tester.tap(find.byKey(const ValueKey('region-submit')));
    await tester.pumpAndSettle();

    expect(submitted!.region.cols, 3, reason: 'still stored as thirds');
    expect(submitted!.region.rows, 1);
    expect(submitted!.region.c1, 1);
    expect(submitted!.region.name, 'Reading pane');
  });
  group('names across languages', () {
    // The stored name is always the English suggestion (a format older installs
    // share); what the field shows is the suggestion in the current language.
    // Whether the name is the suggestion or the user's own is decided once, from
    // the stored name, and then by whether the user has edited the field. It is
    // never read back from the field's text.
    Widget inLanguage(Locale locale, Widget sheet) =>
        localizedApp(locale, SizedBox(width: 600, height: 700, child: sheet));

    RegionPickerSheet sheet({
      CustomRegion? initial,
      void Function(RegionDraft)? onSubmit,
      bool withChord = false,
      String? Function(KeyChord)? conflictName,
    }) =>
        RegionPickerSheet(
          initial: initial,
          initialChord:
              withChord ? carbon(123, kControlOption | kShiftKey) : null,
          gridCols: 6,
          gridRows: 6,
          onSubmit: onSubmit ?? (_) {},
          onCancel: () {},
          onDelete: initial == null ? null : () {},
          conflictName: conflictName,
        );

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('region-submit')));
      await tester.pumpAndSettle();
    }

    /// A sheet opened from nothing. Pumping a second sheet over the first
    /// would update its state in place and keep the first one's combination,
    /// name and collision answer.
    Future<void> openFresh(
        WidgetTester tester, Locale locale, RegionPickerSheet s) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(inLanguage(locale, s));
      await tester.pumpAndSettle();
    }

    testWidgets('a new region under Chinese shows the Chinese suggestion and '
        'stores the English one', (tester) async {
      RegionDraft? submitted;
      await tester.pumpWidget(inLanguage(
          kSimplified, sheet(onSubmit: (d) => submitted = d)));

      await _dragCells(tester, cols: 6, rows: 6, c0: 0, r0: 0, c1: 3, r1: 5);
      expect(find.text('左 ⅔'), findsOneWidget);
      expect(find.text('Left ⅔'), findsNothing);

      await save(tester);
      expect(submitted!.region.name, 'Left ⅔',
          reason: 'the stored format is English whatever language showed');
    });

    for (final (locale, words) in [
      (kEnglish, 'Full screen'),
      (kSimplified, '全屏'),
      (kTraditional, '全螢幕'),
      (kHongKong, '全螢幕'),
    ]) {
      testWidgets('a stored generated name opens in the current language '
          '(${locale.toLanguageTag()})', (tester) async {
        const stored = CustomRegion(
          id: 'r2',
          name: 'Full screen',
          cols: 1,
          rows: 1,
          c0: 0,
          c1: 0,
          r0: 0,
          r1: 0,
        );
        await tester.pumpWidget(inLanguage(locale, sheet(initial: stored)));
        expect(find.text(words), findsOneWidget);
        if (locale != kEnglish) {
          expect(find.text('Full screen'), findsNothing);
        }
      });
    }

    testWidgets('reshaping a generated region keeps following the shape, in '
        'the current language', (tester) async {
      RegionDraft? submitted;
      await tester.pumpWidget(inLanguage(kSimplified,
          sheet(initial: _leftTwoThirds, onSubmit: (d) => submitted = d)));
      expect(find.text('左 ⅔'), findsOneWidget);

      await _dragCells(tester, cols: 6, rows: 6, c0: 0, r0: 0, c1: 1, r1: 5);
      expect(find.text('左 ⅓'), findsOneWidget);

      await _dragCells(tester, cols: 6, rows: 6, c0: 0, r0: 0, c1: 5, r1: 2);
      expect(find.text('上 ½'), findsOneWidget);

      await save(tester);
      expect(submitted!.region.name, 'Top ½');
    });

    testWidgets('saving a generated region without touching it stores it '
        'byte for byte, English name included', (tester) async {
      RegionDraft? submitted;
      await tester.pumpWidget(inLanguage(kSimplified,
          sheet(initial: _leftTwoThirds, onSubmit: (d) => submitted = d)));

      await save(tester);
      expect(submitted!.region, _leftTwoThirds);
    });

    testWidgets('typing in the field makes the name the user\'s own',
        (tester) async {
      RegionDraft? submitted;
      await tester.pumpWidget(inLanguage(kSimplified,
          sheet(initial: _leftTwoThirds, onSubmit: (d) => submitted = d)));

      await tester.enterText(find.byType(TextField), '阅读区');
      await _dragCells(tester, cols: 6, rows: 6, c0: 0, r0: 0, c1: 1, r1: 5);
      expect(find.text('阅读区'), findsOneWidget,
          reason: 'a typed name is not overwritten by a later drag');

      await save(tester);
      expect(submitted!.region.name, '阅读区');
    });

    testWidgets('retyping exactly the suggestion is still the user\'s own',
        (tester) async {
      // Generated status is never derived from the field's text: the user
      // chose these words, so a later reshape must not take them back.
      RegionDraft? submitted;
      await tester.pumpWidget(inLanguage(kSimplified,
          sheet(initial: _leftTwoThirds, onSubmit: (d) => submitted = d)));

      // Cleared first: entering text the field already holds changes nothing,
      // so it fires no edit, exactly as it would not for a person.
      await tester.enterText(find.byType(TextField), '');
      await tester.enterText(find.byType(TextField), '左 ⅔');
      await _dragCells(tester, cols: 6, rows: 6, c0: 0, r0: 0, c1: 1, r1: 5);
      expect(find.text('左 ⅔'), findsOneWidget);

      await save(tester);
      expect(submitted!.region.name, '左 ⅔');
    });

    for (final locale in [kEnglish, kSimplified, kTraditional, kHongKong]) {
      testWidgets('opening an authored name that equals the translated '
          'suggestion and saving stores it unchanged '
          '(${locale.toLanguageTag()})', (tester) async {
        // A user who wrote 左 ⅔ for a left two-thirds region wrote it: the
        // stored format is English, so this is not a generated name, however
        // much it looks like the suggestion in the language on screen.
        const theirs = CustomRegion(
          id: 'r1',
          name: '左 ⅔',
          cols: 3,
          rows: 1,
          c0: 0,
          c1: 1,
          r0: 0,
          r1: 0,
        );
        RegionDraft? submitted;
        await tester.pumpWidget(inLanguage(
            locale, sheet(initial: theirs, onSubmit: (d) => submitted = d)));
        expect(find.text('左 ⅔'), findsOneWidget);

        await save(tester);
        expect(submitted!.region.name, '左 ⅔');
        expect(submitted!.region, theirs,
            reason: 'nothing about it changes, so nothing is rewritten');
      });
    }

    testWidgets('an authored name is not re-suggested when the shape changes',
        (tester) async {
      RegionDraft? submitted;
      await tester.pumpWidget(inLanguage(
          kSimplified,
          sheet(
              initial: _leftTwoThirds.copyWith(name: '左 ⅔'),
              onSubmit: (d) => submitted = d)));

      await _dragCells(tester, cols: 6, rows: 6, c0: 0, r0: 0, c1: 1, r1: 5);
      expect(find.text('左 ⅔'), findsOneWidget);

      await save(tester);
      expect(submitted!.region.name, '左 ⅔');
      expect(submitted!.region.c1, 1);
    });

    testWidgets('a name saved in Chinese reads as generated by the same sheet '
        'in English, and by an older build\'s round trip', (tester) async {
      RegionDraft? saved;
      await tester.pumpWidget(
          inLanguage(kSimplified, sheet(onSubmit: (d) => saved = d)));
      await _dragCells(tester, cols: 6, rows: 6, c0: 0, r0: 0, c1: 3, r1: 5);
      await save(tester);

      // Through today's serializer, which an older build reads and rewrites.
      final back = CustomRegion.tryFromJson(saved!.region.toJson())!;
      RegionDraft? resaved;
      await openFresh(tester, kEnglish,
          sheet(initial: back, onSubmit: (d) => resaved = d));
      expect(find.text('Left ⅔'), findsOneWidget);

      await _dragCells(tester, cols: 6, rows: 6, c0: 0, r0: 0, c1: 1, r1: 5);
      expect(find.text('Left ⅓'), findsOneWidget,
          reason: 'still following the shape after the round trip');
      await save(tester);
      expect(resaved!.region.name, 'Left ⅓');
    });

    testWidgets('a language change while the sheet is open moves a generated '
        'name and leaves an authored one', (tester) async {
      await tester.pumpWidget(
          inLanguage(kEnglish, sheet(initial: _leftTwoThirds)));
      expect(find.text('Left ⅔'), findsOneWidget);

      await tester.pumpWidget(
          inLanguage(kSimplified, sheet(initial: _leftTwoThirds)));
      await tester.pumpAndSettle();
      expect(find.text('左 ⅔'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Reading pane');
      await tester.pumpWidget(
          inLanguage(kTraditional, sheet(initial: _leftTwoThirds)));
      await tester.pumpAndSettle();
      expect(find.text('Reading pane'), findsOneWidget);
    });

    testWidgets('the sheet\'s own labels are translated', (tester) async {
      await tester.pumpWidget(inLanguage(
          kSimplified, sheet(initial: _leftTwoThirds, withChord: true)));
      expect(find.text('编辑区域'), findsOneWidget);
      expect(find.text('名称'), findsOneWidget);
      expect(find.text('快捷键'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
      expect(find.textContaining('方向键移动'), findsOneWidget);

      await openFresh(tester, kTraditional, sheet());
      expect(find.text('新增區域'), findsOneWidget);
      expect(find.text('快速鍵'), findsOneWidget);
      expect(find.text('按一下以錄製'), findsOneWidget);
      expect(find.text('新增'), findsOneWidget);
    });

    for (final locale in [kSimplified, kTraditional, kHongKong]) {
      testWidgets('no English is left in the sheet (${locale.toLanguageTag()})',
          (tester) async {
        // Creating, with nothing set.
        await openFresh(tester, locale, sheet());
        expectNoEnglish(tester);

        // Editing a generated region with a combination and a way to delete.
        await openFresh(
            tester, locale, sheet(initial: _leftTwoThirds, withChord: true));
        expectNoEnglish(tester);

        // A collision, before and after it is accepted. The owner's name is
        // whatever the list calls the command, so the test hands in Chinese.
        await openFresh(
            tester,
            locale,
            sheet(
              initial: _leftTwoThirds,
              withChord: true,
              conflictName: (_) => '左半屏',
            ));
        expect(find.textContaining('左半屏'), findsOneWidget);
        expectNoEnglish(tester);
        await tester.tap(find.byKey(const ValueKey('region-take-anyway')));
        await tester.pumpAndSettle();
        expect(find.textContaining('左半屏'), findsOneWidget);
        expectNoEnglish(tester);
      });
    }

    for (final locale in [kSimplified, kTraditional, kHongKong]) {
      testWidgets('no English is left while the shortcut field listens '
          '(${locale.toLanguageTag()})', (tester) async {
        // The state the sheet's other no-English test never reached: the
        // field has become the shared recorder, which draws its own prompt and
        // the modifiers it hears.
        await openFresh(tester, locale, sheet());
        await tester.tap(find.byKey(const ValueKey('region-record')));
        await tester.pumpAndSettle();
        expect(find.byType(RecordingField), findsOneWidget);
        expectNoEnglish(tester);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expectNoEnglish(tester);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      });

      testWidgets('and a key Windows cannot use is refused in the language '
          '(${locale.toLanguageTag()})', (tester) async {
        // The recorder's refusal is drawn by the sheet under its field.
        setAppStrings(locale);
        addTearDown(() => setAppStrings(kEnglish));
        await openFresh(tester, locale, sheet());
        await tester.tap(find.byKey(const ValueKey('region-record')));
        await tester.pumpAndSettle();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
        await tester.pumpAndSettle();
        expect(find.textContaining('Windows'), findsOneWidget,
            reason: 'the refusal is on screen');
        expect(find.byType(RecordingField), findsOneWidget,
            reason: 'still listening: a refusal is not a cancel');
        expectNoEnglish(tester);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
    }

    testWidgets('the collision notice is one whole message each way',
        (tester) async {
      await tester.pumpWidget(inLanguage(
          kSimplified,
          sheet(
            initial: _leftTwoThirds,
            withChord: true,
            conflictName: (_) => 'Left half',
          )));
      expect(find.text('Left half 已使用此组合键。'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('region-take-anyway')));
      await tester.pumpAndSettle();
      expect(find.text('保存后，Left half 将不再使用此组合键。'), findsOneWidget);
    });
  });
}
