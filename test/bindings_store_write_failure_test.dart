import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/bindings_store.dart';

import 'support/carbon_terms.dart';

// A file of its own on purpose. SharedPreferences.setMockInitialValues swaps
// the store for the whole test isolate, and these tests need the default one:
// the real preferences cache in front of a disk faked on the plugin channel,
// because a failed write is exactly where the two disagree. setString puts
// the value in the cache before the write is known to have failed, so only a
// restart that re-reads the disk can show what a failure left behind.

const _channel = MethodChannel('plugins.flutter.io/shared_preferences');
const _v2Key = 'flutter.orthant.bindings.v2';
const _v3Key = 'flutter.orthant.bindings.v3';

final _v2 = jsonEncode({
  'bindings': [
    {'command': 'center', 'keyCode': 17, 'modifiers': kControlOption},
    {'command': 'custom:r1', 'keyCode': 37, 'modifiers': kControlOption},
  ],
  'regions': [
    {'id': 'r1', 'name': 'Left ⅔', 'cols': 3, 'rows': 1, 'c0': 0, 'c1': 1,
        'r0': 0, 'r1': 0},
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Map<String, Object> disk;
  late String writes; // 'ok', 'throw' or 'false'

  setUp(() {
    disk = {_v2Key: _v2};
    writes = 'ok';
    messenger.setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case 'getAll':
        case 'getAllWithParameters':
          return Map<String, Object>.of(disk);
        case 'setString':
          if (writes == 'throw') throw PlatformException(code: 'disk-full');
          if (writes == 'false') return false;
          final args = call.arguments as Map;
          disk[args['key'] as String] = args['value'] as Object;
          return true;
      }
      return null;
    });
    SharedPreferences.resetStatic();
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    SharedPreferences.resetStatic();
  });

  /// A launch: nothing cached, everything read from the disk again.
  Future<StoredBindings> launch() {
    SharedPreferences.resetStatic();
    return BindingsStore().load();
  }

  Binding of(StoredBindings s, String name) =>
      s.bindings.firstWhere((b) => b.command.jsonName == name);

  for (final failure in ['throw', 'false']) {
    test('a migration whose write fails ($failure) still loads, and the next '
        'launch migrates again', () async {
      writes = failure;
      final first = await launch();
      expect(of(first, 'center').keyCode, 17, reason: 'usable at once');
      expect(of(first, 'custom:r1').keyCode, 37);
      expect(first.regions.single.id, 'r1');
      expect(disk.containsKey(_v3Key), isFalse, reason: 'nothing was written');
      expect(disk[_v2Key], _v2, reason: 'v2 is never touched');
      // Within the same session the cache may already hold v3 (setString
      // stores it before the write fails); it holds the same shortcuts.
      expect((await BindingsStore().load()).bindings, first.bindings);

      writes = 'ok';
      final second = await launch();
      expect(second.bindings, first.bindings);
      expect(second.regions, first.regions);
      expect(disk.containsKey(_v3Key), isTrue, reason: 'the retry landed');
      expect(disk[_v2Key], _v2);

      // And it does not run a third time: with v3 on the disk, a v2 changed
      // underneath (a downgraded build's edit) is not read.
      disk[_v2Key] = jsonEncode({'bindings': [], 'regions': []});
      final third = await launch();
      expect(third.bindings, first.bindings);
      expect(third.regions, first.regions);
    });
  }

  test('a launch with nothing stored writes nothing', () async {
    disk = {};
    final loaded = await launch();
    expect(loaded.bindings, macDefaults);
    expect(disk, isEmpty);
  });
}
