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
