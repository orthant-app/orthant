import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/shortcuts/apply_region.dart';
import 'package:orthant/shortcuts/command_queue.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

/// A [WindowController] that models the part of the native side the pure-Dart
/// fakes elsewhere leave out: **one** capture slot, shared by every command.
///
/// `captureFrontmost` overwrites the slot and `applyFrame` moves whatever is in
/// it *at the moment it runs* — not what the caller captured. Every method
/// takes a real turn of the event loop, because the hazard only exists in the
/// gap between a command's capture and its apply.
class _SlottedWc implements WindowController {
  _SlottedWc(this.frontmostInTurn);

  /// Which window is frontmost for the nth capture. Indexed rather than mutated
  /// from the test so the sequence holds however the calls interleave —
  /// otherwise the assertion would be measuring the test's own timing.
  final List<String> frontmostInTurn;

  /// Long enough that two commands started together genuinely overlap, short
  /// enough that the suite stays fast.
  static const lag = Duration(milliseconds: 5);

  int _captures = 0;
  String? _slot;

  /// One entry per placement: which window actually moved, and to what x.
  final moves = <String>[];

  @override
  Future<CapturedWindow?> captureFrontmost() async {
    await Future<void>.delayed(lag);
    final turn = _captures++;
    _slot = frontmostInTurn[turn.clamp(0, frontmostInTurn.length - 1)];
    return CapturedWindow(_slot!, const WinRect(0, 0, 400, 300));
  }

  @override
  Future<bool> applyFrame(WinRect t) async {
    await Future<void>.delayed(lag);
    moves.add('$_slot@${t.x.toInt()}');
    return true;
  }

  @override
  Future<List<WinRect>> screenFrames() async {
    await Future<void>.delayed(lag);
    return const [WinRect(0, 0, 1440, 900)];
  }

  @override
  Future<WinRect> activeScreenFrame() async => const WinRect(0, 0, 1440, 900);
  @override
  Future<bool> checkPermission() async => true;
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> openAccessibilitySettings() async {}
  @override
  Future<void> showConfigWindow() async {}
  @override
  Future<void> hideConfigWindow() async {}
  @override
  Future<void> showOverlay() async {}
  @override
  Future<void> hideOverlay() async {}
  @override
  Future<void> setOverlayGrid({
    required int cols,
    required int rows,
    required double gap,
    required bool saveHint,
  }) async {}
  // Launch-at-login is not what any of these tests exercise; the seam just
  // requires an answer. `unavailable` is the honest default for a fake.
  @override
  Future<AppVersion> appVersion() async => const AppVersion('1.0.0', '1');

  @override
  Future<bool> automaticUpdateChecks() async => true;

  @override
  Future<bool> setAutomaticUpdateChecks(bool enabled) async => enabled;

  @override
  Future<LoginItemStatus> loginItemStatus() async => LoginItemStatus.unavailable;
  @override
  Future<LoginItemStatus> setLoginItem(bool enabled) async =>
      LoginItemStatus.unavailable;
  @override
  Future<void> openLoginItemsSettings() async {}
  @override
  Future<void> checkForUpdates() async {}
}

void main() {
  // Window A is frontmost for the first capture, B for the second — the user
  // pressed ⌃⌥←, clicked another window, and pressed ⌃⌥→ before the first
  // command had finished its round trips.
  const burst = ['A', 'B'];

  test('a burst of shortcuts each moves the window it captured', () async {
    final wc = _SlottedWc(burst);
    final q = CommandQueue();
    final a = q.add(() => applyRegion(wc, const BuiltIn(ShortcutCommand.leftHalf)));
    final b = q.add(() => applyRegion(wc, const BuiltIn(ShortcutCommand.rightHalf)));
    await Future.wait([a, b]);

    expect(wc.moves, ['A@0', 'B@720']);
  });

  test('unqueued, the second capture steals the first command\'s window',
      () async {
    // Pinned deliberately: this is the defect, and it is what makes the test
    // above meaningful rather than vacuously true. Both commands end up moving
    // B — A is never touched, and B is moved twice, the second time to a rect
    // computed from A's geometry.
    final wc = _SlottedWc(burst);
    await Future.wait([
      applyRegion(wc, const BuiltIn(ShortcutCommand.leftHalf)),
      applyRegion(wc, const BuiltIn(ShortcutCommand.rightHalf)),
    ]);

    expect(wc.moves, ['B@0', 'B@720']);
  });
}
