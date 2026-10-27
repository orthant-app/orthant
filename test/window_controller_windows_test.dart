import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/channel.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/core/window_controller_windows.dart';
import 'package:orthant/core/windows_language_store.dart';
import 'package:orthant/core/windows_login_item.dart';
import 'package:orthant/core/windows_updater.dart';
import 'package:orthant/core/windows_window_ops.dart';

import 'support/fake_win32.dart';

/// WinSparkle as a record of calls.
class _Sparkle implements SparkleApi {
  final calls = <String>[];

  @override
  void setRegistryPath(String path) {}
  @override
  void setAppcastUrl(String url) {}
  @override
  bool setEdDsaPublicKey(String key) => true;
  @override
  void setAppDetails(String company, String app, String version) {}
  @override
  void setAppBuildVersion(String build) {}
  @override
  void setAutomaticCheck(bool on) => calls.add('automatic $on');
  @override
  void setShutdownRequestCallback(void Function() onRequest) {}
  @override
  void setSkippedCallback(void Function() onSkipped) {}
  @override
  void setNotFoundCallback(void Function() onNotFound) {}
  @override
  void init() => calls.add('init');
  @override
  void checkWithUi() => calls.add('check');
}

/// The update settings; `throws` makes every read and write throw, as a
/// broken registry would, and `throwsOnSet` only the setting's change.
class _Store implements UpdateStore {
  bool? automatic = true;
  bool throws = false;
  bool throwsOnSet = false;

  @override
  bool? readAutomaticChecks() {
    if (throws) throw StateError('broken');
    return automatic;
  }

  @override
  void writeAutomaticChecks(bool on) {
    if (throws || throwsOnSet) throw StateError('broken');
    automatic = on;
  }

  @override
  int? readLastCheck() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
  @override
  void writeLastCheck(int seconds) {}
  AvailableUpdate? found;
  @override
  AvailableUpdate? readFound() => found;
  @override
  void writeFound(AvailableUpdate? update) => found = update;
  @override
  String? readSkipped() => null;
}

/// The stored language choice, held in memory.
class _Language implements LanguageStore {
  String? stored;
  final List<String?> writes = [];

  @override
  String? read() => stored;

  @override
  void write(String? tag) {
    writes.add(tag);
    stored = tag;
  }
}

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

/// The two registry values launch at login lives in, held in memory.
class _Startup implements StartupRegistry {
  String? run;
  Uint8List? approved;
  bool throws = false;
  bool refuses = false;
  final List<String> writes = [];

  @override
  RegRead<String> readRun() {
    if (throws) throw StateError('advapi32 went away');
    return run == null
        ? (found: RegFound.absent, data: null)
        : (found: RegFound.present, data: run);
  }

  @override
  RegRead<Uint8List> readApproved() => approved == null
      ? (found: RegFound.absent, data: null)
      : (found: RegFound.present, data: approved);

  @override
  bool writeRun(String command) {
    writes.add('write $command');
    if (refuses) return false;
    run = command;
    return true;
  }

  @override
  bool deleteRun() {
    writes.add('delete');
    if (refuses) return false;
    run = null;
    return true;
  }
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

  test('the accent is read from the palette, never from the runner', () async {
    final palette = Uint8List.fromList([
      for (var i = 0; i < 8; i++) ...[i * 16, i * 16 + 1, i * 16 + 2, 0],
    ]);
    WindowsWindowController withReader(Uint8List? Function() read) =>
        WindowsWindowController.forTest(
            readVersion: () => null,
            desktop: NoWindows(),
            placer: NoWindows(),
            readAccentPalette: read);
    expect(
        await withReader(() => palette).accentColor(),
        const AccentColors(
            light: 0xFF404142,
            dark: 0xFF101112,
            linkLight: 0xFF505152,
            linkDark: 0xFF000102));
    expect(await withReader(() => null).accentColor(), isNull);
    expect(await withReader(() => throw StateError('advapi32 went away'))
        .accentColor(), isNull, reason: 'display data never throws');
    expect(calls, isEmpty);
  });

  group('language', () {
    WindowsWindowController withLanguage(
            {List<Locale> Function()? systemLocales, LanguageStore? store}) =>
        WindowsWindowController.forTest(
            readVersion: () => null,
            desktop: NoWindows(),
            placer: NoWindows(),
            systemLocales: systemLocales,
            languageStore: store);

    test('the system languages are the OS list, in its order', () async {
      final wanted = [
        Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
        const Locale('en', 'US'),
      ];
      expect(await withLanguage(systemLocales: () => wanted).systemLocales(),
          wanted);
      expect(calls, isEmpty, reason: 'the runner knows nothing about it');
    });

    test('with no function injected they are the platform dispatcher\'s',
        () async {
      expect(await withLanguage().systemLocales(),
          PlatformDispatcher.instance.locales);
    });

    test('the stored choice round trips as the whole tag', () async {
      final store = _Language();
      final c = withLanguage(store: store);
      expect(await c.languageOverride(), isNull);
      await c.setLanguageOverride('zh-Hant-HK');
      expect(store.stored, 'zh-Hant-HK');
      expect(await c.languageOverride(), 'zh-Hant-HK');
      await c.setLanguageOverride('en');
      expect(await c.languageOverride(), 'en');
      expect(calls, isEmpty, reason: 'Windows keeps this in the registry');
    });

    test('System is null, which clears the stored choice', () async {
      final store = _Language()..stored = 'zh-Hans';
      final c = withLanguage(store: store);
      await c.setLanguageOverride(null);
      expect(store.writes, [null]);
      expect(await c.languageOverride(), isNull);
    });

    test('a garbage stored value is returned as it is', () async {
      // Task 2's resolver reads an unparsable choice as System; this seam
      // neither validates nor repairs what the user's registry holds.
      for (final garbage in ['!!', 'klingon-QQ-x', ' zh ']) {
        final c = withLanguage(store: _Language()..stored = garbage);
        expect(await c.languageOverride(), garbage);
      }
    });
  });

  group('launch at login', () {
    const exe = r'C:\Programs\Orthant\Orthant.exe';
    late _Startup startup;
    late int opened;
    WindowsWindowController login({bool opens = true}) =>
        WindowsWindowController.forTest(
          readVersion: () => null,
          desktop: NoWindows(),
          placer: NoWindows(),
          startup: startup,
          exePath: () => exe,
          openStartupApps: () {
            opened++;
            return opens;
          },
        );
    setUp(() {
      startup = _Startup();
      opened = 0;
    });

    test('reads the Run value and its StartupApproved record', () async {
      expect(await login().loginItemStatus(), LoginItemStatus.disabled);
      startup.run = '"$exe"';
      expect(await login().loginItemStatus(), LoginItemStatus.enabled);
      startup.approved = Uint8List.fromList([3, 0, 0, 0]);
      expect(await login().loginItemStatus(), LoginItemStatus.requiresApproval);
      expect(calls, isEmpty, reason: 'a registry read needs no window');
    });

    test('on writes this executable, quoted; off deletes the value', () async {
      final c = login();
      expect(await c.setLoginItem(true), LoginItemStatus.enabled);
      expect(startup.run, '"$exe"');
      expect(await c.setLoginItem(false), LoginItemStatus.disabled);
      expect(startup.run, isNull);
      expect(startup.writes, ['write "$exe"', 'delete']);
      expect(calls, isEmpty);
    });

    test("turning it on never overrides the user's off in Startup apps",
        () async {
      // Measured: Task Manager keeps a disabled record across a rewrite of
      // the Run value, so the status after the write says so; the record is
      // Windows' and is never written here.
      startup.approved = Uint8List.fromList([1, 0, 0, 0, 9, 9, 9, 9]);
      expect(await login().setLoginItem(true),
          LoginItemStatus.requiresApproval);
      expect(startup.approved, [1, 0, 0, 0, 9, 9, 9, 9]);
    });

    test('the answer is what the registry says after the write, not the ask',
        () async {
      startup.refuses = true;
      expect(await login().setLoginItem(true), LoginItemStatus.disabled);
      startup
        ..refuses = false
        ..run = '"$exe"'
        ..refuses = true;
      expect(await login().setLoginItem(false), LoginItemStatus.enabled);
    });

    test('a registry that throws reads as unavailable, never as a throw',
        () async {
      startup.throws = true;
      expect(await login().loginItemStatus(), LoginItemStatus.unavailable);
      expect(await login().setLoginItem(true), LoginItemStatus.unavailable);
    });

    test("opens Settings' Startup apps page, never through the channel",
        () async {
      await login().openLoginItemsSettings();
      await login(opens: false).openLoginItemsSettings();
      expect(opened, 2);
      expect(calls, isEmpty);
    });
  });

  test('with no updater started, the update calls answer safely and never '
      'reach the channel', () async {
    final c = wc();
    expect(await c.automaticUpdateChecks(), isFalse);
    expect(await c.setAutomaticUpdateChecks(true), isFalse);
    await c.checkForUpdates();
    expect(calls, isEmpty,
        reason: 'the updater is FFI; the runner has no handler for these');
  });

  group('updates', () {
    ({WindowsWindowController c, _Sparkle api, _Store store}) started(
        {AvailableUpdate? found}) {
      final api = _Sparkle();
      final store = _Store()..found = found;
      final updater = WindowsUpdater(api, store,
          (url) => Future.error(StateError('no feed in this test')),
          feedUrl: 'f',
          publicKey: 'k',
          system: () => (major: 10, minor: 0, build: 22631, servicePack: 0))
        ..start(build: '8', display: '1.1.0', onShutdownRequested: () {});
      api.calls.clear();
      return (
        c: WindowsWindowController.forTest(
            readVersion: () => (short: '1.1.0', build: '8'),
            desktop: NoWindows(),
            placer: NoWindows(),
            updater: updater),
        api: api,
        store: store,
      );
    }

    test('Check for Updates opens WinSparkle\'s window', () async {
      final t = started();
      await t.c.checkForUpdates();
      expect(t.api.calls, ['check']);
      expect(calls, isEmpty);
    });

    test('what a check found reaches the seam, as the updater holds it',
        () async {
      final t = started(found: const AvailableUpdate('1.0.4', 9));
      expect(t.c.availableUpdate.value, const AvailableUpdate('1.0.4', 9));
      expect(started().c.availableUpdate.value, isNull);
    });

    test('the setting is what is stored after the change', () async {
      final t = started();
      expect(await t.c.automaticUpdateChecks(), isTrue);
      expect(await t.c.setAutomaticUpdateChecks(false), isFalse);
      expect(await t.c.automaticUpdateChecks(), isFalse);
    });

    test('a broken store is answered as nothing changed, never thrown into '
        'the pane', () async {
      final t = started();
      // A change that fails reads back as what is still stored: on.
      t.store.throwsOnSet = true;
      expect(await t.c.setAutomaticUpdateChecks(false), isTrue);
      // Nothing readable at all: off.
      t.store.throws = true;
      expect(await t.c.automaticUpdateChecks(), isFalse);
      expect(await t.c.setAutomaticUpdateChecks(false), isFalse);
    });
  });

  test('a release build names itself by its tag', () async {
    final c = WindowsWindowController.forTest(
        readVersion: () => (short: '1.1.0', build: '8'),
        desktop: NoWindows(),
        placer: NoWindows(),
        releaseName: '1.1.0-beta.1');
    final v = await c.appVersion();
    expect(v.display, '1.1.0-beta.1');
    expect(v.buildNumber, '8');
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
      await wc().setOverlayGrid(
          cols: 4, rows: 3, gap: 8, saveHint: true, locale: 'zh-Hant');
      expect(calls, [kSetOverlayGrid]);
      // The language rides with the grid because the overlay's engine cannot
      // ask for it (it has no preferences of its own to read).
      expect(sent, {
        'cols': 4,
        'rows': 3,
        'gap': 8.0,
        'saveHint': true,
        'locale': 'zh-Hant',
      });
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
      expect(sent, {'captureId': c.captureId, 'appName': 'Notepad', 'pid': 7},
          reason: 'a summon with no press sends no pressedAtMs, and with no '
              'cached icon no appIcon');
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
        'pid': 7,
        'pressedAtMs': 1234.5,
      });
    });

    group('the captured app\'s icon', () {
      // Read off the summon path (SHGetFileInfo can block), cached by
      // executable, and sent to the open grid once it is read.
      final png = Uint8List.fromList([1, 2, 3]);
      late List<MethodCall> sentCalls;
      late List<String> asked;
      late Completer<Uint8List?> reading;

      setUp(() {
        sentCalls = [];
        asked = [];
        reading = Completer();
        answer = (call) {
          sentCalls.add(call);
          return call.method == kShowOverlay ? true : null;
        };
      });

      WindowsWindowController notepad(
          {FakeDesktop? desktop, Map<String, Completer<Uint8List?>>? reads}) {
        final d = desktop ??
            (FakeDesktop(ownPid: 1)
              ..windows.add(windowFacts(0x10, pid: 7))
              ..foreground = 0x10
              ..names[7] = 'Notepad'
              ..paths[7] = r'C:\Windows\notepad.exe');
        return WindowsWindowController.forTest(
          readVersion: () => null,
          desktop: d,
          placer: FakeWindow(frame: const PxRect(0, 0, 800, 600)),
          clock: FakeClock(),
          readIcon: (exe) {
            asked.add(exe);
            return (reads?[exe] ?? reading).future;
          },
        );
      }

      Map<Object?, Object?> argsOf(String method, [int nth = 0]) =>
          sentCalls.where((c) => c.method == method).elementAt(nth).arguments
              as Map<Object?, Object?>;

      test('is read once, sent to the open grid, then carried by the summon',
          () async {
        final c = notepad();
        await c.showOverlay();
        final first = c.captureId;
        expect(argsOf(kShowOverlay).containsKey('appIcon'), isFalse,
            reason: 'nothing cached yet: the summon does not wait for it');
        expect(asked, [r'C:\Windows\notepad.exe']);
        reading.complete(png);
        await pumpEventQueue();
        expect(argsOf(kSetAppIcon), {'sessionId': first, 'png': png});

        await c.showOverlay();
        expect(argsOf(kShowOverlay, 1)['appIcon'], png);
        expect(asked, hasLength(1), reason: 'cached by executable');
        expect(sentCalls.where((c) => c.method == kSetAppIcon), hasLength(1));
      });

      test('goes to the open grid of its app, whichever summon asked',
          () async {
        final c = notepad();
        await c.showOverlay();
        await c.showOverlay();
        final second = c.captureId;
        expect(asked, hasLength(1), reason: 'one read in flight per app');
        reading.complete(png);
        await pumpEventQueue();
        expect(argsOf(kSetAppIcon), {'sessionId': second, 'png': png});
      });

      test('for an app no longer in front is kept, not sent to another\'s '
          'grid', () async {
        final desktop = FakeDesktop(ownPid: 1)
          ..windows.add(windowFacts(0x10, pid: 7))
          ..foreground = 0x10
          ..paths[7] = r'C:\Windows\notepad.exe'
          ..paths[8] = r'C:\Windows\regedit.exe';
        // Registry Editor's own read never finishes here.
        final c = notepad(
            desktop: desktop,
            reads: {r'C:\Windows\regedit.exe': Completer<Uint8List?>()});
        await c.showOverlay();
        desktop.windows
          ..clear()
          ..add(windowFacts(0x20, pid: 8, className: 'RegEdit_RegEdit'));
        desktop.foreground = 0x20;
        await c.showOverlay();
        reading.complete(png);
        await pumpEventQueue();
        expect(sentCalls.where((c) => c.method == kSetAppIcon), isEmpty,
            reason: 'Notepad\'s icon on Registry Editor\'s grid');
      });

      test('that arrives after its grid closed is kept, not sent', () async {
        final c = notepad();
        await c.showOverlay();
        await c.hideOverlay();
        reading.complete(png);
        await pumpEventQueue();
        expect(sentCalls.where((c) => c.method == kSetAppIcon), isEmpty);
        await c.showOverlay();
        expect(argsOf(kShowOverlay, 1)['appIcon'], png);
      });

      test('an app with none is not asked about again', () async {
        final c = notepad();
        await c.showOverlay();
        reading.complete(null);
        await pumpEventQueue();
        await c.showOverlay();
        expect(sentCalls.where((c) => c.method == kSetAppIcon), isEmpty);
        expect(argsOf(kShowOverlay, 1).containsKey('appIcon'), isFalse);
        expect(asked, hasLength(1));
      });

      test('a read that throws costs only the chip, and is tried again',
          () async {
        final c = notepad();
        await c.showOverlay();
        reading.completeError(StateError('isolate went away'));
        await pumpEventQueue();
        expect(sentCalls.where((c) => c.method == kSetAppIcon), isEmpty);
        reading = Completer();
        await c.showOverlay();
        expect(asked, hasLength(2));
      });

      test('a send that fails keeps the icon for the next summon', () async {
        answer = (call) {
          sentCalls.add(call);
          if (call.method == kSetAppIcon) {
            throw PlatformException(code: 'gone');
          }
          return call.method == kShowOverlay ? true : null;
        };
        final c = notepad();
        await c.showOverlay();
        reading.complete(png);
        await pumpEventQueue();
        await c.showOverlay();
        expect(argsOf(kShowOverlay, 1)['appIcon'], png);
        expect(asked, hasLength(1), reason: 'read once, kept, carried');
      });

      test('a read that lands while the next summon is in flight reaches '
          'that summon\'s grid', () async {
        // The first summon's read is still going when its grid closes; the
        // second summon goes out with no icon, none being cached yet, and the
        // read lands before its reply, when no grid of this app is open.
        final held = Completer<bool>();
        var shows = 0;
        answer = (call) {
          sentCalls.add(call);
          if (call.method != kShowOverlay) return null;
          return ++shows == 2 ? held.future : true;
        };
        final c = notepad();
        await c.showOverlay();
        await c.hideOverlay();
        final second = c.showOverlay();
        await pumpEventQueue();
        reading.complete(png);
        await pumpEventQueue();
        expect(argsOf(kShowOverlay, 1).containsKey('appIcon'), isFalse);
        expect(sentCalls.where((c) => c.method == kSetAppIcon), isEmpty);
        held.complete(true);
        await second;
        await pumpEventQueue();
        expect(argsOf(kSetAppIcon), {'sessionId': c.captureId, 'png': png});
        expect(asked, hasLength(1));
      });

      test('a window whose executable cannot be named asks for nothing',
          () async {
        final c = notepad(
            desktop: FakeDesktop(ownPid: 1)
              ..windows.add(windowFacts(0x10, pid: 7))
              ..foreground = 0x10);
        await c.showOverlay();
        expect(asked, isEmpty);
        expect(argsOf(kShowOverlay).containsKey('appIcon'), isFalse);
      });

      test('a summon the runner refuses asks for nothing', () async {
        answer = (call) {
          sentCalls.add(call);
          return call.method == kShowOverlay ? false : null;
        };
        await notepad().showOverlay();
        expect(asked, isEmpty, reason: 'no grid will show it');
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

      test('a summon that finds nothing marks the grid closed', () async {
        // Its hide goes through hideOverlay, so a capture after it has no
        // grid left to end.
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
        await c.showOverlay();
        desktop.windows.add(windowFacts(0x10, pid: 7));
        desktop.foreground = 0x10;
        calls.clear();
        await c.captureFrontmost();
        expect(calls, isEmpty);
      });

      test('a refused summon whose hide fails leaves the grid marked open',
          () async {
        // The runner can refuse before it replaces the live session, so the
        // old grid may still be up: the next capture tries the hide again.
        final c = shown();
        await c.showOverlay();
        answer = (call) => switch (call.method) {
              kShowOverlay => false,
              kHideOverlay => throw PlatformException(code: 'gone'),
              _ => null,
            };
        await expectLater(c.showOverlay(), throwsA(isA<PlatformException>()));
        answer = (_) => null;
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

    test('startOverlay asks the runner, and a failure there stays there',
        () async {
      await wc().startOverlay();
      expect(calls, [kStartOverlay]);
      // The runner's deadline starts the engines anyway; launch, which awaits
      // this last, must not fail for it.
      answer = (_) => throw PlatformException(code: 'gone');
      await expectLater(wc().startOverlay(), completes);
    });

    test('setCommandsRunning tells the runner, and a failure there stays '
        'there', () async {
      final sent = <Object?>[];
      answer = (call) {
        sent.add(call.arguments);
        return null;
      };
      await wc().setCommandsRunning(true);
      await wc().setCommandsRunning(false);
      expect(calls, [kSetCommandsRunning, kSetCommandsRunning]);
      expect(sent, [
        {'running': true},
        {'running': false},
      ]);
      // A command must never fail for its bracket: the runner has a ceiling.
      answer = (_) => throw PlatformException(code: 'gone');
      await expectLater(wc().setCommandsRunning(true), completes);
    });

    test('hideOverlay asks the runner', () async {
      await wc().hideOverlay();
      expect(calls, [kHideOverlay]);
    });

    group('a hide names the grid it ends', () {
      // So a hide meant for one grid can never end a newer one: the runner
      // dismisses only the live session it names.
      late List<Object?> hides;
      setUp(() {
        hides = [];
        answer = (call) {
          if (call.method == kHideOverlay) hides.add(call.arguments);
          return call.method == kShowOverlay ? true : null;
        };
      });

      WindowsWindowController withNotepad(FakeDesktop desktop) => wc(
          desktop: desktop
            ..windows.add(windowFacts(0x10, pid: 7))
            ..foreground = 0x10,
          placer: FakeWindow(frame: const PxRect(0, 0, 800, 600)));

      test('a capture over an open grid names that grid', () async {
        final c = withNotepad(FakeDesktop(ownPid: 1));
        await c.showOverlay();
        final grid = c.captureId;
        await c.captureFrontmost();
        expect(hides, [
          {'sessionId': grid},
        ]);
      });

      test('a refused summon names the grid that was open before it',
          () async {
        final c = withNotepad(FakeDesktop(ownPid: 1));
        await c.showOverlay();
        final grid = c.captureId;
        answer = (call) {
          if (call.method == kHideOverlay) hides.add(call.arguments);
          return call.method == kShowOverlay ? false : null;
        };
        await c.showOverlay();
        expect(hides, [
          {'sessionId': grid},
        ], reason: 'the refused summon\'s own capture never had a grid');
      });

      test('with no grid ever shown, it names none', () async {
        await wc().hideOverlay();
        expect(hides, [
          {'sessionId': -1},
        ]);
      });
    });
  });
}
