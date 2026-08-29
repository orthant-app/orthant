import '../core/grid_config.dart';

/// Clamps on a grid axis.
///
/// Below two there is no grid to speak of; past twelve the miniature's cells
/// are smaller than the pointer that has to hit them, and the overlay stops
/// being aimable. These bound the settings pane's steppers *and* whatever a
/// hand-edited preferences file contains.
const int kMinGridAxis = 2;
const int kMaxGridAxis = 12;

/// Points of gap, when gaps are on. The cap is generous rather than principled:
/// it exists so a hand-edited value cannot consume the whole display.
const int kMaxGapSize = 64;
const int kDefaultGapSize = 8;

/// Everything the user can configure that is not a keyboard shortcut.
///
/// Two deliberate absences:
///
/// * **The summon shortcut** is a [Binding] like any other placement, so it
///   lives in the bindings list where it can share one recorder and one
///   collision check. See `ShortcutCommand`.
/// * **Launch-at-login** is owned by `SMAppService`. A copy here would disagree
///   the moment the user turns the login item off in System Settings, which
///   macOS does not tell us about.
class Settings {
  const Settings({
    // Sourced from grid_config rather than restated, so the default and the
    // geometry cannot drift apart.
    this.gridCols = kDefaultGridCols,
    this.gridRows = kDefaultGridRows,
    this.gaps = false,
    this.gapSize = kDefaultGapSize,
  });

  final int gridCols;
  final int gridRows;
  final bool gaps;

  /// Points of screen inset *and* inter-window gutter — one number, per spec §8.
  ///
  /// Orthant places into `visibleFrame`, which already excludes the menu bar and
  /// the notch, so the usual reason to want a separate top inset is gone before
  /// the setting exists.
  ///
  /// Kept when [gaps] is false rather than zeroed, so switching gaps off and on
  /// again returns the value the user chose instead of a default.
  final int gapSize;

  /// The gap to hand to `gridBlock` — zero unless gaps are on.
  ///
  /// Read this rather than [gapSize] at every call site; it is the difference
  /// between "the size the user picked" and "the size in force".
  double get effectiveGap => gaps ? gapSize.toDouble() : 0;

  Settings clamped() => Settings(
        gridCols: gridCols.clamp(kMinGridAxis, kMaxGridAxis),
        gridRows: gridRows.clamp(kMinGridAxis, kMaxGridAxis),
        gaps: gaps,
        gapSize: gapSize.clamp(0, kMaxGapSize),
      );

  Settings copyWith({
    int? gridCols,
    int? gridRows,
    bool? gaps,
    int? gapSize,
  }) =>
      Settings(
        gridCols: gridCols ?? this.gridCols,
        gridRows: gridRows ?? this.gridRows,
        gaps: gaps ?? this.gaps,
        gapSize: gapSize ?? this.gapSize,
      );

  Map<String, Object?> toJson() => {
        'gridCols': gridCols,
        'gridRows': gridRows,
        'gaps': gaps,
        'gapSize': gapSize,
      };

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      other.gridCols == gridCols &&
      other.gridRows == gridRows &&
      other.gaps == gaps &&
      other.gapSize == gapSize;

  @override
  int get hashCode => Object.hash(gridCols, gridRows, gaps, gapSize);

  @override
  String toString() =>
      'Settings($gridCols x $gridRows, gaps=$gaps/$gapSize pt)';
}
