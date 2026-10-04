import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every method Dart can send on `app.orthant/window` from code that runs on
/// Windows must be answered by `windows/runner/window_channel.cpp`, and every
/// callback the runner sends must be handled by Dart (Windows design §5.1). A
/// caller with no native branch gets `NotImplemented`, which Dart surfaces as
/// `MissingPluginException`, and several callers neither await nor catch: W0's
/// plan missed `configFirstFrame` exactly this way, and only review caught it.
/// This test is that sweep, run on every change.
void main() {
  final constants = <String, String>{
    for (final m in RegExp(r"const String (k\w+) = '([^']+)';")
        .allMatches(File('lib/core/channel.dart').readAsStringSync()))
      m.group(1)!: m.group(2)!,
  };

  String resolve(String arg) => arg.startsWith("'")
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
      for (final m in RegExp(r"invoke(?:List|Map)?Method(?:<[^(]*>)?\(\s*(k\w+|'[^']+')")
          .allMatches(src)) {
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
    for (final m in RegExp(r'InvokeMethod\("([^"]+)"').allMatches(cpp)) m.group(1)!,
  };

  test('the sweep sees the calls it must (a regex gone blind fails here)', () {
    expect(dartCalls(),
        containsAll(['showConfigWindow', 'configFirstFrame', 'replaceHotkeys']));
    expect(answered, isNotEmpty);
    expect(sent, isNotEmpty);
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
      for (final m in RegExp(r"call\.method == (k\w+|'[^']+')").allMatches(dart))
        resolve(m.group(1)!),
    };
    expect(sent.difference(handled), isEmpty);
  });
}
