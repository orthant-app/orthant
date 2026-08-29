import Cocoa
import ApplicationServices

enum Accessibility {
  static func isTrusted() -> Bool {
    return AXIsProcessTrusted()
  }

  static func requestTrust() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [key: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  /// macOS users expect Reduce Motion to kill transitions; all overlay motion
  /// is gated on this. Read natively and delivered in the summon payload
  /// rather than costing a separate round trip.
  static func reduceMotionEnabled() -> Bool {
    return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }
}
