import 'package:flutter/material.dart';

import '../shortcuts/bindings.dart';
import 'mac_theme.dart';
import 'keyboard_labels.dart';

/// A single physical-looking key, the way macOS renders shortcut glyphs.
///
/// Extracted so the shortcuts list and onboarding draw the *same* key. They
/// show the same binding to the same user minutes apart; two implementations of
/// this would drift, and the drift would be visible.
class Keycap extends StatelessWidget {
  const Keycap(this.glyph, {super.key});

  final String glyph;

  @override
  Widget build(BuildContext context) {
    final t = context.mac;
    return Container(
      constraints: const BoxConstraints(minWidth: 21),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
      decoration: BoxDecoration(
        color: t.keycapFill,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: t.keycapBorder),
        boxShadow: [
          BoxShadow(
            color: t.keycapShadow,
            blurRadius: 0,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        glyph,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: MacTokens.monoFamily,
          fontSize: 11.5,
          height: 1.25,
          color: t.labelPrimary,
        ),
      ),
    );
  }
}

/// A combination as one keycap per symbol, or a muted "Not set".
class KeycapRow extends StatelessWidget {
  const KeycapRow({
    super.key,
    required this.keyCode,
    required this.modifiers,
    this.unsetLabel = 'Not set',
    this.mainAxisAlignment = MainAxisAlignment.start,
  });

  final int keyCode;
  final int modifiers;
  final String unsetLabel;
  final MainAxisAlignment mainAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final t = context.mac;
    final symbols = comboSymbols(keyCode, modifiers, keyLabels: KeyboardLabels.of(context));
    if (symbols.isEmpty) {
      return Text(unsetLabel,
          style: TextStyle(fontSize: 12, color: t.labelTertiary));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: mainAxisAlignment,
      children: [
        for (final symbol in symbols)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Keycap(symbol),
          ),
      ],
    );
  }
}


/// The stand-in for a keycap row on a command with no shortcut.
///
/// Deliberately shaped like the keycaps beside it — same height, same border,
/// same radius — so a list reads as "every row has something you press", and
/// the empty one is not the odd one out. Plain grey status text there was
/// reported twice as "I can't set this": on a row whose entire purpose is to be
/// clicked, a status reads as a verdict.
///
/// Shared by the shortcuts list and the region picker, which had the same
/// unset state wearing two different faces.
///
/// **Its label is secondary, not tertiary.** Tertiary is macOS's disabled
/// weight — 2.4:1 against the pane in light mode and 3.1:1 in dark, below the
/// 4.5:1 that 11.5 pt text needs — so an invitation drawn in it carried the
/// same visual weight as the thing this control was built to stop looking like.
/// Secondary measures 4.7:1 and 6.0:1 and still reads as quiet.
class SetShortcutPill extends StatelessWidget {
  const SetShortcutPill({super.key, required this.label, this.hovered = false});

  final String label;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final t = context.mac;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: hovered ? t.accent.withValues(alpha: 0.14) : Colors.transparent,
        border: Border.all(color: hovered ? t.accent : t.keycapBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          color: hovered ? t.accent : t.labelSecondary,
        ),
      ),
    );
  }
}
