import '../core/geometry.dart';
import '../core/window_controller.dart';
import 'command_ref.dart';
import 'custom_region.dart';
import 'region_commands.dart';

/// Capture the frontmost window and snap it to [ref]'s region. Returns false if
/// nothing was capturable, if no display can be named for it, or if [ref]
/// places nothing (the summon, or a custom region that is not in [regions]).
/// Capture happens first, before any placement.
///
/// The region is computed within **the window's own display** (the one it
/// mostly occupies), not the display under the cursor. Using the cursor would
/// fling a window to another screen whenever the mouse happened to be resting
/// there, which is not what any keyboard shortcut should do. (The overlay,
/// which the user summons deliberately at the pointer, still uses the cursor's
/// display.) A window on none of the reported displays goes to the first of
/// them ([displayContaining]).
///
/// An empty list means the platform could not name its displays (Windows
/// answers one when a monitor has no working panel). The cursor's display is
/// then used only for a window that is on it, and otherwise nothing is
/// placed: snapping a window on another monitor to the cursor's display would
/// move it there.
///
/// Custom regions inherit all of that unchanged, which is the point: a region
/// is purely fractional, so "left two-thirds" means two-thirds of whichever
/// display the window is already on. [gap] is device-independent; the chosen
/// display's scale converts it (`gapForPlacement`).
///
/// [displayOffset] moves the placement that many displays along the reported
/// order, wrapping; 0, which every shortcut uses, keeps it on the window's own
/// display. Only Windows' W1 debug item passes 1, to cross a DPI boundary on
/// purpose (Windows design §9, W1). It does not apply to the cursor fallback.
Future<bool> applyRegion(
  WindowController wc,
  CommandRef ref, {
  List<CustomRegion> regions = const [],
  double gap = 0,
  int displayOffset = 0,
}) async {
  final captured = await wc.captureFrontmost();
  if (captured == null) return false;
  final displays = await wc.screenFrames();
  final own = displayContaining(captured.frame, displays);
  final Display? display;
  if (own == null) {
    final cursor = await wc.activeScreenFrame();
    display = cursor != null && overlaps(captured.frame, cursor.frame)
        ? cursor
        : null;
  } else {
    display =
        displays[(displays.indexOf(own) + displayOffset) % displays.length];
  }
  if (display == null) return false;
  final rect = rectFor(ref, display.frame,
      current: captured.frame,
      regions: regions,
      gap: gap,
      scale: display.scale);
  if (rect == null) return false;
  return wc.applyFrame(rect);
}
