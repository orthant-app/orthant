import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/custom_region.dart';
import 'package:orthant/shortcuts/region_commands.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

// Built through functions, never as const literals: Dart canonicalizes const
// instances, so an equality test written with them passes with operator ==
// deleted (CLAUDE.md, M9 traps).
WinRect rect(double x, double y, double w, double h) => WinRect(x, y, w, h);
Display display(WinRect frame, double scale) => Display(frame, scale);

void main() {
  group('Display', () {
    test('is equal by frame and scale, and only by both', () {
      expect(display(rect(0, 0, 10, 10), 1.5), display(rect(0, 0, 10, 10), 1.5));
      expect(display(rect(0, 0, 10, 10), 1.5),
          isNot(display(rect(0, 0, 10, 10), 1)));
      expect(display(rect(0, 0, 10, 10), 1.5),
          isNot(display(rect(0, 0, 10, 11), 1.5)));
      expect(display(rect(0, 0, 10, 10), 1.5).hashCode,
          display(rect(0, 0, 10, 10), 1.5).hashCode);
    });
  });

  group('displayContaining', () {
    final a = display(rect(0, 0, 1920, 1040), 1);
    final b = display(rect(1920, 0, 2880, 1560), 1.5);

    test('returns the display the window mostly occupies, with its scale', () {
      expect(displayContaining(rect(2000, 100, 800, 600), [a, b]), same(b));
      // 220 px on a, 780 on b.
      expect(displayContaining(rect(1700, 100, 1000, 500), [a, b]), same(b));
      // 720 px on a, 280 on b.
      expect(displayContaining(rect(1200, 100, 1000, 500), [a, b]), same(a));
    });

    test('falls back to the first display, and is null for none', () {
      expect(displayContaining(rect(9000, 9000, 10, 10), [a, b]), same(a));
      expect(displayContaining(rect(0, 0, 10, 10), const []), isNull);
    });
  });

  group('gridBlock on a scaled display', () {
    final frame = rect(1920, 0, 2880, 1560); // 150 %, physical pixels

    test('the gap is device-independent: 16 at scale 1.5 is 24 pixels', () {
      final r = gridBlock(frame,
          cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 1, gap: 16, scale: 1.5);
      expect(r,
          gridBlock(frame, cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 1, gap: 24));
      expect(r.x, 1920 + 24);
      expect(r.width, (2880 - 3 * 24) / 2);
    });

    test('the size floor scales too, so a cell never drops under 40 points',
        () {
      // 1000 px, ten columns, one cell, a 30-point gap at scale 2. An
      // unscaled 40 px floor would allow a 54.5 px gap and a 40 px cell,
      // which is 20 points; the scaled floor stops at an 80 px cell.
      final r = gridBlock(rect(0, 0, 1000, 1000),
          cols: 10, rows: 1, c0: 0, c1: 0, r0: 0, r1: 0, gap: 30, scale: 2);
      expect(r.width, closeTo(kMinPlacedCell * 2, 1e-9));
    });
  });

  group('rectFor on a scaled display', () {
    final frame = rect(0, 0, 3000, 2000);

    test('center insets by the scaled gap', () {
      final r = rectForCommand(RegionCommand.center, frame,
          current: rect(0, 0, 2990, 1990), gap: 10, scale: 2);
      // Usable is 2960 x 1960, so the oversized window is clamped to it.
      expect(r, rect(20, 20, 2960, 1960));
    });

    test('built-ins and custom regions take the scale alike', () {
      const region = CustomRegion(
          id: 'r', name: 'Left 2/3', cols: 3, rows: 1, c0: 0, c1: 1, r0: 0, r1: 0);
      expect(
        rectFor(const Custom('r'), frame,
            current: frame, regions: const [region], gap: 8, scale: 1.5),
        gridBlock(frame, cols: 3, rows: 1, c0: 0, c1: 1, r0: 0, r1: 0, gap: 12),
      );
      expect(
        rectFor(const BuiltIn(ShortcutCommand.leftHalf), frame,
            current: frame, regions: const [], gap: 8, scale: 1.5),
        gridBlock(frame, cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 1, gap: 12),
      );
    });
  });
}
