import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/overlay/grid_selection.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/custom_region.dart';
import 'package:orthant/shortcuts/region_commands.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

void main() {
  const screen = WinRect(0, 0, 1440, 900);
  const current = WinRect(300, 300, 400, 300);

  test('halves and quarters map to 2x2 blocks (no gap)', () {
    expect(rectForCommand(RegionCommand.leftHalf, screen, current: current),
        const WinRect(0, 0, 720, 900));
    expect(rectForCommand(RegionCommand.bottomRight, screen, current: current),
        const WinRect(720, 450, 720, 450));
    expect(rectForCommand(RegionCommand.maximize, screen, current: current),
        const WinRect(0, 0, 1440, 900));
  });

  test('center keeps the window size and centers it', () {
    expect(rectForCommand(RegionCommand.center, screen, current: current),
        const WinRect((1440 - 400) / 2, (900 - 300) / 2, 400, 300));
  });

  test('a direct shortcut is unaffected by the overlay grid size', () {
    // "Left half" is half the *screen*, never half the grid. rectForCommand is
    // a fixed 2x2 by definition; this test exists so that stays true now that
    // the grid is something a user can set to 8x8 or 10x4. If someone ever
    // wires the setting into this path, this is what catches it.
    expect(rectForCommand(RegionCommand.leftHalf, screen, current: current),
        const WinRect(0, 0, 720, 900));
    expect(rectForCommand(RegionCommand.maximize, screen, current: current),
        screen);
  });

  test('gaps apply to direct shortcuts too, using the same formula', () {
    // One preference about how windows are placed, not one per path. The
    // numbers here are gridBlock's, so the grid and the keyboard cannot drift.
    const square = WinRect(0, 0, 1000, 1000);
    expect(
        rectForCommand(RegionCommand.leftHalf, square,
            current: const WinRect(0, 0, 10, 10), gap: 10),
        const WinRect(10, 10, 485, 980));
  });

  group('rectFor', () {
    const frame = WinRect(0, 0, 1200, 900);
    const win = WinRect(0, 0, 400, 300);
    const leftTwoThirds = CustomRegion(
      id: 'r1',
      name: 'Left \u2154',
      cols: 3,
      rows: 1,
      c0: 0,
      c1: 1,
      r0: 0,
      r1: 0,
    );

    test('delegates a built-in to rectForCommand', () {
      expect(
        rectFor(const BuiltIn(ShortcutCommand.leftHalf), frame,
            current: win, regions: const []),
        rectForCommand(RegionCommand.leftHalf, frame, current: win),
      );
    });

    test('places a custom region on its own denominators', () {
      expect(
        rectFor(const Custom('r1'), frame,
            current: win, regions: const [leftTwoThirds]),
        const WinRect(0, 0, 800, 900),
      );
    });

    test('a custom region ignores the live grid setting', () {
      // The whole reason a region carries its own cols/rows: two-thirds stays
      // two-thirds however the user later changes the overlay grid.
      expect(
        rectFor(const Custom('r1'), frame,
                current: win, regions: const [leftTwoThirds])!
            .width,
        800,
      );
    });

    test('applies gaps to a custom region', () {
      expect(
        rectFor(const Custom('r1'), frame,
            current: win, regions: const [leftTwoThirds], gap: 10),
        gridBlock(frame, cols: 3, rows: 1, c0: 0, c1: 1, r0: 0, r1: 0, gap: 10),
      );
    });

    test('a region saved from the grid reproduces the placement it was offered',
        () {
      // ⌘S is "Return plus an offer": native places the window and *then*
      // offers to keep the shape. The shortcut that results must land in the
      // same place, or the offer was a lie.
      //
      // Run at a gap, because a zero-gap test cannot see the failure this
      // guards against: `gapForPlacement` returns early at zero, and the clamp
      // is the only thing that could ever make these two disagree. 1440 x 800
      // is about a 13" display's visible frame — small enough that a single
      // cell of twelfths is still clamped, so both regimes below are real.
      const small = WinRect(0, 0, 1440, 800);

      WinRect overlay(CellBlock b) =>
          targetRect(b, small, cols: 12, rows: 12, gap: 64);

      void roundTrip(CellBlock b, String label) {
        // The region `requestSaveRegion` builds from the block ⌘S emitted.
        final saved = CustomRegion(
          id: 'r1', name: 'n', cols: 12, rows: 12,
          c0: b.c0, c1: b.c1, r0: b.r0, r1: b.r1,
        );
        expect(
          rectFor(const Custom('r1'), small,
              current: win, regions: [saved], gap: 64),
          overlay(b),
          reason: label,
        );
      }

      roundTrip(const CellBlock(0, 7, 0, 11), 'left two-thirds');
      roundTrip(const CellBlock(3, 3, 4, 4), 'a single cell');

      // Both gap regimes are genuinely exercised, so neither case can go
      // trivially true: the wide block keeps the 64 pt it asked for, and the
      // single cell is the one that still cannot.
      expect(overlay(const CellBlock(0, 7, 0, 11)).x, 64);
      expect(overlay(const CellBlock(0, 0, 0, 0)).x, closeTo(320 / 13, 1e-9));
    });

    test('returns null for the summon and for a missing region', () {
      expect(
        rectFor(const BuiltIn(ShortcutCommand.showGrid), frame,
            current: win, regions: const []),
        isNull,
      );
      expect(
        rectFor(const Custom('gone'), frame,
            current: win, regions: const [leftTwoThirds]),
        isNull,
      );
    });
  });
}
