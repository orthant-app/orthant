import 'package:flutter/foundation.dart';

import 'key_chord.dart';

/// What the platform calls the keys of a shortcut.
///
/// macOS draws its modifiers as glyphs in Apple's order and runs a chord
/// together (⌃⌥←); Windows names them, Win first, and joins them with a plus
/// (Win+Ctrl+Shift+←). Named keys follow suit: ↩ is Enter on Windows and ⎋ is
/// Esc. The arrows keep their glyphs on both, and letters, digits, function
/// keys and punctuation read alike, so the shared table in `bindings.dart`
/// labels those and this names only what differs. macOS's words are exactly
/// what 1.0.x shows.
///
/// Free of any widget tree on purpose: the tray, which has none, labels the
/// grid's chord with these, and so does the settings window.
class KeyWords {
  const KeyWords._({
    required this.modifiers,
    required this.joiner,
    required this.spacedJoiner,
    required this.menuGap,
    required this.escape,
    required this.system,
    required this.named,
  });

  /// Each modifier and its name, in the order the platform writes them.
  final List<({Modifiers flag, String name})> modifiers;

  /// Between the parts of a chord in running text.
  final String joiner;

  /// Between the parts of a chord the recorder shows while it listens.
  final String spacedJoiner;

  /// Between a menu item's label and its shortcut.
  final String menuGap;

  /// The Escape key, as a sentence names it.
  final String escape;

  /// The operating system, as a sentence names it.
  final String system;

  /// The keys this platform names otherwise than the shared table, by USB HID
  /// usage.
  final Map<int, String> named;

  static const macOS = KeyWords._(
    modifiers: [
      (flag: Modifiers.ctrl, name: '⌃'),
      (flag: Modifiers.alt, name: '⌥'),
      (flag: Modifiers.shift, name: '⇧'),
      (flag: Modifiers.meta, name: '⌘'),
    ],
    joiner: '',
    spacedJoiner: ' ',
    // tray_manager 0.5.3 sets no key equivalent on macOS, so the combo goes
    // inline in the label (`main.dart`).
    menuGap: '   ',
    escape: 'esc',
    system: 'macOS',
    named: {},
  );

  static const windows = KeyWords._(
    modifiers: [
      (flag: Modifiers.meta, name: 'Win'),
      (flag: Modifiers.ctrl, name: 'Ctrl'),
      (flag: Modifiers.alt, name: 'Alt'),
      (flag: Modifiers.shift, name: 'Shift'),
    ],
    joiner: '+',
    spacedJoiner: '+',
    // A native menu draws whatever follows a tab in its right-aligned
    // accelerator column.
    menuGap: '\t',
    escape: 'Esc',
    system: 'Windows',
    named: {
      0x00070028: 'Enter', 0x0007002C: 'Space', 0x0007002B: 'Tab',
      0x0007002A: 'Backspace', 0x00070029: 'Esc', 0x0007004A: 'Home',
      0x0007004D: 'End', 0x0007004B: 'PgUp', 0x0007004E: 'PgDn',
      0x0007004C: 'Del', 0x00070053: 'Num Lock', 0x00070058: 'Num Enter',
    },
  );

  /// The app runs on macOS and Windows only; anything else (a test host)
  /// reads as macOS, where it began.
  static KeyWords of(TargetPlatform platform) =>
      platform == TargetPlatform.windows ? windows : macOS;

  /// For the running platform. Read at use, so a test can name its platform.
  static KeyWords get current => of(defaultTargetPlatform);

  /// The modifiers [held], named in the platform's order.
  List<String> modifierNames(Modifiers held) => [
    for (final m in modifiers)
      if (held.has(m.flag)) m.name,
  ];

  /// The platform's own name for the key at [usage], or null where it draws
  /// the shared glyph.
  String? keyName(int? usage) => named[usage];

  /// [parts] as one chord in running text.
  String join(Iterable<String> parts) => parts.join(joiner);

  /// [parts] as the recorder shows them while it listens.
  String joinSpaced(Iterable<String> parts) => parts.join(spacedJoiner);

  /// [label] with [shortcut] beside it, in a menu.
  String menuItem(String label, String shortcut) => '$label$menuGap$shortcut';

  /// Every modifier, the way a sentence lists the ones a combination needs.
  String get anyModifier {
    final names = [for (final m in modifiers) m.name];
    return '${names.take(names.length - 1).join(', ')} or ${names.last}';
  }

  /// Shift, as a sentence names it.
  String get shiftName => modifierNames(Modifiers.shift).single;
}
