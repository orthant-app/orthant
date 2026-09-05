import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
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

  /// What a screen reader would be told, via Flutter's own accessibility
  /// channel — the overlay never goes through native for this.
  late List<String> announced;

  setUp(() {
    sent = [];
    announced = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      sent.add(call);
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility,
            (message) async {
      final m = message as Map;
      if (m['type'] == 'announce') {
        announced.add((m['data'] as Map)['message'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null);
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

  testWidgets('the active panel announces the grid; the others stay silent',
      (tester) async {
    await tester.pumpWidget(const OverlayApp());
    await send('summon', summon(active: false));
    await tester.pump();
    expect(announced, isEmpty,
        reason: 'one grid per display must not be spoken once per display');
    await send('summon', summon());
    await tester.pump();
    expect(announced, [
      'Grid open for TextEdit. 6 columns, 6 rows. Arrow keys move, '
          'Shift and arrows extend, Return places, Escape cancels.',
    ]);
    expect(sent.where((c) => c.method == 'announceSelection'), isEmpty,
        reason: 'announcements are Flutter\'s, not a native hop');
  });

  testWidgets('keyboard selection announces its actual target once per change',
      (tester) async {
    await tester.pumpWidget(const OverlayApp());
    await send('summon', summon());
    await tester.pump();
    announced.clear();
    await send('moveSelection', {'sessionId': 1, 'direction': 'right'});
    await tester.pump();
    expect(announced, hasLength(1));
    expect(announced.single, contains('Row 1, column 1'));
    expect(announced.single, contains('x 0, y 0, width 200, height 100 points'));

    announced.clear();
    // Clamping at the edge is not a new selection, nor is a stale key.
    await send('moveSelection', {'sessionId': 1, 'direction': 'left'});
    await send('moveSelection', {'sessionId': 0, 'direction': 'down'});
    await tester.pump();
    expect(announced, isEmpty);
    await send('hidden');
    await tester.pump();
    announced.clear(); // the dismissal itself is spoken — covered below
    await send('moveSelection', {'sessionId': 1, 'direction': 'down'});
    await tester.pump();
    expect(announced, isEmpty);
  });

  testWidgets('semantic save and cancel use the live overlay session',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const OverlayApp());
    await send('summon', summon(session: 7));
    await tester.pump();
    final save = find.semantics.byLabel('Place window and save shortcut');
    expect(save.evaluate().single.getSemanticsData()
        .hasAction(SemanticsAction.tap), isFalse);
    tester.semantics.performAction(
        find.semantics.byLabel('Move right'), SemanticsAction.tap);
    await tester.pump();
    tester.semantics.performAction(
        find.semantics.byLabel('Extend down'), SemanticsAction.tap);
    await tester.pump();
    announced.clear();
    tester.semantics.performAction(save, SemanticsAction.tap);
    await tester.pump();
    expect(announced, ['Placing window.']);
    expect(sent.where((c) => c.method == 'saveRegion').single.arguments, {
      'sessionId': 7, 'cols': 6, 'rows': 6,
      'c0': 0, 'c1': 0, 'r0': 0, 'r1': 1,
      'x': 0.0, 'y': 0.0, 'w': 200.0, 'h': 200.0,
    });
    tester.semantics.performAction(
        find.semantics.byLabel('Cancel grid'), SemanticsAction.tap);
    await tester.pump();
    expect(sent.where((c) => c.method == 'hide').single.arguments,
        {'sessionId': 7});
    semantics.dispose();
  });

  testWidgets('a dismissal is announced once, however it happened; a placement is not',
      (tester) async {
    await tester.pumpWidget(const OverlayApp());
    // Esc and click-away are native grabs: Dart only ever sees `hidden`.
    await send('summon', summon());
    await tester.pump();
    announced.clear();
    await send('hidden');
    await tester.pump();
    expect(announced, ['Grid closed.']);

    // A commit is followed by the same `hidden`, and must not be read as a
    // cancellation on top of "Placing window.".
    await send('summon', summon(session: 2));
    await tester.pump();
    announced.clear();
    await send('moveSelection', {'sessionId': 2, 'direction': 'right'});
    await send('commitCurrent', 2);
    await tester.pump();
    await send('hidden');
    await tester.pump();
    expect(announced.where((m) => m == 'Grid closed.'), isEmpty);
    expect(announced.last, 'Placing window.');

    // The other displays' panels are hidden too, and say nothing.
    await send('summon', summon(session: 3, active: false));
    await tester.pump();
    announced.clear();
    await send('hidden');
    await tester.pump();
    expect(announced, isEmpty);
  });
}
