import 'dart:ui' show Locale;

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

  test('keyboard labels retain valid Unicode and ignore malformed entries', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'keyboardLabels');
      return <Object, Object>{31: 'R', 0: 'Ä', 1: '', 2: 3, -1: 'X',
        128: 'Y', '31': 'wrong key type'};
    });
    // Swift answers by Carbon code; the seam answers by key position (USB HID
    // usage), which is how a binding names its key.
    expect(await const MacosWindowController().keyboardLabels(), {
      PhysicalKeyboardKey.keyO.usbHidUsage: 'R',
      PhysicalKeyboardKey.keyA.usbHidUsage: 'Ä',
    });
  });

  test('a label for a code no shortcut can use is dropped', () async {
    // 48 is Tab and 53 Escape, neither bindable; 42 is the backslash key.
    messenger.setMockMethodCallHandler(channel, (call) async =>
        <Object, Object>{48: 'T', 53: 'E', 42: '#'});
    expect(await const MacosWindowController().keyboardLabels(),
        {PhysicalKeyboardKey.backslash.usbHidUsage: '#'});
  });

  test('a failed keyboard label read is an empty map, not a launch failure', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'layout');
    });
    expect(await const MacosWindowController().keyboardLabels(), isEmpty);
    // No handler at all — the shape of a Dart side newer than its native side.
    messenger.setMockMethodCallHandler(channel, null);
    expect(await const MacosWindowController().keyboardLabels(), isEmpty);
  });

  test('the accent is both appearances\' colours, as Swift resolves them',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'accentColor');
      return <Object, Object>{'light': 0xFF953D96, 'dark': 0xFFA550A7};
    });
    expect(await const MacosWindowController().accentColor(),
        const AccentColors(light: 0xFF953D96, dark: 0xFFA550A7));
  });

  test('an accent reply that is missing, malformed or failed is no accent',
      () async {
    for (final reply in <Object?>[
      null,
      'blue',
      <Object, Object>{'light': 0xFF007AFF},
      <Object, Object>{'light': 0xFF007AFF, 'dark': '0A84FF'},
      <Object, Object>{'light': -1, 'dark': 0xFF0A84FF},
      <Object, Object>{'light': 0x1FF007AFF, 'dark': 0xFF0A84FF},
    ]) {
      messenger.setMockMethodCallHandler(channel, (call) async => reply);
      expect(await const MacosWindowController().accentColor(), isNull,
          reason: '$reply');
    }
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'accent');
    });
    expect(await const MacosWindowController().accentColor(), isNull);
    // No handler at all: a Dart side newer than its native side.
    messenger.setMockMethodCallHandler(channel, null);
    expect(await const MacosWindowController().accentColor(), isNull);
  });

  test('startOverlay asks the native side nothing: macOS starts its overlay '
      'engine with the app, and Swift answers no such method', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    await const MacosWindowController().startOverlay();
    expect(calls, isEmpty);
  });

  test('setCommandsRunning asks the native side nothing: macOS has no engine '
      'attaches to defer, and Swift answers no such method', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    await const MacosWindowController().setCommandsRunning(true);
    await const MacosWindowController().setCommandsRunning(false);
    expect(calls, isEmpty);
  });

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

  test('every macOS display reports scale 1.0, because AX places in points',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, kScreenFrames);
      return [
        {'x': 0, 'y': 0, 'w': 1512, 'h': 945},
        {'x': 1512, 'y': 0, 'w': 2560, 'h': 1440},
      ];
    });
    final displays = await const MacosWindowController().screenFrames();
    expect(displays.map((d) => d.frame).toList(), [
      const WinRect(0, 0, 1512, 945),
      const WinRect(1512, 0, 2560, 1440),
    ]);
    expect(displays.map((d) => d.scale), everyElement(1.0));
  });

  test('a missing active display is null, not a zero rect', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await const MacosWindowController().activeScreenFrame(), isNull);
  });

  test('applyOverlayCommit places nothing and never reaches native', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    expect(
        await const MacosWindowController()
            .applyOverlayCommit(1, const WinRect(0, 0, 10, 10)),
        isFalse);
    expect(calls, isEmpty);
  });

  group('language', () {
    test('the system languages are the OS tags, in the OS order', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return <Object>['zh-Hant-TW', 'en-US'];
      });
      final locales = await const MacosWindowController().systemLocales();
      expect(calls.single.method, kSystemLanguages);
      expect(calls.single.arguments, isNull);
      expect(locales, [
        Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
        Locale.fromSubtags(languageCode: 'en', countryCode: 'US'),
      ]);
    });

    test('a system languages reply of the wrong shape never throws', () async {
      final cases = <Object?, List<Locale>>{
        'zh-Hans': const [],
        null: const [],
        <Object?>['en', 3, '']: const [Locale('en')],
        <Object?>[]: const [],
      };
      for (final entry in cases.entries) {
        messenger.setMockMethodCallHandler(
            channel, (call) async => entry.key);
        expect(await const MacosWindowController().systemLocales(),
            entry.value,
            reason: '${entry.key}');
      }
    });

    test('a failed system languages read is an empty list', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'languages');
      });
      expect(await const MacosWindowController().systemLocales(), isEmpty);
      // No handler at all: a Dart side newer than its native side.
      messenger.setMockMethodCallHandler(channel, null);
      expect(await const MacosWindowController().systemLocales(), isEmpty);
    });

    test('the stored choice is the whole tag, region kept', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return 'zh-Hant-HK';
      });
      expect(await const MacosWindowController().languageOverride(),
          'zh-Hant-HK');
      expect(calls.single.method, kLanguageOverride);
      expect(calls.single.arguments, isNull);
    });

    test('no stored choice is null', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await const MacosWindowController().languageOverride(), isNull);
    });

    test('a stored choice reply of the wrong shape is null, never a throw',
        () async {
      for (final reply in <Object?>[
        <Object?>['zh-Hans'],
        3,
        '',
      ]) {
        messenger.setMockMethodCallHandler(channel, (call) async => reply);
        expect(await const MacosWindowController().languageOverride(), isNull,
            reason: '$reply');
      }
    });

    test('a failed stored choice read is null', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'languages');
      });
      expect(await const MacosWindowController().languageOverride(), isNull);
      messenger.setMockMethodCallHandler(channel, null);
      expect(await const MacosWindowController().languageOverride(), isNull);
    });

    test('setting the choice sends the tag, or null for System', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      await const MacosWindowController().setLanguageOverride('zh-Hans');
      await const MacosWindowController().setLanguageOverride(null);
      expect(calls.map((c) => c.method),
          [kSetLanguageOverride, kSetLanguageOverride]);
      expect(calls.map((c) => c.arguments), ['zh-Hans', null]);
    });
  });

  test('the grid reaches Swift with the language the overlay is to speak',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    await const MacosWindowController().setOverlayGrid(
        cols: 6, rows: 4, gap: 8, saveHint: false, locale: 'zh-Hant');
    expect(calls.map((c) => c.method), [kSetOverlayGrid]);
    // Swift ignores the key until the overlay reads it; it must still arrive
    // beside the grid, which is what the overlay's engine is told by.
    expect(calls.single.arguments, {
      'cols': 6,
      'rows': 4,
      'gap': 8.0,
      'saveHint': false,
      'locale': 'zh-Hant',
    });
  });
}
