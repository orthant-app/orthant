import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/windows_keys.dart';

// The Dart-side patterns take either quote style: `prefer_single_quotes` is
// off, so a double-quoted name must not escape the sweep without failing it.
final _constant = RegExp(r'''const String (k\w+) = (['"])([^'"]+)\2;''');
final _invoke = RegExp(
    r'''invoke(?:List|Map)?Method(?:<[^(]*>)?\(\s*(k\w+|'[^']+'|"[^"]+")''');
final _handled = RegExp(r'''call\.method == (k\w+|'[^']+'|"[^"]+")''');

/// The runner's grab table (`kGrabs` in `windows_overlay_set.cpp`), one record
/// per line of it. Every line that is not blank or a comment must be an entry
/// this reads, whatever its spacing, an id in decimal or hexadecimal, and a
/// modifier single or combined: a line it cannot read fails the test, rather
/// than dropping out of what the checks see.
List<({int id, int modifiers, int vk})> _grabTable(String cpp) {
  const vks = {
    'VK_ESCAPE': 0x1B,
    'VK_RETURN': 0x0D,
    'VK_LEFT': 0x25,
    'VK_UP': 0x26,
    'VK_RIGHT': 0x27,
    'VK_DOWN': 0x28,
  };
  const mods = {
    '0': 0,
    'MOD_ALT': 1,
    'MOD_CONTROL': 2,
    'MOD_SHIFT': 4,
    'MOD_WIN': 8,
  };
  final table = RegExp(r'constexpr Grab kGrabs\[\] = \{(.*?)\n\};', dotAll: true)
      .firstMatch(cpp)!
      .group(1)!;
  final entry = RegExp(r'''^\{\s*(0[xX][0-9A-Fa-f]+|\d+)\s*,\s*([\w|\s]+?)\s*,'''
      r'''\s*('[^']'|\w+)\s*,\s*(?:true|false)\s*,\s*"[^"]*"\s*\},?$''');
  return [
    for (final raw in table.split('\n'))
      if (raw.trim() case final line when line.isNotEmpty && !line.startsWith('//'))
        () {
          final m = entry.firstMatch(line) ??
              fail('kGrabs has a line this test cannot read: $line');
          final id = m.group(1)!;
          final key = m.group(3)!;
          return (
            id: id.toLowerCase().startsWith('0x')
                ? int.parse(id.substring(2), radix: 16)
                : int.parse(id),
            modifiers: m.group(2)!.split('|').fold(0, (all, name) {
              return all |
                  (mods[name.trim()] ??
                      fail('kGrabs names an unknown modifier: $line'));
            }),
            vk: key.startsWith("'")
                ? key.codeUnitAt(1)
                : vks[key] ?? fail('kGrabs names an unknown key: $line'),
          );
        }(),
  ];
}

/// Every method Dart can send on `app.orthant/window` from code that runs on
/// Windows must be answered by `windows/runner/window_channel.cpp`, and every
/// callback the runner sends must be handled by Dart (Windows design §5.1). A
/// caller with no native branch gets `NotImplemented`, which Dart surfaces as
/// `MissingPluginException`, and several callers neither await nor catch: W0's
/// plan missed `configFirstFrame` exactly this way, and only review caught it.
/// This test is that sweep, run on every change.
void main() {
  final constants = <String, String>{
    for (final m in _constant
        .allMatches(File('lib/core/channel.dart').readAsStringSync()))
      m.group(1)!: m.group(3)!,
  };

  String resolve(String arg) => arg.startsWith("'") || arg.startsWith('"')
      ? arg.substring(1, arg.length - 1)
      : constants[arg] ?? '<unknown constant $arg>';

  Set<String> dartCalls() {
    final calls = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      // Constructed only on macOS (window_controller_factory.dart).
      if (f.path.endsWith('window_controller_macos.dart')) continue;
      final src = f.readAsStringSync();
      if (!src.contains('kOrthantChannel')) continue;
      for (final m in _invoke.allMatches(src)) {
        calls.add(resolve(m.group(1)!));
      }
    }
    return calls;
  }

  // Read with LF endings whatever the checkout did (core.autocrlf true gives
  // CRLF): the spans below end on a closing brace on a line of its own.
  final cpp = File('windows/runner/window_channel.cpp')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final answered = {
    for (final m in RegExp(r'method == "([^"]+)"').allMatches(cpp)) m.group(1)!,
  };
  final sent = {
    for (final m in RegExp(r'InvokeMethod\(\s*"([^"]+)"').allMatches(cpp))
      m.group(1)!,
  };

  test('the sweep sees the calls it must (a regex gone blind fails here)', () {
    expect(dartCalls(),
        containsAll(['showConfigWindow', 'configFirstFrame', 'replaceHotkeys',
          'showOverlay', 'setOverlayGrid']));
    expect(answered, isNotEmpty);
    expect(sent, isNotEmpty);
  });

  test('the Dart-side patterns see a double-quoted name too', () {
    expect(_invoke.firstMatch('invokeMethod("x")')?.group(1), '"x"');
    expect(_constant.firstMatch('const String kX = "x";')?.group(3), 'x');
    expect(_handled.firstMatch('call.method == "x"')?.group(1), '"x"');
    expect(resolve('"x"'), 'x');
  });

  test('every Dart call that can run on Windows is answered by the runner', () {
    final missing = dartCalls().difference(answered);
    expect(missing, isEmpty,
        reason: 'window_channel.cpp answers NotImplemented for these, and Dart '
            'throws MissingPluginException where it calls them');
  });

  test('every runner callback is handled by Dart', () {
    final dart = File('lib/shortcuts/hotkey_service.dart').readAsStringSync();
    final handled = {
      for (final m in _handled.allMatches(dart)) resolve(m.group(1)!),
    };
    expect(sent.difference(handled), isEmpty);
  });

  // The overlay's own channel, app.orthant/overlay: every call overlayMain
  // makes must be answered by the runner's panel handler, and every call the
  // runner makes to a panel must be handled by overlayMain. The same failure
  // as above, one engine over: an unanswered call is dropped, and a summon
  // overlayMain cannot handle leaves a panel on screen with nothing in it.
  final overlayDart = File('lib/overlay/overlay_main.dart').readAsStringSync();
  final overlayCalls = {
    for (final m in RegExp(r'''_overlay\.invokeMethod(?:<[^(]*>)?\(\s*['"]([^'"]+)['"]''')
        .allMatches(overlayDart))
      m.group(1)!,
    for (final m in RegExp(r'''_send\(\s*\w+,\s*['"]([^'"]+)['"]''')
        .allMatches(overlayDart))
      m.group(1)!,
  };
  final overlayHandled = {
    for (final m in RegExp(r'''case ['"]([^'"]+)['"]:''').allMatches(overlayDart))
      m.group(1)!,
  };
  final overlayCpp = File('windows/runner/windows_overlay_set.cpp')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final overlayAnswered = {
    for (final m in RegExp(r'method == "([^"]+)"').allMatches(overlayCpp))
      m.group(1)!,
  };
  // Literal InvokeMethod calls, and the grabs' relays, which name their
  // method as Relay's first argument.
  final overlaySent = {
    for (final m in RegExp(r'InvokeMethod\(\s*"([^"]+)"').allMatches(overlayCpp))
      m.group(1)!,
    for (final m in RegExp(r'Relay\(\s*"([^"]+)"').allMatches(overlayCpp))
      m.group(1)!,
  };

  test('the overlay sweep sees what it must (a regex gone blind fails here)',
      () {
    expect(overlayCalls,
        containsAll(['ready', 'firstFrame', 'commit', 'saveRegion', 'hide']));
    expect(overlayHandled, containsAll(['summon', 'hidden', 'commitCurrent']));
    expect(overlayAnswered, containsAll(['ready', 'commit']));
    expect(overlaySent,
        containsAll(['summon', 'hidden', 'setActive', 'commitCurrent']));
    // One Dart user of the channel: a second would call the runner from
    // outside this sweep.
    final users = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            f.readAsStringSync().contains('app.orthant/overlay'))
          f.path.replaceAll(r'\', '/'),
    ];
    expect(users, ['lib/overlay/overlay_main.dart']);
  });

  test('every call overlayMain makes is answered by the runner', () {
    expect(overlayCalls.difference(overlayAnswered), isEmpty,
        reason: 'windows_overlay_set.cpp ignores these, and overlayMain waits '
            'on a reply or a state change that never comes');
  });

  test('every call the runner makes to a panel is handled by overlayMain', () {
    expect(overlaySent.difference(overlayHandled), isEmpty);
  });

  // The shell's surfaces are named twice: Dart's capture never takes one as a
  // target (windows_capture.dart), and the runner's click-away ends a grid when
  // the foreground moves to one, whatever its process: a File Explorer window
  // can share a process with the desktop, the taskbar and Alt+Tab, so for a
  // grid opened over one the process alone cannot tell them apart. Menus
  // are left out on purpose: the captured app's own menu is not going
  // elsewhere.
  test('the runner ends a grid on every shell surface the capture skips', () {
    final dart = File('lib/core/windows_capture.dart').readAsStringSync();
    final sets = RegExp(
        r'const Set<String> k(?:Desktop|Tray|ShellSurface)Classes = \{(.*?)\};',
        dotAll: true);
    final classes = {
      for (final set in sets.allMatches(dart))
        for (final c in RegExp(r"'([^']+)'").allMatches(set.group(1)!))
          c.group(1)!,
    }..remove('#32768');
    final list = RegExp(r'kShellSurfaces\[\] = \{(.*?)\};', dotAll: true)
        .firstMatch(overlayCpp);
    final runner = {
      for (final c in RegExp(r'L"([^"]+)"').allMatches(list?.group(1) ?? ''))
        c.group(1)!,
    };
    expect(classes, hasLength(8), reason: 'the sweep must see all three sets');
    expect(runner.containsAll(classes), isTrue,
        reason: 'missing from the runner: ${classes.difference(runner)}');
  });

  // The payloads themselves: a key spelled one way on one side and another way
  // on the other is not an error anywhere, it is a field that reads as absent
  // and quietly takes its default (a scale of 1, no press, no session). Every
  // key the runner reads must be one Dart writes, and every key it writes one
  // Dart reads, on both channels.
  final runnerSources = [cpp, overlayCpp];
  // The save-region's block crosses as a list of names in a loop, not as
  // literals at a call: read from the overlay, written to Dart.
  final blockKeys = {
    for (final src in runnerSources)
      for (final list in RegExp(r'for \(const char\* key : \{([^}]*)\}\)')
          .allMatches(src))
        for (final k in RegExp(r'"(\w+)"').allMatches(list.group(1)!))
          k.group(1)!,
  };
  final runnerReads = {
    for (final src in runnerSources)
      for (final m in RegExp(r'Field\([^;]*?,\s*"(\w+)"\)').allMatches(src))
        m.group(1)!,
    ...blockKeys,
  };
  final runnerWrites = {
    for (final src in runnerSources)
      for (final m in RegExp(r'EncodableValue\("(\w+)"\)').allMatches(src))
        m.group(1)!,
    ...blockKeys,
  };
  // The Dart that talks to the runner: the Windows controller, the hotkey
  // service (both of app.orthant/window), the overlay (app.orthant/overlay),
  // and the coordinator, which reads the save-region's block.
  final dartSources = [
    'lib/core/window_controller_windows.dart',
    'lib/shortcuts/hotkey_service.dart',
    'lib/overlay/overlay_main.dart',
    'lib/app/coordinator.dart',
  ].map((f) => File(f).readAsStringSync()).toList();
  // A map literal's keys, in either quote style (`prefer_single_quotes` is
  // off); `case 'summon':` is a method name, not a key.
  final writeKey = RegExp(r'''(?<!case )['"](\w+)['"]:''');
  final readKey = RegExp(r'''(?:\[|read\(|intOf\()\s*['"](\w+)['"]''');
  // Whole-line comments are prose, which quotes words too ("placed": ...).
  String code(String src) => src
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');
  Set<String> keys(RegExp re, Iterable<String> sources) => {
        for (final src in sources)
          for (final m in re.allMatches(code(src))) m.group(1)!,
      };
  final dartWrites = keys(writeKey, dartSources);
  final dartReads = keys(readKey, dartSources);

  test('the key sweeps see what they must (a regex gone blind fails here)', () {
    // The keys no test checked across the seam before (W3's list), and the
    // block's.
    const crossing = [
      'sessionId', 'x', 'y', 'w', 'h', 'block', 'scale', 'warm', 'triggerMs',
      'pressedAtMs',
    ];
    expect(runnerReads.union(runnerWrites), containsAll(crossing));
    expect(blockKeys, {'cols', 'rows', 'c0', 'c1', 'r0', 'r1'});
    expect(runnerReads, containsAll(['captureId', 'appIcon', 'pid', 'png']));
    expect(dartReads, containsAll(['triggerMs', 'pressedAtMs', 'c0', 'scale']));
  });

  test('every key the runner reads is one Dart writes', () {
    expect(runnerReads.difference(dartWrites), isEmpty,
        reason: 'the runner reads these and Dart never sends them');
  });

  test('every key the runner writes is one Dart reads', () {
    expect(runnerWrites.difference(dartReads), isEmpty,
        reason: 'the runner sends these and Dart never reads them');
  });

  // The two Dart files that speak only to the runner (on Windows), checked in
  // the other direction too: nothing they send is ignored, and nothing they
  // read is never sent.
  final windowsSources = [
    'lib/core/window_controller_windows.dart',
    'lib/overlay/overlay_main.dart',
  ].map((f) => File(f).readAsStringSync()).toList();

  test("every key the Windows controller and the overlay write, the runner "
      'reads', () {
    expect(keys(writeKey, windowsSources).difference(runnerReads), isEmpty,
        reason: 'Dart sends these and the runner ignores them');
  });

  test("every key the Windows controller and the overlay read, the runner "
      'writes', () {
    expect(keys(readKey, windowsSources).difference(runnerWrites), isEmpty,
        reason: 'Dart reads these and the runner never sends them');
  });

  test('the key sweeps see a double-quoted key', () {
    expect(writeKey.firstMatch('{"x": 1}')?.group(1), 'x');
    expect(readKey.firstMatch('a["x"]')?.group(1), 'x');
    expect(writeKey.firstMatch("case 'summon':"), isNull);
  });

  // The two summons, field by field. The sets above pool every message, so a
  // key swapped for one that crosses elsewhere passes them (the panel
  // summon's `appIcon` written as `png`, setAppIcon's key); and these are the
  // payloads whose fields are optional, so a lost one reads as absent.
  String span(String src, String start, String end) {
    final i = src.indexOf(start);
    expect(i, isNonNegative, reason: 'no "$start"');
    final j = src.indexOf(end, i + start.length);
    expect(j, greaterThan(i), reason: 'no end after "$start"');
    return src.substring(i, j);
  }

  test('the panel summon: overlayMain reads every field the runner writes, '
      'and no other', () {
    final writes = {
      for (final m in RegExp(r'EncodableValue\("(\w+)"\)').allMatches(span(
          overlayCpp,
          'flutter::EncodableMap WindowsOverlaySet::SummonPayload(',
          '\n}\n')))
        m.group(1)!,
    };
    final reads = keys(readKey, [
      span(File('lib/overlay/overlay_main.dart').readAsStringSync(),
          "case 'summon':", "case '"),
    ]);
    expect(writes, hasLength(greaterThan(10)));
    expect(reads, writes);
  });

  test('showOverlay: the runner reads every field Dart sends, and no other',
      () {
    final sends = keys(writeKey, [
      span(File('lib/core/window_controller_windows.dart').readAsStringSync(),
          'kShowOverlay, {', '});'),
    ]);
    final reads = {
      for (final m in RegExp(r'Field\([^;]*?,\s*"(\w+)"\)').allMatches(
          span(cpp, 'method == "showOverlay"', '} else if (method ==')))
        m.group(1)!,
    };
    expect(sends, hasLength(5));
    expect(reads, sends);
  });

  test('Dart\'s shortcut ids end just below the runner\'s first grab id', () {
    // One number on each side of the seam: a shortcut at the grab id would
    // fire the grid's Esc, or be swallowed as one.
    final dartMax = int.parse(RegExp(r'static const int _maxId = (\d+);')
        .firstMatch(File('lib/shortcuts/hotkey_service.dart').readAsStringSync())!
        .group(1)!);
    final header = File('windows/runner/windows_overlay_set.h').readAsStringSync();
    final firstGrab = int.parse(RegExp(r'static constexpr int kFirstGrabId = (\d+);')
        .firstMatch(header)!
        .group(1)!);
    expect(dartMax + 1, firstGrab);
    // Every entry of the table, whatever its spacing or modifier: a pattern
    // that read only some let the rest through at any id.
    final grabs = _grabTable(overlayCpp);
    expect(grabs, isNotEmpty);
    expect(grabs.every((g) => g.id >= firstGrab && g.id <= 0xBFFF), isTrue,
        reason: 'ids: ${grabs.map((g) => g.id).join(', ')}');
  });

  // The grid's key grabs are one table in C++ (kGrabs) and one in Dart
  // (windowsOverlayGrabs), which refuses a shortcut on any of them: a chord
  // added to one and not the other is either a dead grid key or a refusal of
  // a chord the grid never takes.
  test('the grid grabs exactly the chords Dart refuses as shortcuts', () {
    final grabs = _grabTable(overlayCpp);
    final chords = {for (final g in grabs) (g.modifiers, g.vk)};
    // One chord per entry: a duplicate would collapse into the set unseen.
    expect(chords, hasLength(grabs.length),
        reason: 'the table must hold each chord once');
    expect(chords, {for (final g in windowsOverlayGrabs) (g.modifiers, g.vk)});
  });
}
