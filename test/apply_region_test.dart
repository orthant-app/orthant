import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/custom_region.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';
import 'package:orthant/shortcuts/apply_region.dart';

class _FakeWc implements WindowController {
  CapturedWindow? toCapture = const CapturedWindow('X', WinRect(300, 300, 400, 300));
  Display? screen = const Display(WinRect(0, 0, 1440, 900), 1);
  List<Display> screens = const [Display(WinRect(0, 0, 1440, 900), 1)];
  WinRect? applied;
  @override
  Future<CapturedWindow?> captureFrontmost() async => toCapture;
  @override
  Future<Display?> activeScreenFrame() async => screen;
  @override
  Future<List<Display>> screenFrames() async => screens;
  @override
  Future<bool> applyFrame(WinRect t) async { applied = t; return true; }
  @override
  Future<bool> applyOverlayCommit(int sessionId, WinRect target) async => false;
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
  Future<void> showOverlay({double? pressedAtMs}) async {}
  @override
  Future<void> hideOverlay() async {}
  @override
  Future<void> setOverlayGrid({
    required int cols,
    required int rows,
    required double gap,
    required bool saveHint,
  }) async {}
  @override
  Future<Map<int, String>> keyboardLabels() async => const {};
  @override
  Future<AppVersion> appVersion() async => const AppVersion('1.0.0', '1');
  @override
  Future<bool> automaticUpdateChecks() async => true;
  @override
  Future<bool> setAutomaticUpdateChecks(bool enabled) async => enabled;
  // Launch-at-login is not what any of these tests exercise; the seam just
  // requires an answer. `unavailable` is the honest default for a fake.
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
  test('applyRegion places the frontmost window at the command rect', () async {
    final wc = _FakeWc();
    final ok = await applyRegion(wc, const BuiltIn(ShortcutCommand.rightHalf));
    expect(ok, isTrue);
    expect(wc.applied, const WinRect(720, 0, 720, 900));
  });

  test('applyRegion no-ops when nothing is capturable', () async {
    final wc = _FakeWc()..toCapture = null;
    expect(await applyRegion(wc, const BuiltIn(ShortcutCommand.maximize)), isFalse);
    expect(wc.applied, isNull);
  });

  test('snaps within the window\'s own display, not the cursor\'s', () async {
    const laptop = Display(WinRect(0, 0, 1512, 945), 1);
    const external = Display(WinRect(1512, 0, 2560, 1440), 1);
    final wc = _FakeWc()
      ..screens = const [laptop, external]
      // The window lives on the external display...
      ..toCapture = const CapturedWindow('X', WinRect(1800, 200, 800, 600))
      // ...while the cursor rests on the laptop. The window must not teleport.
      ..screen = laptop;

    expect(await applyRegion(wc, const BuiltIn(ShortcutCommand.leftHalf)), isTrue);
    expect(wc.applied, const WinRect(1512, 0, 1280, 1440));
  });

  test('with no display list, falls back to the cursor display when the '
      'window is on it', () async {
    final wc = _FakeWc()..screens = const [];
    expect(await applyRegion(wc, const BuiltIn(ShortcutCommand.leftHalf)), isTrue);
    expect(wc.applied, const WinRect(0, 0, 720, 900));
  });

  test('with no display list, places nothing when the window is not on the '
      'cursor display', () async {
    // Windows answers an empty list when it cannot name its displays. The
    // cursor's display is then all that is known, and snapping a window that
    // sits on another monitor onto it would move it there.
    final wc = _FakeWc()
      ..screens = const []
      ..screen = const Display(WinRect(0, 0, 1920, 1040), 1)
      ..toCapture = const CapturedWindow('X', WinRect(2000, 100, 800, 600));
    expect(await applyRegion(wc, const BuiltIn(ShortcutCommand.leftHalf)),
        isFalse);
    expect(wc.applied, isNull);
  });

  test('a window on none of the reported displays is placed on the first of '
      'them, not the cursor\'s', () async {
    // Today's rule for a non-empty list, pinned: screenContaining falls back
    // to the first display when nothing overlaps, so the cursor display is
    // never consulted while there is a list.
    const a = Display(WinRect(0, 0, 1920, 1040), 1);
    const b = Display(WinRect(1920, 0, 2560, 1440), 1);
    final wc = _FakeWc()
      ..screens = const [a, b]
      ..screen = b
      ..toCapture = const CapturedWindow('X', WinRect(-3000, 100, 800, 600));
    expect(await applyRegion(wc, const BuiltIn(ShortcutCommand.leftHalf)),
        isTrue);
    expect(wc.applied, const WinRect(0, 0, 960, 1040));
  });

  test('returns false when no display can be named', () async {
    final wc = _FakeWc()
      ..screens = const []
      ..screen = null;
    expect(await applyRegion(wc, const BuiltIn(ShortcutCommand.leftHalf)), isFalse);
    expect(wc.applied, isNull,
        reason: 'a placement must never be computed against a guessed rect');
  });

  test('the gap is converted by the window\'s own display\'s scale', () async {
    const laptop = Display(WinRect(0, 0, 1920, 1040), 1);
    const hiDpi = Display(WinRect(1920, 0, 2880, 1560), 1.5);
    final wc = _FakeWc()
      ..screens = const [laptop, hiDpi]
      ..toCapture = const CapturedWindow('X', WinRect(2000, 100, 800, 600));
    await applyRegion(wc, const BuiltIn(ShortcutCommand.leftHalf), gap: 16);
    expect(
      wc.applied,
      gridBlock(hiDpi.frame,
          cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 1, gap: 24),
    );
  });

  test('displayOffset moves to the next display, wrapping, with its scale',
      () async {
    const a = Display(WinRect(0, 0, 1920, 1040), 1);
    const b = Display(WinRect(1920, 0, 2880, 1560), 1.5);
    final wc = _FakeWc()
      ..screens = const [a, b]
      ..toCapture = const CapturedWindow('X', WinRect(100, 100, 800, 600));
    await applyRegion(wc, const BuiltIn(ShortcutCommand.leftHalf),
        gap: 16, displayOffset: 1);
    expect(wc.applied,
        gridBlock(b.frame, cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 1, gap: 24));

    wc.toCapture = const CapturedWindow('X', WinRect(2000, 100, 800, 600));
    await applyRegion(wc, const BuiltIn(ShortcutCommand.leftHalf),
        gap: 16, displayOffset: 1);
    expect(wc.applied,
        gridBlock(a.frame, cols: 2, rows: 2, c0: 0, c1: 0, r0: 0, r1: 1, gap: 16),
        reason: 'from the last display, the next one is the first');
  });

  group('custom regions', () {
    const leftTwoThirds = CustomRegion(
      id: 'r1',
      name: 'Left ⅔',
      cols: 3,
      rows: 1,
      c0: 0,
      c1: 1,
      r0: 0,
      r1: 0,
    );

    test('places a custom region on the window own display', () async {
      const laptop = Display(WinRect(0, 0, 1200, 900), 1);
      const external = Display(WinRect(1200, 0, 1200, 900), 1);
      final wc = _FakeWc()
        ..screens = const [laptop, external]
        ..toCapture = const CapturedWindow('X', WinRect(1500, 40, 400, 300))
        ..screen = laptop;

      final ok = await applyRegion(wc, const Custom('r1'),
          regions: const [leftTwoThirds]);

      expect(ok, isTrue);
      // Two-thirds of the *second* display, because that is where the window is.
      expect(wc.applied, const WinRect(1200, 0, 800, 900));
    });

    test('returns false and places nothing for a missing region', () async {
      final wc = _FakeWc();
      final ok = await applyRegion(wc, const Custom('gone'), regions: const []);
      expect(ok, isFalse);
      expect(wc.applied, isNull);
    });

    test('returns false for the summon, which places nothing', () async {
      final wc = _FakeWc();
      final ok =
          await applyRegion(wc, const BuiltIn(ShortcutCommand.showGrid));
      expect(ok, isFalse);
      expect(wc.applied, isNull);
    });

    test('a custom region takes the gap like any other placement', () async {
      final wc = _FakeWc();
      await applyRegion(wc, const Custom('r1'),
          regions: const [leftTwoThirds], gap: 10);
      expect(
        wc.applied,
        gridBlock(const WinRect(0, 0, 1440, 900),
            cols: 3, rows: 1, c0: 0, c1: 1, r0: 0, r1: 0, gap: 10),
      );
    });
  });
}
