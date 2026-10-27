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
/// SHA-256 of [bytes], as lowercase hex. The suite has no crypto package and
/// this is all it needs of one, so it is written out; [main] pins it to two
/// known answers before it is trusted with a vendored file.
String _sha256(List<int> bytes) {
  const k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  const mask = 0xffffffff;
  int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & mask;
  var h = <int>[
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  final padded = <int>[...bytes, 0x80];
  while (padded.length % 64 != 56) {
    padded.add(0);
  }
  final bits = bytes.length * 8;
  for (var i = 7; i >= 0; i--) {
    padded.add((bits >> (i * 8)) & 0xff);
  }
  for (var o = 0; o < padded.length; o += 64) {
    final w = List<int>.filled(64, 0);
    for (var t = 0; t < 16; t++) {
      w[t] = (padded[o + 4 * t] << 24) |
          (padded[o + 4 * t + 1] << 16) |
          (padded[o + 4 * t + 2] << 8) |
          padded[o + 4 * t + 3];
    }
    for (var t = 16; t < 64; t++) {
      final s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3);
      final s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10);
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & mask;
    }
    var [a, b, c, d, e, f, g, hh] = h;
    for (var t = 0; t < 64; t++) {
      final big1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ (~e & mask & g);
      final t1 = (hh + big1 + ch + k[t] + w[t]) & mask;
      final big0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (big0 + maj) & mask;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & mask;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & mask;
    }
    final next = [a, b, c, d, e, f, g, hh];
    h = [for (var i = 0; i < 8; i++) (h[i] + next[i]) & mask];
  }
  return h.map((x) => x.toRadixString(16).padLeft(8, '0')).join();
}

/// The lines of one section of an Inno Setup script: its name without the
/// brackets, then the lines under it with comments and blanks dropped. A
/// directive in a comment is no directive, so no check may see one.
Map<String, List<String>> _sections(String iss) {
  final sections = <String, List<String>>{};
  var current = '';
  for (final raw in iss.split('\n')) {
    final line = raw.replaceAll('\uFEFF', '').trim();
    if (line.isEmpty || line.startsWith(';') || line.startsWith('//')) continue;
    final header = RegExp(r'^\[(\w+)\]$').firstMatch(line);
    if (header != null) {
      current = header.group(1)!;
      continue;
    }
    sections.putIfAbsent(current, () => []).add(line);
  }
  return sections;
}

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
    expect(
        keys(writeKey, windowsSources).difference(runnerReads), isEmpty,
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

  // The app's language is resolved once, in the main engine, and reaches each
  // panel's own engine only inside the summon: Dart hands it to the runner
  // with the grid's settings and the runner puts it in every payload. A seam
  // that dropped it would leave the grid English for a Chinese reader, and no
  // Dart test would notice.
  test('the language crosses the runner: setOverlayGrid reads it and every '
      'summon carries it', () {
    expect(
        RegExp(r'Field\([^;]*?,\s*"locale"\)').hasMatch(
            span(cpp, 'method == "setOverlayGrid"', '} else if (method ==')),
        isTrue,
        reason: 'window_channel.cpp does not read setOverlayGrid\'s locale');
    expect(
        span(overlayCpp, 'flutter::EncodableMap WindowsOverlaySet::SummonPayload(',
            '\n}\n'),
        contains('EncodableValue("locale")'));
  });

  test('on macOS the same: the channel reads the locale and the summon '
      'payload carries it', () {
    expect(File('macos/Runner/MainFlutterWindow.swift').readAsStringSync(),
        contains('a["locale"]'));
    expect(File('macos/Runner/OverlayPanelSet.swift').readAsStringSync(),
        contains('"locale":'));
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

  // Setup tells whether Orthant is running by its panels' window class and
  // its mutex, and asks it to quit with a registered message, each by name
  // (windows/installer/orthant.iss). A name changed on one side only makes
  // Setup believe Orthant is not running, and a silent update over a running
  // copy then fails on the files in use, which only the VM battery, not CI,
  // would notice.
  test('the installer finds and quits Orthant by the names the runner uses', () {
    String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');
    // The one name `pattern` captures in `src`: a pattern gone blind, or a
    // second, different name beside the first, fails here.
    String only(RegExp pattern, String src, String what) {
      final names = {for (final m in pattern.allMatches(src)) m.group(1)!};
      expect(names, hasLength(1), reason: what);
      return names.single;
    }

    final iss = read('windows/installer/orthant.iss');
    expect(
        only(RegExp(r"FindWindowByClassName\('([^']+)'\)"), iss, 'Setup: the panel class'),
        only(RegExp(r'kPanelClass\[\] = L"([^"]+)";'),
            read('windows/runner/windows_overlay_set.cpp'), 'the runner: the panel class'));
    expect(
        only(RegExp(r"CheckForMutexes\('([^']+)'\)"), iss, 'Setup: the mutex'),
        only(RegExp(r'CreateMutexW\(nullptr, FALSE, L"([^"]+)"\)'),
            read('windows/runner/main.cpp'), 'the runner: the mutex'));
    expect(
        only(RegExp(r"RegisterWindowMessage\('([^']+)'\)"), iss, 'Setup: the quit request'),
        only(RegExp(r'QuitRequestMessage\(\) \{\s*static const UINT message = '
                r'RegisterWindowMessageW\(L"([^"]+)"\);'),
            read('windows/runner/flutter_window.cpp'), 'the runner: the quit request'));
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
  // The installer speaks English, Simplified and Traditional Chinese by
  // Windows' display language (spec, "The installer"). Inno Setup 6.7.1 has no
  // official Chinese, so the two translations are vendored; and Orthant's own
  // texts live in [CustomMessages], one definition per language, because a
  // literal in the script would be English for everyone.
  group('the installer\'s languages', () {
    const dir = 'windows/installer';
    const languages = ['english', 'chinesesimplified', 'chinesetraditional'];

    String read(String path) =>
        File(path).readAsStringSync().replaceAll('\r\n', '\n');
    final iss = read('$dir/orthant.iss');
    final sections = _sections(iss);

    test('the SHA-256 written here agrees with two known answers', () {
      expect(_sha256(const []),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(_sha256('abc'.codeUnits),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      // Longer than one block, so the padding and the chaining are both used.
      expect(
          _sha256(('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')
              .codeUnits),
          '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
    });

    test('Setup picks by the display language and never asks', () {
      final setup = sections['Setup']!;
      // ShowLanguageDialog=no: the default would show "Select Language" to
      // everyone whose Windows is neither English nor Chinese.
      expect(setup, contains('ShowLanguageDialog=no'));
      // UsePreviousLanguage=no: its default reuses the language the last
      // install recorded, which for every existing install is English.
      expect(setup, contains('UsePreviousLanguage=no'));
    });

    test('[Languages] names English and the two vendored Chinese files', () {
      final entries = {
        for (final line in sections['Languages']!)
          RegExp(r'Name: "(\w+)"').firstMatch(line)!.group(1)!:
              RegExp(r'MessagesFile: "([^"]+)"').firstMatch(line)!.group(1)!,
      };
      expect(entries, {
        'english': 'compiler:Default.isl',
        'chinesesimplified': 'ChineseSimplified.isl',
        'chinesetraditional': 'ChineseTraditional.isl',
      });
      for (final name in ['ChineseSimplified.isl', 'ChineseTraditional.isl']) {
        expect(File('$dir/$name').existsSync(), isTrue, reason: name);
      }
    });

    test('each vendored file is the bytes the script says it is', () {
      // Recorded beside [Languages]: the file, where it came from, its hash.
      final recorded = RegExp(
              r'^; +(\w+\.isl)\n; +(https://\S+)\n; +sha256 ([0-9a-f]{64})$',
              multiLine: true)
          .allMatches(iss)
          .toList();
      expect([for (final m in recorded) m.group(1)],
          ['ChineseSimplified.isl', 'ChineseTraditional.isl']);
      for (final m in recorded) {
        final name = m.group(1)!;
        expect(
            m.group(2),
            'https://raw.githubusercontent.com/jrsoftware/issrc/is-6_7_1/'
            'Files/Languages/Unofficial/$name',
            reason: '$name comes from the tag the release runner compiles with');
        expect(_sha256(File('$dir/$name').readAsBytesSync()), m.group(3),
            reason: '$name was changed after it was vendored, or git rewrote '
                'its line endings');
      }
    });

    test('git stores the vendored files as they are', () {
      // Without this a checkout that converts line endings (a Windows
      // runner's default) changes the bytes, and the hash above with them.
      final attributes = File('.gitattributes').readAsStringSync();
      expect(attributes.split('\n').map((l) => l.trim()),
          contains('windows/installer/*.isl -text'));
    });

    test('every custom message is defined for all three languages', () {
      final defined = <String, Map<String, String>>{};
      for (final line in sections['CustomMessages']!) {
        final m = RegExp(r'^(\w+)\.(\w+)=(.+)$').firstMatch(line);
        expect(m, isNotNull, reason: 'unreadable line: $line');
        expect(languages, contains(m!.group(1)),
            reason: 'not a language of [Languages]: $line');
        final byLanguage = defined.putIfAbsent(m.group(2)!, () => {});
        expect(byLanguage, isNot(contains(m.group(1))),
            reason: 'defined twice: $line');
        byLanguage[m.group(1)!] = m.group(3)!;
      }
      expect(defined, isNotEmpty);
      for (final MapEntry(key: name, value: byLanguage) in defined.entries) {
        expect(byLanguage.keys.toSet(), languages.toSet(), reason: name);
        for (final text in byLanguage.values) {
          expect(text.trim(), isNotEmpty, reason: name);
          expect(text, isNot(contains('—')),
              reason: '$name: no em dash, in any language');
        }
      }
      // And every message the script uses is one of them.
      final used = {
        for (final m in RegExp(r"CustomMessage\('(\w+)'\)").allMatches(iss))
          m.group(1)!,
        for (final m in RegExp(r'\{cm:(\w+)').allMatches(iss)) m.group(1)!,
      };
      expect(used, isNotEmpty);
      expect(defined.keys.toSet(), used,
          reason: 'a message nothing uses, or one used and not defined');
    });

    test('English is what it was before the installer was translated', () {
      final english = {
        for (final line in sections['CustomMessages']!)
          if (line.startsWith('english.'))
            line.substring(8, line.indexOf('=')): line.substring(line.indexOf('=') + 1),
      };
      expect(english.values.toSet(), {
        'Launch Orthant',
        'Orthant is still running. Quit it from its icon in the notification '
            'area, then run Setup again.',
        'Orthant could not be updated, and some of its files were already '
            'replaced, so it was not started again. Run the installer again '
            'to finish installing it, or download Orthant from orthant.app.',
        'Orthant could not be updated, and whether its files are still whole '
            'could not be verified, so it was not started again. Run the '
            'installer again to finish installing it, or download Orthant '
            'from orthant.app.',
        'Orthant is still running. Quit it from its icon in the notification '
            'area, then uninstall it again.',
      });
    });

    test('no text a person reads is an English literal in the script', () {
      // A message box, the text Setup refuses with (`Result :=` in
      // PrepareToInstall) and a [Run] description each go through a custom
      // message. An English word pair inside a string literal on any of those
      // lines is the regression this guards; a computed answer such as
      // `Result := Found.Count > 0` carries none.
      final english = RegExp(r'[A-Za-z]{2,} [A-Za-z]{2,}');
      final literals = RegExp(r"'(?:[^']|'')*'|" r'"[^"]*"');
      var checked = 0;
      for (final MapEntry(key: section, value: lines) in sections.entries) {
        if (section == 'CustomMessages') continue;
        for (final line in lines) {
          if (!(line.contains('MsgBox(') ||
              line.startsWith('Result :=') ||
              line.contains('Description:'))) {
            continue;
          }
          checked++;
          for (final literal in literals.allMatches(line)) {
            expect(english.hasMatch(literal.group(0)!), isFalse,
                reason: 'English text in: $line');
          }
        }
      }
      expect(checked, greaterThanOrEqualTo(5),
          reason: 'the description and the four message texts were all seen');
      // And the five are each a custom message: not merely free of English,
      // which a literal in some other language would also be.
      expect(
          RegExp(r"(MsgBox|Result :=)[^\n]*CustomMessage\('").allMatches(iss),
          hasLength(4));
      expect(
          RegExp(r'Description: "\{cm:\w+\}"').allMatches(iss), hasLength(1));
    });
  });
}
