import Carbon.HIToolbox
import Cocoa

/// What each physical key prints under the keyboard layout the user has
/// selected right now.
///
/// A shortcut is stored as a Carbon key code — a *position* on the keyboard —
/// and Dart's fallback table names those positions with the letters of the US
/// layout. On Dvorak, AZERTY or a Cyrillic layout the printed keycap and the
/// label in the Shortcuts pane then disagree, so a user is told to press `⌃⌥O`
/// when the key that fires it says `R`. This asks the system's own layout data
/// what each position produces and hands that to Dart as display data only:
/// bindings keep their key codes, so a layout switch changes what is *shown*,
/// never what *fires*.
enum KeyboardLayout {
  /// Keypad positions. `UCKeyTranslate` renders these as plain digits and
  /// operators, indistinguishable from the top row, so Dart's own `Num 1`
  /// style labels stay in charge of them.
  static let keypadKeyCodes: Set<Int> = [
    65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 95,
  ]

  /// Labels for every key code in `0...127` that produces a printable
  /// character under `source`, or under the current keyboard layout when
  /// `source` is nil. Positions that translate to nothing printable — arrows,
  /// Return, the function keys, dead positions — are absent, which is the
  /// signal for Dart to fall back to its own glyph for them.
  ///
  /// `TISCopyCurrentKeyboardLayoutInputSource` answers with a *layout* even
  /// when the selected input source is an input method (Japanese, Pinyin):
  /// the method's underlying layout is what the physical keys still print.
  static func labels(for source: TISInputSource? = nil) -> [Int: String] {
    let layoutSource: TISInputSource
    if let source = source {
      layoutSource = source
    } else if let current = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() {
      layoutSource = current
    } else {
      return [:]
    }
    guard let raw = TISGetInputSourceProperty(layoutSource, kTISPropertyUnicodeKeyLayoutData) else {
      return [:]
    }
    let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
    return data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [Int: String] in
      guard let base = bytes.baseAddress else { return [:] }
      let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
      let keyboardType = UInt32(LMGetKbdType())
      var out: [Int: String] = [:]
      var chars = [UniChar](repeating: 0, count: 4)
      for code in 0...127 where !keypadKeyCodes.contains(code) {
        var deadKeyState: UInt32 = 0
        var length = 0
        // No modifiers: the label is the key's unshifted character, and
        // `kUCKeyActionDisplay` with dead keys suppressed asks for what the
        // key *shows* rather than what a second press would compose.
        let status = UCKeyTranslate(
          layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, keyboardType,
          UInt32(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
          chars.count, &length, &chars)
        guard status == noErr, length > 0 else { continue }
        if let label = displayLabel(String(utf16CodeUnits: chars, count: length)) {
          out[code] = label
        }
      }
      return out
    }
  }

  /// The keycap form of a translated string, or nil when it is not something a
  /// keycap could show. Pure, so it is unit-tested directly.
  ///
  /// Rejected: control characters (Return, Tab, Delete), whitespace (Space —
  /// Dart draws `␣`), and the private-use range where macOS parks the arrows
  /// and function keys (`U+F700…`). Letters are uppercased the way macOS menus
  /// print shortcut keys, unless uppercasing changes the length (`ß` → `SS`),
  /// in which case the character stays as it is.
  static func displayLabel(_ translated: String) -> String? {
    guard translated.count == 1 else { return nil }
    for scalar in translated.unicodeScalars {
      switch scalar.properties.generalCategory {
      case .control, .format, .surrogate, .privateUse, .unassigned,
           .spaceSeparator, .lineSeparator, .paragraphSeparator:
        return nil
      default:
        continue
      }
    }
    let upper = translated.uppercased()
    return upper.count == 1 ? upper : translated
  }

  /// Calls `handler` on the main queue whenever the user switches input
  /// source, for as long as the returned token is retained. The notification
  /// is distributed (system-wide) because the switch happens in the menu bar
  /// or by a system shortcut, never inside this process.
  static func observeChanges(_ handler: @escaping () -> Void) -> NSObjectProtocol {
    DistributedNotificationCenter.default().addObserver(
      forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
      object: nil, queue: .main) { _ in handler() }
  }

  /// A specific installed-or-not layout by its input source id, for tests
  /// that must not depend on which layout the machine running them has
  /// selected. Nil when macOS does not know the id.
  static func source(withId id: String) -> TISInputSource? {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue(),
          CFArrayGetCount(list) > 0 else { return nil }
    // The element is +0 and owned by the array; hold the array until the
    // element has been retained as a return value.
    return withExtendedLifetime(list) {
      unsafeBitCast(CFArrayGetValueAtIndex(list, 0), to: TISInputSource.self)
    }
  }
}
