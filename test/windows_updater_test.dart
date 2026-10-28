import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/core/windows_updater.dart';

/// WinSparkle's calls, recorded in order, with the callbacks it was given.
class _FakeSparkle implements SparkleApi {
  final calls = <String>[];
  bool keyAccepted = true;
  void Function()? shutdown;
  void Function()? skipped;
  void Function()? notFound;

  @override
  void setRegistryPath(String path) => calls.add('registry $path');
  @override
  void setAppcastUrl(String url) => calls.add('feed $url');
  @override
  bool setEdDsaPublicKey(String key) {
    calls.add('key $key');
    return keyAccepted;
  }

  @override
  void setAppDetails(String company, String app, String version) =>
      calls.add('details $company $app $version');
  @override
  void setAppBuildVersion(String build) => calls.add('build $build');
  @override
  void setAutomaticCheck(bool on) => calls.add('automatic $on');
  @override
  void setLang(String language) => calls.add('lang $language');
  @override
  void setShutdownRequestCallback(void Function() onRequest) {
    calls.add('shutdown callback');
    shutdown = onRequest;
  }

  @override
  void setSkippedCallback(void Function() onSkipped) {
    calls.add('skipped callback');
    skipped = onSkipped;
  }

  @override
  void setNotFoundCallback(void Function() onNotFound) {
    calls.add('not-found callback');
    notFound = onNotFound;
  }

  @override
  void init() => calls.add('init');
  @override
  void checkWithUi() => calls.add('check');
}

/// The registry's values, held here.
class _FakeStore implements UpdateStore {
  bool? automatic;
  int? lastCheck;
  AvailableUpdate? found;
  String? skipped;

  @override
  bool? readAutomaticChecks() => automatic;
  @override
  void writeAutomaticChecks(bool on) => automatic = on;
  @override
  int? readLastCheck() => lastCheck;
  @override
  void writeLastCheck(int seconds) => lastCheck = seconds;
  @override
  AvailableUpdate? readFound() => found;
  @override
  void writeFound(AvailableUpdate? update) => found = update;
  @override
  String? readSkipped() => skipped;
}

/// Windows 11 23H2, as RtlGetVersion reports it.
const _win11 = (major: 10, minor: 0, build: 22631, servicePack: 0);

/// A feed as tool/ci/windows_appcast.py writes it: 1.0.4 (8) above 1.0.3 (7).
String _feed(
        {int newest = 8,
        String name = '1.0.4',
        String os = 'windows-x64',
        String minimum = '10.0.17763'}) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>Orthant</title>
        <item>
            <title>$name</title>
            <pubDate>Sun, 18 Oct 2026 12:00:00 GMT</pubDate>
            <sparkle:version>$newest</sparkle:version>
            <sparkle:shortVersionString>$name</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
            <enclosure url="https://example/Orthant-$name-setup.exe" length="1000" type="application/octet-stream" sparkle:os="$os" sparkle:installerArguments="/SILENT /SP- /NOCANCEL /SUPPRESSMSGBOXES /RELAUNCH=1" sparkle:edSignature="AAAA"/>
        </item>
        <item>
            <title>1.0.3</title>
            <pubDate>Sat, 17 Oct 2026 12:00:00 GMT</pubDate>
            <sparkle:version>7</sparkle:version>
            <sparkle:shortVersionString>1.0.3</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>10.0.17763</sparkle:minimumSystemVersion>
            <enclosure url="https://example/Orthant-1.0.3-setup.exe" length="1000" type="application/octet-stream" sparkle:os="windows-x64" sparkle:installerArguments="/SILENT /SP- /NOCANCEL /SUPPRESSMSGBOXES /RELAUNCH=1" sparkle:edSignature="AAAA"/>
        </item>
    </channel>
</rss>
''';

void main() {
  const feed = 'https://updates.example/appcast-win.xml';
  const key = 'Oyo4ZcSrr7nWOq3L3vrTmzbQS8efqoGK0ifYh0EB27w=';
  const now = 2000000000, day = 86400;

  ({
    WindowsUpdater updater,
    _FakeSparkle api,
    _FakeStore store,
    List<String> log,
    List<FutureOr<FeedResponse> Function()> answers,
    List<String> fetched,
  }) make({WindowsVersion Function()? system}) {
    final api = _FakeSparkle();
    final store = _FakeStore();
    final log = <String>[];
    final answers = <FutureOr<FeedResponse> Function()>[];
    final fetched = <String>[];
    Future<FeedResponse> fetch(String url) async {
      fetched.add(url);
      return answers.removeAt(0)();
    }

    return (
      updater: WindowsUpdater(api, store, fetch,
          feedUrl: feed,
          publicKey: key,
          system: system ?? () => _win11,
          log: log.add,
          clock: () => now),
      api: api,
      store: store,
      log: log,
      answers: answers,
      fetched: fetched,
    );
  }

  void start(WindowsUpdater updater, {String build = '7'}) =>
      updater.start(build: build, display: '1.0.3', onShutdownRequested: () {});

  test('configures everything before it starts, the build number compared '
      'and the release name shown', () {
    final t = make();
    t.store.automatic = true;
    expect(
        t.updater.start(
            build: '8', display: '1.1.0-beta.1', onShutdownRequested: () {}),
        isTrue);
    expect(t.api.calls, [
      'registry $kUpdaterRegistryPath',
      'feed $feed',
      'key $key',
      'details Orthant Orthant 1.1.0-beta.1',
      'build 8',
      'automatic false',
      'shutdown callback',
      'skipped callback',
      'not-found callback',
      'init',
    ]);
    expect(t.updater.running, isTrue);
  });

  test('WinSparkle is told Orthant\'s language before it starts, so that its '
      'windows speak it, in the lowercase its catalogue lookup matches', () {
    final t = make();
    t.store.automatic = true;
    expect(
        t.updater.start(
            build: '8',
            display: '1.1.0',
            onShutdownRequested: () {},
            language: 'zh-TW'),
        isTrue);
    expect(t.api.calls, [
      'registry $kUpdaterRegistryPath',
      'feed $feed',
      'key $key',
      'details Orthant Orthant 1.1.0',
      'build 8',
      'lang zh-tw',
      'automatic false',
      'shutdown callback',
      'skipped callback',
      'not-found callback',
      'init',
    ]);
  });

  test('English is a language too: it is set, never left to WinSparkle to '
      'guess', () {
    // A Japanese Windows would otherwise get an English Orthant with a
    // Japanese update window (spec, "Windows").
    final t = make();
    t.updater.start(
        build: '8',
        display: '1.1.0',
        onShutdownRequested: () {},
        language: 'en');
    expect(t.api.calls.where((c) => c.startsWith('lang')), ['lang en']);
    expect(t.api.calls.indexOf('lang en'),
        lessThan(t.api.calls.indexOf('init')));
  });

  test('the tag goes to WinSparkle lowercased, whatever its region', () {
    // wxWidgets 3.2.10 inside WinSparkle 0.9.4 lowercases the names of the
    // DLL's catalogues (translation.cpp:1999) but matches the requested tag
    // case-sensitively (:1595), so `zh-CN` and `pt-BR` find nothing and the
    // window stays English; measured on the VM, `zh-cn`, `zh-tw` and `pt-br`
    // find theirs.
    for (final (given, passed) in [
      ('zh-CN', 'zh-cn'),
      ('zh-TW', 'zh-tw'),
      ('pt-BR', 'pt-br'),
      ('en', 'en'),
      ('zh-tw', 'zh-tw'),
    ]) {
      final t = make();
      t.updater.start(
          build: '8',
          display: '1.1.0',
          onShutdownRequested: () {},
          language: given);
      expect(t.api.calls.where((c) => c.startsWith('lang')), ['lang $passed'],
          reason: given);
    }
  });

  test('with no language given it does not set one', () {
    final t = make();
    start(t.updater);
    expect(t.api.calls.where((c) => c.startsWith('lang')), isEmpty);
  });

  test('WinSparkle\'s own schedule never starts, with checks on or off: it '
      'would open its offer unasked', () {
    for (final choice in [true, false, null]) {
      final t = make();
      t.store.automatic = choice;
      start(t.updater);
      expect(t.api.calls, contains('automatic false'));
      expect(t.api.calls.indexOf('automatic false'),
          lessThan(t.api.calls.indexOf('init')));
      expect(t.api.calls, isNot(contains('automatic true')));
    }
  });

  test('never starts without a key WinSparkle accepts: it would install an '
      'update it cannot verify', () {
    final t = make();
    t.api.keyAccepted = false;
    expect(
        t.updater.start(build: '8', display: '1.1.0', onShutdownRequested: () {}),
        isFalse);
    expect(t.api.calls, isNot(contains('init')));
    expect(t.updater.running, isFalse);
    expect(t.log.single, contains('public key'));
  });

  test('never starts without a build number to compare', () {
    for (final build in ['', '1.0.3']) {
      final t = make();
      expect(
          t.updater.start(build: build, display: '', onShutdownRequested: () {}),
          isFalse);
      expect(t.api.calls, isEmpty);
      expect(t.log.single, contains('build'));
    }
  });

  test('a first run checks on a schedule, as macOS does', () {
    final t = make();
    start(t.updater);
    expect(t.store.automatic, isTrue);
    expect(t.updater.automaticChecks, isTrue);
  });

  test('a choice the user made is kept, on or off', () {
    for (final choice in [true, false]) {
      final t = make();
      t.store.automatic = choice;
      start(t.updater);
      expect(t.store.automatic, choice);
      expect(t.updater.automaticChecks, choice);
    }
  });

  test('a second start changes nothing: WinSparkle is configured once', () {
    final t = make();
    start(t.updater, build: '8');
    final first = List.of(t.api.calls);
    expect(
        t.updater.start(build: '9', display: '1.2.0', onShutdownRequested: () {}),
        isTrue);
    expect(t.api.calls, first);
  });

  test('the shutdown request reaches the app', () {
    final t = make();
    var asked = 0;
    t.updater.start(
        build: '8', display: '1.1.0', onShutdownRequested: () => asked++);
    t.api.shutdown!();
    expect(asked, 1);
  });

  test('what the setting reads back is what is stored', () {
    final t = make();
    t.store.automatic = true;
    start(t.updater);
    t.store.automatic = false;
    expect(t.updater.automaticChecks, isFalse);
  });

  test('before it started, or after it refused to, nothing is checked', () async {
    final t = make();
    t.store.automatic = true;
    t.updater.checkNow();
    expect(t.updater.setAutomaticChecks(false), isTrue);
    expect(t.store.automatic, isTrue);
    await t.updater.check();
    t.api.keyAccepted = false;
    start(t.updater);
    t.api.calls.removeWhere((c) => c != 'check');
    t.updater.checkNow();
    await t.updater.check();
    expect(t.api.calls, isEmpty);
    expect(t.fetched, isEmpty);
  });

  test('Check for Updates opens WinSparkle\'s own window', () {
    final t = make();
    start(t.updater);
    t.api.calls.clear();
    t.updater.checkNow();
    expect(t.api.calls, ['check']);
  });

  group('a scheduled check', () {
    ({
      WindowsUpdater updater,
      _FakeSparkle api,
      _FakeStore store,
      List<String> log,
      List<FutureOr<FeedResponse> Function()> answers,
      List<String> fetched,
    }) started({bool automatic = true, int? lastCheck}) {
      final t = make();
      t.store.automatic = automatic;
      t.store.lastCheck = lastCheck;
      start(t.updater);
      t.api.calls.clear();
      return t;
    }

    test('is made at once when none has succeeded, and finding nothing shows '
        'nothing', () async {
      final t = started();
      t.answers.add(() => (status: 200, body: _feed(newest: 7, name: '1.0.3')));
      await t.updater.check();
      expect(t.fetched, [feed]);
      expect(t.store.lastCheck, now);
      expect(t.updater.found.value, isNull);
      expect(t.api.calls, isEmpty);
      expect(t.log.last, 'updater: checked: up to date');
    });

    test('shows what it finds without opening any window', () async {
      final t = started();
      t.answers.add(() => (status: 200, body: _feed()));
      await t.updater.check();
      expect(t.updater.found.value, const AvailableUpdate('1.0.4', 8));
      expect(t.store.found, const AvailableUpdate('1.0.4', 8));
      expect(t.api.calls, isEmpty, reason: 'WinSparkle is never asked');
      expect(t.log.last, 'updater: checked: 1.0.4 (8) available');
    });

    test('is due a day after the last that succeeded, and at once after one '
        'dated later than now', () async {
      final t = started(lastCheck: now - day + 1);
      await t.updater.check();
      expect(t.fetched, isEmpty);
      final due = started(lastCheck: now - day);
      due.answers.add(() => (status: 200, body: _feed()));
      await due.updater.check();
      expect(due.fetched, [feed]);
      // Made while the clock ran ahead, then corrected: waiting for the clock
      // to pass it would stop every check for as long as it lags.
      final ahead = started(lastCheck: now + 30 * day);
      ahead.answers.add(() => (status: 200, body: _feed()));
      await ahead.updater.check();
      expect(ahead.fetched, [feed]);
      expect(ahead.store.lastCheck, now);
    });

    test('that fails stays due, and is made again at the next call', () async {
      final t = started(lastCheck: now - 2 * day);
      t.answers
        ..add(() => throw StateError('offline'))
        ..add(() => (status: 404, body: 'Not Found'))
        ..add(() => (status: 200, body: _feed()));
      await t.updater.check();
      expect(t.store.lastCheck, now - 2 * day);
      expect(t.log.last, contains('check failed'));
      await t.updater.check();
      expect(t.store.lastCheck, now - 2 * day);
      expect(t.log.last, contains('404'));
      await t.updater.check();
      expect(t.fetched, [feed, feed, feed]);
      expect(t.store.lastCheck, now);
      expect(t.updater.found.value, const AvailableUpdate('1.0.4', 8));
    });

    test('is not made while checks are off', () async {
      final t = started(automatic: false);
      await t.updater.check();
      expect(t.fetched, isEmpty);
    });

    test('turned on, a due check is made at once, and nothing of WinSparkle\'s '
        'is touched: an update it is installing goes on', () async {
      final t = started(automatic: false);
      t.answers.add(() => (status: 200, body: _feed()));
      expect(t.updater.setAutomaticChecks(true), isTrue);
      await pumpEventQueue();
      expect(t.fetched, [feed]);
      expect(t.updater.setAutomaticChecks(false), isFalse);
      expect(t.api.calls, isEmpty);
    });

    test('is made once while one is in flight', () async {
      final t = started();
      final answer = Completer<FeedResponse>();
      t.answers.add(() => answer.future);
      final first = t.updater.check();
      await t.updater.check();
      answer.complete((status: 200, body: _feed()));
      await first;
      expect(t.fetched, [feed]);
    });

    test('that reads a feed which is not well-formed fails: still due, and '
        'what an earlier check found is kept', () async {
      final t = started(lastCheck: now - 2 * day);
      t.store.found = const AvailableUpdate('1.0.4', 8);
      final whole = _feed(newest: 9, name: '1.0.5');
      t.answers
        ..add(() => (status: 200, body: whole.substring(0, whole.length ~/ 3)))
        ..add(() => (status: 200, body: whole));
      await t.updater.check();
      expect(t.store.lastCheck, now - 2 * day);
      expect(t.store.found, const AvailableUpdate('1.0.4', 8));
      expect(t.log.last, contains('check failed'));
      await t.updater.check();
      expect(t.fetched, [feed, feed]);
      expect(t.store.lastCheck, now);
      expect(t.updater.found.value, const AvailableUpdate('1.0.5', 9));
    });

    test('that cannot read which Windows this is fails, and stays due; the '
        'start was not stopped by it', () async {
      final t = make(system: () => throw StateError('no RtlGetVersion'));
      t.store.automatic = true;
      start(t.updater);
      expect(t.updater.running, isTrue);
      t.answers.add(() => (status: 200, body: _feed()));
      await t.updater.check();
      expect(t.store.lastCheck, isNull);
      expect(t.log.last, contains('check failed'));
    });

    test('does not show the version the user chose to skip', () async {
      final t = started();
      t.store.skipped = '8';
      t.answers.add(() => (status: 200, body: _feed()));
      await t.updater.check();
      expect(t.updater.found.value, isNull);
      expect(t.store.lastCheck, now);
    });
  });

  group('what a check found', () {
    test('is shown again after a relaunch, until it is installed or skipped',
        () {
      final kept = make();
      kept.store.found = const AvailableUpdate('1.0.4', 8);
      start(kept.updater);
      expect(kept.updater.found.value, const AvailableUpdate('1.0.4', 8));

      final installed = make();
      installed.store.found = const AvailableUpdate('1.0.4', 8);
      start(installed.updater, build: '8');
      expect(installed.updater.found.value, isNull);
      expect(installed.store.found, isNull);

      final skipped = make();
      skipped.store
        ..found = const AvailableUpdate('1.0.4', 8)
        ..skipped = '8';
      start(skipped.updater);
      expect(skipped.updater.found.value, isNull);
      expect(skipped.store.found, isNull);
    });

    test('goes when the user skips it in WinSparkle\'s offer, or WinSparkle '
        'finds nothing to install', () {
      for (final event in ['skipped', 'not found']) {
        final t = make();
        t.store.found = const AvailableUpdate('1.0.4', 8);
        start(t.updater);
        (event == 'skipped' ? t.api.skipped : t.api.notFound)!();
        expect(t.updater.found.value, isNull, reason: event);
        expect(t.store.found, isNull, reason: event);
      }
    });
  });

  group('reading the feed, as WinSparkle does', () {
    test('the newest item for this machine, by build number', () {
      expect(newestUpdate(_feed(), build: 7, system: _win11), const AvailableUpdate('1.0.4', 8));
      expect(newestUpdate(_feed(), build: 8, system: _win11), isNull);
      expect(newestUpdate(_feed(), build: 9, system: _win11), isNull);
      expect(
          newestUpdate(_feed().replaceFirst('<channel>', '<channel xml:lang="en">'),
              build: 7, system: _win11),
          const AvailableUpdate('1.0.4', 8),
          reason: 'xml: is always declared');
      // Two items of one build: the first is kept, as WinSparkle keeps it.
      expect(newestUpdate(_feed(newest: 7, name: '1.0.3a'), build: 6, system: _win11),
          const AvailableUpdate('1.0.3a', 7));
    });

    test('an item for another system is passed over; one for any Windows, or '
        'none named, is not', () {
      expect(newestUpdate(_feed(os: 'windows-arm64'), build: 6, system: _win11),
          const AvailableUpdate('1.0.3', 7));
      expect(newestUpdate(_feed(os: 'macos'), build: 6, system: _win11),
          const AvailableUpdate('1.0.3', 7));
      expect(newestUpdate(_feed(os: 'windows'), build: 7, system: _win11),
          const AvailableUpdate('1.0.4', 8));
      expect(
          newestUpdate(_feed().replaceFirst(' sparkle:os="windows-x64"', ''),
              build: 7, system: _win11),
          const AvailableUpdate('1.0.4', 8));
    });

    test('the newest is chosen before the skip is: an older one is not '
        'offered in its place', () {
      expect(newestUpdate(_feed(newest: 9, name: '1.0.5'), build: 7, system: _win11, skip: '9'),
          isNull);
      expect(newestUpdate(_feed(), build: 7, system: _win11, skip: '7'),
          const AvailableUpdate('1.0.4', 8));
    });

    test('an item it cannot read is passed over; the name is unescaped, and '
        'the build stands in for a missing one', () {
      final noVersion = _feed().replaceFirst(
          '<sparkle:version>8</sparkle:version>', '<sparkle:version>x</sparkle:version>');
      expect(newestUpdate(noVersion, build: 6, system: _win11), const AvailableUpdate('1.0.3', 7));
      final noEnclosure = _feed().replaceFirst(RegExp(r'<enclosure [^>]*/>'), '');
      expect(newestUpdate(noEnclosure, build: 6, system: _win11), const AvailableUpdate('1.0.3', 7));
      expect(
          newestUpdate(_feed(name: '1.0.4 &amp; more'),
                  build: 7, system: _win11)!
              .name,
          '1.0.4 & more');
      final noName = _feed().replaceFirst(
          '<sparkle:shortVersionString>1.0.4</sparkle:shortVersionString>', '');
      expect(newestUpdate(noName, build: 7, system: _win11), const AvailableUpdate('8', 8));
      final blankName = _feed().replaceFirst(
          '<sparkle:shortVersionString>1.0.4</sparkle:shortVersionString>',
          '<sparkle:shortVersionString> </sparkle:shortVersionString>');
      expect(newestUpdate(blankName, build: 7, system: _win11), const AvailableUpdate('8', 8));
      final signed = _feed().replaceFirst(
          '<sparkle:version>8</sparkle:version>', '<sparkle:version>+8</sparkle:version>');
      expect(newestUpdate(signed, build: 6, system: _win11), const AvailableUpdate('1.0.3', 7),
          reason: 'a version that is not digits is not a build number');
    });

    test('a body that is not a well-formed feed is refused, not read as no '
        'update: another document, unclosed tags, a truncated feed, a prefix '
        'it never declares', () {
      for (final body in [
        '<html><body>Not Found</body></html>',
        '<feed><channel></channel></feed>',
        '<rss><channel>',
        _feed().substring(0, _feed().length ~/ 2),
        _feed().replaceFirst(
            ' xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"', ''),
        _feed().replaceFirst('sparkle:os=', 'winsparkle:os='),
      ]) {
        expect(() => newestUpdate(body, build: 7, system: _win11),
            throwsFormatException,
            reason: body);
      }
    });

    test('an item inside a comment is not an item, and a name in CDATA is '
        'read', () {
      final commented = _feed().replaceFirst('<item>', '<!--<item>').replaceFirst(
          '</item>', '</item>-->');
      expect(newestUpdate(commented, build: 6, system: _win11),
          const AvailableUpdate('1.0.3', 7));
      expect(newestUpdate(commented, build: 7, system: _win11), isNull);
      final cdata = _feed().replaceFirst(
          '<sparkle:shortVersionString>1.0.4</sparkle:shortVersionString>',
          '<sparkle:shortVersionString><![CDATA[1.0.4]]></sparkle:shortVersionString>');
      expect(newestUpdate(cdata, build: 7, system: _win11),
          const AvailableUpdate('1.0.4', 8));
    });

    test('an item for a newer Windows than this one is passed over before '
        'the newest is chosen, as WinSparkle passes it over', () {
      final later = _feed(minimum: '10.0.99999');
      expect(newestUpdate(later, build: 6, system: _win11),
          const AvailableUpdate('1.0.3', 7));
      expect(
          newestUpdate(later,
              build: 6,
              system: (major: 10, minor: 0, build: 99999, servicePack: 0)),
          const AvailableUpdate('1.0.4', 8));
    });

    test('the minimum Windows is read as WinSparkle reads it', () {
      bool offered(String minimum, {int servicePack = 0}) =>
          newestUpdate(_feed(minimum: minimum),
              build: 7,
              system: (
                major: 10,
                minor: 0,
                build: 22631,
                servicePack: servicePack
              )) !=
          null;
      expect(offered('10.0.22631'), isTrue);
      expect(offered('10.0.22632'), isFalse);
      expect(offered('10.0-22632'), isFalse, reason: 'major.minor-build');
      expect(offered('10.0.5'), isFalse, reason: 'under 100: a service pack');
      expect(offered('10.0.5', servicePack: 5), isTrue);
      expect(offered('10'), isTrue);
      expect(offered('11'), isFalse);
      expect(offered('10.1'), isFalse);
      expect(offered('6.3.9600'), isTrue);
      expect(offered('6.1.7601'), isTrue);
      // VerifyVersionInfoW, as WinSparkle calls it, compares major, minor and
      // service pack in that order, and the build number on its own.
      expect(offered('9.9.99999'), isFalse, reason: 'the build on its own');
      expect(offered('6.3.99999'), isFalse, reason: 'the build on its own');
      expect(offered('10.0.100'), isTrue, reason: 'from 100 up, a build');
      expect(offered('10.0.99'), isFalse, reason: 'under 100, a service pack');
      expect(offered('later'), isTrue, reason: 'not a number: no limit');
      expect(offered(''), isTrue);
    });
  });

  // WinINet's timeouts bound each call, not the request: a server dripping
  // bytes under the 1 MiB cap would hold `_checking` for the session.
  group('reading the response body', () {
    /// [chunks] chunks of [size] bytes each, then the end; each read takes
    /// [each] on the fake clock.
    ({Uint8List Function() next, Duration Function() elapsed}) server(
        {required int chunks, int size = 100, Duration each = Duration.zero}) {
      var reads = 0;
      var now = Duration.zero;
      return (
        next: () {
          now += each;
          return reads++ < chunks ? Uint8List(size) : Uint8List(0);
        },
        elapsed: () => now,
      );
    }

    test('reads to the end', () {
      final s = server(chunks: 3);
      expect(readFeedBody(s.next, elapsed: s.elapsed), hasLength(300));
    });

    test('stops a response that is still arriving after the limit', () {
      // One chunk a second, for ever.
      final s = server(chunks: 1 << 30, size: 1, each: const Duration(seconds: 1));
      expect(
          () => readFeedBody(s.next, elapsed: s.elapsed),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('120 s'))));
      expect(s.elapsed(), kFeedFetchLimit + const Duration(seconds: 1),
          reason: 'stopped at the first read past the limit');
    });

    test('keeps a response that ends just as the limit passes', () {
      // The end itself comes after the limit: the body is whole.
      final s = server(chunks: 120, size: 1, each: const Duration(seconds: 1));
      expect(readFeedBody(s.next, elapsed: s.elapsed), hasLength(120));
    });

    test('stops a response over 1 MiB', () {
      final s = server(chunks: 65, size: 16384);
      expect(
          () => readFeedBody(s.next, elapsed: s.elapsed),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('1 MiB'))));
    });

    test('allows two minutes', () {
      expect(kFeedFetchLimit, const Duration(seconds: 120));
    });
  });

  test('a shipped build checks the Windows stable feed on our own domain, '
      'and trusts the same key macOS does', () {
    expect(kUpdateFeedUrl, 'https://updates.orthant.app/appcast-win.xml');
    final plist = File('macos/Runner/Info.plist').readAsStringSync();
    final macKey = RegExp(r'<key>SUPublicEDKey</key>\s*<string>([^<]+)</string>')
        .firstMatch(plist)!
        .group(1);
    expect(kUpdatePublicKey, macKey);
  });
}
