import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'package:flutter/services.dart' show PhysicalKeyboardKey;

import '../core/key_words.dart';
import '../l10n/app_localizations.dart';
import '../l10n/strings.dart';
import '../settings/keycap.dart';
import '../settings/first_frame_report.dart';
import '../settings/mac_control.dart';
import '../settings/platform_theme.dart';
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

/// The key that places, as a keycap names it: ↩ on macOS, Enter on Windows.
final _enter = PhysicalKeyboardKey.enter.usbHidUsage;

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

  /// One chord's keycaps, preceded by a warning when the OS will not deliver
  /// them.
  Widget _chord(PlatformTokens t, AppLocalizations l, Binding b,
          {required String unsetLabel}) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (b.isBound && unavailable.contains(b.command)) ...[
          Tooltip(
            message: l.readyUnavailableTooltip(KeyWords.current.system),
            child: Icon(Icons.warning_amber_rounded, size: 14, color: t.warning),
          ),
          const SizedBox(width: 5),
        ],
        KeycapRow(chord: b.chord, unsetLabel: unsetLabel),
      ]);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = context.l10n;
    final summon = _bindingFor(const BuiltIn(ShortcutCommand.showGrid));
    final left = _bindingFor(const BuiltIn(ShortcutCommand.leftHalf));
    final right = _bindingFor(const BuiltIn(ShortcutCommand.rightHalf));

    // Scrolls in a window shorter than itself, its two buttons below the
    // fold rather than cut off: on Windows the window's floor gives way to a
    // short screen's work area (a 768-pixel screen at 200 % leaves about 300
    // points). Taller, it fills the window exactly as before.
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(34, 34, 34, 22),
      child: Column(
        children: [
          Text(
            l.readyTitle,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
              color: t.labelPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            l.readySubtitle,
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
                        chords: [
                          _chord(t, l, summon,
                              unsetLabel: l.readyNoShortcutSet),
                        ],
                        // The arrows are named here because this card is
                        // the only place the grid is ever explained, and a
                        // keyboard feature nobody is told about is one
                        // nobody finds — least of all on a grid that
                        // arrives under the pointer.
                        // Enter is in both tables, so the fallback names a key
                        // legend that is English in every language anyway.
                        caption: l.readyGridCaption(KeyWords.current.shiftName,
                            keySymbol(_enter) ?? 'Enter'),
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
                                RegionGlyph(
                                    command: RegionCommand.leftHalf),
                                SizedBox(width: 6),
                                RegionGlyph(
                                    command: RegionCommand.rightHalf),
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
                        chords: [
                          _chord(t, l, left, unsetLabel: l.shortcutNotSet),
                          _chord(t, l, right, unsetLabel: l.shortcutNotSet),
                        ],
                        // The last clause is the only place anything tells
                        // a new user that the eleven defaults are not the
                        // whole vocabulary. A feature nobody is told about
                        // is one nobody finds — the same hole the grid
                        // itself fell into before this screen existed.
                        caption: l.readyDirectCaption,
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
                  l.readyChangeShortcuts,
                  style: TextStyle(fontSize: 12.5, color: t.link),
                ),
              ),
              FilledButton(
                onPressed: onDone,
                style: FilledButton.styleFrom(
                  backgroundColor: t.accent,
                  foregroundColor: t.onAccent,
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
                child: Text(l.readyDone),
              ),
            ],
          ),
        ],
      ),
    );
    return FirstFrameReport(
      name: 'ready',
      onMacOS: false,
      child: Scaffold(
        backgroundColor: t.windowBackground,
        body: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(child: content),
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.tokens,
    required this.art,
    required this.chords,
    required this.caption,
  });

  final PlatformTokens tokens;
  final Widget art;

  /// Each chord whole. On macOS they stay on one line: a centred row at full
  /// size while they fit, as the default chords do, and scaled down together
  /// when they are wider than the card, as two rebound to four modifiers each
  /// are (the row they replace ran past the card). Windows names its keys
  /// (Win, Ctrl, Shift), so its default chords are wider than a card, and
  /// scaled to fit they would draw far smaller than the first card's: there
  /// the second goes beneath the first, at full size, and only a chord wider
  /// than the card on its own is scaled down, to the card's width.
  final List<Widget> chords;
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
          if (defaultTargetPlatform == TargetPlatform.windows)
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final chord in chords)
                  FittedBox(fit: BoxFit.scaleDown, child: chord),
              ],
            )
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < chords.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    chords[i],
                  ],
                ],
              ),
            ),
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
