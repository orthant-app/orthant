import 'package:flutter/material.dart';

import 'mac_control.dart';
import 'mac_theme.dart';

/// A small numeric field with stacked ▲/▼ buttons — AppKit's `NSStepper`, which
/// is what macOS uses for a bounded integer nobody wants to type.
///
/// The buttons disable at the bounds rather than clamping silently, so the
/// limit is visible before it is hit.
class MacStepper extends StatelessWidget {
  const MacStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.enabled = true,
    this.semanticLabel = 'Value',
  });

  /// What a screen reader calls this stepper. Two bare arrows announce nothing
  /// on their own, and this pane has four of them.
  final String semanticLabel;

  final int value;
  final int min;
  final int max;
  final void Function(int) onChanged;

  /// False greys the whole control — used for the gap size while gaps are off,
  /// where hiding it instead would lose the value the user chose.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.mac;
    final canRaise = enabled && value < max;
    final canLower = enabled && value > min;

    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: Container(
        decoration: BoxDecoration(
          color: t.contentBackground,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: t.keycapBorder),
          boxShadow: [
            BoxShadow(
                color: t.keycapShadow,
                blurRadius: 1,
                offset: const Offset(0, 1)),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 34),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                alignment: Alignment.center,
                child: Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: t.labelPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: t.keycapBorder)),
                ),
                // ↑ ↓ move between the two arrows, which is what a macOS user
                // reaches for on a stepper.
                child: MacArrowTraversal(
                  axis: Axis.vertical,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Arrow(
                        up: true,
                        tokens: t,
                        label: '$semanticLabel, increase',
                        onPressed: canRaise ? () => onChanged(value + 1) : null,
                      ),
                      Container(height: 0.5, width: 17, color: t.keycapBorder),
                      _Arrow(
                        up: false,
                        tokens: t,
                        label: '$semanticLabel, decrease',
                        onPressed: canLower ? () => onChanged(value - 1) : null,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.up,
    required this.tokens,
    required this.onPressed,
    required this.label,
  });

  final bool up;
  final MacTokens tokens;
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return MacControl(
      onPressed: onPressed,
      semanticLabel: label,
      focusRingRadius: 3,
      inset: 1,
      child: SizedBox(
        width: 17,
        height: 11,
        child: Icon(
          up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          size: 15,
          color: enabled ? tokens.labelPrimary : tokens.labelTertiary,
        ),
      ),
    );
  }
}
