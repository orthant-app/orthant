import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/channel.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/core/window_controller_windows.dart';
import 'package:orthant/core/windows_window_ops.dart';

import 'support/fake_win32.dart';

class _ThrowingDesktop extends FakeDesktop {
  @override
  int foregroundWindow() => throw StateError('user32 went away');
}

/// Throws only once capture has found its window: at the process name.
class _NameThrowingDesktop extends FakeDesktop {
  _NameThrowingDesktop() : super(ownPid: 1);

  @override
  String? processName(int pid) => throw StateError('OpenProcess went away');
}

// Built through functions so equality is tested, not const identity.
Display display(double x, double y, double w, double h, double s) =>
    Display(WinRect(x, y, w, h), s);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(kOrthantChannel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  Object? Function(MethodCall call) answer = (_) => null;

  setUp(() {
    calls.clear();
    answer = (_) => null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return answer(call);
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  WindowsWindowController wc({
    Win32Desktop? desktop,
    Win32Placer? placer,
    PlacementClock? clock,
    String? Function(int vk)? keyLabel,
  }) =>
      WindowsWindowController.forTest(
        readVersion: () => (short: '1.0.3', build: '7'),
        desktop: desktop ?? NoWindows(),
        placer: placer ?? NoWindows(),
        clock: clock ?? FakeClock(),
        keyLabel: keyLabel,
      );

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
    final unreadable = WindowsWindowController.forTest(
        readVersion: () => null, desktop: NoWindows(), placer: NoWindows());
    expect((await unreadable.appVersion()).isKnown, isFalse);
  });

  test('the remaining stubs answer safely and never reach native', () async {
    final c = wc();
    expect(await c.loginItemStatus(), LoginItemStatus.unavailable);
    expect(await c.setLoginItem(true), LoginItemStatus.unavailable);
    await c.openLoginItemsSettings();
    expect(await c.automaticUpdateChecks(), isFalse);
    expect(await c.setAutomaticUpdateChecks(true), isFalse);
    await c.checkForUpdates();
    expect(calls, isEmpty,
        reason: 'a stub that reaches native hits a handler that does not '
            'exist yet and throws MissingPluginException');
  });

  group('keyboard labels', () {
    test('label the layout-dependent keys by their logical key', () async {
      // German: the key that types Ä is VK_OEM_7, which Flutter names quote.
      // Brazil's ABNT_C1 (0xC1) keeps its own id, not VK_OEM_AX's.
      final labels = await wc(
          keyLabel: (vk) =>
              {0xDE: 'Ä', 0xBA: 'Ü', 0xE2: '<', 0xC1: '/'}[vk]).keyboardLabels();
      expect(labels, {
        LogicalKeyboardKey.quote.keyId: 'Ä',
        LogicalKeyboardKey.semicolon.keyId: 'Ü',
        0xE2: '<',
        0xC1: '/',
      });
      expect(calls, isEmpty, reason: 'read over FFI, not the channel');
    });

    test('read only the keys whose symbol depends on the layout', () async {
      final asked = <int>[];
      await wc(keyLabel: (vk) {
        asked.add(vk);
        return null;
      }).keyboardLabels();
      expect(asked, isNot(contains(0x41)), reason: 'letters name themselves');
      expect(asked, containsAll([0xBA, 0xDE, 0xE2]));
    });

    test('a key that types nothing, or a failing read, leaves the glyph',
        () async {
      expect(await wc(keyLabel: (_) => ' ').keyboardLabels(), isEmpty);
      expect(await wc(keyLabel: (_) => throw StateError('ffi'))
          .keyboardLabels(), isEmpty);
    });
  });

  group('capture and placement', () {
    test('captures the foreground window, named, at its DWM frame, and '
        'places that window', () async {
      final desktop = FakeDesktop(ownPid: 1)
        ..windows.add(windowFacts(0x10, pid: 7, frame: const PxRect(100, 100, 900, 700)))
        ..foreground = 0x10
        ..names[7] = 'Notepad';
      final window = FakeWindow(frame: const PxRect(100, 100, 900, 700));
      final c = wc(desktop: desktop, placer: window);

      final captured = await c.captureFrontmost();
      expect(captured!.appName, 'Notepad');
      expect(captured.frame, const WinRect(100, 100, 800, 600));
      expect(await c.applyFrame(const WinRect(0, 0, 960, 1040)), isTrue);
      expect(window.lastHwnd, 0x10);
      expect(window.frame, const PxRect(0, 0, 960, 1040));
      expect(desktop.reactivated, isEmpty,
          reason: 'the foreground window already has focus');
      expect(calls, isEmpty, reason: 'capture and placement are FFI, not the channel');
    });

    test('a tray-path capture reactivates the window it found beneath',
        () async {
      final desktop = FakeDesktop(ownPid: 1)
        ..windows.addAll([
          windowFacts(0x2, pid: 1, visible: false),
          windowFacts(0x10, pid: 7),
        ])
        ..foreground = 0x2;
      final c = wc(desktop: desktop, placer: FakeWindow(frame: const PxRect(0, 0, 800, 600)));
      expect(await c.captureFrontmost(), isNotNull);
      expect(desktop.reactivated, [0x10]);
    });

    test('a refused reactivation still captures, and the log says refused',
        () async {
      final desktop = FakeDesktop(ownPid: 1)
        ..windows.addAll([
          windowFacts(0x2, pid: 1, visible: false),
          windowFacts(0x10, pid: 7),
        ])
        ..foreground = 0x2
        ..foregroundRefused = true;
      final c = wc(desktop: desktop, placer: FakeWindow(frame: const PxRect(0, 0, 800, 600)));
      // The result has no field for it; the debug log the harness reads does.
      final logged = <String>[];
      final saved = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) => logged.add('$message');
      try {
        expect(await c.captureFrontmost(), isNotNull);
      } finally {
        debugPrint = saved;
      }
      expect(desktop.reactivated, [0x10]);
      expect(logged.where((l) => l.contains('capture: branch=beneath')).single,
          contains('reactivated=refused'));
    });

    test('an unnamed process is captured with an empty name', () async {
      final desktop = FakeDesktop(ownPid: 1)
        ..windows.add(windowFacts(0x10, pid: 7))
        ..foreground = 0x10;
      expect((await wc(desktop: desktop).captureFrontmost())!.appName, '');
    });

    test('a failed capture empties the slot, so applyFrame cannot move an '
        'earlier window', () async {
      final desktop = FakeDesktop(ownPid: 1)
        ..windows.addAll([
          windowFacts(0x10, pid: 7),
          windowFacts(0x5, pid: 9, className: 'Progman'),
        ])
        ..foreground = 0x10;
      final window = FakeWindow(frame: const PxRect(0, 0, 800, 600));
      final c = wc(desktop: desktop, placer: window);
      expect(await c.captureFrontmost(), isNotNull);
      desktop.foreground = 0x5;
      expect(await c.captureFrontmost(), isNull);
      expect(await c.applyFrame(const WinRect(0, 0, 960, 1040)), isFalse);
      expect(window.writes, isEmpty);
      expect(window.touches, 0);
    });

    test('a handle that names another window by the time applyFrame runs is '
        'not placed: the captured window closed and Windows reused its handle',
        () async {
      for (final (label, successor) in <(String, WindowFacts?)>[
        ('another process', windowFacts(0x10, pid: 9)),
        ('the same process, another class',
            windowFacts(0x10, pid: 7, className: 'NotepadPopup')),
        ('nothing: the window is simply gone', null),
      ]) {
        final desktop = FakeDesktop(ownPid: 1)
          ..windows.add(windowFacts(0x10, pid: 7))
          ..foreground = 0x10;
        final window = FakeWindow(frame: const PxRect(0, 0, 800, 600));
        final c = wc(desktop: desktop, placer: window);
        expect(await c.captureFrontmost(), isNotNull, reason: label);
        desktop.windows.clear();
        if (successor != null) desktop.windows.add(successor);
        expect(await c.applyFrame(const WinRect(0, 0, 960, 1040)), isFalse,
            reason: label);
        expect(window.writes, isEmpty, reason: label);
        expect(window.touches, 0, reason: label);
      }
    });

    test('applyFrame with nothing captured is false and touches nothing',
        () async {
      final window = FakeWindow(frame: const PxRect(0, 0, 800, 600));
      expect(await wc(placer: window).applyFrame(const WinRect(0, 0, 10, 10)),
          isFalse);
      expect(window.touches, 0);
    });

    test('a desktop that throws is a failed capture, not a crash', () async {
      expect(await wc(desktop: _ThrowingDesktop()).captureFrontmost(), isNull);
    });

    test('a capture that throws after finding its window leaves nothing '
        'captured, so applyFrame moves nothing', () async {
      final desktop = _NameThrowingDesktop()
        ..windows.add(windowFacts(0x10, pid: 7))
        ..foreground = 0x10;
      final window = FakeWindow(frame: const PxRect(0, 0, 800, 600));
      final c = wc(desktop: desktop, placer: window);
      expect(await c.captureFrontmost(), isNull);
      expect(await c.applyFrame(const WinRect(0, 0, 960, 1040)), isFalse);
      expect(window.writes, isEmpty);
      expect(window.touches, 0);
    });

    test('an elevated target is not placed, and was beeped at', () async {
      final desktop = FakeDesktop(ownPid: 1)
        ..windows.add(windowFacts(0x10, pid: 7))
        ..foreground = 0x10;
      final window = FakeWindow(frame: const PxRect(0, 0, 800, 600))
        ..deniedTouch = true;
      final c = wc(desktop: desktop, placer: window);
      await c.captureFrontmost();
      expect(await c.applyFrame(const WinRect(0, 0, 960, 1040)), isFalse);
      expect(window.beeps, 1);
    });
  });

  group('the overlay commit contract', () {
    // Notepad (0x10, pid 7) in front, and the window placement moves.
    (FakeDesktop, FakeWindow, WindowsWindowController) notepad() {
      final desktop = FakeDesktop(ownPid: 1)
        ..windows.add(windowFacts(0x10, pid: 7))
        ..foreground = 0x10;
      final window = FakeWindow(frame: const PxRect(0, 0, 800, 600));
      return (desktop, window, wc(desktop: desktop, placer: window));
    }

    const target = WinRect(0, 0, 960, 1040);

    test('every capture gets a new, larger id', () async {
      final (_, _, c) = notepad();
      await c.captureFrontmost();
      final first = c.captureId!;
      await c.captureFrontmost();
      expect(c.captureId!, greaterThan(first));
    });

    test('a commit for the current capture places it, exactly once',
        () async {
      final (_, window, c) = notepad();
      await c.captureFrontmost();
      final id = c.captureId!;
      expect(await c.applyOverlayCommit(id, target), isTrue);
      expect(window.frame, const PxRect(0, 0, 960, 1040));
      final writes = window.writes.length;
      expect(await c.applyOverlayCommit(id, target), isFalse,
          reason: 'a duplicate');
      expect(window.writes, hasLength(writes),
          reason: 'the duplicate moved nothing');
      expect(window.beeps, 0,
          reason: 'a refused duplicate is not a failed placement');
    });

    test('a commit naming an older capture is dropped', () async {
      final (_, window, c) = notepad();
      await c.captureFrontmost();
      final older = c.captureId!;
      await c.captureFrontmost();
      expect(await c.applyOverlayCommit(older, target), isFalse);
      expect(window.writes, isEmpty);
      expect(window.touches, 0);
      expect(window.beeps, 0);
    });

    test('a commit with nothing captured is dropped', () async {
      final (_, window, c) = notepad();
      expect(await c.applyOverlayCommit(1, target), isFalse);
      expect(window.writes, isEmpty);
    });

    test('after one session is committed, the next capture can be',
        () async {
      final (_, window, c) = notepad();
      await c.captureFrontmost();
      expect(await c.applyOverlayCommit(c.captureId!, target), isTrue);
      await c.captureFrontmost();
      expect(
          await c.applyOverlayCommit(
              c.captureId!, const WinRect(960, 0, 960, 1040)),
          isTrue);
      expect(window.frame, const PxRect(960, 0, 1920, 1040));
    });

    test('a commit that does not land beeps once; an elevated one is not '
        'beeped at twice', () async {
      final (_, hung, c) = notepad();
      hung.hung = true;
      await c.captureFrontmost();
      expect(await c.applyOverlayCommit(c.captureId!, target), isFalse);
      expect(hung.beeps, 1);

      final (_, elevated, c2) = notepad();
      elevated.deniedTouch = true;
      await c2.captureFrontmost();
      expect(await c2.applyOverlayCommit(c2.captureId!, target), isFalse);
      expect(elevated.beeps, 1, reason: 'placement beeped; the commit did not');
    });

    test('a commit whose window is gone beeps and moves nothing', () async {
      final (desktop, window, c) = notepad();
      await c.captureFrontmost();
      desktop.windows.clear();
      expect(await c.applyOverlayCommit(c.captureId!, target), isFalse);
      expect(window.writes, isEmpty);
      expect(window.beeps, 1);
    });
  });

  group('displays', () {
    test('screenFrames reads the runner reply, scale included', () async {
      answer = (call) => call.method == kScreenFrames
          ? [
              {'x': 0.0, 'y': 0.0, 'w': 1920.0, 'h': 1040.0, 'scale': 1.0},
              {'x': 1920.0, 'y': 0.0, 'w': 2880.0, 'h': 1560.0, 'scale': 1.5},
            ]
          : null;
      expect(await wc().screenFrames(), [
        display(0, 0, 1920, 1040, 1),
        display(1920, 0, 2880, 1560, 1.5),
      ]);
      expect(calls, [kScreenFrames]);
    });

    test('activeScreenFrame reads one display, or null when the runner names '
        'none', () async {
      answer = (call) =>
          {'x': -1920.0, 'y': 0.0, 'w': 1920.0, 'h': 1040.0, 'scale': 1.25};
      expect(await wc().activeScreenFrame(), display(-1920, 0, 1920, 1040, 1.25));
      answer = (call) => null;
      expect(await wc().activeScreenFrame(), isNull);
    });
  });

  group('displayFromReply', () {
    Map<String, Object?> valid() =>
        {'x': 0.0, 'y': 0.0, 'w': 100.0, 'h': 50.0, 'scale': 1.5};

    test('reads a well-formed display, integers included', () {
      expect(displayFromReply(valid()), display(0, 0, 100, 50, 1.5));
      expect(displayFromReply({'x': 1, 'y': 2, 'w': 3, 'h': 4, 'scale': 2}),
          display(1, 2, 3, 4, 2));
    });

    test('a missing, non-numeric or impossible field is no display', () {
      for (final key in ['x', 'y', 'w', 'h', 'scale']) {
        expect(displayFromReply(valid()..remove(key)), isNull, reason: 'no $key');
        expect(displayFromReply(valid()..[key] = 'wide'), isNull, reason: key);
      }
      expect(displayFromReply(valid()..['w'] = 0.0), isNull);
      expect(displayFromReply(valid()..['h'] = -1.0), isNull);
      expect(displayFromReply(valid()..['scale'] = 0.0), isNull);
      expect(displayFromReply(valid()..['scale'] = double.nan), isNull);
      expect(displayFromReply(null), isNull);
      expect(displayFromReply([1, 2]), isNull);
    });
  });

  group('displaysFromReply', () {
    test('one bad entry empties the list', () {
      expect(
          displaysFromReply([
            {'x': 0.0, 'y': 0.0, 'w': 100.0, 'h': 50.0, 'scale': 1.0},
            {'x': 100.0, 'y': 0.0, 'w': 100.0, 'h': 50.0},
          ]),
          isEmpty,
          reason: 'displayContaining falls back to the first display, so a '
              'list missing the window\'s own display would fling it away');
    });

    test('anything but a list is no displays', () {
      expect(displaysFromReply(null), isEmpty);
      expect(displaysFromReply({'x': 0}), isEmpty);
    });
  });

  group('the overlay over the channel', () {
    test('the grid reaches the runner as plain numbers', () async {
      Object? sent;
      answer = (call) {
        sent = call.arguments;
        return null;
      };
      await wc().setOverlayGrid(cols: 4, rows: 3, gap: 8, saveHint: true);
      expect(calls, [kSetOverlayGrid]);
      expect(sent, {'cols': 4, 'rows': 3, 'gap': 8.0, 'saveHint': true});
    });

    test('a summon captures first, then names the session by the capture id',
        () async {
      final desktop = FakeDesktop(ownPid: 1)
        ..windows.add(windowFacts(0x10, pid: 7))
        ..foreground = 0x10
        ..names[7] = 'Notepad';
      Object? sent;
      answer = (call) {
        sent = call.arguments;
        return true;
      };
      final c = wc(
          desktop: desktop,
          placer: FakeWindow(frame: const PxRect(0, 0, 800, 600)));
      await c.showOverlay();
      expect(calls, [kShowOverlay],
          reason: 'a summon that showed hides nothing');
      expect(sent, {'captureId': c.captureId, 'appName': 'Notepad'},
          reason: 'a summon with no press sends no pressedAtMs');
      expect(c.captureId, isNotNull);
    });

    test('a summon sends the press that asked for it, for the stale check',
        () async {
      final desktop = FakeDesktop(ownPid: 1)
        ..windows.add(windowFacts(0x10, pid: 7))
        ..foreground = 0x10
        ..names[7] = 'Notepad';
      Object? sent;
      answer = (call) {
        sent = call.arguments;
        return true;
      };
      final c = wc(
          desktop: desktop,
          placer: FakeWindow(frame: const PxRect(0, 0, 800, 600)));
      await c.showOverlay(pressedAtMs: 1234.5);
      expect(sent, {
        'captureId': c.captureId,
        'appName': 'Notepad',
        'pressedAtMs': 1234.5,
      });
    });

    test('nothing to capture: a beep, and the runner is told to hide',
        () async {
      final window = FakeWindow(frame: const PxRect(0, 0, 800, 600));
      await wc(desktop: FakeDesktop(ownPid: 1), placer: window).showOverlay();
      expect(calls, [kHideOverlay],
          reason: 'a grid still open names the capture just cleared');
      expect(window.beeps, 1);
    });

    test('a summon the runner refuses leaves nothing applied', () async {
      final desktop = FakeDesktop(ownPid: 1)
        ..windows.add(windowFacts(0x10, pid: 7))
        ..foreground = 0x10;
      answer = (_) => false;
      final window = FakeWindow(frame: const PxRect(0, 0, 800, 600));
      final c = wc(desktop: desktop, placer: window);
      await c.showOverlay();
      expect(window.writes, isEmpty);
      expect(window.beeps, 0, reason: 'the runner beeps for its own refusal');
    });

    test('a summon the runner refuses ends any grid still open', () async {
      // The capture slot was just replaced, so an earlier summon's grid names
      // a capture that no longer exists; a stale press is refused before the
      // runner replaces that grid's session, so Dart must end it.
      final desktop = FakeDesktop(ownPid: 1)
        ..windows.add(windowFacts(0x10, pid: 7))
        ..foreground = 0x10;
      answer = (call) => call.method == kShowOverlay ? false : null;
      await wc(
              desktop: desktop,
              placer: FakeWindow(frame: const PxRect(0, 0, 800, 600)))
          .showOverlay(pressedAtMs: 1);
      expect(calls, [kShowOverlay, kHideOverlay]);
    });

    group('a capture that replaces the slot', () {
      WindowsWindowController shown() {
        final desktop = FakeDesktop(ownPid: 1)
          ..windows.add(windowFacts(0x10, pid: 7))
          ..foreground = 0x10;
        answer = (call) => call.method == kShowOverlay ? true : null;
        return wc(
            desktop: desktop,
            placer: FakeWindow(frame: const PxRect(0, 0, 800, 600)));
      }

      test('ends a grid still open, before capturing', () async {
        // A shortcut pressed just before the grid showed waits behind the
        // summon in the command queue; its capture would leave the grid on a
        // capture that no longer exists.
        final c = shown();
        await c.showOverlay();
        final grid = c.captureId;
        await c.captureFrontmost();
        expect(calls, [kShowOverlay, kHideOverlay]);
        expect(c.captureId, isNot(grid));
      });

      test('hides nothing once a commit has closed the grid', () async {
        final c = shown();
        await c.showOverlay();
        await c.applyOverlayCommit(c.captureId!, const WinRect(0, 0, 400, 300));
        await c.captureFrontmost();
        expect(calls, [kShowOverlay]);
      });

      test('hides nothing after the grid was hidden', () async {
        final c = shown();
        await c.showOverlay();
        await c.hideOverlay();
        await c.captureFrontmost();
        expect(calls, [kShowOverlay, kHideOverlay]);
      });

      test('ends the grid even when the capture then finds nothing', () async {
        // The slot is cleared either way, so the grid's capture is gone.
        final desktop = FakeDesktop(ownPid: 1)
          ..windows.add(windowFacts(0x10, pid: 7))
          ..foreground = 0x10;
        answer = (call) => call.method == kShowOverlay ? true : null;
        final c = wc(
            desktop: desktop,
            placer: FakeWindow(frame: const PxRect(0, 0, 800, 600)));
        await c.showOverlay();
        desktop.windows.clear();
        desktop.foreground = 0;
        expect(await c.captureFrontmost(), isNull);
        expect(calls, [kShowOverlay, kHideOverlay]);
      });

      test('a failed hide captures nothing, and the next capture hides again',
          () async {
        // The grid may still be up: its capture stays, and nothing escapes
        // into the command queue.
        final c = shown();
        await c.showOverlay();
        final grid = c.captureId;
        answer = (call) => call.method == kHideOverlay
            ? throw PlatformException(code: 'gone')
            : null;
        expect(await c.captureFrontmost(), isNull);
        expect(c.captureId, grid);
        answer = (_) => null;
        calls.clear();
        expect(await c.captureFrontmost(), isNotNull);
        expect(calls, [kHideOverlay]);
      });

      test('a stale commit leaves the newer grid open', () async {
        // A commit from a grid a newer summon replaced is dropped, and must
        // not mark the newer grid closed: a capture after it ends that grid.
        final c = shown();
        await c.showOverlay();
        final first = c.captureId!;
        await c.showOverlay();
        expect(
            await c.applyOverlayCommit(first, const WinRect(0, 0, 400, 300)),
            isFalse);
        calls.clear();
        await c.captureFrontmost();
        expect(calls, [kHideOverlay]);
      });

      test('a second summon leaves replacing the grid to the runner', () async {
        // The runner ends a live session when a new summon shows (its
        // "replaced" path): Dart sends no hide of its own on that path.
        final c = shown();
        await c.showOverlay();
        await c.showOverlay();
        expect(calls, [kShowOverlay, kShowOverlay]);
      });

      test('hides nothing after a refused summon', () async {
        final c = shown();
        answer = (_) => false;
        await c.showOverlay();
        calls.clear();
        await c.captureFrontmost();
        expect(calls, isEmpty);
      });
    });

    test('hideOverlay asks the runner', () async {
      await wc().hideOverlay();
      expect(calls, [kHideOverlay]);
    });
  });
}
