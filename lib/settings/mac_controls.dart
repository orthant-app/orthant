import 'package:flutter/material.dart';

import 'mac_control.dart';
import 'mac_theme.dart';

/// A macOS push button, drawn over [MacTokens].
///
/// Extracted from `general_pane.dart` when the About pane needed the same
/// control. Two hand-tuned copies of one button is how the two quietly stop
/// matching — and in a window whose whole job is to look like a system
/// preferences pane, "quietly stops matching" is the defect.
///
/// [MacControl] underneath, so a tap and Space/Return reach the same callback
/// and the focus ring is painted outside the child rather than inside it.
class MacPushButton extends StatelessWidget {
  const MacPushButton({
    super.key,
    required this.label,
    required this.tokens,
    required this.onPressed,
  });

  final String label;
  final MacTokens tokens;

  /// Null disables the button — [MacControl] handles the semantics.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return MacControl(
      onPressed: onPressed,
      focusRingRadius: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: tokens.contentBackground,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: tokens.keycapBorder),
          boxShadow: [
            BoxShadow(
              color: tokens.keycapShadow,
              blurRadius: 1,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12.5, color: tokens.labelPrimary),
        ),
      ),
    );
  }
}

/// A macOS checkbox and its label, as one control.
///
/// Moved here from `general_pane.dart` when the About pane needed one too. The
/// accessibility notes inside are load-bearing and were paid for once already —
/// a composite row that announces itself five times is a real defect, not a
/// nitpick.
class MacCheckbox extends StatelessWidget {
  const MacCheckbox({
    super.key,
    required this.label,
    required this.tokens,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final MacTokens tokens;
  final bool value;
  final void Function(bool)? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: MacControl(
        onPressed: enabled ? () => onChanged!(!value) : null,
        // The box and its label are one control, so it announces as one thing.
        // The state rides as a *flag* rather than in the name: a screen reader
        // says "checkbox, unchecked" itself, and spelling it out here as well
        // had it read twice.
        semanticLabel: label,
        checked: value,
        focusRingRadius: 4,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              // Excluded: MacControl above already announces this row as one
              // control with its state, and a nested Checkbox would have
              // VoiceOver read the state a second time.
              child: ExcludeSemantics(
                child: Checkbox(
                  value: value,
                  onChanged: enabled ? (v) => onChanged!(v ?? false) : null,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeColor: tokens.accent,
                  side: BorderSide(color: tokens.keycapBorder, width: 1),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: tokens.labelPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
