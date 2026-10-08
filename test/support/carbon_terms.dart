import 'package:flutter/foundation.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/core/carbon_keys.dart';
import 'package:orthant/shortcuts/custom_region.dart';
import 'package:orthant/core/key_chord.dart';

export 'package:orthant/core/carbon_keys.dart';

// This suite's shortcuts were written as Carbon key codes and masks, the way
// Orthant 1.0.x stored them (123 is the left arrow, 6144 is ⌃⌥). These keep
// every one of those numbers meaning what it always meant now that a binding
// holds a KeyChord: `carbon` builds a chord through the migration's own
// converter, and the getters read one back. A suite that still states its
// expectations in the old numbers is the evidence that the neutral bindings
// changed nothing on macOS.

/// The chord an earlier version stored as [keyCode] and [mask].
KeyChord carbon(int keyCode, int mask) {
  final chord = chordFromCarbon(keyCode, mask);
  if (chord == null) {
    throw ArgumentError('no chord for Carbon key code $keyCode, mask $mask');
  }
  return chord;
}

/// The macOS defaults, which is what `kDefaultBindings` was.
List<Binding> get macDefaults =>
    defaultBindings(platform: TargetPlatform.macOS, altGr: false);

/// Keyboard labels written by Carbon key code, keyed the way the seam keys
/// them now (USB HID usage).
Map<int, String> labelsByCarbon(Map<int, String> byCarbon) => {
      for (final entry in byCarbon.entries)
        physicalFromCarbon(entry.key)!: entry.value,
    };

extension ChordInCarbon on KeyChord {
  int get keyCode => carbonKeyCode(physical)!;
  int get carbonMask => carbonModifiers(modifiers);
}

extension BindingInCarbon on Binding {
  int get keyCode => chord?.keyCode ?? kUnboundKey;
  int get modifiers => chord?.carbonMask ?? 0;
}

/// On the region picker's draft. Written as the record type itself, which is
/// what `RegionDraft` names, so this file needs nothing from the UI.
extension DraftInCarbon on ({CustomRegion region, KeyChord? chord}) {
  int get keyCode => chord?.keyCode ?? kUnboundKey;
  int get modifiers => chord?.carbonMask ?? 0;
}
