import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/custom_region.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';
import 'package:orthant/shortcuts/apply_region.dart';

class _FakeWc implements WindowController {
  CapturedWindow? toCapture = const CapturedWindow('X', WinRect(300, 300, 400, 300));
  WinRect screen = const WinRect(0, 0, 1440, 900);
  List<WinRect> screens = const [WinRect(0, 0, 1440, 900)];
  WinRect? applied;
  @override
  Future<CapturedWindow?> captureFrontmost() async => toCapture;
  @override
  Future<WinRect> activeScreenFrame() async => screen;
  @override
  Future<List<WinRect>> screenFrames() async => screens;
  @override
  Future<bool> applyFrame(WinRect t) async { applied = t; return true; }
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
  Future<Map<int, String>> keyboardLabels() async => const {};

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
    const laptop = WinRect(0, 0, 1512, 945);
    const external = WinRect(1512, 0, 2560, 1440);
    final wc = _FakeWc()
      ..screens = const [laptop, external]
      // The window lives on the external display…
      ..toCapture = const CapturedWindow('X', WinRect(1800, 200, 800, 600))
      // …while the cursor rests on the laptop. The window must not teleport.
      ..screen = laptop;

    expect(await applyRegion(wc, const BuiltIn(ShortcutCommand.leftHalf)), isTrue);
    expect(wc.applied, const WinRect(1512, 0, 1280, 1440));
  });

  test('falls back to the cursor display when no screens are reported',
      () async {
    final wc = _FakeWc()..screens = const [];
    expect(await applyRegion(wc, const BuiltIn(ShortcutCommand.leftHalf)), isTrue);
    expect(wc.applied, const WinRect(0, 0, 720, 900));
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
      const laptop = WinRect(0, 0, 1200, 900);
      const external = WinRect(1200, 0, 1200, 900);
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
