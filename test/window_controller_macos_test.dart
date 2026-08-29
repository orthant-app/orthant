import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/channel.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/core/window_controller_macos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(kOrthantChannel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('applyFrame sends the rect and returns the native bool', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });

    final ok =
        await const MacosWindowController().applyFrame(const WinRect(0, 0, 720, 900));

    expect(ok, isTrue);
    expect(calls.single.method, kApplyFrame);
    expect(calls.single.arguments,
        {'x': 0.0, 'y': 0.0, 'w': 720.0, 'h': 900.0});
  });

  test('captureFrontmost parses a native map', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, kCaptureFrontmost);
      return {
        'ok': true,
        'appName': 'Safari',
        'frame': {'x': 10.0, 'y': 20.0, 'w': 800.0, 'h': 600.0},
      };
    });

    final captured = await const MacosWindowController().captureFrontmost();

    expect(captured, isNotNull);
    expect(captured!.appName, 'Safari');
    expect(captured.frame, const WinRect(10, 20, 800, 600));
  });

  test('captureFrontmost returns null when ok is false', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => {'ok': false});
    expect(await const MacosWindowController().captureFrontmost(), isNull);
  });

  test('config/settings methods invoke the right channel calls', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    const wc = MacosWindowController();
    await wc.openAccessibilitySettings();
    await wc.showConfigWindow();
    await wc.hideConfigWindow();
    expect(calls, [
      kOpenAccessibilitySettings,
      kShowConfigWindow,
      kHideConfigWindow,
    ]);
  });

  test('checkForUpdates asks the native side and takes no arguments', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });

    await const MacosWindowController().checkForUpdates();

    expect(calls.single.method, kCheckForUpdates);
    expect(calls.single.arguments, isNull,
        reason: 'the updater owns its own state; Dart has nothing to tell it');
  });

  group('login item', () {
    test('parses every status the native side can report', () async {
      for (final entry in {
        'enabled': LoginItemStatus.enabled,
        'disabled': LoginItemStatus.disabled,
        'requiresApproval': LoginItemStatus.requiresApproval,
        'unavailable': LoginItemStatus.unavailable,
      }.entries) {
        messenger.setMockMethodCallHandler(channel, (_) async => entry.key);
        expect(await const MacosWindowController().loginItemStatus(),
            entry.value);
      }
    });

    test('an unrecognised or absent reply is unavailable, not a throw',
        () async {
      // This is read whenever the settings window opens. A future macOS status
      // we do not know about must degrade to "we cannot say" rather than take
      // the pane down — and must not be mistaken for "enabled".
      for (final reply in <Object?>[null, 'somethingNew', 42]) {
        messenger.setMockMethodCallHandler(channel, (_) async => reply);
        expect(await const MacosWindowController().loginItemStatus(),
            LoginItemStatus.unavailable,
            reason: 'reply $reply');
      }
    });

    test('setLoginItem sends the bool and returns the resulting status',
        () async {
      // The *resulting* status, not the requested one: registration can be
      // refused, and reporting back what was asked for would make the checkbox
      // claim a state the system never entered.
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return 'requiresApproval';
      });

      final got = await const MacosWindowController().setLoginItem(true);

      expect(calls.single.method, kSetLoginItem);
      expect(calls.single.arguments, isTrue);
      expect(got, LoginItemStatus.requiresApproval);
    });

    test('openLoginItemsSettings reaches the native side', () async {
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        return null;
      });
      await const MacosWindowController().openLoginItemsSettings();
      expect(methods, [kOpenLoginItemsSettings]);
    });
  });
}
