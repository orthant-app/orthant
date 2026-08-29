import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/settings/mac_theme.dart';
import 'package:orthant/settings/region_glyph.dart';
import 'package:orthant/shortcuts/custom_region.dart';
import 'package:orthant/shortcuts/region_commands.dart';

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

void main() {
  test('a custom glyph paints the rect gridBlock computes', () {
    // The contract: the filled rect is the placement formula over a unit frame,
    // so the diagram cannot drift from what the shortcut does.
    expect(
      unitRectForGlyph(command: null, custom: _leftTwoThirds),
      const WinRect(0, 0, 2 / 3, 1),
    );
  });

  test('a built-in glyph is unchanged', () {
    expect(
      unitRectForGlyph(command: RegionCommand.leftHalf, custom: null),
      const WinRect(0, 0, 0.5, 1),
    );
  });

  test('a custom region wins over a command when both are given', () {
    expect(
      unitRectForGlyph(
          command: RegionCommand.maximize, custom: _leftTwoThirds),
      const WinRect(0, 0, 2 / 3, 1),
    );
  });

  test('the summon has no rect — it draws a lattice instead', () {
    expect(unitRectForGlyph(command: null, custom: null), isNull);
  });

  testWidgets('renders each kind without throwing', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: macTheme(Brightness.light),
      home: const Scaffold(
        body: Row(
          children: [
            RegionGlyph(custom: _leftTwoThirds),
            RegionGlyph(command: RegionCommand.leftHalf),
            RegionGlyph(),
          ],
        ),
      ),
    ));
    expect(find.byType(RegionGlyph), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a one-of-twelve region actually paints pixels', (tester) async {
    // 26 / 12 = 2.17 pt wide. A flat 1.5 inset takes 3 pt off, the painter's
    // guard bailed, and a valid shape rendered as an empty outline.
    //
    // Asserted against the rendered image rather than by re-deriving the inset:
    // a test that recomputes the formula it is checking passes whatever the
    // painter does, which is exactly what the first version of this test did.
    const thin = CustomRegion(
      id: 'thin',
      name: 'Sliver',
      cols: 12,
      rows: 12,
      c0: 0,
      c1: 0,
      r0: 0,
      r1: 0,
    );

    Future<int> accentPixels(Widget glyph) async {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: macTheme(Brightness.light),
        home: Scaffold(
          body: Center(child: RepaintBoundary(key: key, child: glyph)),
        ),
      ));
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      // runAsync: toImage/toByteData complete on the real event loop, and a
      // widget test's fake async zone would otherwise wait for them forever.
      final bytes = (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 4);
        final data = await image.toByteData(format: ImageByteFormat.rawRgba);
        return data!.buffer.asUint8List();
      }))!;
      // The fill is the accent (a strong blue); the outline is a faint grey.
      // Count pixels that are decisively more blue than red.
      var n = 0;
      for (var i = 0; i + 3 < bytes.length; i += 4) {
        if (bytes[i + 3] > 200 && bytes[i + 2] > bytes[i] + 40) n++;
      }
      return n;
    }

    final drawn = await accentPixels(const RegionGlyph(custom: thin));
    expect(drawn, greaterThan(0),
        reason: 'the thinnest valid region must still show a fill');

    // A sanity anchor: a half fills far more of the glyph than a twelfth.
    final half =
        await accentPixels(const RegionGlyph(command: RegionCommand.leftHalf));
    expect(half, greaterThan(drawn * 3));
  });
}
