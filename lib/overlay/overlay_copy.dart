import 'package:flutter/foundation.dart';

import '../l10n/strings.dart';

/// The overlay's words for the keys it names, on the platform it runs on.
///
/// Three things differ: the key that places ([place]), the chord that places
/// and keeps the shape ([save]), and what a global coordinate is counted in
/// ([unit]): points on macOS, physical pixels on Windows (the coordinate
/// contract in `grid_overlay.dart`). Everything else the overlay says is the
/// same on both. macOS's words are exactly what 1.0.x said.
///
/// The sentences are ARB messages, so they are in the language this engine was
/// last told (`appStrings`, which each summon points at the summon's language),
/// and the key words are placeholders in them: they are printed on the
/// keyboard in English, so they stay English in every language.
class OverlayCopy {
  const OverlayCopy._({
    required this.place,
    required this.save,
    required this.pixels,
  });

  /// The key that places the window.
  final String place;

  /// The chord that places the window and offers the shape as a shortcut.
  final String save;

  /// Whether a coordinate is a physical pixel (Windows) rather than a point.
  final bool pixels;

  static const macOS = OverlayCopy._(place: 'Return', save: '⌘S', pixels: false);
  static const windows =
      OverlayCopy._(place: 'Enter', save: 'Ctrl+S', pixels: true);

  /// The overlay runs on macOS and Windows only; anything else (a test host)
  /// reads as macOS, where it began.
  static OverlayCopy of(TargetPlatform platform) =>
      platform == TargetPlatform.windows ? windows : macOS;

  /// For the running platform. Read at use, so a test can name its platform.
  static OverlayCopy get current => of(defaultTargetPlatform);

  /// What the spoken target's numbers count.
  String get unit =>
      pixels ? appStrings.overlayUnitPixels : appStrings.overlayUnitPoints;

  /// The caption under the panel.
  String get saveHint => appStrings.overlaySaveHint(save);

  /// The grid's accessibility hint.
  String get gridHint => appStrings.overlayGridHint(place);

  /// Spoken by the active panel when a grid opens.
  String opened(String appName, int cols, int rows) => appStrings.overlayOpened(
      appName.isEmpty ? appStrings.overlayCapturedWindow : appName,
      appStrings.overlayColumns(cols),
      appStrings.overlayRows(rows),
      place);
}
