import '../core/geometry.dart';
import '../core/window_controller.dart';
import 'command_ref.dart';
import 'custom_region.dart';
import 'region_commands.dart';

/// Capture the frontmost window and snap it to [ref]'s region. Returns false if
/// nothing was capturable, or if [ref] places nothing — the summon, or a custom
/// region that is not in [regions]. Capture happens first, before any placement.
///
/// The region is computed within **the window's own display** — the one it
/// mostly occupies — not the display under the cursor. Using the cursor would
/// fling a window to another screen whenever the mouse happened to be resting
/// there, which is not what any keyboard shortcut should do. (The overlay,
/// which the user summons deliberately at the pointer, still uses the cursor's
/// display.) Falls back to the cursor display if no screens are reported.
///
/// Custom regions inherit all of that unchanged, which is the point: a region
/// is purely fractional, so "left two-thirds" means two-thirds of whichever
/// display the window is already on.
Future<bool> applyRegion(
  WindowController wc,
  CommandRef ref, {
  List<CustomRegion> regions = const [],
  double gap = 0,
}) async {
  final captured = await wc.captureFrontmost();
  if (captured == null) return false;
  final screens = await wc.screenFrames();
  final screen = screenContaining(captured.frame, screens) ??
      await wc.activeScreenFrame();
  final rect = rectFor(ref, screen,
      current: captured.frame, regions: regions, gap: gap);
  if (rect == null) return false;
  return wc.applyFrame(rect);
}
