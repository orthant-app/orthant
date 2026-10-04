import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/channel.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/core/window_controller_windows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(kOrthantChannel);
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  WindowsWindowController wc() => WindowsWindowController.forTest(
      readVersion: () => (short: '1.0.3', build: '7'));

  test('permission is always granted and the prompts are no-ops', () async {
    final c = wc();
    expect(await c.checkPermission(), isTrue);
    await c.requestPermission();
    await c.openAccessibilitySettings();
    expect(calls, isEmpty, reason: 'Windows has nothing to ask native for');
  });

  test('the config window is shown and hidden over the channel', () async {
    final c = wc();
    await c.showConfigWindow();
    await c.hideConfigWindow();
    expect(calls, [kShowConfigWindow, kHideConfigWindow]);
  });

  test('the version comes from the resource reader', () async {
    expect(await wc().appVersion(), const AppVersion('1.0.3', '7'));
    final unreadable =
        WindowsWindowController.forTest(readVersion: () => null);
    expect((await unreadable.appVersion()).isKnown, isFalse);
  });

  test('stubs answer safely and never reach native', () async {
    final c = wc();
    expect(await c.captureFrontmost(), isNull);
    expect(await c.screenFrames(), isEmpty);
    expect(await c.applyFrame(const WinRect(0, 0, 10, 10)), isFalse);
    await c.setOverlayGrid(cols: 2, rows: 2, gap: 0, saveHint: false);
    await c.showOverlay();
    await c.hideOverlay();
    expect(await c.keyboardLabels(), isEmpty);
    expect(await c.loginItemStatus(), LoginItemStatus.unavailable);
    expect(await c.setLoginItem(true), LoginItemStatus.unavailable);
    await c.openLoginItemsSettings();
    expect(await c.automaticUpdateChecks(), isFalse);
    expect(await c.setAutomaticUpdateChecks(true), isFalse);
    await c.checkForUpdates();
    expect(calls, isEmpty,
        reason: 'a stub that reaches native hits a handler that does not '
            'exist yet and throws MissingPluginException on the launch path');
  });
}
