import 'package:flutter/material.dart';

import '../core/window_controller.dart';
import 'mac_button.dart';
import 'mac_theme.dart';

/// What the running build is, and the one action anyone wants after reading it.
///
/// **Why a pane rather than macOS's own About panel.** `orderFrontStandardAboutPanel`
/// is free, native and correct — on macOS. Windows is the planned second target
/// (spec §8) and has no standard about box at all; every Windows app draws its
/// own. Taking the free panel would therefore mean *two* implementations and two
/// different-looking dialogs for one piece of information, and it would put UI
/// natively in an app whose architecture is deliberately "Flutter for the shared
/// UI, Swift for the native core". An about box is UI.
///
/// **Why it lives in the settings window rather than its own.** Flutter's macOS
/// embedding is one view per engine, so a separate window means a third
/// `FlutterEngine` — the overlay's cost ~5.7 MB apiece and leak on teardown
/// unless shut down exactly right (M5). That is a steep price for four lines of
/// text. The settings window already owns the show/hide, activation-policy and
/// frame-restoration machinery this needs.
///
/// **Why it replaced a disabled tray row.** The version shipped first as a greyed
/// item in the tray menu. A greyed row among live commands reads as *a command
/// that is broken* — macOS greys what you cannot do — and the original argument
/// for the placement ("version and next action in one glance") does not survive
/// contact: a user cannot tell whether `1.0.0 (2)` is current, because they do
/// not know what the current one is. Only *Check for Updates…* answers that. The
/// version's real audience is a bug report, and a bug report can afford a click.
class AboutPane extends StatelessWidget {
  const AboutPane({
    super.key,
    required this.version,
    this.onCheckForUpdates,
    this.scrollController,
  });

  /// Read from the running bundle by the platform. Rendered only when
  /// [AppVersion.isKnown] — a build that cannot say what it is shows nothing
  /// rather than `Version  ()`.
  final AppVersion version;

  /// Null disables the button. The same call the tray's *Check for Updates…*
  /// makes; two entry points, one updater session.
  final VoidCallback? onCheckForUpdates;

  final ScrollController? scrollController;

  /// Drawn at 64 pt, the size macOS's own About panel uses. The asset is 256 px,
  /// so it stays crisp at 2x with room over.
  static const double iconSize = 64;

  @override
  Widget build(BuildContext context) {
    final t = context.mac;
    // Centre in the *viewport*, and scroll when the viewport is too short for
    // the content. `minHeight` has to come from the incoming constraints, not
    // a constant: a `SingleChildScrollView` sizes its child to the child's own
    // height, so `Center` inside a fixed 380 pt box centres within 380 pt and
    // leaves the rest of a 620 pt window empty below it. Measured — it looked
    // top-weighted rather than centred.
    //
    // Scrolling is not optional here. The window is user-resizable down to a
    // 500 pt content height, and a pane that centres its own content will clip
    // its only action first.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        controller: scrollController,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Decorative: the name is right underneath in text, so a screen
                  // reader announcing the icon too would just say it twice.
                  ExcludeSemantics(
                    child: Image.asset(
                      'assets/app_icon.png',
                      width: iconSize,
                      height: iconSize,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Orthant',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: t.labelPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (version.isKnown) ...[
                    const SizedBox(height: 4),
                    Text(
                      // `Version 1.0.0 (2)` — the macOS form, and the one Sparkle's
                      // own update prompt uses, so the app and its updater describe
                      // versions identically.
                      //
                      // labelSecondary, never labelTertiary: tertiary is macOS's
                      // *disabled* weight at 2.4:1, and this text is not disabled.
                      // The Shortcuts pane already paid for that confusion once.
                      'Version ${version.display}',
                      style: TextStyle(fontSize: 13, color: t.labelSecondary),
                    ),
                  ],
                  const SizedBox(height: 20),
                  MacPushButton(
                    label: 'Check for Updates…',
                    tokens: t,
                    onPressed: onCheckForUpdates,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    // No platform named. Windows is the planned second target
                    // (spec §8), and "for macOS" is a line that would be wrong
                    // the day that ships while still looking perfectly fine.
                    'A grid-based window manager.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: t.labelSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
