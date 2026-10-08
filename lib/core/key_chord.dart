import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, immutable, visibleForTesting;
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, PhysicalKeyboardKey;

/// The modifiers a shortcut holds, in no platform's encoding.
///
/// Its own type rather than a bare `int`. Bindings carried Carbon's masks (⌃
/// was 4096) until this type existed, and a Carbon mask arriving where this set
/// belongs would compile as an int and read as different modifiers, or as none.
/// As a type of its own it does not compile at all. `carbon_keys.dart` is the
/// one place the two encodings meet.
extension type const Modifiers._(int _bits) {
  static const none = Modifiers._(0);
  static const ctrl = Modifiers._(1);
  static const alt = Modifiers._(2);
  static const shift = Modifiers._(4);
  static const meta = Modifiers._(8);

  Modifiers operator |(Modifiers other) => Modifiers._(_bits | other._bits);

  /// Whether every flag in [flags] is held.
  bool has(Modifiers flags) => _bits & flags._bits == flags._bits;

  bool get isEmpty => _bits == 0;
}

/// One key combination, holding both of the ways a platform can name its key.
///
/// macOS registers a hotkey by the key's *position*. Windows registers it by
/// the key's *meaning*: it matches a hotkey against the layout of whichever app
/// is in front, so it cannot be asked for a position at all. A key event
/// carries both, so the recorder keeps both, and each platform reads its own.
@immutable
class KeyChord {
  const KeyChord({
    required this.physical,
    required this.logical,
    required this.modifiers,
  });

  /// The key's position, as its USB HID usage
  /// ([PhysicalKeyboardKey.usbHidUsage]). What macOS registers.
  final int physical;

  /// What the key meant under the layout it was recorded on
  /// ([LogicalKeyboardKey.keyId]). What Windows registers; macOS never reads
  /// it.
  final int logical;

  final Modifiers modifiers;

  /// [physical] with the logical key the US layout gives it, or null when
  /// [physical] is not a key a shortcut may use.
  ///
  /// For a chord no key event produced: the defaults, and a shortcut migrated
  /// from a file that stored positions only. Those files exist only on macOS,
  /// which never reads the logical key, so there it is a placeholder.
  static KeyChord? us(int physical, Modifiers modifiers) {
    final logical = _usLogicalKeys[physical];
    if (logical == null) return null;
    return KeyChord(physical: physical, logical: logical, modifiers: modifiers);
  }

  /// Whether pressing [other] fires this chord on the platform running now:
  /// the same modifiers on the same key, where "the same key" is the position
  /// on macOS and the meaning on Windows. Two commands holding chords that
  /// answer yes would be one hotkey registered twice.
  ///
  /// Read from [defaultTargetPlatform], like `createWindowController`, so a
  /// test can choose with `debugDefaultTargetPlatformOverride`.
  bool sameChordAs(KeyChord other) =>
      modifiers == other.modifiers &&
      (defaultTargetPlatform == TargetPlatform.windows
          ? logical == other.logical
          : physical == other.physical);

  /// As v3 stores it: both keys, and the modifiers by name.
  Map<String, Object?> toJson() => {
        'physical': physical,
        'logical': logical,
        'modifiers': [
          for (final (flag, name) in _modifierNames)
            if (modifiers.has(flag)) name,
        ],
      };

  /// One stored chord, or null if this build cannot register it.
  ///
  /// Strict about what it accepts, for the reason `Binding.tryFromJson` is
  /// tolerant: a key this build cannot bind, or a modifier it does not know,
  /// rejects the whole chord, and the command falls back to its default.
  /// Dropping only the unknown part would register a different chord from the
  /// one stored. And a bound chord needs a modifier, because a bare global
  /// hotkey takes its key from every app for as long as Orthant runs.
  static KeyChord? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final physical = raw['physical'];
    final logical = raw['logical'];
    final names = raw['modifiers'];
    if (physical is! int || logical is! int || names is! List) return null;
    if (!isBindableKey(physical) || logical <= 0) return null;
    var modifiers = Modifiers.none;
    for (final name in names) {
      final flag = _modifierFlags[name];
      if (flag == null) return null;
      modifiers = modifiers | flag;
    }
    if (modifiers.isEmpty) return null;
    return KeyChord(physical: physical, logical: logical, modifiers: modifiers);
  }

  @override
  bool operator ==(Object other) =>
      other is KeyChord &&
      other.physical == physical &&
      other.logical == logical &&
      other.modifiers == modifiers;

  @override
  int get hashCode => Object.hash(physical, logical, modifiers);

  @override
  String toString() => 'KeyChord(physical: 0x${physical.toRadixString(16)}, '
      'logical: 0x${logical.toRadixString(16)}, modifiers: $modifiers)';
}

/// The modifiers by the names v3 stores, in the order glyphs are drawn.
const _modifierNames = [
  (Modifiers.ctrl, 'ctrl'),
  (Modifiers.alt, 'alt'),
  (Modifiers.shift, 'shift'),
  (Modifiers.meta, 'meta'),
];

final Map<String, Modifiers> _modifierFlags = {
  for (final (flag, name) in _modifierNames) name: flag,
};

/// Whether a shortcut may use the key at [physical], a USB HID usage.
bool isBindableKey(int physical) => _usLogicalKeys.containsKey(physical);

/// Every key a shortcut may use, as USB HID usages.
@visibleForTesting
Iterable<int> get bindableKeys => _usLogicalKeys.keys;

/// Every key a shortcut may use, with the logical key the US layout gives it:
/// Flutter's own logical key of the same name, which is what the engine reports
/// for that position when no layout remaps it.
///
/// Tab is absent on purpose: ⌃⇥ and ⌘⇥ switch tabs and apps everywhere, and a
/// global hotkey would take them without a word. Escape is absent because it
/// cancels the recorder.
final Map<int, int> _usLogicalKeys = {
  for (final (physical, logical) in const [
    // Arrows, Return, Space.
    (PhysicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowLeft),
    (PhysicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowRight),
    (PhysicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowDown),
    (PhysicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowUp),
    (PhysicalKeyboardKey.enter, LogicalKeyboardKey.enter),
    (PhysicalKeyboardKey.space, LogicalKeyboardKey.space),
    // Letters.
    (PhysicalKeyboardKey.keyA, LogicalKeyboardKey.keyA),
    (PhysicalKeyboardKey.keyB, LogicalKeyboardKey.keyB),
    (PhysicalKeyboardKey.keyC, LogicalKeyboardKey.keyC),
    (PhysicalKeyboardKey.keyD, LogicalKeyboardKey.keyD),
    (PhysicalKeyboardKey.keyE, LogicalKeyboardKey.keyE),
    (PhysicalKeyboardKey.keyF, LogicalKeyboardKey.keyF),
    (PhysicalKeyboardKey.keyG, LogicalKeyboardKey.keyG),
    (PhysicalKeyboardKey.keyH, LogicalKeyboardKey.keyH),
    (PhysicalKeyboardKey.keyI, LogicalKeyboardKey.keyI),
    (PhysicalKeyboardKey.keyJ, LogicalKeyboardKey.keyJ),
    (PhysicalKeyboardKey.keyK, LogicalKeyboardKey.keyK),
    (PhysicalKeyboardKey.keyL, LogicalKeyboardKey.keyL),
    (PhysicalKeyboardKey.keyM, LogicalKeyboardKey.keyM),
    (PhysicalKeyboardKey.keyN, LogicalKeyboardKey.keyN),
    (PhysicalKeyboardKey.keyO, LogicalKeyboardKey.keyO),
    (PhysicalKeyboardKey.keyP, LogicalKeyboardKey.keyP),
    (PhysicalKeyboardKey.keyQ, LogicalKeyboardKey.keyQ),
    (PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR),
    (PhysicalKeyboardKey.keyS, LogicalKeyboardKey.keyS),
    (PhysicalKeyboardKey.keyT, LogicalKeyboardKey.keyT),
    (PhysicalKeyboardKey.keyU, LogicalKeyboardKey.keyU),
    (PhysicalKeyboardKey.keyV, LogicalKeyboardKey.keyV),
    (PhysicalKeyboardKey.keyW, LogicalKeyboardKey.keyW),
    (PhysicalKeyboardKey.keyX, LogicalKeyboardKey.keyX),
    (PhysicalKeyboardKey.keyY, LogicalKeyboardKey.keyY),
    (PhysicalKeyboardKey.keyZ, LogicalKeyboardKey.keyZ),
    // Digits.
    (PhysicalKeyboardKey.digit1, LogicalKeyboardKey.digit1),
    (PhysicalKeyboardKey.digit2, LogicalKeyboardKey.digit2),
    (PhysicalKeyboardKey.digit3, LogicalKeyboardKey.digit3),
    (PhysicalKeyboardKey.digit4, LogicalKeyboardKey.digit4),
    (PhysicalKeyboardKey.digit5, LogicalKeyboardKey.digit5),
    (PhysicalKeyboardKey.digit6, LogicalKeyboardKey.digit6),
    (PhysicalKeyboardKey.digit7, LogicalKeyboardKey.digit7),
    (PhysicalKeyboardKey.digit8, LogicalKeyboardKey.digit8),
    (PhysicalKeyboardKey.digit9, LogicalKeyboardKey.digit9),
    (PhysicalKeyboardKey.digit0, LogicalKeyboardKey.digit0),
    // Punctuation, and the extra ISO key beside left Shift.
    (PhysicalKeyboardKey.minus, LogicalKeyboardKey.minus),
    (PhysicalKeyboardKey.equal, LogicalKeyboardKey.equal),
    (PhysicalKeyboardKey.bracketLeft, LogicalKeyboardKey.bracketLeft),
    (PhysicalKeyboardKey.bracketRight, LogicalKeyboardKey.bracketRight),
    (PhysicalKeyboardKey.backslash, LogicalKeyboardKey.backslash),
    (PhysicalKeyboardKey.semicolon, LogicalKeyboardKey.semicolon),
    (PhysicalKeyboardKey.quote, LogicalKeyboardKey.quote),
    (PhysicalKeyboardKey.backquote, LogicalKeyboardKey.backquote),
    (PhysicalKeyboardKey.comma, LogicalKeyboardKey.comma),
    (PhysicalKeyboardKey.period, LogicalKeyboardKey.period),
    (PhysicalKeyboardKey.slash, LogicalKeyboardKey.slash),
    (PhysicalKeyboardKey.intlBackslash, LogicalKeyboardKey.intlBackslash),
    // Editing and navigation.
    (PhysicalKeyboardKey.backspace, LogicalKeyboardKey.backspace),
    (PhysicalKeyboardKey.home, LogicalKeyboardKey.home),
    (PhysicalKeyboardKey.pageUp, LogicalKeyboardKey.pageUp),
    (PhysicalKeyboardKey.delete, LogicalKeyboardKey.delete),
    (PhysicalKeyboardKey.end, LogicalKeyboardKey.end),
    (PhysicalKeyboardKey.pageDown, LogicalKeyboardKey.pageDown),
    // F1 to F20.
    (PhysicalKeyboardKey.f1, LogicalKeyboardKey.f1),
    (PhysicalKeyboardKey.f2, LogicalKeyboardKey.f2),
    (PhysicalKeyboardKey.f3, LogicalKeyboardKey.f3),
    (PhysicalKeyboardKey.f4, LogicalKeyboardKey.f4),
    (PhysicalKeyboardKey.f5, LogicalKeyboardKey.f5),
    (PhysicalKeyboardKey.f6, LogicalKeyboardKey.f6),
    (PhysicalKeyboardKey.f7, LogicalKeyboardKey.f7),
    (PhysicalKeyboardKey.f8, LogicalKeyboardKey.f8),
    (PhysicalKeyboardKey.f9, LogicalKeyboardKey.f9),
    (PhysicalKeyboardKey.f10, LogicalKeyboardKey.f10),
    (PhysicalKeyboardKey.f11, LogicalKeyboardKey.f11),
    (PhysicalKeyboardKey.f12, LogicalKeyboardKey.f12),
    (PhysicalKeyboardKey.f13, LogicalKeyboardKey.f13),
    (PhysicalKeyboardKey.f14, LogicalKeyboardKey.f14),
    (PhysicalKeyboardKey.f15, LogicalKeyboardKey.f15),
    (PhysicalKeyboardKey.f16, LogicalKeyboardKey.f16),
    (PhysicalKeyboardKey.f17, LogicalKeyboardKey.f17),
    (PhysicalKeyboardKey.f18, LogicalKeyboardKey.f18),
    (PhysicalKeyboardKey.f19, LogicalKeyboardKey.f19),
    (PhysicalKeyboardKey.f20, LogicalKeyboardKey.f20),
    // Numeric keypad, including its own Enter and decimal keys.
    (PhysicalKeyboardKey.numLock, LogicalKeyboardKey.numLock),
    (PhysicalKeyboardKey.numpadDivide, LogicalKeyboardKey.numpadDivide),
    (PhysicalKeyboardKey.numpadMultiply, LogicalKeyboardKey.numpadMultiply),
    (PhysicalKeyboardKey.numpadSubtract, LogicalKeyboardKey.numpadSubtract),
    (PhysicalKeyboardKey.numpadAdd, LogicalKeyboardKey.numpadAdd),
    (PhysicalKeyboardKey.numpadEnter, LogicalKeyboardKey.numpadEnter),
    (PhysicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad1),
    (PhysicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad2),
    (PhysicalKeyboardKey.numpad3, LogicalKeyboardKey.numpad3),
    (PhysicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad4),
    (PhysicalKeyboardKey.numpad5, LogicalKeyboardKey.numpad5),
    (PhysicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad6),
    (PhysicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad7),
    (PhysicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad8),
    (PhysicalKeyboardKey.numpad9, LogicalKeyboardKey.numpad9),
    (PhysicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad0),
    (PhysicalKeyboardKey.numpadDecimal, LogicalKeyboardKey.numpadDecimal),
    (PhysicalKeyboardKey.numpadEqual, LogicalKeyboardKey.numpadEqual),
    (PhysicalKeyboardKey.numpadComma, LogicalKeyboardKey.numpadComma),
    // JIS keys with a dedicated position.
    (PhysicalKeyboardKey.intlRo, LogicalKeyboardKey.intlRo),
    (PhysicalKeyboardKey.intlYen, LogicalKeyboardKey.intlYen),
  ])
    physical.usbHidUsage: logical.keyId,
};
