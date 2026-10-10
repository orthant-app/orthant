import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/channel.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/core/key_chord.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/hotkey_service.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

import 'support/carbon_terms.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(kOrthantChannel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('layout notifications arrive before Accessibility enables shortcuts', () async {
    var changes = 0;
    HotkeyService(onCommand: (_) {}, onKeyboardLayoutChanged: () => changes++);
    // First-run onboarding has not called apply(), but its labels must update.
    await messenger.handlePlatformMessage(
      kOrthantChannel,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onKeyboardLayoutChanged')),
      (_) {},
    );
    expect(changes, 1);
  });

  /// Records the ids `apply` asks the native side to register. [reply] decides
  /// what the OS "says" for each id; the default is that every chord is taken.
  List<int> captureIds({bool Function(int id)? reply}) {
    final ids = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'replaceHotkeys') return null;
      final entries =
          (call.arguments as Map)['bindings'] as List<Object?>;
      final refused = <int>[];
      for (final e in entries) {
        final id = (e as Map)['id'] as int;
        ids.add(id);
        if (!(reply?.call(id) ?? true)) refused.add(id);
      }
      return refused;
    });
    return ids;
  }

  test('apply registers one hotkey per binding with id = command index',
      () async {
    final ids = captureIds();
    await HotkeyService(onCommand: (_) {}).apply(macDefaults);
    expect(ids.toSet(),
        {for (final b in macDefaults) (b.command as BuiltIn).command.index});
  });

  test('apply replaces the whole set in a single native call', () async {
    // The old shape was `unregisterAllHotkeys` followed by eleven separately
    // awaited `registerHotkey` calls. Two callers overlapping in that window —
    // a rebind and a window close, say — could have the newer one unregister
    // everything while the older one was mid-loop, after which the older loop
    // re-registered a combo the UI had already moved on from. One call cannot
    // interleave with itself: the native side does the whole swap inside one
    // handler invocation, on the main thread.
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <int>[];
    });
    await HotkeyService(onCommand: (_) {}).apply(macDefaults);

    expect(calls.map((c) => c.method).toList(), ['replaceHotkeys']);
    final sent = (calls.single.arguments as Map)['bindings'] as List<Object?>;
    expect(sent.length, macDefaults.length,
        reason: 'the call carries the entire snapshot, not a delta');
  });

  test('the summon is registered like any other binding', () async {
    // No longer a bespoke reserved id registered outside the loop: it is simply
    // the first entry in the list, which is what lets it share the recorder,
    // the persistence and the collision check with the ten placements.
    final ids = captureIds();
    await HotkeyService(onCommand: (_) {}, onSummon: ({pressedAtMs}) {})
        .apply(macDefaults);
    expect(ids, contains(ShortcutCommand.showGrid.index));
  });

  test('apply skips unbound commands', () async {
    final ids = captureIds();
    final bindings = withRebind(macDefaults,
        Binding(BuiltIn(ShortcutCommand.leftHalf), carbon(124, kControlOption)));
    await HotkeyService(onCommand: (_) {}).apply(bindings);

    // rightHalf lost its combo to leftHalf, so it must not be registered.
    expect(ids, isNot(contains(ShortcutCommand.rightHalf.index)));
    expect(ids.length, macDefaults.length - 1);
  });

  test('the native side is sent exactly what 1.0.3 sent for the defaults',
      () async {
    // The registration half of "macOS behaves exactly as before". Typed out,
    // not derived: a list computed through carbon_keys.dart would share any
    // mistake in it.
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <int>[];
    });
    await HotkeyService(onCommand: (_) {}).apply(macDefaults);
    expect((calls.single.arguments as Map)['bindings'], [
      {'id': 0, 'keyCode': 31, 'modifiers': 6144},
      {'id': 1, 'keyCode': 123, 'modifiers': 6144},
      {'id': 2, 'keyCode': 124, 'modifiers': 6144},
      {'id': 3, 'keyCode': 126, 'modifiers': 6144},
      {'id': 4, 'keyCode': 125, 'modifiers': 6144},
      {'id': 5, 'keyCode': 32, 'modifiers': 6144},
      {'id': 6, 'keyCode': 34, 'modifiers': 6144},
      {'id': 7, 'keyCode': 38, 'modifiers': 6144},
      {'id': 8, 'keyCode': 40, 'modifiers': 6144},
      {'id': 9, 'keyCode': 36, 'modifiers': 6144},
      {'id': 10, 'keyCode': 8, 'modifiers': 6144},
    ]);
  });

  test('a chord with no Carbon code is reported refused, and never sent',
      () async {
    // Nothing in this build produces one (carbon_keys_test proves every
    // bindable key has a code), so this guards that proof: if the two drift,
    // the row says "unavailable" instead of looking live and doing nothing.
    final ids = captureIds();
    final orphan = KeyChord(
      physical: 0x00070032,
      logical: LogicalKeyboardKey.backslash.keyId,
      modifiers: Modifiers.ctrl | Modifiers.alt,
    );
    final bindings = [
      for (final b in macDefaults)
        b.command == const BuiltIn(ShortcutCommand.center)
            ? Binding(b.command, orphan)
            : b,
    ];
    final refused = await HotkeyService(onCommand: (_) {}).apply(bindings);
    expect(ids, isNot(contains(ShortcutCommand.center.index)));
    expect(refused, {const BuiltIn(ShortcutCommand.center)});
  });

  test('unregisterAll drops every native hotkey', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return null;
    });
    await HotkeyService(onCommand: (_) {}).unregisterAll();
    expect(methods, ['unregisterAllHotkeys']);
  });

  test('an incoming showGrid id summons rather than placing a window', () async {
    var summons = 0;
    CommandRef? placed;
    final svc =
        HotkeyService(
        onCommand: (c) => placed = c, onSummon: ({pressedAtMs}) => summons++);
    messenger.setMockMethodCallHandler(channel, (_) async => <int>[]);
    await svc.apply(macDefaults);

    await svc.debugHandle(ShortcutCommand.showGrid.index);
    expect(summons, 1);
    expect(placed, isNull, reason: 'the summon places nothing itself');
  });

  test('an incoming onHotkey dispatches the mapped region command', () async {
    CommandRef? got;
    final svc = HotkeyService(onCommand: (c) => got = c);
    messenger.setMockMethodCallHandler(channel, (_) async => <int>[]);
    await svc.apply(macDefaults);
    await svc.debugHandle(ShortcutCommand.maximize.index);
    expect(got, const BuiltIn(ShortcutCommand.maximize));
  });

  test('an unknown id is ignored rather than dispatched', () async {
    // Esc-to-dismiss and Return-to-commit are grabbed natively at reserved ids
    // (900+) that never reach Dart, so a stray id must fall through harmlessly
    // rather than be mapped onto whatever command sits at that index.
    var commands = 0;
    var summons = 0;
    final svc =
        HotkeyService(
        onCommand: (_) => commands++, onSummon: ({pressedAtMs}) => summons++);
    messenger.setMockMethodCallHandler(channel, (_) async => <int>[]);
    await svc.apply(macDefaults);

    await svc.debugHandle(901); // the native Esc grab's id
    await svc.debugHandle(ShortcutCommand.values.length);
    await svc.debugHandle(-1);
    expect(commands, 0);
    expect(summons, 0);
  });

  test('apply reports the combos the OS refused', () async {
    // Carbon rejects a chord macOS or another app already owns, and says so
    // only here. Without this the row keeps showing the combo and the shortcut
    // never fires — indistinguishable, from the user's side, from a broken app.
    const taken = ShortcutCommand.leftHalf;
    captureIds(reply: (id) => id != taken.index);
    final refused =
        await HotkeyService(onCommand: (_) {}).apply(macDefaults);
    expect(refused, {const BuiltIn(taken)});
  });

  test('a refused summon chord is reported like any other', () async {
    // ⌃⌥O can be taken by another app exactly as ⌃⌥← can. It now surfaces
    // through the same `unavailable` set the settings row already renders,
    // instead of the bespoke bool the ⌃⌥G spike needed.
    captureIds(reply: (id) => id != ShortcutCommand.showGrid.index);
    final refused = await HotkeyService(
            onCommand: (_) {}, onSummon: ({pressedAtMs}) {})
        .apply(macDefaults);
    expect(refused, {const BuiltIn(ShortcutCommand.showGrid)});
  });

  test('a reply that is not a list of ids counts as everything refused',
      () async {
    // Silence is the failure mode being guarded against, so it must not read
    // as success. A native side that answered `null` — not implemented, an
    // older build, an argument it could not parse — has registered nothing,
    // and the honest report is that no shortcut works.
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final refused =
        await HotkeyService(onCommand: (_) {}).apply(macDefaults);
    expect(refused, {for (final b in macDefaults) b.command});
  });

  test('a reply of the wrong shape degrades instead of throwing', () async {
    // This runs on the launch path, before any window exists. A typed
    // invokeMethod would have thrown here and taken the app down over a reply
    // it could simply have disbelieved.
    messenger.setMockMethodCallHandler(channel, (_) async => true);
    final refused =
        await HotkeyService(onCommand: (_) {}).apply(macDefaults);
    expect(refused, {for (final b in macDefaults) b.command});
  });

  test('an unbound command is neither sent nor reported as refused', () async {
    // "No shortcut assigned" and "macOS would not give us this chord" look the
    // same in the list if the second is inferred from the first's absence.
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final bindings = withRebind(macDefaults,
        Binding(BuiltIn(ShortcutCommand.leftHalf), carbon(124, kControlOption)));
    final refused =
        await HotkeyService(onCommand: (_) {}).apply(bindings);
    expect(refused, isNot(contains(const BuiltIn(ShortcutCommand.rightHalf))));
  });

  test('a native placement failure reaches its callback', () async {
    // The grid is native end to end, so this channel message is its *only*
    // route into the permission recovery the direct shortcuts get by returning
    // through Dart. It is sent both when a commit does not land and when the
    // summon never captured a window at all — a revoked grant breaks capture
    // first, and that used to be answered with a beep and nothing else.
    var failures = 0;
    final svc =
        HotkeyService(onCommand: (_) {}, onPlacementFailed: () => failures++);
    messenger.setMockMethodCallHandler(channel, (_) async => <int>[]);
    await svc.apply(macDefaults); // installs the inbound handler
    await messenger.handlePlatformMessage(
      kOrthantChannel,
      const StandardMethodCodec()
          .encodeMethodCall(const MethodCall('onPlacementFailed')),
      (_) {},
    );
    expect(failures, 1);
  });

  test('a native config-window close reaches its callback', () async {
    // Closing the window with its own close button is the one path Dart never
    // initiates, so it can only arrive over the channel. Driven through a real
    // platform message rather than a debug hook, because the routing inside
    // the handler is the thing under test.
    var closes = 0;
    final svc =
        HotkeyService(onCommand: (_) {}, onConfigWindowClosed: () => closes++);
    messenger.setMockMethodCallHandler(channel, (_) async => <int>[]);
    await svc.apply(macDefaults); // installs the inbound handler
    await messenger.handlePlatformMessage(
      kOrthantChannel,
      const StandardMethodCodec()
          .encodeMethodCall(const MethodCall('onConfigWindowClosed')),
      (_) {},
    );
    expect(closes, 1);
  });

  group('ids come from the applied set', () {
    test('built-ins keep their enum indices', () async {
      final ids = captureIds();
      await HotkeyService(onCommand: (_) {}).apply(macDefaults);
      // _completed puts the eleven built-ins first in enum order, so indexing
      // the applied list reproduces the ids they have always had.
      expect(ids, [for (var i = 0; i < macDefaults.length; i++) i]);
    });

    test('a custom region gets an id past the built-ins, clear of 900',
        () async {
      final ids = captureIds();
      await HotkeyService(onCommand: (_) {}).apply([
        ...macDefaults,
        Binding(Custom('r1'), carbon(123, kControlOption | kShiftKey)),
      ]);

      expect(ids.last, macDefaults.length);
      expect(ids.last, lessThan(900),
          reason: 'the overlay reserves 900+ for its Esc/Return grabs');
    });

    test('dispatches a press to the ref that id was applied for', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => <int>[]);
      final fired = <CommandRef>[];
      final svc = HotkeyService(onCommand: fired.add);
      await svc.apply([
        ...macDefaults,
        Binding(Custom('r1'), carbon(123, kControlOption | kShiftKey)),
      ]);

      await svc.debugHandle(macDefaults.length);
      await svc.debugHandle(1); // leftHalf

      expect(fired, [
        const Custom('r1'),
        const BuiltIn(ShortcutCommand.leftHalf),
      ]);
    });

    test('an unbound row does not consume the id of the row after it', () async {
      // The id is the index in the *whole* list, not in the bound subset, so a
      // cleared shortcut leaves a hole rather than shifting everything after
      // it — which would silently re-point a press at its neighbour.
      final ids = captureIds();
      final bindings = [
        ...macDefaults,
        const Binding.unbound(Custom('gap')),
        Binding(Custom('r2'), carbon(123, kControlOption | kShiftKey)),
      ];
      await HotkeyService(onCommand: (_) {}).apply(bindings);

      expect(ids.last, macDefaults.length + 1);
    });

    test('refusals come back as the refs they were sent for', () async {
      captureIds(reply: (id) => id != 1);
      final refused =
          await HotkeyService(onCommand: (_) {}).apply(macDefaults);
      expect(refused, {const BuiltIn(ShortcutCommand.leftHalf)});
    });

    test('a press arriving before any apply is ignored', () async {
      var fired = 0;
      final svc = HotkeyService(onCommand: (_) => fired++);
      await svc.debugHandle(0);
      expect(fired, 0);
    });
  });

  Future<void> fromNative(String method, [Object? arguments]) =>
      messenger.handlePlatformMessage(
        kOrthantChannel,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );

  group('overlayCommitFrom', () {
    test('reads a whole commit', () {
      expect(
          overlayCommitFrom(
              {'sessionId': 7, 'x': 0.0, 'y': -2160.0, 'w': 1280.0, 'h': 1044.0}),
          (sessionId: 7, rect: const WinRect(0, -2160, 1280, 1044)));
    });

    test('takes integral numbers as numbers', () {
      expect(
          overlayCommitFrom({'sessionId': 7, 'x': 0, 'y': 0, 'w': 10, 'h': 10})
              ?.rect,
          const WinRect(0, 0, 10, 10));
    });

    test('refuses anything missing, mistyped or impossible', () {
      final whole = {'sessionId': 7, 'x': 0.0, 'y': 0.0, 'w': 10.0, 'h': 10.0};
      for (final (label, bad) in <(String, Object?)>[
        ('not a map', 7),
        ('null', null),
        ('no session', {...whole}..remove('sessionId')),
        ('a string session', {...whole, 'sessionId': '7'}),
        ('a double session', {...whole, 'sessionId': 7.0}),
        ('no x', {...whole}..remove('x')),
        ('a string width', {...whole, 'w': '10'}),
        ('an infinite height', {...whole, 'h': double.infinity}),
        ('a NaN x', {...whole, 'x': double.nan}),
        ('a zero width', {...whole, 'w': 0.0}),
        ('a negative height', {...whole, 'h': -1.0}),
        // Finite, but no coordinate SetWindowPos can take: narrowed to 32 bits
        // at the native boundary it would be a different, plausible rect.
        ('an unrepresentable width', {...whole, 'w': 4294968096.0}),
        ('an edge past the coordinate range',
            {...whole, 'x': 1073741000.0, 'w': 10000.0}),
      ]) {
        expect(overlayCommitFrom(bad), isNull, reason: label);
      }
    });
  });

  test('a commit from the runner reaches onOverlayCommit; a bad one does not',
      () async {
    final got = <(int, WinRect)>[];
    HotkeyService(
        onCommand: (_) {}, onOverlayCommit: (id, r) => got.add((id, r)));
    await fromNative(kOverlayCommit,
        {'sessionId': 3, 'x': 10.0, 'y': 20.0, 'w': 300.0, 'h': 400.0});
    await fromNative(kOverlayCommit, {'sessionId': 3, 'x': 10.0});
    expect(got, [(3, const WinRect(10, 20, 300, 400))]);
  });

  test('a save-region from the runner carries its block; no block, no call',
      () async {
    final got = <(int, WinRect, Map<Object?, Object?>)>[];
    HotkeyService(
        onCommand: (_) {},
        onOverlaySaveRegion: (id, r, b) => got.add((id, r, b)));
    const block = {'cols': 6, 'rows': 6, 'c0': 0, 'c1': 2, 'r0': 0, 'r1': 5};
    await fromNative(kOverlaySaveRegion, {
      'sessionId': 4,
      'block': block,
      'x': 0.0,
      'y': 0.0,
      'w': 1280.0,
      'h': 1392.0,
    });
    await fromNative(kOverlaySaveRegion,
        {'sessionId': 4, 'x': 0.0, 'y': 0.0, 'w': 1280.0, 'h': 1392.0});
    expect(got, hasLength(1));
    expect(got.single.$1, 4);
    expect(got.single.$2, const WinRect(0, 0, 1280, 1392));
    expect(got.single.$3, block);
  });

  test('a save-region that is not a map is ignored, and answered', () async {
    var calls = 0;
    HotkeyService(
        onCommand: (_) {}, onOverlaySaveRegion: (id, rect, block) => calls++);
    ByteData? reply;
    await messenger.handlePlatformMessage(
      kOrthantChannel,
      const StandardMethodCodec()
          .encodeMethodCall(const MethodCall(kOverlaySaveRegion, 'garbage')),
      (r) => reply = r,
    );
    expect(calls, 0);
    // A handler that threw is answered with an error envelope, which throws
    // here; a handled call decodes to null.
    expect(const StandardMethodCodec().decodeEnvelope(reply!), isNull);
  });

  group('on Windows', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    List<Map<Object?, Object?>> capturePayload() {
      final sent = <Map<Object?, Object?>>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'replaceHotkeys') return null;
        for (final e in (call.arguments as Map)['bindings'] as List<Object?>) {
          sent.add(e as Map<Object?, Object?>);
        }
        return <int>[];
      });
      return sent;
    }

    test('apply sends a virtual key from the logical key, and the flags',
        () async {
      final sent = capturePayload();
      await HotkeyService(onCommand: (_) {})
          .apply(defaultBindings(platform: TargetPlatform.windows));
      // Win+Ctrl+Shift is MOD_WIN | MOD_CONTROL | MOD_SHIFT.
      expect(sent, [
        {'id': 0, 'vk': 0x4F, 'modifiers': 0xE}, // O, the grid
        {'id': 1, 'vk': 0x25, 'modifiers': 0xE}, // Left
        {'id': 2, 'vk': 0x27, 'modifiers': 0xE}, // Right
        {'id': 3, 'vk': 0x26, 'modifiers': 0xE}, // Up
        {'id': 4, 'vk': 0x28, 'modifiers': 0xE}, // Down
        {'id': 5, 'vk': 0x55, 'modifiers': 0xE}, // U
        {'id': 6, 'vk': 0x49, 'modifiers': 0xE}, // I
        {'id': 7, 'vk': 0x4A, 'modifiers': 0xE}, // J
        {'id': 8, 'vk': 0x4B, 'modifiers': 0xE}, // K
        {'id': 9, 'vk': 0x0D, 'modifiers': 0xE}, // Enter
        {'id': 10, 'vk': 0x43, 'modifiers': 0xE}, // C
      ]);
    });

    test('a chord recorded on German registers the key that typed it',
        () async {
      final sent = capturePayload();
      final german = Binding(
        const BuiltIn(ShortcutCommand.showGrid),
        KeyChord(
          physical: PhysicalKeyboardKey.keyY.usbHidUsage,
          logical: LogicalKeyboardKey.keyZ.keyId,
          modifiers: Modifiers.ctrl | Modifiers.alt,
        ),
      );
      await HotkeyService(onCommand: (_) {}).apply([german]);
      expect(sent, [
        {'id': 0, 'vk': 0x5A, 'modifiers': 0x3},
      ]);
    });

    test("Brazil's keypad separator registers its own key, not the ISO key's",
        () async {
      // ABNT_C2 reaches Flutter as logical 0xE2, VK_OEM_102's id; its
      // position is what tells them apart.
      final sent = capturePayload();
      final abnt = Binding(
        const BuiltIn(ShortcutCommand.center),
        KeyChord(
          physical: PhysicalKeyboardKey.numpadComma.usbHidUsage,
          logical: 0xE2,
          modifiers: Modifiers.ctrl | Modifiers.alt,
        ),
      );
      await HotkeyService(onCommand: (_) {}).apply([abnt]);
      expect(sent, [
        {'id': 0, 'vk': 0xC2, 'modifiers': 0x3},
      ]);
    });

    test('a chord Windows cannot register is refused, never sent', () async {
      final sent = capturePayload();
      final keypad = Binding(
        const BuiltIn(ShortcutCommand.center),
        KeyChord(
          physical: PhysicalKeyboardKey.numpad1.usbHidUsage,
          logical: LogicalKeyboardKey.numpad1.keyId,
          modifiers: Modifiers.ctrl,
        ),
      );
      final refused = await HotkeyService(onCommand: (_) {}).apply([
        ...defaultBindings(platform: TargetPlatform.windows).take(10),
        keypad,
      ]);
      expect(refused, {const BuiltIn(ShortcutCommand.center)});
      expect(sent.map((e) => e['id']), isNot(contains(10)));
      expect(sent, hasLength(10));
    });

    test('a chord with no modifier is refused, never registered bare',
        () async {
      // The reader refuses one; this is the payload's own guard, since a bare
      // global hotkey would take its key from every app.
      final sent = capturePayload();
      final bare = Binding(
        const BuiltIn(ShortcutCommand.center),
        KeyChord(
          physical: PhysicalKeyboardKey.keyC.usbHidUsage,
          logical: LogicalKeyboardKey.keyC.keyId,
          modifiers: Modifiers.none,
        ),
      );
      final refused = await HotkeyService(onCommand: (_) {}).apply([bare]);
      expect(refused, {const BuiltIn(ShortcutCommand.center)});
      expect(sent, isEmpty);
    });

    test('a hotkey carries its press to the summon, and only the summon',
        () async {
      final presses = <double?>[];
      final commands = <CommandRef>[];
      final svc = HotkeyService(
          onCommand: commands.add,
          onSummon: ({pressedAtMs}) => presses.add(pressedAtMs));
      capturePayload();
      await svc.apply(defaultBindings(platform: TargetPlatform.windows));
      final grid = ShortcutCommand.showGrid.index;
      await fromNative('onHotkey', {'id': grid, 'pressedAtMs': 123.5});
      await fromNative('onHotkey', {'id': grid, 'pressedAtMs': 1700000000000});
      await fromNative('onHotkey', {'id': grid, 'pressedAtMs': 'soon'});
      await fromNative('onHotkey', {'id': grid});
      // The codec carries both; a press time that is not a finite number is no
      // press time, and the summon must hear null rather than a number the
      // runner's stale check would compare against.
      await fromNative('onHotkey', {'id': grid, 'pressedAtMs': double.nan});
      await fromNative(
          'onHotkey', {'id': grid, 'pressedAtMs': double.infinity});
      expect(presses, [123.5, 1700000000000.0, null, null, null, null]);
      await fromNative('onHotkey',
          {'id': ShortcutCommand.leftHalf.index, 'pressedAtMs': 9.0});
      expect(commands, [const BuiltIn(ShortcutCommand.leftHalf)]);
    });

    test('a hotkey notice of the wrong shape is ignored, logged, and answered',
        () async {
      var calls = 0;
      final svc = HotkeyService(
          onCommand: (_) => calls++, onSummon: ({pressedAtMs}) => calls++);
      capturePayload();
      await svc.apply(defaultBindings(platform: TargetPlatform.windows));
      final logged = <String?>[];
      final realDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => logged.add(message);
      addTearDown(() => debugPrint = realDebugPrint);
      ByteData? reply;
      await messenger.handlePlatformMessage(
        kOrthantChannel,
        const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onHotkey', {'id': 'grid', 'pressedAtMs': 1.0})),
        (r) => reply = r,
      );
      expect(calls, 0);
      expect(const StandardMethodCodec().decodeEnvelope(reply!), isNull);
      expect(logged, hasLength(1));
      expect(logged.single, contains('onHotkey'));
    });
  });

  test('a hotkey summon carries no press time: macOS stamps its own',
      () async {
    final presses = <double?>[];
    final svc = HotkeyService(
        onCommand: (_) {},
        onSummon: ({pressedAtMs}) => presses.add(pressedAtMs));
    messenger.setMockMethodCallHandler(channel, (_) async => <int>[]);
    await svc.apply(macDefaults);
    await svc.debugHandle(ShortcutCommand.showGrid.index);
    expect(presses, [null]);
  });

  test('a macOS hotkey arrives as a bare id and dispatches through the channel',
      () async {
    // Swift sends `Int(hkID.id)`: no map, no press time. Every macOS shortcut
    // takes this branch of the handler, so it is driven the way native drives
    // it rather than through debugHandle.
    final presses = <double?>[];
    final commands = <CommandRef>[];
    final svc = HotkeyService(
        onCommand: commands.add,
        onSummon: ({pressedAtMs}) => presses.add(pressedAtMs));
    messenger.setMockMethodCallHandler(channel, (_) async => <int>[]);
    await svc.apply(macDefaults);

    await fromNative('onHotkey', ShortcutCommand.showGrid.index);
    expect(presses, [null]);
    expect(commands, isEmpty, reason: 'the summon places nothing itself');

    await fromNative('onHotkey', ShortcutCommand.leftHalf.index);
    expect(commands, [const BuiltIn(ShortcutCommand.leftHalf)]);
    expect(presses, [null], reason: 'a placement is not a summon');
  });
}
