import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/bindings_store.dart';
import 'package:orthant/shortcuts/custom_region.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

import 'support/carbon_terms.dart';

/// Preload the prefs key the store reads, with whatever raw string a corrupt or
/// older install might have left there.
void _stored(String raw) =>
    SharedPreferences.setMockInitialValues({'orthant.bindings.v1': raw});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load returns defaults when nothing is stored', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await BindingsStore().load()).bindings, macDefaults);
  });

  test('save then load round-trips a custom binding', () async {
    SharedPreferences.setMockInitialValues({});
    final store = BindingsStore();
    // Replace by command, not by index: load() rebuilds the list in enum order,
    // so a positional edit would only pass while the edited slot happened to
    // match the command that lives there.
    final custom = [
      for (final b in macDefaults)
        if (b.command == const BuiltIn(ShortcutCommand.leftHalf))
          Binding(BuiltIn(ShortcutCommand.leftHalf), carbon(123, kControlKey | kShiftKey))
        else
          b,
    ];
    await store.save(custom, const []);
    expect((await store.load()).bindings, custom);
  });

  test('saves exactly the bytes 1.0.3 saved', () async {
    // Storage does not move in this commit; only what is in memory changes.
    // This is the document 1.0.3's serializer wrote for these bindings.
    SharedPreferences.setMockInitialValues({});
    const left = CustomRegion(id: 'r1', name: 'Left ⅔', cols: 3, rows: 1,
        c0: 0, c1: 1, r0: 0, r1: 0);
    const right = CustomRegion(id: 'r2', name: 'Right ⅓', cols: 3, rows: 1,
        c0: 2, c1: 2, r0: 0, r1: 0);
    final bindings = [
      for (final b in macDefaults)
        switch ((b.command as BuiltIn).command) {
          ShortcutCommand.showGrid =>
            Binding(b.command, carbon(5, kControlOption | kShiftKey)),
          ShortcutCommand.center =>
            Binding(b.command, carbon(42, kControlOption | kCmdKey)),
          ShortcutCommand.maximize => Binding.unbound(b.command),
          _ => b,
        },
      Binding(const Custom('r1'), carbon(37, kControlOption | kShiftKey)),
      const Binding.unbound(Custom('r2')),
    ];
    await BindingsStore().save(bindings, const [left, right]);
    expect((await SharedPreferences.getInstance()).getString('orthant.bindings.v2'),
        '{"bindings":[{"command":"showGrid","keyCode":5,"modifiers":6656},{"command":"leftHalf","keyCode":123,"modifiers":6144},{"command":"rightHalf","keyCode":124,"modifiers":6144},{"command":"topHalf","keyCode":126,"modifiers":6144},{"command":"bottomHalf","keyCode":125,"modifiers":6144},{"command":"topLeft","keyCode":32,"modifiers":6144},{"command":"topRight","keyCode":34,"modifiers":6144},{"command":"bottomLeft","keyCode":38,"modifiers":6144},{"command":"bottomRight","keyCode":40,"modifiers":6144},{"command":"maximize","keyCode":-1,"modifiers":0},{"command":"center","keyCode":42,"modifiers":6400},{"command":"custom:r1","keyCode":37,"modifiers":6656},{"command":"custom:r2","keyCode":-1,"modifiers":0}],"regions":[{"id":"r1","name":"Left ⅔","cols":3,"rows":1,"c0":0,"c1":1,"r0":0,"r1":0},{"id":"r2","name":"Right ⅓","cols":3,"rows":1,"c0":2,"c1":2,"r0":0,"r1":0}]}');
  });

  // Everything below is about surviving a prefs file we did not write. load()
  // runs before the shortcuts are registered, so anything it throws takes the
  // whole feature down at launch with no way for the user to recover short of
  // deleting the preferences by hand.

  test('unparseable JSON falls back to the defaults', () async {
    _stored('{ this is not json');
    expect((await BindingsStore().load()).bindings, macDefaults);
  });

  test('JSON of the wrong shape falls back to the defaults', () async {
    _stored('{"command":"leftHalf"}'); // an object where a list belongs
    expect((await BindingsStore().load()).bindings, macDefaults);
  });

  test('an entry naming a command that no longer exists is dropped', () async {
    _stored(jsonEncode([
      {'command': 'quadrantOfMars', 'keyCode': 1, 'modifiers': kControlOption},
      {'command': 'center', 'keyCode': 99, 'modifiers': kCmdKey},
    ]));
    final loaded = (await BindingsStore().load()).bindings;
    expect(loaded.length, ShortcutCommand.values.length);
    expect(loaded.firstWhere((b) => b.command == const BuiltIn(ShortcutCommand.center)),
        Binding(BuiltIn(ShortcutCommand.center), carbon(99, kCmdKey)));
  });

  test('an entry with a malformed field is dropped, not the whole file',
      () async {
    _stored(jsonEncode([
      {'command': 'leftHalf', 'keyCode': 'twelve', 'modifiers': kControlOption},
      {'command': 'center', 'keyCode': 99, 'modifiers': kCmdKey},
    ]));
    final loaded = (await BindingsStore().load()).bindings;
    // leftHalf reverts to its default; center keeps what was stored.
    expect(loaded.firstWhere((b) => b.command == const BuiltIn(ShortcutCommand.leftHalf)),
        macDefaults.firstWhere((b) => b.command == const BuiltIn(ShortcutCommand.leftHalf)));
    expect(loaded.firstWhere((b) => b.command == const BuiltIn(ShortcutCommand.center)).keyCode, 99);
  });

  test('a key code the native side would trap on is rejected', () async {
    // Not a bad shortcut — a hard crash. keyCode and modifiers cross to Swift
    // as UInt32, whose initialiser traps on a negative value, and this runs on
    // the launch path. -1 is the "unbound" sentinel and is filtered by isBound;
    // -2 is not, so it used to sail through to UInt32(-2).
    for (final bad in [-2, -1000, 0x80, 99999]) {
      _stored(jsonEncode([
        {'command': 'leftHalf', 'keyCode': bad, 'modifiers': kControlOption},
      ]));
      final loaded = (await BindingsStore().load()).bindings;
      expect(
          loaded.firstWhere((b) => b.command == const BuiltIn(ShortcutCommand.leftHalf)),
          macDefaults
              .firstWhere((b) => b.command == const BuiltIn(ShortcutCommand.leftHalf)),
          reason: 'keyCode $bad must not survive into a registration');
    }
  });

  test('a negative or oversized modifier mask is rejected', () async {
    for (final bad in [-1, 0x1FFFF]) {
      _stored(jsonEncode([
        {'command': 'center', 'keyCode': 8, 'modifiers': bad},
      ]));
      final loaded = (await BindingsStore().load()).bindings;
      expect(loaded.firstWhere((b) => b.command == const BuiltIn(ShortcutCommand.center)).modifiers,
          kControlOption,
          reason: 'modifiers $bad must not survive into a registration');
    }
  });

  test('a bound combo with no modifier is rejected', () async {
    // Registering a bare key as a *global* hotkey takes that key away from
    // every other app for as long as Orthant runs. The recorder refuses to
    // produce one; a hand-edited file must not be able to either.
    _stored(jsonEncode([
      {'command': 'center', 'keyCode': 8, 'modifiers': 0},
    ]));
    final loaded = (await BindingsStore().load()).bindings;
    expect(loaded.firstWhere((b) => b.command == const BuiltIn(ShortcutCommand.center)).modifiers,
        kControlOption);
  });

  test('load always yields one entry per command, in enum order', () async {
    // A file written by an older version knows nothing about a command added
    // since. The settings list looks its binding up with firstWhere, so a gap
    // is a StateError in the UI rather than a missing row.
    _stored(jsonEncode([
      {'command': 'center', 'keyCode': 99, 'modifiers': kCmdKey},
    ]));
    final loaded = (await BindingsStore().load()).bindings;
    expect(loaded.map((b) => b.command),
        [for (final c in ShortcutCommand.values) BuiltIn(c)]);
  });

  test('a stored unbound command stays unbound', () async {
    // Clearing a shortcut is a real choice; "no combo" must not read as
    // "missing entry" and get quietly restored to the default.
    _stored(jsonEncode([{'command': 'maximize', 'keyCode': -1, 'modifiers': 0}]));
    final loaded = (await BindingsStore().load()).bindings;
    expect(loaded.firstWhere((b) => b.command == const BuiltIn(ShortcutCommand.maximize)).isBound,
        isFalse);
  });

  group('v2 with custom regions', () {
    const region = CustomRegion(
      id: 'r1',
      name: 'Left ⅔',
      cols: 3,
      rows: 1,
      c0: 0,
      c1: 1,
      r0: 0,
      r1: 0,
    );

    test('round-trips regions and their bindings', () async {
      SharedPreferences.setMockInitialValues({});
      final store = BindingsStore();
      await store.save(
        [
          ...macDefaults,
          Binding(Custom('r1'), carbon(123, kControlOption | kShiftKey)),
        ],
        const [region],
      );

      final loaded = await store.load();
      expect(loaded.regions, const [region]);
      expect(loaded.bindings.last.command, const Custom('r1'));
      expect(loaded.bindings.last.keyCode, 123);
    });

    test('built-ins come first in enum order, then regions in list order',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = BindingsStore();
      await store.save(macDefaults, [
        region,
        region.copyWithId('r2').copyWith(name: 'Right ⅔'),
      ]);

      final loaded = await store.load();
      expect(loaded.bindings.length, ShortcutCommand.values.length + 2);
      for (var i = 0; i < ShortcutCommand.values.length; i++) {
        expect(loaded.bindings[i].command, BuiltIn(ShortcutCommand.values[i]));
      }
      expect(loaded.bindings[11].command, const Custom('r1'));
      expect(loaded.bindings[12].command, const Custom('r2'));
    });

    test('a region with no combo still gets an unbound row', () async {
      SharedPreferences.setMockInitialValues({});
      final store = BindingsStore();
      await store.save(macDefaults, const [region]);

      final loaded = await store.load();
      expect(loaded.bindings.last.command, const Custom('r1'));
      expect(loaded.bindings.last.isBound, isFalse);
    });

    test('a binding naming a region that did not survive is dropped', () async {
      SharedPreferences.setMockInitialValues({
        'orthant.bindings.v2': jsonEncode({
          'bindings': [
            {'command': 'custom:ghost', 'keyCode': 123, 'modifiers': 6144},
          ],
          // c1 == cols, so this region fails validation and is dropped. Its
          // binding must go with it: a row with no shape to place and no name
          // to show is worse than no row.
          'regions': [
            {
              'id': 'ghost',
              'name': 'n',
              'cols': 3,
              'rows': 1,
              'c0': 0,
              'c1': 3,
              'r0': 0,
              'r1': 0,
            },
          ],
        }),
      });

      final loaded = await BindingsStore().load();
      expect(loaded.regions, isEmpty);
      expect(loaded.bindings.any((b) => b.command is Custom), isFalse);
      expect(loaded.bindings.length, ShortcutCommand.values.length);
    });

    test('duplicate region ids are dropped after the first', () async {
      SharedPreferences.setMockInitialValues({
        'orthant.bindings.v2': jsonEncode({
          'bindings': const [],
          'regions': [region.toJson(), region.copyWith(name: 'Other').toJson()],
        }),
      });

      final loaded = await BindingsStore().load();
      expect(loaded.regions.length, 1);
      expect(loaded.regions.single.name, 'Left ⅔');
    });

    test('reads a v1 file unchanged when v2 is absent', () async {
      SharedPreferences.setMockInitialValues({
        'orthant.bindings.v1': jsonEncode([
          {'command': 'leftHalf', 'keyCode': 99, 'modifiers': 6144},
        ]),
      });

      final loaded = await BindingsStore().load();
      expect(loaded.regions, isEmpty);
      expect(
        loaded.bindings
            .firstWhere(
                (b) => b.command == const BuiltIn(ShortcutCommand.leftHalf))
            .keyCode,
        99,
      );
    });

    test('survives a corrupt v2 payload without throwing', () async {
      SharedPreferences.setMockInitialValues({
        'orthant.bindings.v2': '{not json',
      });
      final loaded = await BindingsStore().load();
      expect(loaded.bindings.length, ShortcutCommand.values.length);
      expect(loaded.regions, isEmpty);
    });
  });
}
