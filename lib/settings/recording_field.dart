import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shortcuts/bindings.dart';
import 'key_capture.dart';
import 'keyboard_labels.dart';
import 'mac_theme.dart';

/// The field while it is listening for a key combination.
///
/// **One implementation, used by both** the shortcuts list and the region
/// picker. It existed twice as near-copies until 2026-08-01, differing only in
/// how it took focus and by a point of padding — and the duplication was
/// already rotting: the second copy carried its doc comment twice. Adding the
/// live preview and the warning state to both was a larger change than moving
/// the widget here once.
///
/// It swallows **every** key: the combination being recorded must never reach
/// the app behind it. That is also why a caller cannot put a Tab-reachable
/// control beside this field and expect the keyboard to get there — the
/// shortcuts pane offers a key gesture for its footer button precisely because
/// Tab cannot walk out of here.
class RecordingField extends StatefulWidget {
  const RecordingField({
    super.key,
    required this.onCombo,
    required this.onCancel,
    this.pending,
    this.verticalPadding = 3,
  });

  final void Function(({int keyCode, int modifiers})) onCombo;
  final VoidCallback onCancel;

  /// A combination already pressed that something else owns.
  ///
  /// Drawn in place of the live preview, in the warning colour, so that the row
  /// the footer's question is about is obvious at a glance.
  final ({int keyCode, int modifiers})? pending;

  final double verticalPadding;

  @override
  State<RecordingField> createState() => _RecordingFieldState();
}

class _RecordingFieldState extends State<RecordingField> {
  /// An explicit request rather than `autofocus: true`.
  ///
  /// The region picker keeps a focus anchor at its root so Return can reach
  /// `CallbackShortcuts`, and two competing autofocus nodes is a race the
  /// anchor wins — leaving this field visibly listening and deaf. The explicit
  /// request wins in both hosts, so it is the only mechanism.
  final _node = FocusNode(debugLabel: 'shortcut-recorder');

  /// The modifiers held right now, so the field shows what it is hearing.
  int _held = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _node.requestFocus();
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Every event refreshes the preview, releases included — that is how a
    // modifier disappears again when it is let go. `HardwareKeyboard` is
    // updated before handlers run, so a key-up has already been removed.
    final held = heldModifiers();
    if (held != _held && mounted) setState(() => _held = held);

    // Repeats are ignored along with releases, and that is **load-bearing
    // beyond the obvious**: the shortcuts pane confirms taking an occupied
    // combination by pressing it a second time, which would otherwise fire on
    // auto-repeat while the chord is merely held down. Flutter models repeats
    // as a distinct `KeyRepeatEvent`, so this one test covers both.
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    final combo = carbonFromKeyEvent(event);
    if (combo != null) widget.onCombo(combo);
    return KeyEventResult.handled; // never let keys leak to the app
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mac;
    final pending = widget.pending;
    final symbols = pending != null
        ? comboSymbols(pending.keyCode, pending.modifiers,
            keyLabels: KeyboardLabels.of(context))
        : modifierSymbols(_held);
    return Focus(
      focusNode: _node,
      onKeyEvent: _onKey,
      child: Container(
        // Wide enough for "Press keys…" whatever it is currently showing, so
        // the pill does not jiggle the row as modifiers are pressed and let go.
        constraints: const BoxConstraints(minWidth: 86),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(
          horizontal: 9,
          vertical: widget.verticalPadding,
        ),
        decoration: BoxDecoration(
          color: pending != null ? t.warning : t.accent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          symbols.isEmpty ? 'Press keys…' : symbols.join(' '),
          style: TextStyle(
            fontFamily: symbols.isEmpty ? null : MacTokens.monoFamily,
            fontSize: 11.5,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
