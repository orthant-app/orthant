import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The Dart-side patterns take either quote style: `prefer_single_quotes` is
// off, so a double-quoted name must not escape the sweep without failing it.
final _constant = RegExp(r'''const String (k\w+) = (['"])([^'"]+)\2;''');
final _invoke = RegExp(
    r'''invoke(?:List|Map)?Method(?:<[^(]*>)?\(\s*(k\w+|'[^']+'|"[^"]+")''');
final _handled = RegExp(r'''call\.method == (k\w+|'[^']+'|"[^"]+")''');

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

  final cpp = File('windows/runner/window_channel.cpp').readAsStringSync();
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
  final overlayCpp =
      File('windows/runner/windows_overlay_set.cpp').readAsStringSync();
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
}
