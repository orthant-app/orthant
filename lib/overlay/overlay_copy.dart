import 'package:flutter/foundation.dart';

/// The overlay's words for the keys it names, on the platform it runs on.
///
/// Three things differ: the key that places ([place]), the chord that places
/// and keeps the shape ([save]), and what a global coordinate is counted in
/// ([unit]): points on macOS, physical pixels on Windows (the coordinate
/// contract in `grid_overlay.dart`). Everything else the overlay says is the
/// same on both. macOS's words are exactly what 1.0.x said.
class OverlayCopy {
  const OverlayCopy._({
    required this.place,
    required this.save,
    required this.unit,
  });

  /// The key that places the window.
  final String place;

  /// The chord that places the window and offers the shape as a shortcut.
  final String save;

  /// What the spoken target's numbers count.
  final String unit;

  static const macOS = OverlayCopy._(place: 'Return', save: '⌘S', unit: 'points');
  static const windows =
      OverlayCopy._(place: 'Enter', save: 'Ctrl+S', unit: 'pixels');

  /// The overlay runs on macOS and Windows only; anything else (a test host)
  /// reads as macOS, where it began.
  static OverlayCopy of(TargetPlatform platform) =>
      platform == TargetPlatform.windows ? windows : macOS;

  /// For the running platform. Read at use, so a test can name its platform.
  static OverlayCopy get current => of(defaultTargetPlatform);

  /// The caption under the panel.
  String get saveHint => '$save  save this shape as a shortcut';

  /// The grid's accessibility hint.
  String get gridHint => 'Arrow keys move. Shift and arrow keys extend. '
      '$place places the window. Escape cancels.';

  /// Spoken by the active panel when a grid opens.
  String opened(String appName, int cols, int rows) =>
      'Grid open for ${appName.isEmpty ? 'the captured window' : appName}. '
      '$cols columns, $rows rows. Arrow keys move, Shift and arrows extend, '
      '$place places, Escape cancels.';
}
