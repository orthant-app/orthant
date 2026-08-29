import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/overlay/overlay_main.dart';

/// The overlay engine's side of the channel.
///
/// This file was the last one with no coverage at all, and it is not an idle
/// gap: it is the only Dart that runs on the second engine, it has no UI a
/// widget test would otherwise touch, and every key the grid takes arrives here
/// as a method call rather than as a key event — the panel is non-activating, so
/// nothing else can deliver one.
///
/// These drive it the way `OverlayPanelSet` does: send calls, then pump. The
/// order matters, because native grabs the keys before it shows the panel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.orthant/overlay');
  late List<MethodCall> sent;

  setUp(() {
    sent = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      sent.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  /// Deliver a call *to* the overlay, as native does.
  Future<void> send(String method, [Object? arguments]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
  }

  Map<String, Object?> summon({int session = 1, bool active = true}) => {
        'sessionId': session,
        'triggerMs': 0,
        'x': 0.0,
        'y': 0.0,
        'w': 1200.0,
        'h': 600.0,
        'appName': 'TextEdit',
        'active': active,
        'cols': 6,
        'rows': 6,
        'gap': 0.0,
      };

  MethodCall? commitIn(List<MethodCall> calls) =>
      calls.where((c) => c.method == 'commit').firstOrNull;

  testWidgets('it announces itself so a summon is never sent into the void',
      (tester) async {
    await tester.pumpWidget(const OverlayApp());
    expect(sent.map((c) => c.method), contains('ready'));
  });

  testWidgets('an arrow and a Return sent before the first frame still commit',
      (tester) async {
    // The gap this covers is real, not theoretical: the arrows are grabbed
    // ahead of the panel appearing, and summon→first-frame has been measured at
    // 44 ms median and 368 ms on a cold engine. Both keys used to land on a null
    // GlobalKey state and vanish without a trace.
    await tester.pumpWidget(const OverlayApp());
    sent.clear();

    await send('summon', summon());
    await send('moveSelection', {'sessionId': 1, 'direction': 'right'});
    await send('commitCurrent', 1);
    expect(commitIn(sent), isNull, reason: 'nothing has been built yet');

    await tester.pump();

    final commit = commitIn(sent);
    expect(commit, isNotNull, reason: 'the queued Return never fired');
    final r = (commit!.arguments as Map).cast<String, Object?>();
    // First arrow lands on the top-left cell; the grid is 6x6 over 1200x600.
    expect(r['x'], 0.0);
    expect(r['y'], 0.0);
    expect(r['w'], 200.0);
    expect(r['h'], 100.0);
  });

  testWidgets('replayed keys keep the order they arrived in', (tester) async {
    await tester.pumpWidget(const OverlayApp());
    sent.clear();

    await send('summon', summon());
    await send('moveSelection', {'sessionId': 1, 'direction': 'right'});
    await send('moveSelection', {'sessionId': 1, 'direction': 'down'});
    // ⇧ extends from wherever the plain arrows left off. Replayed out of order
    // this would select a different rect while still "working".
    await send('moveSelection',
        {'sessionId': 1, 'direction': 'right', 'extend': true});
    await send('commitCurrent', 1);
    await tester.pump();

    final r = (commitIn(sent)!.arguments as Map).cast<String, Object?>();
    expect(r['w'], 400.0, reason: 'two columns wide after the ⇧-extend');
    expect(r['h'], 100.0);
  });

  testWidgets('a key held over from a finished session is not replayed',
      (tester) async {
    await tester.pumpWidget(const OverlayApp());

    await send('summon', summon());
    await send('moveSelection', {'sessionId': 1, 'direction': 'right'});
    await send('hidden');
    sent.clear();

    // A fresh summon starts from an empty selection, not from the arrow the
    // previous session never got around to.
    await send('summon', summon(session: 2));
    await send('commitCurrent', 2);
    await tester.pump();
    expect(commitIn(sent), isNull);
  });

  testWidgets('a key for another session is dropped, not queued',
      (tester) async {
    await tester.pumpWidget(const OverlayApp());
    sent.clear();

    await send('summon', summon(session: 7));
    await send('moveSelection', {'sessionId': 6, 'direction': 'right'});
    await send('commitCurrent', 7);
    await tester.pump();
    expect(commitIn(sent), isNull, reason: 'the stale arrow selected nothing');
  });

  testWidgets('an inactive panel ignores arrows meant for the active one',
      (tester) async {
    // One panel per display, all summoned together; only the one under the
    // pointer is active. A queued arrow must respect that too.
    await tester.pumpWidget(const OverlayApp());
    sent.clear();

    await send('summon', summon(active: false));
    await send('moveSelection', {'sessionId': 1, 'direction': 'right'});
    await send('commitCurrent', 1);
    await tester.pump();
    expect(commitIn(sent), isNull);
  });
}
