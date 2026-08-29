import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

/// Build refs through a function, never a `const` expression.
///
/// This is load-bearing, and a first draft of this file got it wrong. Dart
/// canonicalizes const instances, so `const BuiltIn(x) == const BuiltIn(x)` is
/// true under plain *identity* equality — an equality test written with const
/// literals passes with `operator ==` deleted, which is exactly the vacuous test
/// mutation testing exists to catch. A function call is never canonicalized, so
/// these are genuinely distinct objects.
CommandRef builtIn(ShortcutCommand c) => BuiltIn(c);
CommandRef custom(String id) => Custom(id);

void main() {
  test('two refs to the same command are equal and hash alike', () {
    expect(builtIn(ShortcutCommand.leftHalf), builtIn(ShortcutCommand.leftHalf));
    expect(builtIn(ShortcutCommand.leftHalf).hashCode,
        builtIn(ShortcutCommand.leftHalf).hashCode);
    expect(custom('r7fk2'), custom('r7fk2'));
    expect(custom('r7fk2').hashCode, custom('r7fk2').hashCode);
  });

  test('different refs are unequal, across kinds', () {
    expect(
      builtIn(ShortcutCommand.leftHalf) == builtIn(ShortcutCommand.rightHalf),
      isFalse,
    );
    expect(custom('a') == custom('b'), isFalse);
    expect(builtIn(ShortcutCommand.leftHalf) == custom('leftHalf'), isFalse);
  });

  test('works as a Set member and a Map key', () {
    // This is what `unavailable` does, and what a broken == would silently turn
    // into "no combo is ever unavailable" — a defect that compiles, analyzes
    // clean, and only shows up when someone drives the app.
    final set = <CommandRef>{
      builtIn(ShortcutCommand.leftHalf),
      custom('a'),
    };
    expect(set.contains(builtIn(ShortcutCommand.leftHalf)), isTrue);
    expect(set.contains(custom('a')), isTrue);
    expect(set.contains(custom('b')), isFalse);
    expect(set.contains(builtIn(ShortcutCommand.center)), isFalse);

    final map = <CommandRef, int>{custom('a'): 1};
    expect(map[custom('a')], 1);
  });

  test('jsonName round-trips both kinds', () {
    for (final ref in <CommandRef>[
      const BuiltIn(ShortcutCommand.showGrid),
      const BuiltIn(ShortcutCommand.center),
      const Custom('r7fk2'),
    ]) {
      expect(CommandRef.tryParse(ref.jsonName), ref);
    }
    expect(const BuiltIn(ShortcutCommand.leftHalf).jsonName, 'leftHalf');
    expect(const Custom('r7fk2').jsonName, 'custom:r7fk2');
  });

  test('tryParse rejects what it cannot make sense of', () {
    expect(CommandRef.tryParse('notACommand'), isNull);
    expect(CommandRef.tryParse('custom:'), isNull);
    expect(CommandRef.tryParse(''), isNull);
  });

  test('switches exhaustively', () {
    String kind(CommandRef ref) => switch (ref) {
          BuiltIn() => 'builtin',
          Custom() => 'custom',
        };
    expect(kind(const BuiltIn(ShortcutCommand.maximize)), 'builtin');
    expect(kind(const Custom('a')), 'custom');
  });
}
