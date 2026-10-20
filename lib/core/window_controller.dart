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

/// An update a check found and nobody has acted on yet: the name it shows
/// (`1.0.4`, `1.1.0-beta.1`) and the build number it is compared by, as
/// Sparkle compares `CFBundleVersion`.
class AvailableUpdate {
  const AvailableUpdate(this.name, this.build);

  final String name;
  final int build;

  @override
  bool operator ==(Object other) =>
      other is AvailableUpdate && other.name == name && other.build == build;

  @override
  int get hashCode => Object.hash(name, build);

  @override
  String toString() => '$name ($build)';
}

/// The user's accent colour as the OS draws its own controls with it, once
/// for a light appearance and once for a dark one, each 0xAARRGGBB.
///
/// Two, not one, because both platforms draw two. macOS resolves
/// `controlAccentColor` per appearance: a purple accent is #953D96 in light
/// and #A550A7 in dark (measured on macOS 26). Windows fills an accent control
/// with a darker shade of the accent in its light theme and a lighter one in
/// its dark theme (`windows_accent.dart`).
///
/// [linkLight] and [linkDark] are the colour of link text, where the OS draws
/// its links from the accent: Windows' WinUI (`AccentTextFillColorPrimary`),
/// one shade past the fill each way. Null on macOS, whose link colour never
/// follows the accent.
class AccentColors {
  const AccentColors({
    required this.light,
    required this.dark,
    this.linkLight,
    this.linkDark,
  });

  final int light;
  final int dark;
  final int? linkLight;
  final int? linkDark;

  @override
  bool operator ==(Object other) =>
      other is AccentColors &&
      other.light == light &&
      other.dark == dark &&
      other.linkLight == linkLight &&
      other.linkDark == linkDark;

  @override
  int get hashCode => Object.hash(light, dark, linkLight, linkDark);

  /// The fills in the form the acceptance harness reads from the app's log,
  /// closing bracket included; the links after it.
  @override
  String toString() => 'AccentColors(light: 0x${light.toRadixString(16)}, '
      'dark: 0x${dark.toRadixString(16)})'
      '${linkLight == null && linkDark == null ? '' : ', links (light: '
          '0x${linkLight?.toRadixString(16)}, '
          'dark: 0x${linkDark?.toRadixString(16)})'}';
}

/// Platform-agnostic window control. Native handles never cross this seam —
/// only plain data does. macOS is backed by a MethodChannel to Swift.
abstract class WindowController {
  Future<bool> checkPermission();
  Future<void> requestPermission();

  /// Capture the frontmost app's focused window natively; return its identity
  /// and current frame, or null if nothing is capturable.
  Future<CapturedWindow?> captureFrontmost();

  /// The display under the cursor: its visible frame (excluding the menu bar
  /// and Dock on macOS, the taskbar on Windows) in global placement space, and
  /// its scale. Used by the overlay, which is summoned where the user is
  /// looking, and as `applyRegion`'s fallback when no displays are reported,
  /// for a window that is on it.
  ///
  /// Null when the platform cannot say. Never a zero rect: a placement
  /// computed against one puts the window at the origin with no size and
  /// reports it as placed.
  Future<Display?> activeScreenFrame();

  /// Every display, in global placement space. Callers choose the relevant one
  /// (see [displayContaining]): keyboard shortcuts pick the display the target
  /// *window* is on, not the one under the cursor.
  Future<List<Display>> screenFrames();

  /// Move + resize the captured window to [target], in global placement space.
  /// Best-effort; true only when the window demonstrably arrived.
  Future<bool> applyFrame(WinRect target);

  /// Place the window captured for the summon named [sessionId] at [target],
  /// in global placement space, at most once.
  ///
  /// Windows only. There the overlay's commit comes back to Dart, which owns
  /// the captured window: it applies only if [sessionId]
  /// names the current capture and that capture has not been applied yet, so
  /// a duplicate, or a late commit from a session a newer capture replaced,
  /// never moves a window. True only when the window demonstrably arrived.
  ///
  /// macOS applies the grid's commit natively and never calls this.
  Future<bool> applyOverlayCommit(int sessionId, WinRect target);

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

  /// [pressedAtMs] is Windows only: the time of the key press that asked for
  /// this summon, in milliseconds on the system's monotonic tick clock, which
  /// only the runner reads (Dart passes it back untouched). The runner refuses
  /// a summon that reached it more than a second after its press, and times
  /// the overlay's first frame from it. A tick, not the wall clock, so a clock
  /// step (time sync after a wake) cannot make a fresh press look stale. Null
  /// for a summon with no press (the tray). macOS stamps its own press
  /// natively and ignores it.
  Future<void> showOverlay({double? pressedAtMs});
  Future<void> hideOverlay();

  /// Launch has done what must answer first (the hotkeys are registered and
  /// the tray is built), so the overlay may start its engines. Windows only:
  /// each overlay engine there costs over a second of the thread every engine
  /// shares, so the runner waits for this (or, failing it, a deadline) rather
  /// than make the shortcuts and the tray wait for the overlay. macOS starts
  /// its overlay engine with the app, and this does nothing there.
  Future<void> startOverlay();

  /// Whether window commands are queued or running: true as the first of a
  /// burst is queued, false once the last has finished, however it ended. On
  /// Windows no overlay engine attaches in between, since an attach holds the
  /// thread the commands share for over a second and a placement leaves that
  /// thread idle between its reads; a time-based hold cannot know when a
  /// placement, or a queue of them, is done. macOS has nothing to defer.
  Future<void> setCommandsRunning(bool running);

  /// What the running bundle reports itself to be. Read natively from
  /// `Bundle.main`, never from pubspec or a Dart constant — those drift
  /// from what actually shipped, which is the whole failure this exists to
  /// prevent.
  Future<AppVersion> appVersion();

  /// Printable labels for keys in the current input source, keyed by
  /// `KeyChord.labelKey`: the physical key's USB HID usage on macOS, which
  /// registers by position, and the key's Windows id (`KeyChord.windowsKey`,
  /// its logical key but for two Brazilian keys) on Windows, which registers
  /// by meaning. Display data only: a binding keeps its key whatever this says.
  Future<Map<int, String>> keyboardLabels();

  /// The user's accent, as the OS draws its own controls with it, or null
  /// when the OS will not say, which the theme reads as the platform's
  /// default. Read from the OS every time, never cached: the user can change
  /// it in System Settings or Windows' Settings at any moment. Display data
  /// only, and never throws: it is read on the way to showing the config
  /// window, which a throw would leave unshown.
  Future<AccentColors?> accentColor();

  /// Whether the app currently launches at login, per the OS.
  Future<LoginItemStatus> loginItemStatus();

  /// Turn launch-at-login on or off, returning the status **after** the
  /// attempt. Registration can be refused; echoing back what was requested
  /// would make the checkbox claim a state the system never entered.
  Future<LoginItemStatus> setLoginItem(bool enabled);

  /// Open System Settings ▸ General ▸ Login Items — the only remedy for
  /// [LoginItemStatus.requiresApproval], since no API can flip that switch.
  Future<void> openLoginItemsSettings();

  /// Whether the updater checks on its own schedule.
  ///
  /// Read from the updater every time, never cached: the value is Sparkle's
  /// and it persists the user's choice itself, so a copy on our side would
  /// start lying the moment it changed. Same reasoning as [loginItemStatus].
  Future<bool> automaticUpdateChecks();

  /// Turn scheduled checks on or off, returning the state **after** the
  /// attempt. Echoing back the request would let the checkbox claim a state the
  /// updater never entered.
  Future<bool> setAutomaticUpdateChecks(bool enabled);

  /// Show Sparkle's update check, the same as the tray item does.
  ///
  /// Fire-and-forget: the updater owns the whole flow from here, including its
  /// own UI, and there is no answer Dart could act on.
  Future<void> checkForUpdates();
}
