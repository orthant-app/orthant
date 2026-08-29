import 'shortcut_command.dart';

/// What a [Binding] is a binding *for*.
///
/// [ShortcutCommand] is a closed enum, and its closedness was load-bearing
/// twice over: its `index` was the native hotkey id, and its `name` is the
/// persistence key. Neither fits an open set of user-defined regions, so the
/// identity moves here and the enum stays exactly as it was — still closed,
/// still exhaustively switchable by `rectForCommand`.
///
/// **Sealed, not a bare `String`.** Placement dispatch must stay exhaustively
/// switchable; the codebase relies on that guarantee deliberately (see
/// `region_commands.dart` and `shortcut_command.dart`), and a string id would
/// discard it silently.
sealed class CommandRef {
  const CommandRef();

  /// The stable form written to preferences.
  String get jsonName;

  /// One persisted name, or null if this build cannot make sense of it.
  ///
  /// Null rather than throwing, for the same reason `Binding.tryFromJson` is
  /// tolerant: this parses a file we did not necessarily write, on the launch
  /// path, before any shortcut is registered.
  ///
  /// The `custom:` prefix is also what makes an *older* Orthant safe against a
  /// newer file: it falls into neither branch below, so a custom row is ignored
  /// and the ten defaults keep working.
  static CommandRef? tryParse(String name) {
    if (name.startsWith(_customPrefix)) {
      final id = name.substring(_customPrefix.length);
      return id.isEmpty ? null : Custom(id);
    }
    for (final command in ShortcutCommand.values) {
      // Not values.byName: it throws for a command this build doesn't have,
      // which is exactly what a file from a future version would contain.
      if (command.name == name) return BuiltIn(command);
    }
    return null;
  }

  static const String _customPrefix = 'custom:';
}

/// One of the eleven commands Orthant ships — the ten placements and the summon.
final class BuiltIn extends CommandRef {
  final ShortcutCommand command;
  const BuiltIn(this.command);

  @override
  String get jsonName => command.name;

  // Value equality is not boilerplate here. Dart gives classes *identity*
  // equality, and two call sites depend on the semantics the enum gave for
  // free: `general_pane.dart` compares with `==` to find the summon, and
  // `unavailable` is a Set membership test threaded through the coordinator,
  // the settings window and the ready screen. Without these the app compiles,
  // analyzes clean, and reports every combo as available and the summon as
  // unbound.
  @override
  bool operator ==(Object other) => other is BuiltIn && other.command == command;

  @override
  int get hashCode => command.hashCode;

  @override
  String toString() => 'BuiltIn(${command.name})';
}

/// A user-defined region, identified by `CustomRegion.id`.
final class Custom extends CommandRef {
  final String id;
  const Custom(this.id);

  @override
  String get jsonName => '${CommandRef._customPrefix}$id';

  @override
  bool operator ==(Object other) => other is Custom && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Custom($id)';
}
