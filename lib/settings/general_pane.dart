import 'package:flutter/material.dart';

import '../core/window_controller.dart';
import '../shortcuts/bindings.dart';
import '../shortcuts/command_ref.dart';
import '../shortcuts/shortcut_command.dart';
import 'grid_preview.dart';
import 'keycap.dart';
import 'mac_button.dart';
import 'mac_control.dart';
import 'mac_stepper.dart';
import 'mac_theme.dart';
import 'settings.dart';

/// The General tab: everything configurable that is not a keyboard shortcut.
///
/// Laid out in the macOS form convention — a fixed left column of right-aligned
/// labels, controls in a right column, groups separated by hairlines. That
/// alignment is most of what makes a hand-built Flutter pane read as a system
/// preferences window rather than a web form.
class GeneralPane extends StatelessWidget {
  const GeneralPane({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    required this.permissionGranted,
    required this.loginStatus,
    required this.bindings,
    this.summonUnavailable = false,
    this.onEditShortcuts,
    this.onSetLoginItem,
    this.onOpenLoginItems,
    this.onOpenAccessibility,
    this.scrollController,
  });

  /// Owned by the window, one per pane, so a pane's scroll position survives a
  /// tab switch. Nothing reads a position from it — the window's size is
  /// AppKit's, and this pane simply scrolls inside whatever it is given.
  final ScrollController? scrollController;

  /// Read-only here. The summon is edited in the Shortcuts tab, where it shares
  /// one collision check with the ten placements — but "the global binding" is
  /// what people come to a General tab looking for, so it is *shown* here with
  /// a way through.
  final List<Binding> bindings;
  final bool summonUnavailable;
  final VoidCallback? onEditShortcuts;

  final Settings settings;
  final void Function(Settings) onSettingsChanged;

  /// Rendered either way — a green "Granted" or a warning with a way to fix it.
  final bool permissionGranted;

  final LoginItemStatus loginStatus;
  final void Function(bool)? onSetLoginItem;
  final VoidCallback? onOpenLoginItems;
  final VoidCallback? onOpenAccessibility;

  /// Width of the label column. Fixed rather than intrinsic so the groups line
  /// up with each other, which is the entire point of the convention.
  static const double labelColumnWidth = 132;

  @override
  Widget build(BuildContext context) {
    final t = context.mac;
    // Scrolling content, pinned footer — the same shape as the Shortcuts pane.
    // `Reset Grid & Gaps` used to live at the bottom of the scroll area, so on
    // a window shorter than the content (an ungranted permission row, or simply
    // a small display) it was cut in half with no way to reach it but a scroll
    // nobody could see was possible. A pane's own action should not be able to
    // leave the pane.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _fields(t)),
        _footer(t),
      ],
    );
  }

  Widget _footer(MacTokens t) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
    child: Align(
      alignment: Alignment.centerRight,
      // Named for what it actually resets. "Reset to Defaults" at the
      // foot of a pane reads as "everything", and this touches neither
      // the shortcuts (Settings holds no bindings) nor launch-at-login
      // (the OS owns that). The Shortcuts tab has its own.
      child: MacPushButton(
        label: 'Reset Grid & Gaps',
        tokens: t,
        onPressed: () => onSettingsChanged(const Settings()),
      ),
    ),
  );

  Widget _fields(MacTokens t) {
    return SingleChildScrollView(
      controller: scrollController,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Shown whether or not it is granted. The tray row stays conditional
            // — a menu has no room for noise — but this is a settings pane, and
            // "does Orthant actually have permission?" is the first thing anyone
            // debugging it wants to see. Spec §6 lists permission status as an M7
            // deliverable in its own right.
            _group(t, 'Accessibility', [_permissionRow(t)]),
            _hairline(t),
            _group(t, 'Open grid', [_summonRow(t)]),
            _hairline(t),
            _gridAndGaps(t),
            _hairline(t),
            _group(t, 'Startup', [_loginRow(t)]),
          ],
        ),
      ),
    );
  }

  Widget _hairline(MacTokens t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Divider(height: 0.5, thickness: 0.5, color: t.separator),
  );

  Widget _group(MacTokens t, String label, List<Widget> fields) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: labelColumnWidth,
        child: Padding(
          padding: const EdgeInsets.only(top: 2, right: 14),
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 13, color: t.labelPrimary),
          ),
        ),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: fields,
        ),
      ),
    ],
  );

  /// Grid and Gaps share one preview: two groups of controls, one picture.
  /// That sharing is what makes an arbitrary 7 x 3 comprehensible, and so what
  /// lets the grid be two steppers rather than a list of safe presets.
  Widget _gridAndGaps(MacTokens t) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _group(t, 'Grid', [
              _stepperRow(
                t,
                'Columns',
                settings.gridCols,
                kMinGridAxis,
                kMaxGridAxis,
                (v) => onSettingsChanged(settings.copyWith(gridCols: v)),
              ),
              const SizedBox(height: 6),
              _stepperRow(
                t,
                'Rows',
                settings.gridRows,
                kMinGridAxis,
                kMaxGridAxis,
                (v) => onSettingsChanged(settings.copyWith(gridRows: v)),
              ),
            ]),
            const SizedBox(height: 15),
            _group(t, 'Gaps', [
              _Checkbox(
                label: 'Leave gaps',
                tokens: t,
                value: settings.gaps,
                onChanged: (v) => onSettingsChanged(settings.copyWith(gaps: v)),
              ),
              const SizedBox(height: 7),
              // Disabled rather than hidden while gaps are off: the size
              // the user chose stays visible, and switching gaps back on
              // returns it instead of a default.
              _stepperRow(
                t,
                'Size',
                settings.gapSize,
                0,
                kMaxGapSize,
                (v) => onSettingsChanged(settings.copyWith(gapSize: v)),
                enabled: settings.gaps,
                unit: 'pt',
              ),
            ]),
          ],
        ),
      ),
      const SizedBox(width: 8),
      GridPreview(
        cols: settings.gridCols,
        rows: settings.gridRows,
        // effectiveGap, not gapSize: the picture must show what a
        // placement would actually do, which is nothing when gaps are off.
        gap: settings.effectiveGap,
      ),
    ],
  );

  Widget _stepperRow(
    MacTokens t,
    String caption,
    int value,
    int min,
    int max,
    void Function(int) onChanged, {
    bool enabled = true,
    String? unit,
  }) => Opacity(
    opacity: enabled ? 1 : 0.42,
    child: Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            caption,
            style: TextStyle(fontSize: 12.5, color: t.labelPrimary),
          ),
        ),
        MacStepper(
          value: value,
          min: min,
          max: max,
          enabled: enabled,
          onChanged: onChanged,
          // Two bare arrows announce nothing on their own, and this pane has
          // three pairs of them.
          semanticLabel: '$caption $value${unit == null ? "" : " $unit"}',
        ),
        if (unit != null) ...[
          const SizedBox(width: 6),
          Text(unit, style: TextStyle(fontSize: 12, color: t.labelSecondary)),
        ],
      ],
    ),
  );

  /// The summon's combo plus a way to the tab that owns it.
  Widget _summonRow(MacTokens t) {
    final summon = bindings.firstWhere(
      (b) => b.command == const BuiltIn(ShortcutCommand.showGrid),
      orElse: () => const Binding.unbound(BuiltIn(ShortcutCommand.showGrid)),
    );
    return Row(
      children: [
        if (summonUnavailable && summon.isBound) ...[
          Tooltip(
            message:
                'macOS or another app already uses this combination, so '
                'it never reaches Orthant.',
            child: Icon(
              Icons.warning_amber_rounded,
              size: 15,
              color: t.warning,
            ),
          ),
          const SizedBox(width: 5),
        ],
        KeycapRow(
          keyCode: summon.keyCode,
          modifiers: summon.modifiers,
          unsetLabel: 'Not set',
        ),
        const SizedBox(width: 14),
        _LinkButton(label: 'Change…', tokens: t, onPressed: onEditShortcuts),
      ],
    );
  }

  Widget _permissionRow(MacTokens t) {
    if (permissionGranted) {
      return Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF34C759),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            'Granted',
            style: TextStyle(fontSize: 13, color: t.labelPrimary),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              // Nudged to sit on the text's first-line baseline rather than
              // centred on a block that may wrap to two lines.
              padding: const EdgeInsets.only(top: 5),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: t.warning,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 7),
            // Flexible, not a fixed width: this string is the longest thing
            // in the pane and the window is only 560 pt wide.
            Flexible(
              child: Text(
                'Not granted — shortcuts and the grid do nothing',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: t.labelPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        MacPushButton(
          label: 'Open Accessibility Settings…',
          tokens: t,
          onPressed: onOpenAccessibility,
        ),
      ],
    );
  }

  Widget _loginRow(MacTokens t) {
    // Only `enabled` renders as on: `unavailable` means the OS would not say,
    // and a ticked box there would claim something nothing established.
    //
    // It stays *interactive* though, which is the correction to an earlier
    // version of this row. Disabling it read as "we can't say" but behaved as
    // "you may not try", and on a build where the status is unavailable that
    // left no way to turn launch-at-login on — or even to find out whether it
    // would work. Letting the attempt through costs nothing: `setLoginItem`
    // returns the status *after* registering, so a refusal simply leaves the
    // box unticked with the explanation below still showing.
    final on = loginStatus == LoginItemStatus.enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Checkbox(
          label: 'Launch at login',
          tokens: t,
          value: on,
          onChanged: (v) => onSetLoginItem?.call(v),
        ),
        if (loginStatus == LoginItemStatus.unavailable) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: 320,
            child: Text(
              'macOS reported a login-item state Orthant does not recognise. '
              'Switching this on may still work.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: t.labelSecondary,
              ),
            ),
          ),
        ],
        if (loginStatus == LoginItemStatus.requiresApproval) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: 320,
            child: Text(
              'Turned off in System Settings ▸ General ▸ Login Items, so '
              'Orthant will not start automatically.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: t.labelSecondary,
              ),
            ),
          ),
          const SizedBox(height: 7),
          _LinkButton(
            label: 'Open Login Items…',
            tokens: t,
            onPressed: onOpenLoginItems,
          ),
        ],
      ],
    );
  }
}

/// A macOS-weight checkbox with its label, clickable as one unit.
class _Checkbox extends StatelessWidget {
  const _Checkbox({
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

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.label,
    required this.tokens,
    required this.onPressed,
  });

  final String label;
  final MacTokens tokens;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return MacControl(
      onPressed: onPressed,
      focusRingRadius: 4,
      inset: 2,
      child: Text(
        label,
        style: TextStyle(fontSize: 12.5, color: tokens.accent),
      ),
    );
  }
}
