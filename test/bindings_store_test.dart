import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/bindings_store.dart';
import 'package:orthant/shortcuts/custom_region.dart';
import 'package:orthant/core/key_chord.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

import 'support/carbon_terms.dart';

/// Preload the oldest prefs key the store reads, with whatever raw string a
/// corrupt or older install might have left there. Every test that uses this
/// is also a migration test: v1 is read only to be converted.
void _storedV1(String raw) =>
    SharedPreferences.setMockInitialValues({'orthant.bindings.v1': raw});

Binding _of(List<Binding> bindings, ShortcutCommand command) =>
    bindings.firstWhere((b) => b.command == BuiltIn(command));

Future<String?> _raw(String key) async =>
    (await SharedPreferences.getInstance()).getString(key);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load returns defaults when nothing is stored', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await BindingsStore().load()).bindings, macDefaults);
    expect(await _raw('orthant.bindings.v3'), isNull,
        reason: 'a first launch writes nothing until something changes');
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
          Binding(const BuiltIn(ShortcutCommand.leftHalf),
              carbon(123, kControlKey | kShiftKey))
        else
          b,
    ];
    await store.save(custom, const []);
    expect((await store.load()).bindings, custom);
  });

  test('save writes v3, and only v3', () async {
    SharedPreferences.setMockInitialValues({});
    await BindingsStore().save(macDefaults, const []);
    final doc = jsonDecode((await _raw('orthant.bindings.v3'))!) as Map;
    expect((doc['bindings'] as List).first, {
      'command': 'showGrid',
      'chord': {
        'physical': PhysicalKeyboardKey.keyO.usbHidUsage,
        'logical': LogicalKeyboardKey.keyO.keyId,
        'modifiers': ['ctrl', 'alt'],
      },
    });
    expect(await _raw('orthant.bindings.v2'), isNull);
    expect(await _raw('orthant.bindings.v1'), isNull);
  });

  test('the logical key survives a save, whatever the layout recorded', () async {
    // On Windows this is the key that registers. A chord recorded under
    // Dvorak, where the US O position types R, must come back holding R.
    SharedPreferences.setMockInitialValues({});
    final dvorak = KeyChord(
      physical: PhysicalKeyboardKey.keyO.usbHidUsage,
      logical: LogicalKeyboardKey.keyR.keyId,
      modifiers: Modifiers.ctrl | Modifiers.alt,
    );
    final bindings = [
      for (final b in macDefaults)
        if (b.command == const BuiltIn(ShortcutCommand.showGrid))
          Binding(b.command, dvorak)
        else
          b,
    ];
    await BindingsStore().save(bindings, const []);
    expect(_of((await BindingsStore().load()).bindings, ShortcutCommand.showGrid)
        .chord, dvorak);
  });

  // Everything below is about surviving a prefs file we did not write. load()
  // runs before the shortcuts are registered, so anything it throws takes the
  // whole feature down at launch with no way for the user to recover short of
  // deleting the preferences by hand.

  test('unparseable JSON falls back to the defaults', () async {
    _storedV1('{ this is not json');
    expect((await BindingsStore().load()).bindings, macDefaults);
  });

  test('JSON of the wrong shape falls back to the defaults', () async {
    _storedV1('{"command":"leftHalf"}'); // an object where a list belongs
    expect((await BindingsStore().load()).bindings, macDefaults);
  });

  test('an entry naming a command that no longer exists is dropped', () async {
    _storedV1(jsonEncode([
      {'command': 'quadrantOfMars', 'keyCode': 1, 'modifiers': kControlOption},
      {'command': 'center', 'keyCode': 99, 'modifiers': kCmdKey},
    ]));
    final loaded = (await BindingsStore().load()).bindings;
    expect(loaded.length, ShortcutCommand.values.length);
    expect(_of(loaded, ShortcutCommand.center),
        Binding(const BuiltIn(ShortcutCommand.center), carbon(99, kCmdKey)));
  });

  test('an entry with a malformed field is dropped, not the whole file',
      () async {
    _storedV1(jsonEncode([
      {'command': 'leftHalf', 'keyCode': 'twelve', 'modifiers': kControlOption},
      {'command': 'center', 'keyCode': 99, 'modifiers': kCmdKey},
    ]));
    final loaded = (await BindingsStore().load()).bindings;
    // leftHalf reverts to its default; center keeps what was stored.
    expect(_of(loaded, ShortcutCommand.leftHalf),
        _of(macDefaults, ShortcutCommand.leftHalf));
    expect(_of(loaded, ShortcutCommand.center).keyCode, 99);
  });

  test('a key code the native side would trap on is rejected', () async {
    // Not a bad shortcut but a hard crash, before neutral bindings: keyCode and
    // modifiers crossed to Swift as UInt32, whose initialiser traps on a
    // negative value, and this runs on the launch path.
    for (final bad in [-2, -1000, 0x80, 99999]) {
      _storedV1(jsonEncode([
        {'command': 'leftHalf', 'keyCode': bad, 'modifiers': kControlOption},
      ]));
      final loaded = (await BindingsStore().load()).bindings;
      expect(_of(loaded, ShortcutCommand.leftHalf),
          _of(macDefaults, ShortcutCommand.leftHalf),
          reason: 'keyCode $bad must not survive into a registration');
    }
  });

  test('a negative or oversized modifier mask is rejected', () async {
    for (final bad in [-1, 0x1FFFF]) {
      _storedV1(jsonEncode([
        {'command': 'center', 'keyCode': 8, 'modifiers': bad},
      ]));
      final loaded = (await BindingsStore().load()).bindings;
      expect(_of(loaded, ShortcutCommand.center).modifiers, kControlOption,
          reason: 'modifiers $bad must not survive into a registration');
    }
  });

  test('a bound combo with no modifier is rejected', () async {
    // Registering a bare key as a *global* hotkey takes that key away from
    // every other app for as long as Orthant runs. The recorder refuses to
    // produce one; a hand-edited file must not be able to either.
    _storedV1(jsonEncode([
      {'command': 'center', 'keyCode': 8, 'modifiers': 0},
    ]));
    final loaded = (await BindingsStore().load()).bindings;
    expect(_of(loaded, ShortcutCommand.center).modifiers, kControlOption);
  });

  test('load always yields one entry per command, in enum order', () async {
    // A file written by an older version knows nothing about a command added
    // since. The settings list looks its binding up with firstWhere, so a gap
    // is a StateError in the UI rather than a missing row.
    _storedV1(jsonEncode([
      {'command': 'center', 'keyCode': 99, 'modifiers': kCmdKey},
    ]));
    final loaded = (await BindingsStore().load()).bindings;
    expect(loaded.map((b) => b.command),
        [for (final c in ShortcutCommand.values) BuiltIn(c)]);
  });

  test('a stored unbound command stays unbound', () async {
    // Clearing a shortcut is a real choice; "no combo" must not read as
    // "missing entry" and get quietly restored to the default.
    _storedV1(jsonEncode([
      {'command': 'maximize', 'keyCode': kUnboundKey, 'modifiers': 0},
    ]));
    final loaded = (await BindingsStore().load()).bindings;
    expect(_of(loaded, ShortcutCommand.maximize).isBound, isFalse);
  });

  group('v3', () {
    Future<List<Binding>> loadV3(List<Object?> bindings) async {
      SharedPreferences.setMockInitialValues({
        'orthant.bindings.v3': jsonEncode({'bindings': bindings, 'regions': []}),
      });
      return (await BindingsStore().load()).bindings;
    }

    Map<String, Object?> centerOn(Map<String, Object?> chord) =>
        {'command': 'center', 'chord': chord};

    final valid = {
      'physical': PhysicalKeyboardKey.keyT.usbHidUsage,
      'logical': LogicalKeyboardKey.keyT.keyId,
      'modifiers': ['ctrl', 'shift'],
    };

    test('a stored chord loads as itself', () async {
      final loaded = await loadV3([centerOn(valid)]);
      expect(_of(loaded, ShortcutCommand.center),
          Binding(const BuiltIn(ShortcutCommand.center),
              carbon(17, kControlKey | kShiftKey)));
    });

    test('a null chord is an unbound command, kept unbound', () async {
      final loaded = await loadV3([
        {'command': 'center', 'chord': null},
      ]);
      expect(_of(loaded, ShortcutCommand.center).isBound, isFalse);
    });

    test('an entry with no chord field at all is dropped, not read as unbound',
        () async {
      final loaded = await loadV3([
        {'command': 'center'},
      ]);
      expect(_of(loaded, ShortcutCommand.center),
          _of(macDefaults, ShortcutCommand.center));
    });

    test('a modifier this build does not know drops the entry, not the flag',
        () async {
      // A newer build's file. Dropping only "hyper" would register ⌃T, a chord
      // nobody chose; the command falls back to its default instead.
      final loaded = await loadV3([
        centerOn({...valid, 'modifiers': ['ctrl', 'hyper']}),
      ]);
      expect(_of(loaded, ShortcutCommand.center),
          _of(macDefaults, ShortcutCommand.center));
    });

    test('a key this build cannot bind drops the entry', () async {
      for (final physical in [
        PhysicalKeyboardKey.tab.usbHidUsage,
        0x00070032,
        -1,
      ]) {
        final loaded = await loadV3([
          centerOn({...valid, 'physical': physical}),
        ]);
        expect(_of(loaded, ShortcutCommand.center),
            _of(macDefaults, ShortcutCommand.center),
            reason: 'physical $physical');
      }
    });

    test('no modifier, a bad logical key or a mistyped field drops the entry',
        () async {
      for (final chord in [
        {...valid, 'modifiers': <String>[]},
        {...valid, 'logical': 0},
        {...valid, 'logical': 'T'},
        {...valid, 'modifiers': 'ctrl'},
      ]) {
        final loaded = await loadV3([centerOn(chord)]);
        expect(_of(loaded, ShortcutCommand.center),
            _of(macDefaults, ShortcutCommand.center),
            reason: '$chord');
      }
    });

    test('a key holding something other than text never stops a launch',
        () async {
      // The newest key present is the one read, whatever it holds, and an
      // older key is never touched when a newer one exists: a stale v1 of the
      // wrong type must not stop a good v2 from loading, nor a v3 of the wrong
      // type throw instead of meaning "the defaults".
      final v2 = jsonEncode({
        'bindings': [
          {'command': 'center', 'keyCode': 17, 'modifiers': kControlOption},
        ],
        'regions': [],
      });
      SharedPreferences.setMockInitialValues(
          {'orthant.bindings.v1': 7, 'orthant.bindings.v2': v2});
      expect(_of((await BindingsStore().load()).bindings, ShortcutCommand.center)
          .keyCode, 17);

      SharedPreferences.setMockInitialValues(
          {'orthant.bindings.v3': 7, 'orthant.bindings.v2': v2});
      expect((await BindingsStore().load()).bindings, macDefaults);

      SharedPreferences.setMockInitialValues(
          {'orthant.bindings.v3': '', 'orthant.bindings.v2': v2});
      expect((await BindingsStore().load()).bindings, macDefaults,
          reason: 'an empty v3 is present, and unreadable');
    });

    test('a corrupt v3 is the defaults, never the older key it replaced',
        () async {
      // v2 is stale by definition once v3 exists. Falling back to it would
      // resurrect shortcuts the user has since changed.
      SharedPreferences.setMockInitialValues({
        'orthant.bindings.v3': '{not json',
        'orthant.bindings.v2': jsonEncode({
          'bindings': [
            {'command': 'center', 'keyCode': 17, 'modifiers': kControlOption},
          ],
          'regions': [],
        }),
      });
      final loaded = await BindingsStore().load();
      expect(loaded.bindings, macDefaults);
      expect(loaded.regions, isEmpty);
    });
  });

  group('migration', () {
    test('converts v2, writes v3, and leaves v2 exactly as it was', () async {
      final v2 = jsonEncode({
        'bindings': [
          {'command': 'center', 'keyCode': 17, 'modifiers': kControlOption},
        ],
        'regions': [],
      });
      SharedPreferences.setMockInitialValues({'orthant.bindings.v2': v2});

      final loaded = await BindingsStore().load();

      expect(_of(loaded.bindings, ShortcutCommand.center).keyCode, 17);
      expect(await _raw('orthant.bindings.v2'), v2,
          reason: 'a downgrade must read what it always did');
      final v3 = await _raw('orthant.bindings.v3');
      expect(v3, isNotNull);
      SharedPreferences.setMockInitialValues({'orthant.bindings.v3': v3!});
      expect((await BindingsStore().load()).bindings, loaded.bindings,
          reason: 'what was written reads back as what was migrated');
    });

    test('converts v1 the same way when v2 is absent, and leaves v1', () async {
      final v1 = jsonEncode([
        {'command': 'leftHalf', 'keyCode': 99, 'modifiers': 6144},
      ]);
      _storedV1(v1);
      final loaded = await BindingsStore().load();
      expect(loaded.regions, isEmpty);
      expect(_of(loaded.bindings, ShortcutCommand.leftHalf).keyCode, 99);
      expect(await _raw('orthant.bindings.v1'), v1);
      expect(await _raw('orthant.bindings.v3'), isNotNull);
    });

    test('runs once: with v3 present, v2 is never read again', () async {
      // The downgrade-and-return case. An older build, run after the
      // migration, writes only v2; that edit is invisible here by design.
      SharedPreferences.setMockInitialValues({
        'orthant.bindings.v2': jsonEncode({
          'bindings': [
            {'command': 'center', 'keyCode': 17, 'modifiers': kControlOption},
          ],
          'regions': [],
        }),
      });
      await BindingsStore().save(macDefaults, const []);
      expect(_of((await BindingsStore().load()).bindings, ShortcutCommand.center),
          _of(macDefaults, ShortcutCommand.center));
    });

    test('a mask with a stray bit drops that entry only', () async {
      // 1.0.x never wrote one; a hand-edited file can. Trimming the bit would
      // register a different chord, so the command keeps its default.
      SharedPreferences.setMockInitialValues({
        'orthant.bindings.v2': jsonEncode({
          'bindings': [
            {'command': 'center', 'keyCode': 17, 'modifiers': kControlOption | 1},
            {'command': 'leftHalf', 'keyCode': 99, 'modifiers': kCmdKey},
          ],
          'regions': [],
        }),
      });
      final loaded = (await BindingsStore().load()).bindings;
      expect(_of(loaded, ShortcutCommand.center),
          _of(macDefaults, ShortcutCommand.center));
      expect(_of(loaded, ShortcutCommand.leftHalf).keyCode, 99);
    });
  });

  group('with custom regions', () {
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
          Binding(const Custom('r1'), carbon(123, kControlOption | kShiftKey)),
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
