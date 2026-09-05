import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/channel.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/hotkey_service.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

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
    await HotkeyService(onCommand: (_) {}).apply(kDefaultBindings);
    expect(ids.toSet(),
        {for (final b in kDefaultBindings) (b.command as BuiltIn).command.index});
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
    await HotkeyService(onCommand: (_) {}).apply(kDefaultBindings);

    expect(calls.map((c) => c.method).toList(), ['replaceHotkeys']);
    final sent = (calls.single.arguments as Map)['bindings'] as List<Object?>;
    expect(sent.length, kDefaultBindings.length,
        reason: 'the call carries the entire snapshot, not a delta');
  });

  test('the summon is registered like any other binding', () async {
    // No longer a bespoke reserved id registered outside the loop: it is simply
    // the first entry in the list, which is what lets it share the recorder,
    // the persistence and the collision check with the ten placements.
    final ids = captureIds();
    await HotkeyService(onCommand: (_) {}, onSummon: () {})
        .apply(kDefaultBindings);
    expect(ids, contains(ShortcutCommand.showGrid.index));
  });

  test('apply skips unbound commands', () async {
    final ids = captureIds();
    final bindings = withRebind(kDefaultBindings,
        const Binding(BuiltIn(ShortcutCommand.leftHalf), 124, kControlOption));
    await HotkeyService(onCommand: (_) {}).apply(bindings);

    // rightHalf lost its combo to leftHalf, so it must not be registered.
    expect(ids, isNot(contains(ShortcutCommand.rightHalf.index)));
    expect(ids.length, kDefaultBindings.length - 1);
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
        HotkeyService(onCommand: (c) => placed = c, onSummon: () => summons++);
    messenger.setMockMethodCallHandler(channel, (_) async => <int>[]);
    await svc.apply(kDefaultBindings);

    await svc.debugHandle(ShortcutCommand.showGrid.index);
    expect(summons, 1);
    expect(placed, isNull, reason: 'the summon places nothing itself');
  });

  test('an incoming onHotkey dispatches the mapped region command', () async {
    CommandRef? got;
    final svc = HotkeyService(onCommand: (c) => got = c);
    messenger.setMockMethodCallHandler(channel, (_) async => <int>[]);
    await svc.apply(kDefaultBindings);
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
        HotkeyService(onCommand: (_) => commands++, onSummon: () => summons++);
    messenger.setMockMethodCallHandler(channel, (_) async => <int>[]);
    await svc.apply(kDefaultBindings);

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
        await HotkeyService(onCommand: (_) {}).apply(kDefaultBindings);
    expect(refused, {const BuiltIn(taken)});
  });

  test('a refused summon chord is reported like any other', () async {
    // ⌃⌥O can be taken by another app exactly as ⌃⌥← can. It now surfaces
    // through the same `unavailable` set the settings row already renders,
    // instead of the bespoke bool the ⌃⌥G spike needed.
    captureIds(reply: (id) => id != ShortcutCommand.showGrid.index);
    final refused = await HotkeyService(onCommand: (_) {}, onSummon: () {})
        .apply(kDefaultBindings);
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
        await HotkeyService(onCommand: (_) {}).apply(kDefaultBindings);
    expect(refused, {for (final b in kDefaultBindings) b.command});
  });

  test('a reply of the wrong shape degrades instead of throwing', () async {
    // This runs on the launch path, before any window exists. A typed
    // invokeMethod would have thrown here and taken the app down over a reply
    // it could simply have disbelieved.
    messenger.setMockMethodCallHandler(channel, (_) async => true);
    final refused =
        await HotkeyService(onCommand: (_) {}).apply(kDefaultBindings);
    expect(refused, {for (final b in kDefaultBindings) b.command});
  });

  test('an unbound command is neither sent nor reported as refused', () async {
    // "No shortcut assigned" and "macOS would not give us this chord" look the
    // same in the list if the second is inferred from the first's absence.
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final bindings = withRebind(kDefaultBindings,
        const Binding(BuiltIn(ShortcutCommand.leftHalf), 124, kControlOption));
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
    await svc.apply(kDefaultBindings); // installs the inbound handler
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
    await svc.apply(kDefaultBindings); // installs the inbound handler
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
      await HotkeyService(onCommand: (_) {}).apply(kDefaultBindings);
      // _completed puts the eleven built-ins first in enum order, so indexing
      // the applied list reproduces the ids they have always had.
      expect(ids, [for (var i = 0; i < kDefaultBindings.length; i++) i]);
    });

    test('a custom region gets an id past the built-ins, clear of 900',
        () async {
      final ids = captureIds();
      await HotkeyService(onCommand: (_) {}).apply([
        ...kDefaultBindings,
        const Binding(Custom('r1'), 123, kControlOption | kShiftKey),
      ]);

      expect(ids.last, kDefaultBindings.length);
      expect(ids.last, lessThan(900),
          reason: 'the overlay reserves 900+ for its Esc/Return grabs');
    });

    test('dispatches a press to the ref that id was applied for', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => <int>[]);
      final fired = <CommandRef>[];
      final svc = HotkeyService(onCommand: fired.add);
      await svc.apply([
        ...kDefaultBindings,
        const Binding(Custom('r1'), 123, kControlOption | kShiftKey),
      ]);

      await svc.debugHandle(kDefaultBindings.length);
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
        ...kDefaultBindings,
        const Binding.unbound(Custom('gap')),
        const Binding(Custom('r2'), 123, kControlOption | kShiftKey),
      ];
      await HotkeyService(onCommand: (_) {}).apply(bindings);

      expect(ids.last, kDefaultBindings.length + 1);
    });

    test('refusals come back as the refs they were sent for', () async {
      captureIds(reply: (id) => id != 1);
      final refused =
          await HotkeyService(onCommand: (_) {}).apply(kDefaultBindings);
      expect(refused, {const BuiltIn(ShortcutCommand.leftHalf)});
    });

    test('a press arriving before any apply is ignored', () async {
      var fired = 0;
      final svc = HotkeyService(onCommand: (_) => fired++);
      await svc.debugHandle(0);
      expect(fired, 0);
    });
  });
}
