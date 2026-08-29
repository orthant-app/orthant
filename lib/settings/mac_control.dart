import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'mac_theme.dart';

/// A control that can be reached and used without a mouse.
///
/// Every interactive thing in this window was a bare `GestureDetector`: no focus
/// node, no keyboard activation, no focus ring, and nothing for VoiceOver to
/// announce. An external review named it the sharpest product finding, and it is
/// a poor look on an app whose entire purpose is keyboard-driven — the settings
/// for the shortcuts were the one part you could not reach with the keyboard.
///
/// [FocusableActionDetector] rather than a hand-rolled `Focus` + `RawKeyboard`
/// pair: it is the widget Flutter provides for exactly this composite (focus,
/// hover, actions, cursor), and it routes `ActivateIntent` — which is Space and
/// Return on every platform, and Enter on the numeric keypad — through the same
/// callback as a tap. One code path for both means they cannot drift.
class MacControl extends StatefulWidget {
  const MacControl({
    super.key,
    required this.child,
    required this.onPressed,
    this.semanticLabel,
    this.checked,
    this.selected,
    this.role,
    this.containsControl = false,
    this.hovered,
    this.onFocusChange,
    this.onAccessibilityFocusChange,
    this.focusRingRadius = 7,
    this.autofocus = false,
    this.inset = 3,
    this.enabled = true,
  });

  final Widget child;

  /// Null disables the control: it stops taking focus and stops announcing
  /// itself as pressable, which is what "disabled" means to a screen reader.
  final VoidCallback? onPressed;

  /// What VoiceOver reads. Falls back to whatever text is inside [child], which
  /// is right for a labelled button and wrong for an icon — pass one there.
  final String? semanticLabel;

  /// Checked state, for a control that has one. Non-null makes this a
  /// **checkbox** rather than a button: a screen reader then names the role and
  /// reads the state itself, so the label must not spell the state out too.
  final bool? checked;

  /// Selected state, for one segment of a segmented control.
  final bool? selected;

  /// What kind of control this is, when "button" is not the truth. A tab
  /// announces as a tab and carries its position in the set; leaving it a
  /// button meant `selected` was the only thing distinguishing it from the
  /// push buttons elsewhere in the same pane.
  final SemanticsRole? role;

  /// Called as a screen reader's cursor arrives and leaves.
  ///
  /// Deliberately separate from [onFocusChange]. VoiceOver's cursor and
  /// Flutter's keyboard focus move independently, so a row that reveals an
  /// affordance on keyboard focus alone still hides it from anyone driving by
  /// VoiceOver — which is how the Shortcuts list's clear button stayed
  /// invisible to a screen reader after being made reachable by Tab.
  final ValueChanged<bool>? onAccessibilityFocusChange;

  /// Set when [child] holds a control of its own.
  ///
  /// A [semanticLabel] normally *replaces* everything inside, so a composite row
  /// announces as one thing. But the Shortcuts rows contain a clear button, and
  /// a blanket exclusion deleted the only way to remove a binding from the
  /// accessibility tree entirely — a nested control is not decoration. Such a
  /// caller excludes its own decorative parts instead.
  final bool containsControl;

  /// Called as the pointer enters and leaves, for rows that highlight.
  final ValueChanged<bool>? hovered;

  /// Called as focus arrives and leaves.
  ///
  /// A row that reveals an affordance on hover has to reveal it on focus too, or
  /// the affordance is mouse-only — which is how the Shortcuts list's "remove
  /// shortcut" button was unreachable by keyboard entirely.
  final ValueChanged<bool>? onFocusChange;

  final double focusRingRadius;

  /// How far the ring sits outside the control, in points. macOS draws it around
  /// the control rather than on its edge.
  final double inset;

  final bool autofocus;
  final bool enabled;

  @override
  State<MacControl> createState() => _MacControlState();
}

class _MacControlState extends State<MacControl> {
  bool _focused = false;

  bool get _live => widget.enabled && widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final t = context.mac;
    final a11yFocus = widget.onAccessibilityFocusChange;
    final node = Semantics(
      container: true,
      // A checkbox is a role of its own, not a button whose name happens to
      // contain a state; so is a tab, once one is asked for.
      button: widget.checked == null && widget.role == null,
      role: widget.role,
      checked: widget.checked,
      selected: widget.selected,
      enabled: _live,
      label: widget.semanticLabel,
      onDidGainAccessibilityFocus: a11yFocus == null ? null : () => a11yFocus(true),
      onDidLoseAccessibilityFocus: a11yFocus == null ? null : () => a11yFocus(false),
      // The action, and the reason this node exists at all. Hearing a control
      // is not using one: VoiceOver activates by *sending* a tap, and without
      // this the whole window announced itself correctly and did nothing. The
      // child `GestureDetector` used to supply it, but on a node of its own —
      // separate from the labelled one for an unlabelled control, and deleted
      // outright by `excludeSemantics` for a labelled one.
      onTap: _live ? widget.onPressed : null,
      // An explicit label *replaces* what is inside rather than preceding it.
      // A composite control is one thing to announce: without this, a shortcut
      // row read "Left half, ⌃⌥←" and then "Left half" and then each keycap
      // separately — five utterances for one row, eleven rows to a pane.
      excludeSemantics: widget.semanticLabel != null && !widget.containsControl,
      child: FocusableActionDetector(
        enabled: _live,
        autofocus: widget.autofocus,
        mouseCursor:
            _live ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowFocusHighlight: (v) {
          if (v == _focused) return;
          setState(() => _focused = v);
          widget.onFocusChange?.call(v);
        },
        onShowHoverHighlight: widget.hovered,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          // The node above owns the action now. Left on, this contributed a
          // second tappable node wrapping the first.
          excludeFromSemantics: true,
          // Painted outside the child rather than around it, so adding keyboard
          // support cannot shift a single pixel of the existing layout — these
          // panes were tuned against a mockup.
          child: CustomPaint(
            foregroundPainter: _focused
                ? _FocusRingPainter(
                    color: t.accent,
                    radius: widget.focusRingRadius,
                    inset: widget.inset,
                  )
                : null,
            child: widget.child,
          ),
        ),
      ),
    );
    // With no explicit label the name comes from the child's own text, which is
    // a *separate* node from the one holding the action. Merging is what makes
    // them one control: unmerged, a screen reader found an unnamed button and,
    // somewhere else entirely, a stray line of text.
    return widget.semanticLabel == null && !widget.containsControl
        ? MergeSemantics(child: node)
        : node;
  }
}

/// macOS's focus ring: the accent colour, semi-transparent, just outside the
/// control's own bounds.
class _FocusRingPainter extends CustomPainter {
  _FocusRingPainter({
    required this.color,
    required this.radius,
    required this.inset,
  });

  final Color color;
  final double radius;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height).inflate(inset);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius + inset)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _FocusRingPainter old) =>
      old.color != color || old.radius != radius || old.inset != inset;
}

/// A traversal group that also accepts ← → as "previous / next".
///
/// For the tab bar and the steppers, where the arrows are what a macOS user
/// reaches for: a segmented control moves between segments with the arrows, and
/// a stepper raises and lowers with ↑ ↓.
class MacArrowTraversal extends StatelessWidget {
  const MacArrowTraversal({super.key, required this.child, this.axis});

  final Widget child;

  /// Which arrow pair moves focus. Null accepts both.
  final Axis? axis;

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == null || axis == Axis.horizontal;
    final vertical = axis == null || axis == Axis.vertical;
    return FocusTraversalGroup(
      child: Shortcuts(
        shortcuts: {
          if (horizontal) ...{
            LogicalKeySet(LogicalKeyboardKey.arrowLeft):
                const DirectionalFocusIntent(TraversalDirection.left),
            LogicalKeySet(LogicalKeyboardKey.arrowRight):
                const DirectionalFocusIntent(TraversalDirection.right),
          },
          if (vertical) ...{
            LogicalKeySet(LogicalKeyboardKey.arrowUp):
                const DirectionalFocusIntent(TraversalDirection.up),
            LogicalKeySet(LogicalKeyboardKey.arrowDown):
                const DirectionalFocusIntent(TraversalDirection.down),
          },
        },
        child: child,
      ),
    );
  }
}
