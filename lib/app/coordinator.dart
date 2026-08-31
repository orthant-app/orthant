import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/window_controller.dart';
import '../permission/permission_controller.dart';
import '../settings/settings.dart';
import '../settings/settings_store.dart';
import '../settings/region_picker_sheet.dart';
import '../settings/settings_window.dart';
import '../shortcuts/apply_region.dart';
import '../shortcuts/bindings.dart';
import '../shortcuts/bindings_store.dart';
import '../shortcuts/command_ref.dart';
import '../shortcuts/custom_region.dart';
import '../shortcuts/command_queue.dart';
import '../shortcuts/hotkey_service.dart';
import '../shortcuts/shortcut_command.dart';

/// What the config window is currently showing.
enum AppScreen { none, onboarding, ready, settings }

/// One row of the tray menu, as data rather than as a `tray_manager` object.
///
/// The coordinator *describes* the menu and `main.dart` renders it. That split
/// is not ceremony: two of this app's shipped defects were in these three
/// fields — a combo advertised for a chord the OS had refused, and a live
/// "Open Grid" that could only beep — and neither was reachable by a test while
/// the description was built inline against a plugin singleton.
@immutable
class TrayEntry {
  const TrayEntry(this.key, this.label, {this.disabled = false});
  const TrayEntry.separator() : key = '', label = '', disabled = false;

  final String key;
  final String label;
  final bool disabled;

  bool get isSeparator => key.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is TrayEntry &&
      other.key == key &&
      other.label == label &&
      other.disabled == disabled;

  @override
  int get hashCode => Object.hash(key, label, disabled);

  @override
  String toString() => isSeparator
      ? 'TrayEntry.separator()'
      : 'TrayEntry($key, "$label"'
            '${disabled ? ", disabled" : ""})';
}

/// Everything the app does that is neither geometry nor a widget: the launch
/// sequence, the permission lifecycle, what the one window is showing, the
/// bindings, the settings, and the tray's contents.
///
/// Extracted from `main.dart`, which had absorbed **21 fix commits at 0 %
/// coverage** — the single most defect-dense file in the project, and named as
/// such by external review. Every one of those defects was an ordering or
/// state-transition question that a unit test can ask directly: does closing
/// onboarding before the grant still show the ready screen; do preferences load
/// when permission is absent; does the tray advertise a chord that cannot fire.
///
/// Dependencies are injected, and only two of them are wide: [WindowController]
/// is the existing platform seam, and [HotkeyRegistrar] exists so this class
/// never touches a MethodChannel. The stores stay concrete because
/// `SharedPreferences.setMockInitialValues` already makes them testable.
class OrthantCoordinator extends ChangeNotifier {
  OrthantCoordinator({
    required this.wc,
    required this.permissions,
    required this.hotkeys,
    BindingsStore? bindingsStore,
    SettingsStore? settingsStore,
    CommandQueue? commands,
    this.pollPeriod = const Duration(milliseconds: 1500),
  }) : _bindingsStore = bindingsStore ?? BindingsStore(),
       _settingsStore = settingsStore ?? SettingsStore(),
       _commands = commands ?? CommandQueue();

  final WindowController wc;
  final PermissionController permissions;
  final HotkeyRegistrar hotkeys;
  final BindingsStore _bindingsStore;
  final SettingsStore _settingsStore;

  /// Everything that touches the single native capture slot runs through here,
  /// one at a time. See [CommandQueue] for why overlapping is unsafe.
  final CommandQueue _commands;

  /// How often to re-check permission *while waiting on the user in System
  /// Settings*. Injectable so a test is not obliged to wait on real time.
  final Duration pollPeriod;

  Timer? _poll;

  // ---------------------------------------------------------------- state

  AppScreen _screen = AppScreen.none;
  AppScreen get screen => _screen;

  List<Binding> _bindings = const [];
  List<Binding> get bindings => _bindings;

  /// The user's own regions, loaded and saved alongside the bindings so a
  /// partial write cannot orphan one against the other.
  List<CustomRegion> _regions = const [];
  List<CustomRegion> get regions => _regions;

  Settings _settings = const Settings();
  Settings get settings => _settings;

  /// Commands the OS refused to register a hotkey for, from the last apply.
  /// Surfaced in the settings list; see [HotkeyService.apply].
  Set<CommandRef> _unavailable = const {};
  Set<CommandRef> get unavailable => _unavailable;

  /// The OS's answer, re-read every time the window opens — never cached.
  LoginItemStatus _loginStatus = LoginItemStatus.unknown;
  LoginItemStatus get loginStatus => _loginStatus;

  /// What the running bundle says it is. Read once at start-up: unlike the
  /// login-item status, this cannot change under a running process, so there
  /// is nothing to re-read and no staleness to guard against.
  AppVersion _appVersion = const AppVersion('', '');
  AppVersion get appVersion => _appVersion;

  /// Which pane the settings window should open on. Only ever not `general`
  /// when something asked for a specific one by name.
  SettingsTab _settingsTab = SettingsTab.general;
  SettingsTab get settingsTab => _settingsTab;

  void _set(AppScreen screen) {
    if (_screen == screen) return;
    _screen = screen;
    notifyListeners();
  }

  // ---------------------------------------------------------------- launch

  /// The launch sequence. Returns once the app knows what to show.
  Future<void> start() async {
    await permissions.refresh();

    // Before anything can render the tray. Cheap, and it cannot change
    // under a running process, so this is the only read.
    _appVersion = await wc.appVersion();

    // Preferences load **either way**. They are settings, not capabilities:
    // Accessibility governs whether a shortcut can move a window, not whether
    // the user has one configured. Loading them only in the granted branch left
    // `_bindings` empty for the entire ungranted session, which is precisely
    // when someone opens the settings window to find out what is wrong — and
    // the Shortcuts list then had nothing to render but a blank grey pane.
    await loadPreferences();

    if (permissions.granted) {
      _unavailable = await hotkeys.apply(_bindings);
      if (!await _settingsStore.hasOnboarded() &&
          await _settingsStore.hasStartedOnboarding()) {
        // Onboarding was shown, never finished, and the grant is here now: they
        // read that window, went to System Settings and granted — with Orthant
        // quit in between, which is an ordinary way to do it. Marking onboarding
        // complete for having *found* the grant retired the one screen that ever
        // mentions the grid, so the whole feature stayed undiscovered. Same
        // defect as the in-process path below already fixed; this is the version
        // that survives a relaunch.
        _set(AppScreen.ready);
        await wc.showConfigWindow();
      } else {
        // Granted before we ever showed anything: there is no moment to put the
        // ready screen in without opening a window unbidden, which M2
        // deliberately does not do. Mark it done so it cannot surface at some
        // arbitrary later grant.
        await _settingsStore.markOnboarded();
        await wc.hideConfigWindow(); // stay a menu-bar agent
      }
    } else {
      // No `permissions.register()` here. It put macOS's own "…would like to
      // control this computer" alert on screen the instant the app launched, on
      // top of the onboarding window that explains the same thing — two surfaces
      // asking one question before the user had done anything. The request is
      // now what the onboarding button does first ([openAccessibility]), which
      // is where a permission prompt belongs: in response to being asked for.
      // Locked in spec §8, because it had flip-flopped four times.
      _set(AppScreen.onboarding);
      // Recorded before the window, so a quit at any point after this counts as
      // having asked. See [SettingsStore.hasStartedOnboarding].
      await _settingsStore.markStartedOnboarding();
      await wc.showConfigWindow();
      _startPolling();
    }

    // Subscribed **after** the branch above, not before it. The first refresh
    // is itself a transition (unknown → granted) and would run
    // [onPermissionChanged], which on a first launch finds `hasOnboarded` false
    // and puts the ready screen on screen — for a user who has just launched an
    // already-granted app and asked for nothing. The branch above is what marks
    // onboarding done in that case, so it has to have run first.
    permissions.addListener(_onPermissionNotified);
    notifyListeners();
  }

  /// Read what the user configured. Needs no permission of any kind.
  Future<void> loadPreferences() async {
    final stored = await _bindingsStore.load();
    _bindings = stored.bindings;
    _regions = stored.regions;
    _settings = await _settingsStore.load();
    await pushGrid();
    notifyListeners();
  }

  /// Preferences, then the registrations that need Accessibility to be useful.
  Future<void> enableShortcuts() async {
    await loadPreferences();
    _unavailable = await hotkeys.apply(_bindings);
    notifyListeners();
  }

  /// Hand the configured grid to native, which puts it in every summon payload.
  Future<void> pushGrid() => wc.setOverlayGrid(
    cols: _settings.gridCols,
    rows: _settings.gridRows,
    gap: _settings.effectiveGap,
    // Offer the hint only to someone who has never made a region. Once one
    // exists they know the feature does, and the overlay goes back to being
    // only the grid.
    saveHint: _regions.isEmpty,
  );

  // ------------------------------------------------------------ permission

  /// Poll only while waiting on the user in System Settings. Once granted we
  /// stop: a resident Flutter engine's idle cost is a real concern (spec §5),
  /// and macOS lets an already-running process keep the Accessibility
  /// capability it was granted — toggling the switch off does not revoke it
  /// live, so there is nothing for a permanent poll to notice. A genuine loss
  /// is caught on demand instead, by [runCommand], and on next launch.
  void _startPolling() =>
      _poll ??= Timer.periodic(pollPeriod, (_) => permissions.refresh());

  /// The permission transition most recently started.
  ///
  /// `notifyListeners` is synchronous and [onPermissionChanged] is not, so
  /// "the grant was noticed" and "the app has finished reacting to it" are
  /// different moments. Exposed so a caller can await the second — otherwise the
  /// only way to observe it is to drain the event queue and hope.
  Future<void> get permissionSettled => _permissionWork ?? Future.value();
  Future<void>? _permissionWork;

  void _onPermissionNotified() => _permissionWork = onPermissionChanged();

  Future<void> onPermissionChanged() async {
    if (permissions.granted) {
      _poll?.cancel();
      _poll = null;
      await enableShortcuts();
      if (await _settingsStore.hasOnboarded()) {
        // Only take down a window we put up ourselves to ask for the grant.
        //
        // **Hidden first, emptied second.** `AppScreen.none` renders
        // `SizedBox.shrink()`, which paints nothing *and* reports no height — so
        // a window still on screen neither resizes nor draws: it sits at its
        // last size and goes solid black. Assigning it before the hide put
        // exactly that on screen for a channel round trip, and it was reported
        // from a real build as "the onboarding dialog is a black screen", at the
        // Shortcuts pane's height because that was the last size it was given.
        //
        // This ordering makes the duration of `hideConfigWindow` irrelevant,
        // which a shorter await would not: the surface only empties once there
        // is nothing on screen to empty.
        if (_screen == AppScreen.onboarding) {
          await wc.hideConfigWindow();
          _set(AppScreen.none);
        }
      } else {
        // Not gated on the onboarding screen still being *visible*. Closing
        // that window and then granting is an ordinary thing to do — the window
        // says "waiting for permission…" and the work is happening in System
        // Settings — and it used to mean the ready screen never appeared, while
        // the next launch marked onboarding complete for having found the grant
        // in place. Since this is the only screen that ever mentions the grid,
        // the whole feature went undiscovered for exactly that click. Shown
        // once, ever, so re-showing the window here cannot become a habit.
        _set(AppScreen.ready);
        await wc.showConfigWindow();
      }
    } else {
      // Never had it, or lost it: make sure we're watching for the grant.
      _startPolling();
    }
    notifyListeners();
  }

  /// The one button that asks macOS for Accessibility.
  ///
  /// First press ever: request. That shows macOS's own alert — which carries its
  /// own "Open System Settings" — and is the only way Orthant gets itself
  /// *listed* in the Accessibility pane at all; without it the user would have
  /// to add the app by hand with `+`.
  ///
  /// Every press after: deep-link. macOS shows that alert at most once per
  /// record, so a second request is silent, and a button that does nothing is
  /// worse than one that opens the pane. Doing both at once is what this used to
  /// do, and it asked the same question twice on one click.
  Future<void> openAccessibility() async {
    if (!await _settingsStore.hasPromptedForAccessibility()) {
      await _settingsStore.markPromptedForAccessibility();
      await permissions.register();
      return;
    }
    await permissions.openSettings();
  }

  /// A placement failed. Check permission on the spot — macOS never tells us
  /// when it is revoked — and fall back to onboarding if that is what happened.
  /// Shared by the shortcut path and the grid, which reports failures over the
  /// channel because it never returns through Dart.
  Future<void> recoverIfPermissionLost() async {
    await permissions.refresh();
    if (permissions.granted) return;
    await hotkeys.unregisterAll();
    _set(AppScreen.onboarding);
    await wc.showConfigWindow();
  }

  // --------------------------------------------------------------- commands

  /// Open the grid.
  ///
  /// No guard here on whether our own window is open. That was tried and was
  /// wrong: leaving the settings window open — the natural thing to do while
  /// trying shortcuts out — silently killed the summon in every other app. Not
  /// capturing *ourselves* is the actual invariant, it depends on who is
  /// frontmost at this instant, and `captureFrontmostWindow` is the only place
  /// that knows without a round trip on the latency-sensitive summon path.
  Future<void> summon() => _commands.add(() => wc.showOverlay());

  /// Run a shortcut. If placement fails we check permission on the spot: this is
  /// how a genuine loss of Accessibility surfaces (macOS never tells us), at the
  /// one moment the user cares, and at zero idle cost. Failures that aren't a
  /// permission problem — e.g. a native-fullscreen window, which beeps natively —
  /// leave the app alone.
  ///
  /// Queued rather than run directly: a press arrives as a fire-and-forget
  /// callback, so two in quick succession would otherwise interleave over the
  /// one native capture slot and move the wrong window ([CommandQueue]).
  Future<void> runCommand(CommandRef cmd) => _commands.add(() async {
    // effectiveGap: gaps are one preference about how windows are placed,
    // not one per path. Without this they would apply to the grid and
    // silently not to the ten shortcuts, which is most of what people use.
    if (await applyRegion(wc, cmd,
        regions: _regions, gap: _settings.effectiveGap)) {
      return;
    }
    await recoverIfPermissionLost();
  });

  // ------------------------------------------------------------------ tray

  /// The tray menu, as data.
  ///
  /// Rebuilt from live state on every read, because macOS never tells us the
  /// grant changed and this is where the user can always see whether Orthant
  /// works.
  List<TrayEntry> get trayMenu => [
    // Only surface permission when it needs attention. A permanently
    // greyed-out "Enabled" row is noise — working is the normal case, and
    // the shortcuts themselves are the feedback that it works.
    if (!permissions.granted) ...[
      const TrayEntry('permission', 'Enable Accessibility…'),
      const TrayEntry.separator(),
    ],
    // Greyed while ungranted, because it cannot work: capture fails, the
    // grid never appears, and all the user gets is a beep and an onboarding
    // window they did not ask for. macOS greys a command it cannot run, and
    // the row above says why this one cannot. Every *other* affordance stays
    // live while ungranted — the settings, the steppers, the shortcut rows —
    // because those configure future behaviour rather than acting now, and
    // they persist perfectly well without the grant.
    TrayEntry('overlay', openGridLabel, disabled: !permissions.granted),
    const TrayEntry('settings', 'Settings…'),
    // Opens Settings on the About pane, which is where the version lives.
    //
    // This row used to *be* the version, rendered as a disabled label. It read
    // as a command that was broken — macOS greys what you cannot do — and the
    // reasoning behind putting it here did not survive use: "the version and
    // the next action in one glance" assumes a user can tell whether their
    // version is current, and they cannot, because they do not know what the
    // current one is. Only the row below answers that. The version's real
    // audience is a bug report, which can afford a click. Unconditional, unlike
    // the old row: this menu is Orthant's only front door, so About must be
    // reachable even from a build that cannot say what version it is.
    const TrayEntry('about', 'About Orthant'),
    const TrayEntry('updates', 'Check for Updates…'),
    const TrayEntry.separator(),
    const TrayEntry('quit', 'Quit Orthant'),
  ];

  /// "Open Grid", with the summon's combo appended when there is one to show.
  ///
  /// The same words as the shortcut row and the General pane, in menu title
  /// case. It read "Show Grid" while everything else said "Open grid", which is
  /// two names for one command.
  ///
  /// The combo is omitted when the shortcut is unset, when the OS refused it,
  /// **and while ungranted** — in all three cases pressing it does nothing, and
  /// a menu that printed it anyway would be advertising a keystroke that cannot
  /// fire. The item itself works either way, which is the point of keeping it.
  String get openGridLabel {
    final combo = permissions.granted
        ? comboLabelFor(
            _bindings,
            const BuiltIn(ShortcutCommand.showGrid),
            unavailable: _unavailable,
          )
        : null;
    return combo == null ? 'Open Grid' : 'Open Grid   $combo';
  }

  /// The tray's "Enable Accessibility…" row. Only reachable while ungranted.
  Future<void> showOnboarding() async {
    _set(AppScreen.onboarding);
    await wc.showConfigWindow();
    _startPolling();
  }

  // -------------------------------------------------------------- the window

  /// The user closed the config window with its own close button. Native has
  /// already put the activation policy back to `.accessory`; what only Dart can
  /// undo is the screen state and — the part that actually breaks things — the
  /// hotkey suspension. Recording a combo unregisters every shortcut so the
  /// combo being recorded doesn't also fire it; a close mid-recording never
  /// delivers `onCaptureEnd`, so without this every shortcut stays dead until
  /// the next rebind or relaunch. Re-applying is idempotent, so it costs nothing
  /// to do it on every close rather than track whether a recording was in
  /// flight.
  Future<void> onConfigWindowClosed() async {
    _set(AppScreen.none);
    if (permissions.granted) _unavailable = await hotkeys.apply(_bindings);
    notifyListeners();
  }

  /// Show the settings window.
  ///
  /// The screen is set *before* any await, deliberately. Fetching the login
  /// status first meant the window could be on screen with the screen state
  /// still at its previous value for a whole channel round trip — and
  /// `SMAppService.mainApp.status` is not fast. When that previous value was
  /// `none`, the visible window rendered `SizedBox.shrink()`: an empty panel.
  /// The status arrives a moment later and re-renders the one row that needs it,
  /// which is what a status read should cost.
  Future<void> openSettings({SettingsTab tab = SettingsTab.general}) async {
    final t0 = DateTime.now();
    _settingsTab = tab;
    _set(AppScreen.settings);
    notifyListeners();
    await wc.showConfigWindow();
    final shown = DateTime.now();
    _loginStatus = await wc.loginItemStatus();
    final statused = DateTime.now();
    notifyListeners();
    if (!kReleaseMode) {
      debugPrint('[orthant] openSettings: '
          'showConfigWindow ${shown.difference(t0).inMilliseconds} ms, '
          'loginItemStatus ${statused.difference(shown).inMilliseconds} ms');
    }
  }

  /// The grant is the one moment a new user is already looking at our window,
  /// and until the ready screen existed it was where onboarding *ended*.
  /// Nothing then ever mentioned the grid, so the expensive half of the app was
  /// undiscoverable. Shown once.
  Future<void> finishOnboarding({bool hide = true}) async {
    await _settingsStore.markOnboarded();
    // Same ordering rule as the grant path above, for the same reason: an
    // emptied surface on a window still on screen is a black rectangle at
    // whatever size the window last had.
    if (hide) await wc.hideConfigWindow();
    _set(AppScreen.none);
  }

  /// Straight from ready to the Shortcuts tab. Routing through
  /// [finishOnboarding] first set the screen to `none` while the window was
  /// still visible, so it rendered empty until the next screen was assigned.
  Future<void> openShortcutsFromReady() async {
    await _settingsStore.markOnboarded();
    await openSettings(tab: SettingsTab.shortcuts);
  }

  // ------------------------------------------------------------- settings

  /// Adopt a settings change.
  ///
  /// The notification comes **first**, before the save and the channel push.
  /// The pane's controls are built from the `settings` prop and each stepper's
  /// callback closes over the value it was built with, so leaving the rebuild
  /// until after two awaits let a second click land on stale props: click
  /// Columns then Rows quickly and `copyWith(gridRows:)` was applied to the
  /// pre-Columns value, silently discarding the first change.
  Future<void> settingsChanged(Settings updated) async {
    _settings = updated.clamped();
    notifyListeners();
    await _settingsStore.save(_settings);
    await pushGrid();
  }

  Future<void> setLoginItem(bool enabled) async {
    _loginStatus = await wc.setLoginItem(enabled);
    notifyListeners();
  }

  /// A shape the user asked to keep, waiting for the picker to open on it.
  CustomRegion? _pendingRegion;
  CustomRegion? get pendingRegion => _pendingRegion;

  /// ⌘S on the grid. Native has already placed the window; this opens the
  /// picker on the shape so it can be named and bound.
  ///
  /// The id is generated here rather than in the sheet, so what waits is a
  /// complete region from the moment it exists — the picker then edits it like
  /// any other rather than carrying a half-built special case.
  Future<void> requestSaveRegion(Map<Object?, Object?> block) async {
    int? intOf(String k) => block[k] is int ? block[k] as int : null;
    final cols = intOf('cols');
    final rows = intOf('rows');
    final c0 = intOf('c0');
    final c1 = intOf('c1');
    final r0 = intOf('r0');
    final r1 = intOf('r1');
    // Dropped rather than thrown: this arrives from a channel, and a malformed
    // payload should cost one offer, not the app.
    if (cols == null || rows == null) return;
    if (c0 == null || c1 == null || r0 == null || r1 == null) return;

    final draft = CustomRegion(
      id: _freshRegionId(),
      name: suggestRegionName(
          cols: cols, rows: rows, c0: c0, c1: c1, r0: r0, r1: r1),
      cols: cols, rows: rows, c0: c0, c1: c1, r0: r0, r1: r1,
    );
    if (CustomRegion.tryFromJson(draft.toJson()) == null) return;

    _pendingRegion = draft;
    // Through openSettings, not straight to showConfigWindow: that is where the
    // fresh SMAppService read lives, and skipping it left General showing a
    // stale — or, since `unknown` became the initial value, an empty —
    // launch-at-login state for anyone who switched tabs afterwards.
    await openSettings(tab: SettingsTab.shortcuts);
  }

  /// The picker has opened on it. Cleared immediately, so a rebuild cannot
  /// reopen the sheet behind the one already on screen.
  void consumePendingRegion() {
    if (_pendingRegion == null) return;
    _pendingRegion = null;
    notifyListeners();
  }

  /// The next id this session will hand out. Only ever moves forward.
  int _regionSeq = 0;

  /// An id no current region uses **and none already handed out**.
  ///
  /// Not time-based: the coordinator has no clock under test. But "unique
  /// within the saved list" was not enough — a ⌘S region sits unsaved in its
  /// picker, invisible to [_regions], so a second handoff computed the very
  /// same id and saving the second **overwrote the first**. Two shapes the user
  /// drew, one row. The counter makes an id spent the moment it is issued, and
  /// the loop still skips anything already on disk.
  String _freshRegionId() {
    var n = _regionSeq;
    while (_regions.any((r) => r.id == 'r$n')) {
      n++;
    }
    _regionSeq = n + 1;
    return 'r$n';
  }

  /// Add or update a region and its combo, as one transaction.
  ///
  /// One write, because the two halves are stored together: a region saved
  /// without its binding, or the reverse, is exactly the orphan state
  /// [BindingsStore] exists to make impossible.
  Future<void> saveRegion(RegionDraft draft) async {
    final region = draft.region;
    final existing = _regions.indexWhere((r) => r.id == region.id);
    _regions = [
      if (existing < 0) ..._regions else ..._regions.sublist(0, existing),
      region,
      if (existing >= 0) ..._regions.sublist(existing + 1),
    ];

    final ref = Custom(region.id);
    final updated = Binding(ref, draft.keyCode, draft.modifiers);
    // withRebind both inserts the row and unbinds whoever held that combo. It
    // matches on command, so a brand-new region needs its row to exist first.
    final withRow = [
      ..._bindings,
      if (!_bindings.any((b) => b.command == ref)) Binding.unbound(ref),
    ];
    _bindings = withRebind(withRow, updated);

    await _bindingsStore.save(_bindings, _regions);
    await pushGrid();
    await applyBindings();
  }

  /// Remove a region and its binding together. A binding left behind would be
  /// a row with no shape to place, which the loader would drop on next launch
  /// anyway — but not before this session registered a hotkey for it.
  Future<void> deleteRegion(String id) async {
    _regions = [for (final r in _regions) if (r.id != id) r];
    _bindings = [for (final b in _bindings) if (b.command != Custom(id)) b];
    await _bindingsStore.save(_bindings, _regions);
    await pushGrid();
    await applyBindings();
  }

  /// Every shortcut back to its default, including the summon.
  Future<void> resetBindings() async {
    // Regions survive a reset. "Reset Shortcuts" restores the *combos* to their
    // defaults; deleting the user's own regions would be a different, much
    // larger promise than the button makes — and an unrecoverable one.
    _bindings = [
      ...kDefaultBindings,
      for (final r in _regions) Binding.unbound(Custom(r.id)),
    ];
    await _bindingsStore.save(_bindings, _regions);
    await applyBindings();
  }

  /// Make the bindings exactly [restored] — the way back from a change that
  /// touched more than one row.
  ///
  /// The pane snapshots its list before taking a combination from another
  /// command, or before a reset, and hands the snapshot back on Undo. One
  /// write and one atomic re-register, where replaying the change row by row
  /// would pass through states in which two commands briefly hold one chord.
  ///
  /// **Reconciled, not trusted.** A snapshot can go stale while the notice
  /// offering it is on screen: ⌘S can add a region, and the picker can delete
  /// one. Applied verbatim, a stale list would resurrect a binding for a region
  /// that no longer exists, or drop one for a region that arrived after the
  /// snapshot was taken. Work done *after* the snapshot is not the mistake the
  /// user is undoing, so it survives — except where it collides with something
  /// the snapshot restores, the undo being the more explicit of the two.
  ///
  /// The result can therefore never hold two commands on one chord, whatever
  /// the snapshot and the present disagree about.
  Future<void> restoreBindings(List<Binding> restored) async {
    final live = <CommandRef>[
      for (final c in ShortcutCommand.values) BuiltIn(c),
      for (final r in _regions) Custom(r.id),
    ];
    final out = [
      for (final b in restored)
        if (live.contains(b.command)) b,
    ];
    for (final ref in live) {
      if (out.any((b) => b.command == ref)) continue;
      final current = _bindings.firstWhere(
        (b) => b.command == ref,
        orElse: () => Binding.unbound(ref),
      );
      out.add(conflictFor(out, current) == null ? current : Binding.unbound(ref));
    }
    _bindings = out;
    await _bindingsStore.save(_bindings, _regions);
    await applyBindings();
  }

  Future<void> rebind(Binding updated) async {
    // withRebind unbinds whoever previously held this combo — duplicate Carbon
    // registrations of one chord shadow each other, so the loser is made
    // visibly unset rather than silently broken.
    _bindings = withRebind(_bindings, updated);
    await _timed('rebind: save', () => _bindingsStore.save(_bindings, _regions));
    await applyBindings();
  }

  /// Time a step, in anything but a Release build.
  ///
  /// Worth having on exactly these calls: this app runs with the UI and
  /// platform threads **merged**, so a slow native call in a channel handler
  /// blocks *Dart*, not just AppKit. "How long did the channel take" is
  /// therefore the same question as "how long was the UI frozen".
  Future<T> _timed<T>(String label, Future<T> Function() body) async {
    if (kReleaseMode) return body();
    final started = DateTime.now();
    final result = await body();
    debugPrint('[orthant] $label: '
        '${DateTime.now().difference(started).inMilliseconds} ms');
    return result;
  }

  /// Re-register and refresh the list, which shows both the current combos and
  /// whichever ones the OS just refused.
  Future<void> applyBindings() async {
    _unavailable =
        await _timed('applyBindings', () => hotkeys.apply(_bindings));
    notifyListeners();
  }

  /// Suspend the global hotkeys while a combo is being recorded — without this
  /// the combo being recorded also *fires*, so a window jumps mid-capture.
  Future<void> suspendHotkeys() =>
      _timed('suspendHotkeys', hotkeys.unregisterAll);

  @override
  void dispose() {
    _poll?.cancel();
    permissions.removeListener(_onPermissionNotified);
    super.dispose();
  }
}
