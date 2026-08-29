import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/overlay/grid_overlay.dart';
import 'package:orthant/overlay/grid_selection.dart';

void main() {
  const frame = WinRect(0, 0, 1200, 600);

  Widget host({
    int sessionId = 1,
    bool active = true,
    int cols = 6,
    int rows = 6,
    double gap = 0,
    void Function()? onBeginDrag,
    void Function()? onEndDrag,
    void Function(WinRect)? onCommit,
    void Function()? onCancel,
    void Function(CellBlock, WinRect)? onSave,
    bool saveHint = false,
    Key? gridKey,
  }) =>
      MediaQuery(
        data: const MediaQueryData(size: Size(1200, 600)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: GridOverlay(
            key: gridKey,
            sessionId: sessionId,
            displayFrame: frame,
            appName: 'Google Chrome',
            active: active,
            cols: cols,
            rows: rows,
            gap: gap,
            onBeginDrag: onBeginDrag ?? () {},
            onEndDrag: onEndDrag ?? () {},
            onCommit: onCommit ?? (_) {},
            onCancel: onCancel ?? () {},
            onSave: onSave,
            saveHint: saveHint,
          ),
        ),
      );

  CustomPainter painterOf(WidgetTester tester) =>
      tester.widget<CustomPaint>(find.byKey(GridOverlay.cellsKey)).painter!;

  // A probe point just inside a target cell's own leading (top-left) corner,
  // rather than its centre or trailing corner: with the panel-vs-cells rect
  // bug, the two rects' *trailing* corners nearly coincide (both are inset
  // from the same panel edges), so a centre or trailing probe can land on the
  // right cell by coincidence even when the rects disagree. The leading edge
  // is where the accumulated per-cell size error is largest and the bug is
  // guaranteed to show up.
  Offset cellProbe(Rect cells, int col, int row) {
    final cellW = cells.width / 6;
    final cellH = cells.height / 6;
    return Offset(cells.left + cellW * col + 2, cells.top + cellH * row + 2);
  }

  testWidgets('names the captured window', (tester) async {
    await tester.pumpWidget(host());
    expect(find.text('Google Chrome'), findsOneWidget);
  });

  testWidgets('a resized grid repaints, rather than drawing the old lattice',
      (tester) async {
    // The panel is *resident*: a summon updates the widget in place instead of
    // building a new one, so this has to be pumped as an update, not as a fresh
    // tree. The painter's cell size is driven by the display's aspect ratio and
    // not by the column count (gridCellsSizeFor), so 6x6 -> 4x4 leaves the
    // CustomPaint exactly the same size — no relayout, and therefore no repaint
    // unless shouldRepaint asks for one. It did not, so the grid went on
    // drawing six columns of lines while hit-testing four.
    await tester.pumpWidget(host(cols: 6, rows: 6));
    final before = painterOf(tester);

    await tester.pumpWidget(host(sessionId: 2, cols: 4, rows: 4));
    final after = painterOf(tester);

    expect(after.shouldRepaint(before), isTrue);
  });

  group('keyboard selection', () {
    // The panel is non-activating, so arrows arrive as a relayed native grab
    // rather than as key events. What is testable here is the wiring: that the
    // relay reaches the selection and that the committed rect follows.
    GridOverlayState state(WidgetTester tester) =>
        tester.state<GridOverlayState>(find.byType(GridOverlay));

    testWidgets('the first arrow selects the top-left cell', (tester) async {
      WinRect? committed;
      await tester.pumpWidget(host(onCommit: (r) => committed = r));
      state(tester).moveSelection(GridDirection.right);
      await tester.pump();
      state(tester).commitCurrent();
      // frame 1200x600, 6x6 => 200x100 cells.
      expect(committed, const WinRect(0, 0, 200, 100));
    });

    testWidgets('arrows walk one cell at a time', (tester) async {
      WinRect? committed;
      await tester.pumpWidget(host(onCommit: (r) => committed = r));
      final s = state(tester);
      s.moveSelection(GridDirection.right); // starts at (0,0)
      s.moveSelection(GridDirection.right); // -> (1,0)
      s.moveSelection(GridDirection.down); //  -> (1,1)
      await tester.pump();
      s.commitCurrent();
      expect(committed, const WinRect(200, 100, 200, 100));
    });

    testWidgets('shift extends the block, and the preview follows',
        (tester) async {
      WinRect? committed;
      await tester.pumpWidget(host(onCommit: (r) => committed = r));
      final s = state(tester);
      s.moveSelection(GridDirection.right);
      s.moveSelection(GridDirection.right, extend: true);
      s.moveSelection(GridDirection.down, extend: true);
      await tester.pump();
      s.commitCurrent();
      // (0,0)..(1,1) => two cells each way.
      expect(committed, const WinRect(0, 0, 400, 200));
    });

    testWidgets('gaps apply to a keyboard selection too', (tester) async {
      // The keyboard and the mouse must reach the same rect: both go through
      // targetRect, and gaps once applied to the grid but not the shortcuts.
      WinRect? committed;
      await tester.pumpWidget(
          host(gap: 10, onCommit: (r) => committed = r));
      state(tester).moveSelection(GridDirection.right);
      await tester.pump();
      state(tester).commitCurrent();
      expect(committed!.x, 10);
      expect(committed!.y, 10);
    });

    testWidgets('an inactive panel ignores arrows', (tester) async {
      // Only the display under the pointer is active; the rest are dimmed
      // indicators, and two panels acting on one relayed key would draw two
      // previews.
      WinRect? committed;
      await tester.pumpWidget(
          host(active: false, onCommit: (r) => committed = r));
      state(tester).moveSelection(GridDirection.right);
      await tester.pump();
      state(tester).commitCurrent();
      expect(committed, isNull);
    });

    testWidgets('a new session clears a keyboard selection', (tester) async {
      // Same rule the pointer path follows: a new summon is a fresh capture, so
      // a block held over from the last one must not be committable.
      WinRect? committed;
      await tester.pumpWidget(host(onCommit: (r) => committed = r));
      state(tester).moveSelection(GridDirection.right);
      await tester.pump();

      await tester.pumpWidget(host(sessionId: 2, onCommit: (r) => committed = r));
      state(tester).commitCurrent();
      expect(committed, isNull);
    });
  });

  testWidgets('an unchanged grid does not repaint', (tester) async {
    // The other half of the contract: this painter redraws on every hover move,
    // so a shouldRepaint that always answered true would be a real cost.
    await tester.pumpWidget(host());
    final before = painterOf(tester);
    await tester.pumpWidget(host());
    expect(painterOf(tester).shouldRepaint(before), isFalse);
  });

  testWidgets('a drag across the grid commits the covered block', (tester) async {
    WinRect? committed;
    var began = 0;
    await tester.pumpWidget(host(
      onBeginDrag: () => began++,
      onCommit: (r) => committed = r,
    ));

    // The grid is centred; find it and drag across its left half, full height.
    final grid = tester.getRect(find.byKey(GridOverlay.cellsKey));
    final cellW = grid.width / 6;
    final cellH = grid.height / 6;
    final start = Offset(grid.left + cellW * 0.5, grid.top + cellH * 0.5);
    final end = Offset(grid.left + cellW * 2.5, grid.top + cellH * 5.5);

    final gesture = await tester.startGesture(start);
    expect(began, 1, reason: 'native needs the drag lock at press, not release');
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(committed, const WinRect(0, 0, 600, 600));
  });

  testWidgets('a click outside the grid cancels', (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(host(onCancel: () => cancelled++));
    await tester.tapAt(const Offset(20, 20)); // far from the centred grid
    await tester.pump();
    expect(cancelled, 1);
  });

  testWidgets('an inactive panel ignores taps entirely', (tester) async {
    var began = 0;
    var cancelled = 0;
    await tester.pumpWidget(host(
      active: false,
      onBeginDrag: () => began++,
      onCancel: () => cancelled++,
    ));
    final grid = tester.getRect(find.byKey(GridOverlay.cellsKey));
    await tester.tapAt(grid.center);
    await tester.pump();
    expect(began, 0);
    expect(cancelled, 0);
  });

  testWidgets('commitCurrent commits the hovered selection and no-ops when '
      'there is none', (tester) async {
    WinRect? committed;
    final key = GlobalKey<GridOverlayState>();
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(1200, 600)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GridOverlay(
          key: key,
          sessionId: 1,
          displayFrame: frame,
          appName: 'Chrome',
          active: true,
          onBeginDrag: () {},
          onEndDrag: () {},
          onCommit: (r) => committed = r,
          onCancel: () {},
        ),
      ),
    ));

    // Nothing hovered yet: Return must do nothing rather than commit a guess.
    key.currentState!.commitCurrent();
    expect(committed, isNull);

    final grid = tester.getRect(find.byKey(GridOverlay.cellsKey));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(grid.topLeft + const Offset(5, 5));
    await tester.pump();

    key.currentState!.commitCurrent();
    expect(committed, isNotNull);
  });

  testWidgets('an interrupted drag returns to hover with the session intact',
      (tester) async {
    // Acceptance step 8. The manual version ("the panel returns to hover state")
    // has no external signal — nothing outside the process can see a Dart field
    // — so the check belongs here, where the state is reachable. What the real
    // app still has to answer is whether macOS delivers the cancel to a
    // non-activating panel at all; that is a different question from whether
    // the handler does the right thing when it arrives.
    WinRect? committed;
    var began = 0, ended = 0, cancelled = 0;
    final key = GlobalKey<GridOverlayState>();
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(1200, 600)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GridOverlay(
          key: key,
          sessionId: 1,
          displayFrame: frame,
          appName: 'Chrome',
          active: true,
          onBeginDrag: () => began++,
          onEndDrag: () => ended++,
          onCommit: (r) => committed = r,
          onCancel: () => cancelled++,
        ),
      ),
    ));

    final grid = tester.getRect(find.byKey(GridOverlay.cellsKey));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.down(cellProbe(grid, 0, 0));
    await tester.pump();
    await gesture.moveTo(cellProbe(grid, 2, 5));
    await tester.pump();
    expect(began, 1);

    await gesture.cancel(); // Mission Control, or anything else that takes the pointer
    await tester.pump();

    expect(committed, isNull, reason: 'an interrupted drag must place nothing');
    expect(cancelled, 0, reason: 'the overlay stays up — this is not a dismiss');
    expect(ended, 1,
        reason: "native's press lock must be released, or becameActive stays "
            'suppressed and no display can be made active again');

    // Nothing is selected any more: Return would have nothing to commit.
    key.currentState!.commitCurrent();
    expect(committed, isNull);

    // And the panel is usable again. If the anchor had survived, this would
    // commit a block stretching back to the old press instead of one cell.
    await gesture.moveTo(cellProbe(grid, 4, 4));
    await tester.pump();
    key.currentState!.commitCurrent();
    expect(committed, const WinRect(800, 400, 200, 100));
  });

  testWidgets(
      're-summon (new sessionId) clears a hovered selection rather than '
      'carrying it into the new session', (tester) async {
    var commits = 0;
    final key = GlobalKey<GridOverlayState>();

    Widget tree(int sessionId) => MediaQuery(
          data: const MediaQueryData(size: Size(1200, 600)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: GridOverlay(
              key: key,
              sessionId: sessionId,
              displayFrame: frame,
              appName: 'Chrome',
              active: true,
              onBeginDrag: () {},
              onEndDrag: () {},
              onCommit: (_) => commits++,
              onCancel: () {},
            ),
          ),
        );

    await tester.pumpWidget(tree(1));

    final grid = tester.getRect(find.byKey(GridOverlay.cellsKey));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(grid.topLeft + const Offset(5, 5));
    await tester.pump();

    // Sanity: within the same session, Return commits the hovered cell.
    key.currentState!.commitCurrent();
    expect(commits, 1);

    // A re-summon rebuilds this resident widget with a new sessionId. The
    // stale hover must not survive into it — this is exactly the case where
    // `hidden` never arrives (a re-summon inside the previous session's fade
    // window skips it via the panel-local fade guard), so the reset cannot
    // depend on that message.
    await tester.pumpWidget(tree(2));
    key.currentState!.commitCurrent();
    expect(commits, 1,
        reason: 'no new commit should fire for a stale-session selection');
  });

  testWidgets('the top-left cell is selectable', (tester) async {
    WinRect? committed;
    final key = GlobalKey<GridOverlayState>();
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(1200, 600)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GridOverlay(
          key: key,
          sessionId: 1,
          displayFrame: frame,
          appName: 'Google Chrome',
          active: true,
          onBeginDrag: () {},
          onEndDrag: () {},
          onCommit: (r) => committed = r,
          onCancel: () {},
        ),
      ),
    ));

    final cells = tester.getRect(find.byKey(GridOverlay.cellsKey));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(cellProbe(cells, 0, 0));
    await tester.pump();

    key.currentState!.commitCurrent();
    expect(committed,
        targetRect(const CellBlock(0, 0, 0, 0), frame, cols: 6, rows: 6),
        reason: 'the top-left cell must be exactly the top-left 1/6 x 1/6 '
            'of the display frame');
  });

  testWidgets('the bottom-right cell is selectable', (tester) async {
    WinRect? committed;
    final key = GlobalKey<GridOverlayState>();
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(1200, 600)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GridOverlay(
          key: key,
          sessionId: 1,
          displayFrame: frame,
          appName: 'Google Chrome',
          active: true,
          onBeginDrag: () {},
          onEndDrag: () {},
          onCommit: (r) => committed = r,
          onCancel: () {},
        ),
      ),
    ));

    final cells = tester.getRect(find.byKey(GridOverlay.cellsKey));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(cellProbe(cells, 5, 5));
    await tester.pump();

    key.currentState!.commitCurrent();
    expect(committed,
        targetRect(const CellBlock(5, 5, 5, 5), frame, cols: 6, rows: 6),
        reason: 'the bottom-right cell must be exactly the bottom-right '
            '1/6 x 1/6 of the display frame');
  });

  testWidgets('a non-default grid drives hit-testing and painting alike',
      (tester) async {
    // The whole point of Task 3: cols/rows reach pointToCell *and* the painter.
    // Probing near the leading corner of cell (1,1) is deliberate — with a
    // widget that painted 4x4 but hit-tested 6x6, a centre probe could still
    // land on the right cell by coincidence, while a leading-edge probe lands
    // on (1,1) only if both agree.
    WinRect? committed;
    final key = GlobalKey<GridOverlayState>();
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(1200, 600)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GridOverlay(
          key: key,
          sessionId: 1,
          displayFrame: frame,
          appName: 'Chrome',
          active: true,
          cols: 4,
          rows: 4,
          onBeginDrag: () {},
          onEndDrag: () {},
          onCommit: (r) => committed = r,
          onCancel: () {},
        ),
      ),
    ));

    final cells = tester.getRect(find.byKey(GridOverlay.cellsKey));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(Offset(
      cells.left + cells.width / 4 + 2,
      cells.top + cells.height / 4 + 2,
    ));
    await tester.pump();

    key.currentState!.commitCurrent();
    expect(committed, const WinRect(300, 150, 300, 150),
        reason: 'cell (1,1) of a 4x4 over 1200x600 is the second quarter');
  });

  testWidgets('gaps reach the committed rect', (tester) async {
    // Gaps are resolved before they get here — this widget receives points, not
    // a toggle — so a non-zero value must simply flow into targetRect.
    WinRect? committed;
    final key = GlobalKey<GridOverlayState>();
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(1200, 600)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GridOverlay(
          key: key,
          sessionId: 1,
          displayFrame: frame,
          appName: 'Chrome',
          active: true,
          cols: 2,
          rows: 2,
          gap: 10,
          onBeginDrag: () {},
          onEndDrag: () {},
          onCommit: (r) => committed = r,
          onCancel: () {},
        ),
      ),
    ));

    final cells = tester.getRect(find.byKey(GridOverlay.cellsKey));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(cells.topLeft + const Offset(2, 2));
    await tester.pump();

    key.currentState!.commitCurrent();
    // usable = 1200-20 = 1180 wide, 600-20 = 580 tall; cell = (1180-10)/2 = 585
    // by (580-10)/2 = 285.
    expect(committed, const WinRect(10, 10, 585, 285));
  });

  testWidgets('a press on the app chip does not select a cell', (tester) async {
    WinRect? committed;
    var began = 0;
    await tester.pumpWidget(host(
      onBeginDrag: () => began++,
      onCommit: (r) => committed = r,
    ));

    // The chip sits inside the panel but above the cells rect; pressing it
    // must be a no-op, not a misread hit on cell (0, 0).
    await tester.tapAt(tester.getCenter(find.text('Google Chrome')));
    await tester.pump();

    expect(began, 0, reason: 'the chip is not a cell, so no drag should start');
    expect(committed, isNull, reason: 'the chip is not a cell, so nothing commits');
  });

  group('the save hint and ⌘S', () {
    testWidgets('the hint shows only when it is asked for', (tester) async {
      await tester.pumpWidget(host(saveHint: true));
      expect(find.textContaining('save this shape'), findsOneWidget);

      await tester.pumpWidget(host(saveHint: false));
      expect(find.textContaining('save this shape'), findsNothing);
    });

    testWidgets('saveCurrent reports the selected block, or nothing',
        (tester) async {
      final saved = <CellBlock>[];
      final rects = <WinRect>[];
      final key = GlobalKey<GridOverlayState>();
      await tester.pumpWidget(host(
        gridKey: key,
        onSave: (b, r) {
          saved.add(b);
          rects.add(r);
        },
      ));

      key.currentState!.saveCurrent();
      expect(saved, isEmpty,
          reason: 'nothing selected — a no-op, not a guess at a corner');

      // Arrows are the selection path that needs no pointer geometry here.
      key.currentState!.moveSelection(GridDirection.right);
      key.currentState!.moveSelection(GridDirection.right, extend: true);
      await tester.pump();

      key.currentState!.saveCurrent();
      expect(saved.single.c0, 0);
      expect(saved.single.c1, 1);
      // The same rect a commit would place, so ⌘S and Return land identically.
      expect(rects.single,
          targetRect(saved.single, frame, cols: 6, rows: 6, gap: 0));
    });

    testWidgets('saveCurrent is inert without an onSave', (tester) async {
      final key = GlobalKey<GridOverlayState>();
      await tester.pumpWidget(host(gridKey: key));
      key.currentState!.moveSelection(GridDirection.right);
      await tester.pump();
      key.currentState!.saveCurrent();
      expect(tester.takeException(), isNull);
    });
  });
}
