import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orthant/core/channel.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/bindings_store.dart';
import 'package:orthant/shortcuts/custom_region.dart';
import 'package:orthant/shortcuts/hotkey_service.dart';

import 'support/carbon_terms.dart';

/// What Orthant 1.0.3 writes, captured from its serializer (unchanged from the
/// 1.0.3 tag to the commit before neutral bindings): Open grid on ⌃⌥⇧G, Center
/// on ⌃⌥⌘\ (the backslash key, which once shared its Carbon code with a second
/// key), Maximize cleared, and two regions, one bound and one not.
const _synthetic103 =
    '{"bindings":[{"command":"showGrid","keyCode":5,"modifiers":6656},'
    '{"command":"leftHalf","keyCode":123,"modifiers":6144},'
    '{"command":"rightHalf","keyCode":124,"modifiers":6144},'
    '{"command":"topHalf","keyCode":126,"modifiers":6144},'
    '{"command":"bottomHalf","keyCode":125,"modifiers":6144},'
    '{"command":"topLeft","keyCode":32,"modifiers":6144},'
    '{"command":"topRight","keyCode":34,"modifiers":6144},'
    '{"command":"bottomLeft","keyCode":38,"modifiers":6144},'
    '{"command":"bottomRight","keyCode":40,"modifiers":6144},'
    '{"command":"maximize","keyCode":-1,"modifiers":0},'
    '{"command":"center","keyCode":42,"modifiers":6400},'
    '{"command":"custom:r1","keyCode":37,"modifiers":6656},'
    '{"command":"custom:r2","keyCode":-1,"modifiers":0}],'
    '"regions":[{"id":"r1","name":"Left ⅔","cols":3,"rows":1,"c0":0,"c1":1,"r0":0,"r1":0},'
    '{"id":"r2","name":"Right ⅓","cols":3,"rows":1,"c0":2,"c1":2,"r0":0,"r1":0}]}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(kOrthantChannel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// Everything the gate asks of a v2 document an earlier version wrote.
  Future<void> expectMigratesUnchanged(String v2) async {
    final stored = jsonDecode(v2) as Map;
    final entries = {
      for (final e in stored['bindings'] as List) (e as Map)['command']: e,
    };
    SharedPreferences.setMockInitialValues({'orthant.bindings.v2': v2});

    final migrated = await BindingsStore().load();

    // Nothing the earlier version stored is lost: every entry survives, as the
    // same Carbon pair, and every region as itself.
    for (final b in migrated.bindings) {
      final entry = entries[b.command.jsonName];
      if (entry == null) continue; // a command the file never mentioned
      expect((b.keyCode, b.modifiers), (entry['keyCode'], entry['modifiers']),
          reason: b.command.jsonName);
    }
    expect(migrated.bindings.map((b) => b.command.jsonName).toSet(),
        containsAll(entries.keys));
    expect(migrated.regions, [
      for (final r in stored['regions'] as List) CustomRegion.tryFromJson(r)!,
    ]);

    // The native side is handed exactly what the earlier version handed it:
    // the same ids, key codes and masks, in the same order.
    final sent = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent.addAll((call.arguments as Map)['bindings'] as List);
      return <int>[];
    });
    await HotkeyService(onCommand: (_) {}).apply(migrated.bindings);
    expect(sent, [
      for (var id = 0; id < migrated.bindings.length; id++)
        if (entries[migrated.bindings[id].command.jsonName] case final e?
            when e['keyCode'] != kUnboundKey)
          {'id': id, 'keyCode': e['keyCode'], 'modifiers': e['modifiers']},
    ]);

    // v2 is left byte for byte; v3 is written and reads back the same.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('orthant.bindings.v2'), v2);
    final v3 = prefs.getString('orthant.bindings.v3');
    expect(v3, isNotNull);
    SharedPreferences.setMockInitialValues({'orthant.bindings.v3': v3!});
    final again = await BindingsStore().load();
    expect(again.bindings, migrated.bindings);
    expect(again.regions, migrated.regions);
  }

  test('a document in 1.0.3\'s exact format migrates unchanged', () async {
    await expectMigratesUnchanged(_synthetic103);

    final loaded = await BindingsStore().load();
    Binding of(String name) =>
        loaded.bindings.firstWhere((b) => b.command.jsonName == name);
    expect(of('showGrid').chord, carbon(5, kControlOption | kShiftKey));
    expect(of('center').chord!.physical, PhysicalKeyboardKey.backslash.usbHidUsage);
    expect(of('maximize').isBound, isFalse);
    expect(of('custom:r1').chord, carbon(37, kControlOption | kShiftKey));
    expect(of('custom:r2').isBound, isFalse);
  });
}
