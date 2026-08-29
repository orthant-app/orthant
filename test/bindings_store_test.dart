import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/bindings_store.dart';
import 'package:orthant/shortcuts/custom_region.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

/// Preload the prefs key the store reads, with whatever raw string a corrupt or
/// older install might have left there.
void _stored(String raw) =>
    SharedPreferences.setMockInitialValues({'orthant.bindings.v1': raw});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load returns defaults when nothing is stored', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await BindingsStore().load()).bindings, kDefaultBindings);
  });

  test('save then load round-trips a custom binding', () async {
    SharedPreferences.setMockInitialValues({});
    final store = BindingsStore();
    // Replace by command, not by index: load() rebuilds the list in enum order,
    // so a positional edit would only pass while the edited slot happened to
    // match the command that lives there.
    final custom = [
      for (final b in kDefaultBindings)
        if (b.command == const BuiltIn(ShortcutCommand.leftHalf))
          const Binding(BuiltIn(ShortcutCommand.leftHalf), 123, kControlKey | kShiftKey)
        else
          b,
    ];
    await store.save(custom, const []);
    expect((await store.load()).bindings, custom);
  });

  // Everything below is about surviving a prefs file we did not write. load()
  // runs before the shortcuts are registered, so anything it throws takes the
  // whole feature down at launch with no way for the user to recover short of
  // deleting the preferences by hand.

  test('unparseable JSON falls back to the defaults', () async {
    _stored('{ this is not json');
    expect((await BindingsStore().load()).bindings, kDefaultBindings);
  });

  test('JSON of the wrong shape falls back to the defaults', () async {
    _stored('{"command":"leftHalf"}'); // an object where a list belongs
    expect((await BindingsStore().load()).bindings, kDefaultBindings);
  });

  test('an entry naming a command that no longer exists is dropped', () async {
    _stored(jsonEncode([
      {'command': 'quadrantOfMars', 'keyCode': 1, 'modifiers': kControlOption},
      {'command': 'center', 'keyCode': 99, 'modifiers': kCmdKey},
    ]));
    final loaded = (await BindingsStore().load()).bindings;
    expect(loaded.length, ShortcutCommand.values.length);
    expect(loaded.firstWhere((b) => b.command == const BuiltIn(ShortcutCommand.center)),
        const Binding(BuiltIn(ShortcutCommand.center), 99, kCmdKey));
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
        kDefaultBindings.firstWhere((b) => b.command == const BuiltIn(ShortcutCommand.leftHalf)));
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
          kDefaultBindings
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
    _stored(jsonEncode([Binding.unbound(BuiltIn(ShortcutCommand.maximize)).toJson()]));
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
          ...kDefaultBindings,
          const Binding(Custom('r1'), 123, kControlOption | kShiftKey),
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
      await store.save(kDefaultBindings, [
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
      await store.save(kDefaultBindings, const [region]);

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
