import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/app/coordinator.dart';
import 'package:orthant/core/channel.dart';
import 'package:orthant/core/window_controller_windows.dart';
import 'package:orthant/permission/permission_controller.dart';
import 'package:orthant/shortcuts/hotkey_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The W0 native contract, as `windows/runner/window_channel.cpp` answers it:
/// the config window works, every hotkey is refused, unregistering is a
/// no-op, and anything else is NotImplemented (a null reply, which Dart
/// reports as MissingPluginException).
///
/// This drives the real coordinator, the real HotkeyService and the real
/// WindowsWindowController through the launch path. Permission reads as
/// granted on Windows, so start() registers hotkeys immediately, and
/// HotkeyService.apply awaits that call with no catch: a native side that
/// answered NotImplemented would throw out of start() before runApp.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(kOrthantChannel);
  final calls = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case kShowConfigWindow:
        case kHideConfigWindow:
        case 'unregisterAllHotkeys':
          return null;
        case 'replaceHotkeys':
          final bindings =
              ((call.arguments as Map)['bindings'] as List).cast<Map>();
          return [for (final b in bindings) b['id'] as int];
        default:
          throw MissingPluginException(
              'W0 native does not implement ${call.method}');
      }
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a first launch completes with every shortcut unavailable', () async {
    final wc = WindowsWindowController.forTest(
        readVersion: () => (short: '1.0.3', build: '7'));
    final app = OrthantCoordinator(
      wc: wc,
      permissions: PermissionController(wc),
      hotkeys: HotkeyService(onCommand: (_) {}),
      pollPeriod: const Duration(hours: 1),
    );
    addTearDown(app.dispose);

    await app.start();

    expect(app.permissions.granted, isTrue);
    expect(app.appVersion.display, '1.0.3 (7)');
    final bound = {
      for (final b in app.bindings)
        if (b.isBound) b.command
    };
    expect(bound, isNotEmpty, reason: 'the defaults must have loaded');
    expect(app.unavailable, bound,
        reason: 'W0 registers nothing, so every default reads Not set');
    expect(calls, contains('replaceHotkeys'));
    expect(calls, contains(kHideConfigWindow),
        reason: 'a granted first launch stays a tray app (no window)');
    expect(app.trayMenu, isNotEmpty);
  });

  test('a native side without the hotkey pair would take the launch down',
      () async {
    // The same launch against a native side that answers NotImplemented for
    // the hotkey pair: the failure Task 7's handler exists to prevent. This
    // documents the requirement on the native side; it cannot enforce it,
    // because the native side is a mock here. Task 11 verifies the real one.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == kShowConfigWindow ||
          call.method == kHideConfigWindow) {
        return null;
      }
      throw MissingPluginException(call.method);
    });
    final wc = WindowsWindowController.forTest(
        readVersion: () => (short: '1.0.3', build: '7'));
    final app = OrthantCoordinator(
      wc: wc,
      permissions: PermissionController(wc),
      hotkeys: HotkeyService(onCommand: (_) {}),
      pollPeriod: const Duration(hours: 1),
    );
    addTearDown(app.dispose);

    await expectLater(app.start(), throwsA(isA<MissingPluginException>()));
  });
}
