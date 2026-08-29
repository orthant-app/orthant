import '../core/geometry.dart';
import 'command_ref.dart';
import 'custom_region.dart';

enum RegionCommand {
  leftHalf, rightHalf, topHalf, bottomHalf,
  topLeft, topRight, bottomLeft, bottomRight,
  maximize, center,
}

/// The target rect for [cmd] within visible screen [frame]. [current] is the
/// captured window's current frame (used only by [RegionCommand.center]).
WinRect rectForCommand(RegionCommand cmd, WinRect frame,
    {required WinRect current, double gap = 0}) {
  WinRect block(int c0, int c1, int r0, int r1) => gridBlock(frame,
      cols: 2, rows: 2, c0: c0, c1: c1, r0: r0, r1: r1, gap: gap);
  switch (cmd) {
    case RegionCommand.leftHalf:    return block(0, 0, 0, 1);
    case RegionCommand.rightHalf:   return block(1, 1, 0, 1);
    case RegionCommand.topHalf:     return block(0, 1, 0, 0);
    case RegionCommand.bottomHalf:  return block(0, 1, 1, 1);
    case RegionCommand.topLeft:     return block(0, 0, 0, 0);
    case RegionCommand.topRight:    return block(1, 1, 0, 0);
    case RegionCommand.bottomLeft:  return block(0, 0, 1, 1);
    case RegionCommand.bottomRight: return block(1, 1, 1, 1);
    case RegionCommand.maximize:    return block(0, 1, 0, 1);
    case RegionCommand.center:
      final usableW = frame.width - 2 * gap;
      final usableH = frame.height - 2 * gap;
      final w = current.width <= usableW ? current.width : usableW;
      final h = current.height <= usableH ? current.height : usableH;
      return WinRect(
        frame.x + (frame.width - w) / 2,
        frame.y + (frame.height - h) / 2,
        w, h,
      );
  }
}

/// The target rect for [ref] within [frame], or **null when [ref] does not place
/// a window** — the summon, which opens the grid instead, or a [Custom] whose
/// region is absent.
///
/// A missing region should be unreachable: `BindingsStore` drops any binding
/// whose region did not survive validation, precisely so this cannot happen.
/// Null rather than a throw all the same, because the cost of being wrong here
/// is one shortcut doing nothing, and the cost of throwing is a launch path
/// that fails.
///
/// The custom branch is the same [gridBlock] the ten built-ins and the overlay
/// already use — with the *region's own* denominators rather than the user's
/// live grid setting, which is what stops a saved shortcut changing meaning when
/// that setting moves.
WinRect? rectFor(
  CommandRef ref,
  WinRect frame, {
  required WinRect current,
  required List<CustomRegion> regions,
  double gap = 0,
}) {
  switch (ref) {
    case BuiltIn(:final command):
      final region = command.region;
      if (region == null) return null;
      return rectForCommand(region, frame, current: current, gap: gap);
    case Custom(:final id):
      for (final r in regions) {
        if (r.id != id) continue;
        // Placed on the denominators it is stored with, and that is safe
        // because `gapForPlacement` measures the block rather than the grid —
        // so a region means the same rectangle however it happens to be
        // written. It has to be: the overlay places a ⌘S selection on the raw
        // live grid before this ever runs, so any reduction here would make the
        // saved shortcut disagree with the placement it was offered from.
        return gridBlock(frame,
            cols: r.cols,
            rows: r.rows,
            c0: r.c0,
            c1: r.c1,
            r0: r.r0,
            r1: r.r1,
            gap: gap);
      }
      return null;
  }
}
