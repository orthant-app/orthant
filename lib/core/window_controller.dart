import 'geometry.dart';

/// A window captured natively; [frame] is its current frame in top-left space.
class CapturedWindow {
  final String appName;
  final WinRect frame;
  const CapturedWindow(this.appName, this.frame);
}

/// Whether the app is set to launch at login, as the OS currently sees it.
///
/// Deliberately not persisted anywhere on our side: the user can change this in
/// System Settings and macOS never tells us, so any cached copy would start
/// lying the moment they did. Always read it.
enum LoginItemStatus {
  /// Not asked yet.
  ///
  /// The window opens before the answer arrives — deliberately, because
  /// `SMAppService.mainApp.status` is not fast — so there has to be a state
  /// that means "we do not know", distinct from [unavailable] which means
  /// "macOS answered with something unrecognised".
  ///
  /// Conflating the two cost a visible defect: the pane rendered
  /// [unavailable]'s notice for the ~50 ms before the real status landed, so
  /// every open briefly told the user macOS had reported a state Orthant did
  /// not recognise — untrue — and grew the window 38 pt to say it.
  unknown,

  enabled,
  disabled,

  /// Registered, but switched off by the user in System Settings ▸ General ▸
  /// Login Items — so the app will *not* launch. Distinct from [disabled]
  /// because the remedy is different and lives outside this app.
  requiresApproval,

  /// The platform could not say — an older macOS, a bundle it cannot find, or
  /// a status this build does not recognise. Never rendered as "on".
  unavailable,
}

/// What the running bundle says it is. Both halves, because
/// `CFBundleShortVersionString` alone cannot distinguish one pre-release from
/// the next — Apple requires it to be three integers, so a `-beta.N` label
/// lives only in the git tag, the DMG filename and the release title. The
/// build number is the part that actually changes between betas, and the part
/// Sparkle compares.
class AppVersion {
  const AppVersion(this.shortVersion, this.buildNumber, {this.releaseName = ''});

  final String shortVersion;
  final String buildNumber;

  /// The release's real name — `1.0.1`, or `1.0.1-beta.2` — stamped into the
  /// bundle by `tool/release.sh` from the tag it is building.
  ///
  /// Empty for anything not built by that script: a local `flutter build`, a
  /// dev build, a debug run. There is no release name for an untagged build to
  /// claim, and inventing one would be the drift this whole value exists to
  /// avoid.
  final String releaseName;

  /// Whether there is anything worth showing.
  bool get isKnown => display.isNotEmpty;

  /// What to call this build, in one string.
  ///
  /// The release name wins when there is one, because it is the only form that
  /// can say `1.0.1-beta.2`: `CFBundleShortVersionString` must be three
  /// integers by Apple's rule, so a pre-release label cannot live there, and
  /// without this an installed beta and the stable after it both render an
  /// identical `1.0.0`.
  ///
  /// Otherwise `1.0.0 (4)` — the macOS convention, and the form Sparkle's own
  /// update prompt uses ("Orthant 1.0.0 (2) is now available—you have
  /// 1.0.0 (1)"). That is the right answer for a dev build, where the build
  /// number is the only thing distinguishing one from the last.
  String get display {
    if (releaseName.isNotEmpty) return releaseName;
    if (shortVersion.isEmpty || buildNumber.isEmpty) return '';
    return '$shortVersion ($buildNumber)';
  }

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      other.shortVersion == shortVersion &&
      other.buildNumber == buildNumber &&
      other.releaseName == releaseName;

  @override
  int get hashCode => Object.hash(shortVersion, buildNumber, releaseName);

  @override
  String toString() =>
      'AppVersion($shortVersion, $buildNumber, releaseName: $releaseName)';
}

/// Platform-agnostic window control. Native handles never cross this seam —
/// only plain data does. macOS is backed by a MethodChannel to Swift.
abstract class WindowController {
  Future<bool> checkPermission();
  Future<void> requestPermission();

  /// Capture the frontmost app's focused window natively; return its identity
  /// and current frame, or null if nothing is capturable.
  Future<CapturedWindow?> captureFrontmost();

  /// Visible frame (excludes menu bar / Dock) of the display under the cursor,
  /// in top-left global points. Used by the overlay, which is summoned where
  /// the user is looking.
  Future<WinRect> activeScreenFrame();

  /// Every display's visible frame, top-left global points. Callers choose the
  /// relevant one (see [screenContaining]) — keyboard shortcuts pick the
  /// display the target *window* is on, not the one under the cursor.
  Future<List<WinRect>> screenFrames();

  /// Move + resize the captured window to [target]. Best-effort.
  Future<bool> applyFrame(WinRect target);

  /// Open System Settings ▸ Privacy & Security ▸ Accessibility.
  Future<void> openAccessibilitySettings();

  /// Show / hide the app's own config (onboarding + settings) window.
  Future<void> showConfigWindow();
  Future<void> hideConfigWindow();

  /// Show / hide the grid overlay. The panel is sized to the active display
  /// natively *before* it is shown, so it inherits that display's scale factor;
  /// showing it must never make Orthant frontmost.
  /// Push the configured grid to the native side, which includes it in every
  /// summon payload. The overlay runs on its own Flutter engine and cannot read
  /// the main isolate's preferences, so this is how it learns the grid at all.
  /// Push the grid, and whether the overlay should offer its save hint.
  ///
  /// [saveHint] is `regions.isEmpty` — the actual condition the hint exists to
  /// address, rather than a summon count nobody can defend. It needs no new
  /// persistence and it stops the moment it stops being true.
  Future<void> setOverlayGrid({
    required int cols,
    required int rows,
    required double gap,
    required bool saveHint,
  });

  Future<void> showOverlay();
  Future<void> hideOverlay();

  /// What the running bundle reports itself to be. Read natively from
  /// `Bundle.main`, never from pubspec or a Dart constant — those drift
  /// from what actually shipped, which is the whole failure this exists to
  /// prevent.
  Future<AppVersion> appVersion();

  /// Whether the app currently launches at login, per the OS.
  Future<LoginItemStatus> loginItemStatus();

  /// Turn launch-at-login on or off, returning the status **after** the
  /// attempt. Registration can be refused; echoing back what was requested
  /// would make the checkbox claim a state the system never entered.
  Future<LoginItemStatus> setLoginItem(bool enabled);

  /// Open System Settings ▸ General ▸ Login Items — the only remedy for
  /// [LoginItemStatus.requiresApproval], since no API can flip that switch.
  Future<void> openLoginItemsSettings();

  /// Show Sparkle's update check, the same as the tray item does.
  ///
  /// Fire-and-forget: the updater owns the whole flow from here, including its
  /// own UI, and there is no answer Dart could act on.
  Future<void> checkForUpdates();
}
