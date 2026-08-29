import 'region_commands.dart';

/// Everything the user can bind a global shortcut to.
///
/// The ten placements keep their own closed [RegionCommand] enum — that is what
/// lets `rectForCommand` switch exhaustively over regions and nothing else —
/// and this wraps them so the grid summon can share the binding list, the
/// recorder, the persistence and, most importantly, the **collision check**.
///
/// One namespace is the whole point. Binding `⌃⌥O` to a region has to unbind
/// the summon, and `withRebind`/`conflictFor` can only do that if both live in
/// the same list. Two lists would mean two recorders, two collision checks, and
/// a combination silently registered twice — which is exactly the Carbon
/// shadowing that `withRebind` exists to prevent.
enum ShortcutCommand {
  showGrid,
  leftHalf,
  rightHalf,
  topHalf,
  bottomHalf,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  maximize,
  center;

  /// The region this places a window into, or null for [showGrid], which opens
  /// the overlay instead of placing anything.
  ///
  /// Written as an exhaustive switch rather than a name lookup so the compiler
  /// carries one half of the guarantee: adding a [ShortcutCommand] without a
  /// case here fails to compile. The other half — adding a [RegionCommand]
  /// without a counterpart here — is covered by `shortcut_command_test.dart`,
  /// because a mapping that quietly returned null would turn a region shortcut
  /// into a second way to open the grid.
  RegionCommand? get region => switch (this) {
        ShortcutCommand.showGrid => null,
        ShortcutCommand.leftHalf => RegionCommand.leftHalf,
        ShortcutCommand.rightHalf => RegionCommand.rightHalf,
        ShortcutCommand.topHalf => RegionCommand.topHalf,
        ShortcutCommand.bottomHalf => RegionCommand.bottomHalf,
        ShortcutCommand.topLeft => RegionCommand.topLeft,
        ShortcutCommand.topRight => RegionCommand.topRight,
        ShortcutCommand.bottomLeft => RegionCommand.bottomLeft,
        ShortcutCommand.bottomRight => RegionCommand.bottomRight,
        ShortcutCommand.maximize => RegionCommand.maximize,
        ShortcutCommand.center => RegionCommand.center,
      };
}
