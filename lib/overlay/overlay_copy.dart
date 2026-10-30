import 'package:flutter/foundation.dart';

import '../core/key_chord.dart';
import '../core/key_words.dart';
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
/// and the key words are placeholders in them. Those are the keys' legends,
/// strings of their own (`keyMacReturn`, `KeyWords.windows`), and they stay
/// English in every language shipped so far because the keyboards print them
/// that way.
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

  /// macOS's words: the Return legend places, and the glyph chord ⌘S saves.
  /// Return is the language's (`keyMacReturn`) and ⌘S, being glyphs, is not,
  /// so this is a getter like [windows].
  static OverlayCopy get macOS => OverlayCopy._(
    place: appStrings.keyMacReturn,
    save: '⌘S',
    pixels: false,
  );

  /// Windows' words: the Enter legend places, and the Ctrl legend joined to S
  /// the way Windows joins every combo (`Ctrl+S`) saves. They come from
  /// [KeyWords.windows], so they follow the language, which is why this is a
  /// getter and not a constant.
  static OverlayCopy get windows {
    final words = KeyWords.windows;
    return OverlayCopy._(
      place: words.keyName(_enterUsage)!,
      save: words.join([...words.modifierNames(Modifiers.ctrl), 'S']),
      pixels: true,
    );
  }

  /// Enter's USB HID usage: the key that places.
  static const _enterUsage = 0x00070028;

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
