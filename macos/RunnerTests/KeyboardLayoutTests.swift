import Cocoa
import XCTest

@testable import Orthant

/// The labels Dart shows for a shortcut follow the selected keyboard layout,
/// while the binding itself stays a physical position. These run against
/// named layouts rather than the machine's current one, so they mean the
/// same thing on a Canadian, US or Dvorak development machine.
final class KeyboardLayoutTests: XCTestCase {
  func testUSLayoutNamesThePositionsDartAssumes() throws {
    let us = try XCTUnwrap(KeyboardLayout.source(withId: "com.apple.keylayout.US"))
    let labels = KeyboardLayout.labels(for: us)
    XCTAssertEqual(labels[31], "O")
    XCTAssertEqual(labels[0], "A")
    XCTAssertEqual(labels[18], "1")
    XCTAssertEqual(labels[41], ";")
    XCTAssertEqual(labels[50], "`")
  }

  func testDvorakRelabelsTheSamePositions() throws {
    // Physical US `O` (code 31) prints `R` on Dvorak; US `S` (code 1) prints `O`.
    // The key codes are unchanged, which is the whole point: the binding is
    // the position, the label is what the position prints.
    let dvorak = try XCTUnwrap(KeyboardLayout.source(withId: "com.apple.keylayout.Dvorak"))
    let labels = KeyboardLayout.labels(for: dvorak)
    XCTAssertEqual(labels[31], "R")
    XCTAssertEqual(labels[1], "O")
    XCTAssertEqual(labels[0], "A")
  }

  func testKeysDartDrawsWithGlyphsAreLeftToDart() throws {
    let us = try XCTUnwrap(KeyboardLayout.source(withId: "com.apple.keylayout.US"))
    let labels = KeyboardLayout.labels(for: us)
    // Arrows, Return, Space, Tab, Delete, Escape and F-keys have fixed glyphs
    // in Dart; a layout must not override them with a control character.
    for code in [123, 124, 125, 126, 36, 49, 48, 51, 53, 122, 111] {
      XCTAssertNil(labels[code], "key code \(code)")
    }
    // The keypad prints digits that would collide with the top row.
    for code in KeyboardLayout.keypadKeyCodes {
      XCTAssertNil(labels[code], "keypad code \(code)")
    }
    XCTAssertTrue(labels.keys.allSatisfy { (0...127).contains($0) })
  }

  func testDisplayLabelKeepsOnlyPrintableSingleCharacters() {
    XCTAssertEqual(KeyboardLayout.displayLabel("o"), "O")
    XCTAssertEqual(KeyboardLayout.displayLabel("é"), "É")
    XCTAssertEqual(KeyboardLayout.displayLabel(";"), ";")
    XCTAssertEqual(KeyboardLayout.displayLabel("ß"), "ß", "uppercasing to SS would not fit a keycap")
    XCTAssertNil(KeyboardLayout.displayLabel(""))
    XCTAssertNil(KeyboardLayout.displayLabel(" "))
    XCTAssertNil(KeyboardLayout.displayLabel("\r"))
    XCTAssertNil(KeyboardLayout.displayLabel("\t"))
    XCTAssertNil(KeyboardLayout.displayLabel("\u{7F}"))
    XCTAssertNil(KeyboardLayout.displayLabel("\u{F700}"), "macOS's private-use arrow")
    XCTAssertNil(KeyboardLayout.displayLabel("ab"))
  }

  func testUnknownLayoutIdIsNilRatherThanACrash() {
    XCTAssertNil(KeyboardLayout.source(withId: "com.apple.keylayout.DoesNotExist"))
  }

  func testCurrentLayoutAnswersWithSomething() {
    // Whatever this machine has selected, a layout exists and letters print.
    XCTAssertFalse(KeyboardLayout.labels().isEmpty)
  }
}
