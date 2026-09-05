import 'package:flutter/material.dart';

import '../settings/keycap.dart';
import '../settings/mac_control.dart';
import '../settings/mac_theme.dart';
import '../settings/region_glyph.dart';
import '../shortcuts/bindings.dart';
import '../shortcuts/command_ref.dart';
import '../shortcuts/custom_region.dart';
import '../shortcuts/region_commands.dart';
import '../shortcuts/shortcut_command.dart';

/// Shown once, straight after the Accessibility grant.
///
/// Onboarding used to end at the grant, so nothing ever told a new user the
/// grid existed. A settings pane only helps people who go looking, and nobody
/// goes looking for a feature they do not know about — which made the grid, the
/// expensive half of this app, effectively undiscoverable.
///
/// Both tiers side by side, because the reason the grid exists is everything
/// the ten named regions cannot say: thirds, two-thirds, an ultrawide split.
/// The example shown beside the halves: two-thirds of the width, full height —
/// a shape the eleven built-ins cannot express, which is the whole point of it
/// being here.
const _twoThirds = CustomRegion(
  id: 'example',
  name: 'Left two-thirds',
  cols: 3,
  rows: 1,
  c0: 0,
  c1: 1,
  r0: 0,
  r1: 0,
);

class ReadyScreen extends StatelessWidget {
  const ReadyScreen({
    super.key,
    required this.bindings,
    required this.onDone,
    required this.onOpenShortcuts,
    this.unavailable = const {},
  });

  /// The live bindings, so the keycaps below are what will actually work.
  /// Hardcoding them would let onboarding lie to anyone who rebound something
  /// before their first launch, or whose combo macOS refused.
  final List<Binding> bindings;

  /// Commands macOS refused to register — it already owns the chord, or another
  /// app does. Marked here for the same reason as in the settings list: the
  /// binding is stored, displayed and never delivered, so a screen that showed
  /// it plainly would be teaching a keystroke that does nothing. This is the
  /// one screen where that lands hardest, because the reader has no prior
  /// experience of the app to contradict it.
  final Set<CommandRef> unavailable;

  final VoidCallback onDone;
  final VoidCallback onOpenShortcuts;

  Binding _bindingFor(CommandRef c) => bindings.firstWhere(
    (b) => b.command == c,
    orElse: () => Binding.unbound(c),
  );

  /// Keycaps, preceded by a warning when the OS will not deliver them.
  List<Widget> _keys(MacTokens t, Binding b, {String unsetLabel = 'Not set'}) => [
        if (b.isBound && unavailable.contains(b.command)) ...[
          Tooltip(
            message: 'macOS or another app already uses this combination, so '
                'it never reaches Orthant.\nPick a different one below.',
            child: Icon(Icons.warning_amber_rounded, size: 14, color: t.warning),
          ),
          const SizedBox(width: 5),
        ],
        KeycapRow(
          keyCode: b.keyCode,
          modifiers: b.modifiers,
          unsetLabel: unsetLabel,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final t = context.mac;
    final summon = _bindingFor(const BuiltIn(ShortcutCommand.showGrid));
    final left = _bindingFor(const BuiltIn(ShortcutCommand.leftHalf));
    final right = _bindingFor(const BuiltIn(ShortcutCommand.rightHalf));

    return Scaffold(
      backgroundColor: t.windowBackground,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(34, 34, 34, 22),
        child: Column(
          children: [
            Text(
              'Orthant is ready',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: t.labelPrimary,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Two ways to put a window where you want it.',
              style: TextStyle(fontSize: 12.5, color: t.labelSecondary),
            ),
            const SizedBox(height: 24),
            // Centred and content-sized, not stretched: the cards hold three
            // short lines each, and letting them fill a 500 pt window left
            // most of each one empty.
            Expanded(
              child: Center(
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _Card(
                          tokens: t,
                          art: const SizedBox(
                            height: 34,
                            child: Center(child: RegionGlyph(command: null)),
                          ),
                          keys:
                              _keys(t, summon, unsetLabel: 'No shortcut set'),
                          // The arrows are named here because this card is the
                          // only place the grid is ever explained, and a
                          // keyboard feature nobody is told about is one nobody
                          // finds — least of all on a grid that arrives under
                          // the pointer.
                          caption:
                              'Opens the grid. Drag across it to pick any '
                              'block: thirds, two-thirds, anything. Or use '
                              'the arrow keys, ⇧ to extend, ↩ to place.',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Card(
                          tokens: t,
                          art: SizedBox(
                            height: 34,
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  RegionGlyph(command: RegionCommand.leftHalf),
                                  SizedBox(width: 6),
                                  RegionGlyph(command: RegionCommand.rightHalf),
                                  SizedBox(width: 6),
                                  // A shape none of the eleven can make. The
                                  // only place onboarding *shows* what "your
                                  // own region" means rather than saying it —
                                  // and a picture survives being skim-read.
                                  RegionGlyph(custom: _twoThirds),
                                ],
                              ),
                            ),
                          ),
                          keys: [
                            ..._keys(t, left),
                            const SizedBox(width: 8),
                            ..._keys(t, right),
                          ],
                          // The last clause is the only place anything tells
                          // a new user that the eleven defaults are not the
                          // whole vocabulary. A feature nobody is told about is
                          // one nobody finds — the same hole the grid itself
                          // fell into before this screen existed.
                          caption:
                              'Snaps straight to a half, a quarter, or full '
                              'screen. No aiming, and you can add shapes of '
                              'your own, like the third one.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                MacControl(
                  onPressed: onOpenShortcuts,
                  focusRingRadius: 4,
                  inset: 2,
                  child: Text(
                    'Change these shortcuts…',
                    style: TextStyle(fontSize: 12.5, color: t.accent),
                  ),
                ),
                FilledButton(
                  onPressed: onDone,
                  style: FilledButton.styleFrom(
                    backgroundColor: t.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.tokens,
    required this.art,
    required this.keys,
    required this.caption,
  });

  final MacTokens tokens;
  final Widget art;
  final List<Widget> keys;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: tokens.contentBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.separator),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          art,
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: keys),
          const SizedBox(height: 10),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: tokens.labelSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
