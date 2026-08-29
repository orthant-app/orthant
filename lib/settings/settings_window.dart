import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/channel.dart';
import 'package:flutter/semantics.dart';

import '../core/window_controller.dart';
import '../shortcuts/bindings.dart';
import '../shortcuts/command_ref.dart';
import '../shortcuts/custom_region.dart';
import '../shortcuts/shortcut_command.dart';
import 'general_pane.dart';
import 'mac_control.dart';
import 'mac_theme.dart';
import 'settings.dart';
import 'region_picker_sheet.dart';
import 'shortcuts_screen.dart';

/// Orthant's settings, as two tabs in the app's one window.
///
/// Spec §6 describes these as tray-menu items. They are here instead because
/// three of them cannot be said in a menu row: the summon shortcut has to be
/// *shown*, as keycaps, beside the shortcuts it competes with;
/// `requiresApproval` needs a sentence and a button; and a grid size is only
/// legible next to a picture of the grid. The tray keeps what a menu is good
/// at — Open Grid, Settings…, Quit.
///
/// Deliberately no Quit button. Divvy has one; quitting is a tray/app-menu
/// action, and a settings window that can terminate the app is a category
/// error.
class SettingsWindow extends StatefulWidget {
  const SettingsWindow({
    super.key,
    required this.settings,
    required this.bindings,
    required this.onSettingsChanged,
    required this.onRebound,
    this.onRestoreBindings,
    this.unavailable = const {},
    this.regions = const [],
    this.onRegionSaved,
    this.onRegionDeleted,
    this.pendingRegion,
    this.onPendingConsumed,
    this.permissionGranted = true,
    this.loginStatus = LoginItemStatus.unavailable,
    this.onSetLoginItem,
    this.onOpenLoginItems,
    this.onOpenAccessibility,
    this.onCaptureStart,
    this.onCaptureEnd,
    this.onResetBindings,
    this.initialTab = SettingsTab.general,
  });

  /// The pane to open on. Read once, in [State] creation — a window already on
  /// screen keeps whichever tab the user last chose.
  final SettingsTab initialTab;

  final Settings settings;
  final List<Binding> bindings;
  final Set<CommandRef> unavailable;

  /// The user's own regions, and the two callbacks that change them. Null
  /// callbacks make the Shortcuts pane read-only for regions.
  final List<CustomRegion> regions;
  final void Function(RegionDraft)? onRegionSaved;
  final void Function(String id)? onRegionDeleted;

  /// A shape ⌘S handed over, for the Shortcuts pane to open its picker on.
  final CustomRegion? pendingRegion;
  final VoidCallback? onPendingConsumed;
  final bool permissionGranted;
  final LoginItemStatus loginStatus;

  final void Function(Settings) onSettingsChanged;
  final void Function(Binding) onRebound;

  /// Make the bindings exactly this — the way back from a change that touched
  /// more than one row. See `ShortcutsScreen.onRestoreBindings`.
  final void Function(List<Binding>)? onRestoreBindings;

  final void Function(bool)? onSetLoginItem;
  final VoidCallback? onOpenLoginItems;
  final VoidCallback? onOpenAccessibility;
  final Future<void> Function()? onCaptureStart;
  final Future<void> Function()? onCaptureEnd;
  final VoidCallback? onResetBindings;

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

/// Which pane the window is showing. Public because callers need to *ask* for
/// one: "Change these shortcuts…" on the ready screen opened this window on
/// General, one click short of the list it named.
enum SettingsTab { general, shortcuts }

class _SettingsWindowState extends State<SettingsWindow> {
  late SettingsTab _tab = widget.initialTab;

  /// One per pane, so each pane's scroll position survives a tab switch —
  /// which matters more now that panes scroll routinely.
  final Map<SettingsTab, ScrollController> _scroll = {
    SettingsTab.general: ScrollController(),
    SettingsTab.shortcuts: ScrollController(),
  };

  @override
  void initState() {
    super.initState();
    final built = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Not kDebugMode: profile builds are the ones worth timing, and that
      // constant is false in exactly those.
      if (!kReleaseMode) {
        debugPrint('[orthant] settings first frame: '
            '${DateTime.now().difference(built).inMilliseconds} ms after the '
            'pane was created');
      }
      // Not debug-only: native shows the window transparent and waits for this
      // to reveal it, so the pane appears already painted rather than as a
      // black rectangle filling in. Native also has a deadline, so failing to
      // send this costs the effect, not the window.
      const MethodChannel(kOrthantChannel).invokeMethod<void>(
        'configFirstFrame',
      );
    });
  }

  @override
  void didUpdateWidget(covariant SettingsWindow old) {
    super.didUpdateWidget(old);
    // A newly-arrived pending region is the one prop change allowed to move
    // the tab. ⌘S can fire with this window already open on General, and the
    // Shortcuts pane — which owns the picker — is not even in the tree there,
    // so without this the save looked like it did nothing while the picker
    // waited behind the wrong pane. The null transition after consumption, and
    // every other rebuild, must leave the user's own tab choice alone.
    if (widget.pendingRegion != null && widget.pendingRegion != old.pendingRegion) {
      _select(SettingsTab.shortcuts);
    }
  }

  @override
  void dispose() {
    for (final c in _scroll.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _select(SettingsTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mac;
    return Scaffold(
      backgroundColor: t.windowBackground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TabBar(current: _tab, onSelect: _select, tokens: t),
          Expanded(
            child: switch (_tab) {
              SettingsTab.general => GeneralPane(
                scrollController: _scroll[SettingsTab.general],
                settings: widget.settings,
                onSettingsChanged: widget.onSettingsChanged,
                permissionGranted: widget.permissionGranted,
                loginStatus: widget.loginStatus,
                bindings: widget.bindings,
                summonUnavailable: widget.unavailable.contains(
                  const BuiltIn(ShortcutCommand.showGrid),
                ),
                onEditShortcuts: () => _select(SettingsTab.shortcuts),
                onSetLoginItem: widget.onSetLoginItem,
                onOpenLoginItems: widget.onOpenLoginItems,
                onOpenAccessibility: widget.onOpenAccessibility,
              ),
              SettingsTab.shortcuts => ShortcutsScreen(
                scrollController: _scroll[SettingsTab.shortcuts],
                bindings: widget.bindings,
                unavailable: widget.unavailable,
                permissionGranted: widget.permissionGranted,
                onOpenAccessibility: widget.onOpenAccessibility,
                onRebound: widget.onRebound,
                onRestoreBindings: widget.onRestoreBindings,
                onCaptureStart: widget.onCaptureStart,
                onCaptureEnd: widget.onCaptureEnd,
                onResetBindings: widget.onResetBindings,
                regions: widget.regions,
                gridCols: widget.settings.gridCols,
                gridRows: widget.settings.gridRows,
                onRegionSaved: widget.onRegionSaved,
                onRegionDeleted: widget.onRegionDeleted,
                pendingRegion: widget.pendingRegion,
                onPendingConsumed: widget.onPendingConsumed,
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// A centred segmented control, the idiom Apple's own `Settings` scene still
/// produces for a small number of panes. Hand-built over [MacTokens] for the
/// same reason the rest of this window is: the spec keeps dependencies lean,
/// and window-owning packages fight over `MainFlutterWindow` (§5).
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.current,
    required this.onSelect,
    required this.tokens,
  });

  final SettingsTab current;
  final void Function(SettingsTab) onSelect;
  final MacTokens tokens;

  static const _labels = {
    SettingsTab.general: ('General', Icons.tune),
    SettingsTab.shortcuts: ('Shortcuts', Icons.keyboard_outlined),
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: tokens.rowHighlight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tokens.separator),
          ),
          // The set the tabs belong to, so a screen reader can say "1 of 2"
          // rather than reading two unrelated controls that happen to be
          // adjacent.
          child: Semantics(
            role: SemanticsRole.tabBar,
            container: true,
            explicitChildNodes: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [for (final tab in SettingsTab.values) _segment(tab)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _segment(SettingsTab tab) {
    final selected = tab == current;
    final (label, icon) = _TabBar._labels[tab]!;
    return MacControl(
      onPressed: () => onSelect(tab),
      semanticLabel: '$label tab',
      selected: selected,
      role: SemanticsRole.tab,
      focusRingRadius: 6,
      inset: 2,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: selected ? tokens.contentBackground : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? tokens.separator : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? tokens.labelPrimary : tokens.labelSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                color: tokens.labelPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
