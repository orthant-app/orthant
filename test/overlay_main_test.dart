import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/l10n/app_localizations.dart';
import 'package:orthant/l10n/strings.dart';
import 'package:orthant/overlay/overlay_main.dart';
import 'package:orthant/overlay/grid_overlay.dart';

import 'support/locales.dart';
import 'support/no_english.dart';

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
    // A summon points the process-wide strings at its language; the next test
    // starts from English as a fresh engine does.
    setAppStrings(kEnglish);
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

  /// The same, returning what the overlay answered. An error envelope, which
  /// is what a throwing handler produces, throws here.
  Future<Object?> reply(String method, [Object? arguments]) async {
    ByteData? answer;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
      (data) => answer = data,
    );
    return const StandardMethodCodec().decodeEnvelope(answer!);
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

  testWidgets('a replaced session\'s selection never commits for the next one',
      (tester) async {
    await tester.pumpWidget(const OverlayApp());
    await send('summon', summon());
    await tester.pump();
    await send('moveSelection', {'sessionId': 1, 'direction': 'right'});
    await tester.pump();
    sent.clear();

    // The runner's replacement order, with no frame between: session 1's grid,
    // and the cell it selected, are still mounted when session 2's Return
    // arrives.
    await send('hidden', 1);
    await send('summon', summon(session: 2));
    await send('commitCurrent', 2);
    await tester.pump();
    expect(commitIn(sent), isNull, reason: 'session 2 selected nothing');
  });

  testWidgets('a gesture on a replaced grid commits under its own session',
      (tester) async {
    await tester.pumpWidget(const OverlayApp());
    await send('summon', summon());
    await tester.pump();
    sent.clear();

    // Session 2 has arrived but not yet been built, so the pointer still hits
    // session 1's grid: what it commits must name session 1, which the runner
    // drops, never session 2.
    await send('hidden', 1);
    await send('summon', summon(session: 2));
    await tester.tapAt(tester.getRect(find.byKey(GridOverlay.cellsKey)).center);
    final commit = commitIn(sent);
    expect(commit, isNotNull, reason: 'the tap reached no cell');
    expect((commit!.arguments as Map)['sessionId'], 1);
  });

  testWidgets('a gesture on a replaced grid neither announces a placement nor '
      'silences the next close', (tester) async {
    await tester.pumpWidget(const OverlayApp());
    await send('summon', summon());
    await tester.pump();

    // The same one-frame window: the pointer hits session 1's grid, whose
    // commit the runner drops, so nothing is being placed.
    await send('hidden', 1);
    await send('summon', summon(session: 2));
    announced.clear();
    await tester.tapAt(tester.getRect(find.byKey(GridOverlay.cellsKey)).center);
    expect(commitIn(sent), isNotNull, reason: 'the tap reached no cell');
    expect(announced, isNot(contains('Placing window.')),
        reason: 'session 1 is over; its commit is dropped');

    // Session 2 is then dismissed without placing anything: a cancellation,
    // and spoken as one.
    await tester.pump();
    announced.clear();
    await send('hidden', 2);
    await tester.pump();
    expect(announced, ['Grid closed.']);
  });

  testWidgets('a gesture on a warm-up grid announces nothing', (tester) async {
    await tester.pumpWidget(const OverlayApp());
    await send('summon', {...summon(session: 1), 'warm': true});
    await tester.pump();
    await tester.tapAt(tester.getRect(find.byKey(GridOverlay.cellsKey)).center);
    expect(commitIn(sent), isNotNull, reason: 'the tap reached no cell');
    expect(announced, isEmpty, reason: 'nobody summoned anything');
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

  testWidgets('on Windows the grid announces Enter, not Return', (tester) async {
    await tester.pumpWidget(const OverlayApp());
    await send('summon', {...summon(), 'appName': 'Notepad'});
    await tester.pump();
    expect(announced, [
      'Grid open for Notepad. 6 columns, 6 rows. Arrow keys move, '
          'Shift and arrows extend, Enter places, Escape cancels.',
    ]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  group('an icon that arrives after the summon', () {
    // A summon on Windows carries an icon only if one was cached; one that was
    // not is fetched off the summon path and follows as setAppIcon. It belongs
    // to the session it names, and to no other.
    // A real one-pixel PNG: the chip decodes what it is given.
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQV'
        'R42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
    Uint8List? shownIcon(WidgetTester tester) =>
        tester.widget<GridOverlay>(find.byType(GridOverlay)).appIcon;

    testWidgets('reaches the grid of the session it names', (tester) async {
      await tester.pumpWidget(const OverlayApp());
      await send('summon', summon(session: 4));
      await tester.pump();
      expect(shownIcon(tester), isNull);
      await send('setAppIcon', {'sessionId': 4, 'png': png});
      await tester.pump();
      expect(shownIcon(tester), png);
    });

    testWidgets('for another session, is dropped', (tester) async {
      await tester.pumpWidget(const OverlayApp());
      await send('summon', summon(session: 5));
      await tester.pump();
      await send('setAppIcon', {'sessionId': 4, 'png': png});
      await tester.pump();
      expect(shownIcon(tester), isNull,
          reason: 'an earlier capture\'s app, on this capture\'s grid');
    });

    testWidgets('after its session ended, is not carried into the next',
        (tester) async {
      await tester.pumpWidget(const OverlayApp());
      await send('summon', summon(session: 6));
      await tester.pump();
      await send('hidden', 6);
      await tester.pump();
      await send('setAppIcon', {'sessionId': 6, 'png': png});
      await send('summon', summon(session: 7));
      await tester.pump();
      expect(shownIcon(tester), isNull);
    });

    testWidgets('of the wrong shape, changes nothing and throws nothing',
        (tester) async {
      await tester.pumpWidget(const OverlayApp());
      await send('summon', {...summon(session: 8), 'appIcon': png});
      await tester.pump();
      for (final bad in <Object?>[
        null,
        8,
        {'sessionId': 8},
        {'sessionId': 8, 'png': 'not bytes'},
        {'sessionId': '8', 'png': png},
      ]) {
        await expectLater(reply('setAppIcon', bad), completes,
            reason: 'answered, not with an error envelope: $bad');
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$bad');
        expect(shownIcon(tester), png, reason: '$bad');
      }
    });
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

  testWidgets('the summon\'s scale reaches the grid; absent or impossible is 1',
      (tester) async {
    await tester.pumpWidget(const OverlayApp());
    var session = 10;
    for (final (given, expected) in <(Object?, double)>[
      (1.5, 1.5),
      (2.5, 2.5),
      (null, 1.0),
      (0.0, 1.0),
      (-2.0, 1.0),
      ('1.5', 1.0),
    ]) {
      final payload = summon(session: session++);
      if (given == null) {
        payload.remove('scale');
      } else {
        payload['scale'] = given;
      }
      await send('summon', payload);
      await tester.pump();
      expect(tester.widget<GridOverlay>(find.byType(GridOverlay)).scale,
          expected,
          reason: 'scale: $given');
    }
  });

  testWidgets('a warm-up summon renders, but neither speaks nor reports a '
      'first frame', (tester) async {
    await tester.pumpWidget(const OverlayApp());
    await send('summon', {...summon(session: 1), 'warm': true});
    await tester.pump();
    await tester.pump();
    expect(find.byType(GridOverlay), findsOneWidget,
        reason: 'rendering is the point of a warm-up');
    expect(sent.where((c) => c.method == 'firstFrame'), isEmpty);
    await send('hidden', 1);
    await tester.pump();
    expect(announced, isEmpty, reason: 'nobody summoned anything');

    // The next, real summon speaks and reports as it always has.
    await send('summon', summon(session: 2));
    await tester.pump();
    await tester.pump();
    expect(sent.where((c) => c.method == 'firstFrame'), hasLength(1));
    expect(announced, isNotEmpty);
  });

  group('the language the summon carries', () {
    // The overlay is a second engine: nothing reaches it but the summon, so the
    // language is a field of that payload, and it has to be set before the
    // first thing the summon says or draws.
    Map<String, Object?> chinese(
            {String tag = 'zh-Hant', bool active = true, int session = 1}) =>
        {
          ...summon(session: session, active: active),
          'locale': tag,
          'appName': '記事本',
          'saveHint': true,
        };

    testWidgets('a Traditional Chinese summon draws and describes the first '
        'frame in Chinese', (tester) async {
      await tester.pumpWidget(const OverlayApp());
      await send('summon', chinese());
      await tester.pump();
      expect(find.byType(GridOverlay), findsOneWidget);
      expectNoEnglish(tester, allow: {'記事本'});
    });

    testWidgets('with no locale the first frame is English, as before',
        (tester) async {
      await tester.pumpWidget(const OverlayApp());
      await send('summon', {...summon(), 'saveHint': true});
      await tester.pump();
      expect(find.text('⌘S  save this shape as a shortcut'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      expect(find.semantics.byLabel('Window grid for TextEdit, 6 columns, 6 rows'),
          findsOne);
      semantics.dispose();
    });

    testWidgets('the announcements, opening first, are spoken in the summon\'s '
        'language', (tester) async {
      await tester.pumpWidget(const OverlayApp());
      // The opening one is spoken inside the summon, before the frame that
      // draws it: it proves the strings were set ahead of everything else.
      await send('summon', chinese());
      await tester.pump();
      final zh = lookupAppLocalizations(kTraditional);
      expect(announced, [
        zh.overlayOpened('記事本', zh.overlayColumns(6), zh.overlayRows(6), 'Return'),
      ]);
      expectNoEnglishIn(announced, allow: {'記事本'});

      announced.clear();
      await send('moveSelection', {'sessionId': 1, 'direction': 'right'});
      await tester.pump();
      // The selection the arrow made is spoken in the same language: the grid
      // composes it from the overlay's own strings, on the first move.
      expect(announced, [
        zh.overlaySelection(zh.overlayRowOne(1), zh.overlayColumnOne(1), '0',
            '0', '200', '100', zh.overlayUnitPoints),
      ]);
      expectNoEnglishIn(announced, allow: {'記事本'});
      await send('commitCurrent', 1);
      await tester.pump();
      expect(announced.last, zh.overlayPlacingWindow);
      await send('hidden');
      await tester.pump();
      expect(announced.where((m) => m == zh.overlayGridClosed), isEmpty,
          reason: 'a placement is not a cancellation');

      await send('summon', chinese(session: 2));
      await tester.pump();
      announced.clear();
      await send('hidden');
      await tester.pump();
      expect(announced, [zh.overlayGridClosed]);
      expectNoEnglishIn(announced, allow: {'記事本'});
    });

    testWidgets('without a locale the same three are exactly the English',
        (tester) async {
      await tester.pumpWidget(const OverlayApp());
      await send('summon', summon());
      await tester.pump();
      expect(announced, [
        'Grid open for TextEdit. 6 columns, 6 rows. Arrow keys move, '
            'Shift and arrows extend, Return places, Escape cancels.',
      ]);
      announced.clear();
      await send('moveSelection', {'sessionId': 1, 'direction': 'right'});
      await send('commitCurrent', 1);
      await tester.pump();
      expect(announced.last, 'Placing window.');
      await send('hidden');
      await send('summon', summon(session: 2));
      await tester.pump();
      announced.clear();
      await send('hidden');
      await tester.pump();
      expect(announced, ['Grid closed.']);
    });

    testWidgets('each summon names its language: a later one without a locale '
        'goes back to English', (tester) async {
      await tester.pumpWidget(const OverlayApp());
      await send('summon', chinese());
      await tester.pump();
      await send('hidden');
      await tester.pump();
      announced.clear();
      await send('summon', summon(session: 2));
      await tester.pump();
      expect(announced.single, startsWith('Grid open for TextEdit.'));
    });

    testWidgets('the Hong Kong tag reaches the Hong Kong file; Simplified is '
        'not Traditional', (tester) async {
      await tester.pumpWidget(const OverlayApp());
      for (final (tag, locale) in [
        ('zh', kSimplified),
        ('zh-Hant', kTraditional),
        ('zh-Hant-HK', kHongKong),
      ]) {
        await send('summon', chinese(tag: tag));
        await tester.pump();
        final s = lookupAppLocalizations(locale);
        expect(announced.last,
            s.overlayOpened('記事本', s.overlayColumns(6), s.overlayRows(6), 'Return'),
            reason: tag);
        await send('hidden');
        await tester.pump();
      }
      expect(lookupAppLocalizations(kSimplified).overlayColumns(6),
          isNot(lookupAppLocalizations(kTraditional).overlayColumns(6)),
          reason: 'columns are 列 in Simplified and 欄 in Traditional');
    });

    testWidgets('a tag that names no language we ship, or is not a string, is '
        'English', (tester) async {
      await tester.pumpWidget(const OverlayApp());
      var session = 1;
      for (final bad in <Object?>['!!', '', 'ja-JP', 7]) {
        announced.clear();
        await send('summon', {...summon(session: session++), 'locale': bad});
        await tester.pump();
        expect(announced.single, startsWith('Grid open for TextEdit.'),
            reason: '$bad');
        await send('hidden');
        await tester.pump();
      }
    });
  });
}
