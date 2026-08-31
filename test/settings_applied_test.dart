import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/settings/settings.dart';
import 'package:orthant/shortcuts/apply_region.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

/// Records what a placement was actually asked to do.
class _RecordingWc implements WindowController {
  WinRect? applied;

  @override
  Future<CapturedWindow?> captureFrontmost() async =>
      const CapturedWindow('Safari', WinRect(100, 100, 400, 300));
  @override
  Future<List<WinRect>> screenFrames() async =>
      const [WinRect(0, 0, 1000, 1000)];
  @override
  Future<WinRect> activeScreenFrame() async => const WinRect(0, 0, 1000, 1000);
  @override
  Future<bool> applyFrame(WinRect target) async {
    applied = target;
    return true;
  }

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
  Future<void> setOverlayGrid({
    required int cols,
    required int rows,
    required double gap,
    required bool saveHint,
  }) async {}
  @override
  Future<void> showOverlay() async {}
  @override
  Future<void> hideOverlay() async {}
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
  group('gaps reach the direct shortcuts, not only the grid', () {
    // Regression for a real wiring bug: applyRegion takes `gap` with a default
    // of 0, and main.dart called it without one. Every geometry test still
    // passed — they exercise rectForCommand — while the running app applied
    // gaps to the grid and silently not to the ten shortcuts, which is most of
    // what people actually use.

    test('with gaps on, a half is inset by the gap', () async {
      const settings = Settings(gaps: true, gapSize: 10);
      final wc = _RecordingWc();
      await applyRegion(wc, const BuiltIn(ShortcutCommand.leftHalf),
          gap: settings.effectiveGap);
      expect(wc.applied, const WinRect(10, 10, 485, 980));
    });

    test('with gaps off, a half is exactly half', () async {
      const settings = Settings(gaps: false, gapSize: 10);
      final wc = _RecordingWc();
      await applyRegion(wc, const BuiltIn(ShortcutCommand.leftHalf),
          gap: settings.effectiveGap);
      expect(wc.applied, const WinRect(0, 0, 500, 1000));
    });
  });

  group('the tray only advertises a shortcut that can fire', () {
    test('shows the bound combo', () {
      expect(comboLabelFor(kDefaultBindings, const BuiltIn(ShortcutCommand.showGrid)),
          '⌃⌥O');
    });

    test('shows a rebound combo, not the default', () {
      final rebound = withRebind(kDefaultBindings,
          const Binding(BuiltIn(ShortcutCommand.showGrid), 17, kCmdKey | kShiftKey));
      expect(comboLabelFor(rebound, const BuiltIn(ShortcutCommand.showGrid)),
          '⇧⌘T');
    });

    test('is null when the command is unbound', () {
      final cleared = withRebind(
          kDefaultBindings, Binding.unbound(BuiltIn(ShortcutCommand.showGrid)));
      expect(comboLabelFor(cleared, const BuiltIn(ShortcutCommand.showGrid)),
          isNull);
    });

    test('is null when the OS refused the chord', () {
      // Stored, displayed, and never delivered. Printing it in the menu would
      // advertise a shortcut that cannot fire — the silence `unavailable`
      // exists to break.
      expect(
          comboLabelFor(kDefaultBindings, const BuiltIn(ShortcutCommand.showGrid),
              unavailable: {const BuiltIn(ShortcutCommand.showGrid)}),
          isNull);
    });

    test('is null when the command is absent entirely', () {
      expect(comboLabelFor(const [], const BuiltIn(ShortcutCommand.showGrid)),
          isNull);
    });
  });
}
