import 'package:flutter/foundation.dart';

import '../l10n/strings.dart';
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
/// Windows' words are translatable strings (`keyCtrl`, `keyEnter`, ...), read
/// from `appStrings` each time [windows] is asked for, so they follow the
/// language the app is shown in. They are the legends printed on the keys, and
/// every language shipped so far keeps them in English; a language whose
/// keyboards print `STRG` can say so without a code change. macOS's words are
/// glyphs, which no language changes, and stay constants.
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

  /// The words Windows uses, in the language of [appStrings] as it is now.
  ///
  /// A getter, so a language change reaches the next read; do not hold on to
  /// the result across one. It is cheap (a list of four and a map of twelve),
  /// which matters because every Shortcuts row and the tray label read it.
  static KeyWords get windows {
    final s = appStrings;
    return KeyWords._(
      modifiers: [
        (flag: Modifiers.meta, name: s.keyWin),
        (flag: Modifiers.ctrl, name: s.keyCtrl),
        (flag: Modifiers.alt, name: s.keyAlt),
        (flag: Modifiers.shift, name: s.keyShift),
      ],
      joiner: '+',
      spacedJoiner: '+',
      // A native menu draws whatever follows a tab in its right-aligned
      // accelerator column.
      menuGap: '\t',
      escape: s.keyEsc,
      system: 'Windows',
      named: {
        0x00070028: s.keyEnter, 0x0007002C: s.keySpace, 0x0007002B: s.keyTab,
        0x0007002A: s.keyBackspace, 0x00070029: s.keyEsc,
        0x0007004A: s.keyHome, 0x0007004D: s.keyEnd, 0x0007004B: s.keyPageUp,
        0x0007004E: s.keyPageDown, 0x0007004C: s.keyDelete,
        0x00070053: s.keyNumLock, 0x00070058: s.keyNumEnter,
      },
    );
  }

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
  /// The list is a string of the language's own (`keyListAnyModifier`), for
  /// both platforms: macOS's four glyphs read "⌃, ⌥, ⇧ or ⌘" in English and
  /// "⌃、⌥、⇧ 或 ⌘" in Chinese.
  String get anyModifier {
    assert(modifiers.length == 4, 'the list sentence names exactly four keys');
    final n = [for (final m in modifiers) m.name];
    return appStrings.keyListAnyModifier(n[0], n[1], n[2], n[3]);
  }

  /// Shift, as a sentence names it.
  String get shiftName => modifierNames(Modifiers.shift).single;
}
