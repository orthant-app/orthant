import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/app/coordinator.dart';
import 'package:orthant/core/geometry.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/permission/permission_controller.dart';
import 'package:orthant/settings/settings.dart';
import 'package:orthant/settings/settings_store.dart';
import 'package:orthant/settings/settings_window.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/command_ref.dart';
import 'package:orthant/shortcuts/bindings_store.dart';
import 'package:orthant/shortcuts/hotkey_service.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orthant/shortcuts/custom_region.dart';

/// Records what the app asked the platform to do, and lets a test decide what
/// the platform says back.
class _FakeWc implements WindowController {
  bool permission = false;
  bool placementSucceeds = true;
  final List<String> calls = [];
  ({int cols, int rows, double gap, bool saveHint})? grid;
  LoginItemStatus login = LoginItemStatus.disabled;
  AppVersion version = const AppVersion('1.0.0', '2');

  @override
  Future<bool> checkPermission() async => permission;
  @override
  Future<void> requestPermission() async => calls.add('requestPermission');
  @override
  Future<void> openAccessibilitySettings() async =>
      calls.add('openAccessibilitySettings');
  @override
  Future<void> showConfigWindow() async => calls.add('show');
  /// Runs *inside* `hideConfigWindow`, so a test can observe app state at
  /// exactly that moment.
  ///
  /// Ordering here cannot be asserted after the fact: whichever way round the
  /// hide and the screen change happen, both end with the window hidden and the
  /// screen `none`. The difference is only visible while the call is in flight.
  void Function()? onHide;

  @override
  Future<void> hideConfigWindow() async {
    calls.add('hide');
    onHide?.call();
  }
  @override
  Future<CapturedWindow?> captureFrontmost() async => placementSucceeds
      ? const CapturedWindow('TextEdit', WinRect(0, 0, 100, 100))
      : null;
  @override
  Future<WinRect> activeScreenFrame() async => const WinRect(0, 0, 1440, 900);
  @override
  Future<List<WinRect>> screenFrames() async => const [
    WinRect(0, 0, 1440, 900),
  ];
  /// The rect the last placement asked for — null if none landed.
  WinRect? placedRect;
  @override
  Future<bool> applyFrame(WinRect target) async {
    if (placementSucceeds) placedRect = target;
    return placementSucceeds;
  }
  @override
  Future<void> showOverlay() async => calls.add('showOverlay');
  @override
  Future<void> hideOverlay() async => calls.add('hideOverlay');
  @override
  Future<void> setOverlayGrid({
    required int cols,
    required int rows,
    required double gap,
    required bool saveHint,
  }) async {
    grid = (cols: cols, rows: rows, gap: gap, saveHint: saveHint);
    calls.add('setOverlayGrid');
  }

  @override
  Future<AppVersion> appVersion() async => version;

  @override
  Future<LoginItemStatus> loginItemStatus() async => login;
  @override
  Future<LoginItemStatus> setLoginItem(bool enabled) async =>
      login = enabled ? LoginItemStatus.enabled : LoginItemStatus.disabled;
  @override
  Future<void> openLoginItemsSettings() async =>
      calls.add('openLoginItemsSettings');
  @override
  Future<void> checkForUpdates() async => calls.add('checkForUpdates');
}

class _FakeRegistrar implements HotkeyRegistrar {
  /// Combos the "OS" refuses.
  Set<CommandRef> refuse = const {};
  final List<List<Binding>> applied = [];
  int unregisterAllCount = 0;

  @override
  Future<Set<CommandRef>> apply(List<Binding> bindings) async {
    applied.add(List.of(bindings));
    return refuse;
  }

  @override
  Future<void> unregisterAll() async => unregisterAllCount++;
}

void main() {
  // For SharedPreferences' mock channel; no widget is built here.
  TestWidgetsFlutterBinding.ensureInitialized();

  final built = <OrthantCoordinator>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    built.clear();
  });
  // Disposing releases the permission listener and the poll timer, so a case
  // cannot leak either into the next one.
  tearDown(() {
    for (final c in built) {
      c.dispose();
    }
  });

  ({OrthantCoordinator app, _FakeWc wc, _FakeRegistrar keys}) build({
    bool granted = false,
  }) {
    final wc = _FakeWc()..permission = granted;
    final keys = _FakeRegistrar();
    final app = OrthantCoordinator(
      wc: wc,
      permissions: PermissionController(wc),
      hotkeys: keys,
      // Long enough that the poll never fires during a test; the transitions
      // are driven by calling refresh directly.
      pollPeriod: const Duration(hours: 1),
    );
    built.add(app);
    return (app: app, wc: wc, keys: keys);
  }

  group('launch', () {
    test('ungranted: onboarding, a visible window, and no prompt', () async {
      // The prompt at launch put macOS's own alert on top of this window — two
      // surfaces asking one question. Locked in spec §8 after four reversals, so
      // this test exists to make the fifth fail loudly.
      final t = build();
      await t.app.start();
      expect(t.app.screen, AppScreen.onboarding);
      expect(t.wc.calls, contains('show'));
      expect(t.wc.calls, isNot(contains('requestPermission')));
    });

    test('ungranted: preferences still load', () async {
      // The blank grey Shortcuts pane. Bindings were loaded only in the granted
      // branch, so the list was empty for the whole ungranted session — which is
      // exactly when someone opens settings to find out what is wrong.
      SharedPreferences.setMockInitialValues({});
      await BindingsStore().save(kDefaultBindings, const []);
      await SettingsStore().save(const Settings(gridCols: 4, gridRows: 3));

      final t = build();
      await t.app.start();
      expect(t.app.bindings, isNotEmpty);
      expect(t.app.settings.gridCols, 4);
      expect(t.keys.applied, isEmpty, reason: 'but nothing is registered');
    });

    test('the tray offers About, and nothing in it is greyed out', () async {
      // Granted deliberately: `Open Grid` is greyed while ungranted *on
      // purpose* — it cannot work without the permission, and the row above it
      // says so. The property below is about rows greyed for no reason, so it
      // has to be asked in the state where there is no reason.
      final t = build(granted: true);
      t.wc.version = const AppVersion('1.0.0', '2');
      await t.app.start();

      final keys = t.app.trayMenu.map((e) => e.key).toList();
      final about = t.app.trayMenu.firstWhere((e) => e.key == 'about');

      expect(about.label, 'About Orthant');
      // The defect this row replaced: the version shipped as a *disabled*
      // label, which reads as a command that is broken, because macOS greys
      // what you cannot do. Asserting the whole menu rather than this one row —
      // the property is "no dead-looking rows", and a future addition should
      // have to argue with this test.
      expect(
        t.app.trayMenu.where((e) => !e.isSeparator && e.disabled),
        isEmpty,
        reason: 'a fully working app should have nothing greyed out',
      );
      expect(
        keys.indexOf('updates'),
        keys.indexOf('about') + 1,
        reason: 'About sits directly above Check for Updates',
      );
    });

    test('About is offered even when the platform cannot say what version it '
        'is', () async {
      final t = build();
      t.wc.version = const AppVersion('', '');
      await t.app.start();

      // The old version row was conditional, because "Orthant  ()" is worse
      // than nothing. This one must not be: the tray is the only front door,
      // and About is where Check for Updates now lives beside. Losing it
      // because a value is missing would hide the pane, not just the version.
      expect(t.app.trayMenu.map((e) => e.key), contains('about'));
    });

    test(
      'ungranted: nothing is registered, so nothing is advertised',
      () async {
        final t = build();
        await t.app.start();
        final overlay = t.app.trayMenu.firstWhere((e) => e.key == 'overlay');
        expect(
          overlay.disabled,
          isTrue,
          reason: 'it can only beep and pop a window nobody asked for',
        );
        expect(
          overlay.label,
          'Open Grid',
          reason: 'no combo: the chord is not registered and cannot fire',
        );
        expect(t.app.trayMenu.map((e) => e.key), contains('permission'));
      },
    );

    test(
      'granted: no window, hotkeys registered, onboarding retired',
      () async {
        final t = build(granted: true);
        await t.app.start();
        expect(t.app.screen, AppScreen.none);
        expect(t.wc.calls, contains('hide'));
        expect(t.wc.calls, isNot(contains('show')));
        expect(t.keys.applied, hasLength(1));
        expect(
          await SettingsStore().hasOnboarded(),
          isTrue,
          reason: 'there is no moment to show the ready screen in',
        );
      },
    );

    test('granted across a relaunch: the ready screen still happens', () async {
      // Start ungranted, close the window, quit, grant while Orthant is not
      // running, relaunch. The in-process version of this is covered below; the
      // launch path had its own copy of the same defect, and marked onboarding
      // complete for having found the grant in place. The ready screen is the
      // only place the grid is ever mentioned.
      SharedPreferences.setMockInitialValues({});
      final first = build();
      await first.app.start();
      expect(first.app.screen, AppScreen.onboarding);

      final second = build(granted: true);
      await second.app.start();
      expect(second.app.screen, AppScreen.ready);
      expect(second.wc.calls, contains('show'));
    });

    test('an upgrade from before the flag existed still shows Ready', () async {
      // Preferences written by an older build cannot hold `onboardingStarted`.
      // The prompt flag stands in for it: only the onboarding button sets it, so
      // having it proves the window was shown. Without this an existing install
      // that saw onboarding, quit, granted and *then* upgraded would take the
      // "never shown" branch and lose the ready screen for good.
      SharedPreferences.setMockInitialValues({
        'flutter.orthant.accessibilityPrompted.v1': true,
      });
      final t = build(granted: true);
      await t.app.start();
      expect(t.app.screen, AppScreen.ready);
      expect(t.wc.calls, contains('show'));
    });

    test('the window is taken down before its surface goes empty', () async {
      // Onboarding already finished, so a later grant takes the window *down*
      // rather than showing Ready. That is the branch a returning user hits
      // after a re-grant, a re-sign, or a `tccutil reset`.
      SharedPreferences.setMockInitialValues({
        'flutter.orthant.onboarded.v1': true,
      });
      final t = build();
      await t.app.start();
      expect(t.app.screen, AppScreen.onboarding);

      AppScreen? screenWhenHidden;
      t.wc.onHide = () => screenWhenHidden = t.app.screen;

      t.wc.permission = true;
      await t.app.permissions.refresh();
      await t.app.permissionSettled;

      // `AppScreen.none` renders `SizedBox.shrink()`, which paints nothing *and
      // reports no height* — so a still-visible window neither resizes nor
      // draws: it sits at whatever size it last had and goes solid black.
      // Assigning it before the hide leaves exactly that on screen for the
      // length of a channel round trip. Reported from a real build as "the
      // onboarding dialog is a black screen", at the Shortcuts pane's height
      // because that was the last size the window had been given.
      expect(screenWhenHidden, AppScreen.onboarding,
          reason: 'the surface must still have content when the window hides');
      expect(t.app.screen, AppScreen.none);
      expect(t.wc.calls, contains('hide'));
    });

    test('granted before Orthant ever ran: still no window', () async {
      // The other half of the pair, and the reason the flag above is "was
      // onboarding shown" rather than "has it finished". A menu-bar agent that
      // opens a window on a launch nobody asked anything of is the behaviour M2
      // set out to avoid.
      SharedPreferences.setMockInitialValues({});
      final t = build(granted: true);
      await t.app.start();
      expect(t.app.screen, AppScreen.none);
      expect(t.wc.calls, isNot(contains('show')));
      expect(await SettingsStore().hasOnboarded(), isTrue);
    });

    test('granted: the grid reaches native before any summon can', () async {
      await SettingsStore().save(
        const Settings(gridCols: 7, gridRows: 2, gaps: true, gapSize: 12),
      );
      final t = build(granted: true);
      await t.app.start();
      expect(t.wc.grid, (cols: 7, rows: 2, gap: 12.0, saveHint: true));
    });

    test('granted: the tray advertises the live combo', () async {
      final t = build(granted: true);
      await t.app.start();
      final overlay = t.app.trayMenu.firstWhere((e) => e.key == 'overlay');
      expect(overlay.disabled, isFalse);
      expect(overlay.label, contains('⌃⌥O'));
      expect(t.app.trayMenu.map((e) => e.key), isNot(contains('permission')));
    });

    test('a refused summon chord is not advertised either', () async {
      final t = build(granted: true);
      t.keys.refuse = {const BuiltIn(ShortcutCommand.showGrid)};
      await t.app.start();
      expect(
        t.app.trayMenu.firstWhere((e) => e.key == 'overlay').label,
        'Open Grid',
      );
    });

    test('the tray offers a check for updates, and it is never disabled', () {
      final t = build(granted: false);
      final entry = t.app.trayMenu.firstWhere((e) => e.key == 'updates');

      expect(entry.label, 'Check for Updates…');
      expect(entry.disabled, isFalse,
          reason: 'updating has nothing to do with the Accessibility grant — '
              'greying it would strand an ungranted user on a broken version');
    });
  });

  group('the grant transition', () {
    test('shows the ready screen', () async {
      final t = build();
      await t.app.start();
      t.wc.permission = true;
      await t.app.permissions.refresh();
      await t.app.permissionSettled;
      expect(t.app.screen, AppScreen.ready);
    });

    test('shows it even if onboarding was closed first', () async {
      // The defect: the handler asked "is the onboarding screen visible?" when
      // the question is "has this user seen the ready screen yet?". Closing that
      // window while the work happens in System Settings is an ordinary thing to
      // do — and it meant the only screen that ever mentions the grid never
      // appeared, while the next launch marked onboarding complete anyway.
      final t = build();
      await t.app.start();
      await t.app.onConfigWindowClosed();
      expect(t.app.screen, AppScreen.none);

      t.wc.permission = true;
      await t.app.permissions.refresh();
      await t.app.permissionSettled;
      expect(t.app.screen, AppScreen.ready);
      expect(
        t.wc.calls.where((c) => c == 'show').length,
        2,
        reason: 'the window is put back up to show it',
      );
    });

    test('shows it once, ever', () async {
      final t = build();
      await t.app.start();
      t.wc.permission = true;
      await t.app.permissions.refresh();
      await t.app.permissionSettled;
      await t.app.finishOnboarding();
      expect(t.app.screen, AppScreen.none);

      // A later transition must not resurrect it.
      t.wc.permission = false;
      await t.app.permissions.refresh();
      await t.app.permissionSettled;
      t.wc.permission = true;
      await t.app.permissions.refresh();
      await t.app.permissionSettled;
      expect(t.app.screen, isNot(AppScreen.ready));
    });

    test('registers the hotkeys it could not register before', () async {
      final t = build();
      await t.app.start();
      expect(t.keys.applied, isEmpty);
      t.wc.permission = true;
      await t.app.permissions.refresh();
      await t.app.permissionSettled;
      expect(t.keys.applied, isNotEmpty);
    });
  });

  group('losing the grant', () {
    test('a failed placement surfaces it and recovers', () async {
      // macOS never tells us the grant was revoked, so a failed placement is the
      // one moment it can be noticed — and the moment the user cares.
      final t = build(granted: true);
      await t.app.start();

      t.wc
        ..placementSucceeds = false
        ..permission = false;
      await t.app.runCommand(const BuiltIn(ShortcutCommand.leftHalf));

      expect(t.app.screen, AppScreen.onboarding);
      expect(
        t.keys.unregisterAllCount,
        1,
        reason: 'dead shortcuts must not stay registered',
      );
    });

    test(
      'a failure that is not a permission loss leaves the app alone',
      () async {
        // A native-fullscreen window cannot be placed and beeps natively. Treating
        // that as a revocation would throw onboarding in the user's face.
        final t = build(granted: true);
        await t.app.start();
        t.wc.placementSucceeds = false; // permission stays granted
        await t.app.runCommand(const BuiltIn(ShortcutCommand.leftHalf));
        expect(t.app.screen, AppScreen.none);
        expect(t.keys.unregisterAllCount, 0);
      },
    );

    test('the grid reports through the same path', () async {
      // The grid is native end to end, so this channel callback is its only
      // route into the recovery the direct shortcuts get by returning to Dart.
      final t = build(granted: true);
      await t.app.start();
      t.wc.permission = false;
      await t.app.recoverIfPermissionLost();
      expect(t.app.screen, AppScreen.onboarding);
    });
  });

  group('the Accessibility button', () {
    test('prompts on the first press and deep-links after', () async {
      // Both at once is what it used to do, and it asked the same question
      // twice on one click. The prompt is still needed: it is the only way macOS
      // lists the app in the pane at all.
      final t = build();
      await t.app.start();

      await t.app.openAccessibility();
      expect(t.wc.calls, contains('requestPermission'));
      expect(t.wc.calls, isNot(contains('openAccessibilitySettings')));

      t.wc.calls.clear();
      await t.app.openAccessibility();
      expect(t.wc.calls, ['openAccessibilitySettings']);
      expect(t.wc.calls, isNot(contains('requestPermission')));
    });

    test('the prompt is remembered across a relaunch', () async {
      // Otherwise every launch would prompt again, which is the behaviour this
      // replaced.
      final first = build();
      await first.app.start();
      await first.app.openAccessibility();

      final second = build();
      await second.app.start();
      await second.app.openAccessibility();
      expect(second.wc.calls, contains('openAccessibilitySettings'));
      expect(second.wc.calls, isNot(contains('requestPermission')));
    });
  });

  group('settings and bindings', () {
    test('a settings change is visible before it is persisted', () async {
      // The pane's steppers close over the value they were built with, so a
      // second click during the save composed onto stale props and silently
      // discarded the first change.
      final t = build(granted: true);
      await t.app.start();
      var notifiedWith = const Settings();
      t.app.addListener(() => notifiedWith = t.app.settings);

      final pending = t.app.settingsChanged(const Settings(gridCols: 9));
      expect(notifiedWith.gridCols, 9, reason: 'before the await completes');
      await pending;
      expect((await SettingsStore().load()).gridCols, 9);
    });

    test('an out-of-range setting is clamped, not stored', () async {
      final t = build(granted: true);
      await t.app.start();
      await t.app.settingsChanged(const Settings(gridCols: 99, gapSize: 999));
      expect(t.app.settings.gridCols, kMaxGridAxis);
      expect(t.app.settings.gapSize, kMaxGapSize);
    });

    test('a settings change reaches the overlay', () async {
      // Gaps once applied to the grid and silently not to the ten shortcuts.
      final t = build(granted: true);
      await t.app.start();
      await t.app.settingsChanged(const Settings(gaps: true, gapSize: 20));
      expect(t.wc.grid?.gap, 20.0);
    });

    test('rebinding unbinds whoever held the combo, and persists', () async {
      final t = build(granted: true);
      await t.app.start();
      await t.app.rebind(
        const Binding(BuiltIn(ShortcutCommand.leftHalf), 124, kControlOption),
      );

      final right = t.app.bindings.firstWhere(
        (b) => b.command == const BuiltIn(ShortcutCommand.rightHalf),
      );
      expect(right.isBound, isFalse, reason: 'it lost ⌃⌥→ to leftHalf');
      expect((await BindingsStore().load()).bindings.length,
          kDefaultBindings.length);
    });

    test('reset restores every default, including the summon', () async {
      final t = build(granted: true);
      await t.app.start();
      await t.app.rebind(Binding.unbound(BuiltIn(ShortcutCommand.showGrid)));
      expect(t.app.bindings.first.isBound, isFalse);

      await t.app.resetBindings();
      expect(t.app.bindings, kDefaultBindings);
    });

    test('closing the window revives hotkeys a recording suspended', () async {
      // Recording unregisters everything so the combo being recorded does not
      // also fire; a close mid-recording never delivers onCaptureEnd, so without
      // this every shortcut stays dead until the next rebind or relaunch.
      final t = build(granted: true);
      await t.app.start();
      await t.app.suspendHotkeys();
      final before = t.keys.applied.length;

      await t.app.onConfigWindowClosed();
      expect(t.keys.applied.length, before + 1);
      expect(t.app.screen, AppScreen.none);
    });

    test('closing while ungranted does not register dead shortcuts', () async {
      final t = build();
      await t.app.start();
      await t.app.onConfigWindowClosed();
      expect(t.keys.applied, isEmpty);
    });
  });

  group('the settings window', () {
    test('opens on the tab it was asked for', () async {
      final t = build(granted: true);
      await t.app.start();
      await t.app.openSettings();
      expect(t.app.settingsTab, SettingsTab.general);

      await t.app.openSettings(tab: SettingsTab.shortcuts);
      expect(t.app.settingsTab, SettingsTab.shortcuts);
    });

    test(
      'the ready screen lands on Shortcuts, and retires onboarding',
      () async {
        // "Change these shortcuts…" named a list and then opened General, one
        // click short of it.
        final t = build();
        await t.app.start();
        await t.app.openShortcutsFromReady();
        expect(t.app.screen, AppScreen.settings);
        expect(t.app.settingsTab, SettingsTab.shortcuts);
        expect(await SettingsStore().hasOnboarded(), isTrue);
      },
    );

    test('the screen is set before the window is shown', () async {
      // Fetching the login status first meant the window could be on screen with
      // the screen state still at its previous value for a whole channel round
      // trip, and `none` renders SizedBox.shrink(): an empty panel.
      final t = build(granted: true);
      await t.app.start();
      final order = <String>[];
      t.app.addListener(() {
        if (t.app.screen == AppScreen.settings) order.add('screen');
      });
      t.wc.calls.clear();
      await t.app.openSettings();
      expect(order.first, 'screen');
      expect(t.wc.calls.first, 'show');
    });

    test('the login status is read fresh every open', () async {
      // Never cached: the user can change it in System Settings without telling
      // us, and `.notFound` merely means "not registered yet".
      final t = build(granted: true);
      await t.app.start();
      t.wc.login = LoginItemStatus.requiresApproval;
      await t.app.openSettings();
      expect(t.app.loginStatus, LoginItemStatus.requiresApproval);
    });
  });

  group('custom regions', () {
    const region = CustomRegion(
      id: 'r1',
      name: 'Left ⅔',
      cols: 3,
      rows: 1,
      c0: 0,
      c1: 1,
      r0: 0,
      r1: 0,
    );

    test('a custom-region hotkey places that region', () async {
      // Guards the wiring, which is where three shipped defects lived: the
      // region list has to reach applyRegion, not just exist in the store.
      SharedPreferences.setMockInitialValues({});
      await BindingsStore().save([
        ...kDefaultBindings,
        const Binding(Custom('r1'), 123, kControlOption | kShiftKey),
      ], const [region]);

      final t = build(granted: true);
      await t.app.start();

      await t.app.runCommand(const Custom('r1'));

      expect(t.wc.placedRect, const WinRect(0, 0, 960, 900));
    });

    test('regions load alongside the bindings', () async {
      SharedPreferences.setMockInitialValues({});
      await BindingsStore().save(kDefaultBindings, const [region]);

      final t = build(granted: true);
      await t.app.start();

      expect(t.app.regions, const [region]);
      expect(t.app.bindings.last.command, const Custom('r1'));
    });

    test('resetBindings keeps the regions and only unbinds them', () async {
      // "Reset Shortcuts" promises to reset combos. Deleting regions the user
      // drew would be a larger, unrecoverable promise than the button makes.
      SharedPreferences.setMockInitialValues({});
      await BindingsStore().save([
        ...kDefaultBindings,
        const Binding(Custom('r1'), 123, kControlOption | kShiftKey),
      ], const [region]);

      final t = build(granted: true);
      await t.app.start();
      await t.app.resetBindings();

      expect(t.app.regions, const [region]);
      final row =
          t.app.bindings.firstWhere((b) => b.command == const Custom('r1'));
      expect(row.isBound, isFalse);
      expect((await BindingsStore().load()).regions, const [region]);
    });

    test('what a reset writes is exactly what defaultBindingFor predicts',
        () async {
      // Two places need to know this. The reset performs it; the pane's Undo
      // has to know *which rows a reset changes* so it can leave the others
      // alone — a row already at its default is not part of the operation and
      // must survive an Undo of it. `defaultBindingFor` states the rule once,
      // and this is what keeps the two from drifting apart silently: change
      // one and the pane's Undo starts claiming the wrong rows, with nothing
      // else to notice.
      SharedPreferences.setMockInitialValues({});
      await BindingsStore().save([
        ...kDefaultBindings,
        const Binding(Custom('r1'), 123, kControlOption | kShiftKey),
      ], const [region]);

      final t = build(granted: true);
      await t.app.start();
      await t.app.resetBindings();

      for (final b in t.app.bindings) {
        expect(b, defaultBindingFor(b.command),
            reason: '${b.command.jsonName} is not what a reset promises');
      }
    });
  });

  group('restoreBindings', () {
    // The way back from a change that touched more than one row: taking a
    // combination off another command, and Reset. The pane snapshots its list
    // and hands the snapshot back — which can go stale while the notice
    // offering it is still on screen, since ⌘S can add a region and the picker
    // can delete one.
    const region = CustomRegion(
      id: 'r1',
      name: 'Left ⅔',
      cols: 3,
      rows: 1,
      c0: 0,
      c1: 1,
      r0: 0,
      r1: 0,
    );

    test('puts an exact snapshot back, and persists it', () async {
      SharedPreferences.setMockInitialValues({});
      final t = build(granted: true);
      await t.app.start();
      final before = [...t.app.bindings];

      await t.app.resetBindings();
      await t.app.rebind(
          const Binding(BuiltIn(ShortcutCommand.showGrid), 6, kControlOption));
      expect(
          t.app.bindings
              .firstWhere(
                  (b) => b.command == const BuiltIn(ShortcutCommand.showGrid))
              .keyCode,
          6);

      await t.app.restoreBindings(before);

      expect(t.app.bindings, before);
      expect((await BindingsStore().load()).bindings, before,
          reason: 'an undo that survives only until relaunch is not an undo');
    });

    test('drops a binding whose region has gone since the snapshot', () async {
      SharedPreferences.setMockInitialValues({});
      await BindingsStore().save([
        ...kDefaultBindings,
        const Binding(Custom('r1'), 6, kControlOption),
      ], const [region]);
      final t = build(granted: true);
      await t.app.start();
      final before = [...t.app.bindings];

      await t.app.deleteRegion('r1');
      await t.app.restoreBindings(before);

      expect(t.app.bindings.any((b) => b.command == const Custom('r1')), isFalse,
          reason: 'a hotkey for a region with no shape to place');
    });

    test('keeps a region added since the snapshot', () async {
      // Work done *after* the snapshot is not the mistake being undone.
      SharedPreferences.setMockInitialValues({});
      final t = build(granted: true);
      await t.app.start();
      final before = [...t.app.bindings];

      await t.app
          .saveRegion((region: region, keyCode: 6, modifiers: kControlOption));
      await t.app.restoreBindings(before);

      final row =
          t.app.bindings.firstWhere((b) => b.command == const Custom('r1'));
      expect(row.keyCode, 6);
    });

    test('unbinds a since-added region whose combo the snapshot restores',
        () async {
      // The one case where post-snapshot work cannot survive: two commands
      // cannot share a chord, and between the undo and a change made while its
      // notice was on screen, the undo is the more explicit.
      SharedPreferences.setMockInitialValues({});
      final t = build(granted: true);
      await t.app.start();
      final before = [...t.app.bindings]; // Left half holds ⌃⌥←

      // Exactly what the picker's "Use it here" does.
      await t.app.saveRegion(
          (region: region, keyCode: 123, modifiers: kControlOption));
      expect(
          t.app.bindings
              .firstWhere(
                  (b) => b.command == const BuiltIn(ShortcutCommand.leftHalf))
              .isBound,
          isFalse);

      await t.app.restoreBindings(before);

      expect(
          t.app.bindings
              .firstWhere(
                  (b) => b.command == const BuiltIn(ShortcutCommand.leftHalf))
              .keyCode,
          123);
      expect(
          t.app.bindings
              .firstWhere((b) => b.command == const Custom('r1'))
              .isBound,
          isFalse,
          reason: 'two commands would hold ⌃⌥←, which shadow each other');
    });

    test('re-registers the restored set', () async {
      SharedPreferences.setMockInitialValues({});
      final t = build(granted: true);
      await t.app.start();
      final before = [...t.app.bindings];
      // A *rebind*, not a reset: with no regions defined, `resetBindings` puts
      // back the very `kDefaultBindings` instances the snapshot holds, so the
      // stale set and the restored one compare equal and the assertion below
      // cannot tell them apart. It has to be a state the snapshot differs from.
      await t.app.rebind(
          const Binding(BuiltIn(ShortcutCommand.center), 6, kControlOption));
      final applies = t.keys.applied.length;

      await t.app.restoreBindings(before);

      expect(t.keys.applied.length, applies + 1);
      // The *argument*, not just the call. A count cannot tell the difference
      // between registering the restored set and registering the stale one it
      // replaced — and getting that wrong leaves every restored shortcut dead
      // until something else happens to apply, which is exactly the failure
      // this test is named for.
      final center = t.keys.applied.last
          .firstWhere((b) => b.command == const BuiltIn(ShortcutCommand.center));
      expect(center.keyCode, 8,
          reason: 'restored bindings that were never registered do nothing');
    });
  });

  group('region editing', () {
    const region = CustomRegion(
      id: 'r1',
      name: 'Left ⅔',
      cols: 3,
      rows: 1,
      c0: 0,
      c1: 1,
      r0: 0,
      r1: 0,
    );

    test('saving a new region adds its row and registers its combo', () async {
      SharedPreferences.setMockInitialValues({});
      final t = build(granted: true);
      await t.app.start();

      await t.app.saveRegion(
          (region: region, keyCode: 123, modifiers: kControlOption | kShiftKey));

      expect(t.app.regions, const [region]);
      final row =
          t.app.bindings.firstWhere((b) => b.command == const Custom('r1'));
      expect(row.keyCode, 123);
      expect(t.keys.applied.last.map((b) => b.command),
          contains(const Custom('r1')));
      expect((await BindingsStore().load()).regions, const [region]);
    });

    test('saving an edit replaces the region in place, keeping its position',
        () async {
      SharedPreferences.setMockInitialValues({});
      final t = build(granted: true);
      await t.app.start();
      await t.app.saveRegion(
          (region: region, keyCode: 123, modifiers: kControlOption | kShiftKey));
      await t.app.saveRegion((
        region: region.copyWithId('r2'),
        keyCode: 124,
        modifiers: kControlOption | kShiftKey
      ));

      await t.app.saveRegion((
        region: region.copyWith(name: 'Reading pane'),
        keyCode: 123,
        modifiers: kControlOption | kShiftKey
      ));

      expect(t.app.regions.map((r) => r.id), ['r1', 'r2']);
      expect(t.app.regions.first.name, 'Reading pane');
      expect(t.app.bindings.where((b) => b.command == const Custom('r1')).length,
          1, reason: 'an edit must not duplicate the row');
    });

    test('a region taking a built-in combo unbinds the built-in', () async {
      SharedPreferences.setMockInitialValues({});
      final t = build(granted: true);
      await t.app.start();

      // ⌃⌥← is leftHalf by default.
      await t.app.saveRegion(
          (region: region, keyCode: 123, modifiers: kControlOption));

      final left = t.app.bindings.firstWhere(
          (b) => b.command == const BuiltIn(ShortcutCommand.leftHalf));
      expect(left.isBound, isFalse);
    });

    test('deleting drops the region and its binding together', () async {
      SharedPreferences.setMockInitialValues({});
      final t = build(granted: true);
      await t.app.start();
      await t.app.saveRegion(
          (region: region, keyCode: 123, modifiers: kControlOption | kShiftKey));

      await t.app.deleteRegion('r1');

      expect(t.app.regions, isEmpty);
      expect(t.app.bindings.any((b) => b.command == const Custom('r1')), isFalse);
      expect(t.keys.applied.last.map((b) => b.command),
          isNot(contains(const Custom('r1'))));
      final stored = await BindingsStore().load();
      expect(stored.regions, isEmpty);
      expect(stored.bindings.any((b) => b.command is Custom), isFalse);
    });
  });

  group('the save hint', () {
    const region = CustomRegion(
      id: 'r1',
      name: 'Left ⅔',
      cols: 3,
      rows: 1,
      c0: 0,
      c1: 1,
      r0: 0,
      r1: 0,
    );

    test('is on while the user has no regions of their own', () async {
      SharedPreferences.setMockInitialValues({});
      final t = build(granted: true);
      await t.app.start();
      expect(t.wc.grid?.saveHint, isTrue);
    });

    test('goes off once a region exists', () async {
      SharedPreferences.setMockInitialValues({});
      final t = build(granted: true);
      await t.app.start();
      await t.app.saveRegion((
        region: region,
        keyCode: kUnboundKey,
        modifiers: 0,
      ));
      expect(t.wc.grid?.saveHint, isFalse);
    });

    test('comes back if the last region is deleted', () async {
      // Correct rather than an edge case: someone with no regions has, again,
      // never made one.
      SharedPreferences.setMockInitialValues({});
      final t = build(granted: true);
      await t.app.start();
      await t.app.saveRegion((
        region: region,
        keyCode: kUnboundKey,
        modifiers: 0,
      ));
      await t.app.deleteRegion('r1');
      expect(t.wc.grid?.saveHint, isTrue);
    });
  });

  group('saving a shape from the grid', () {
    Map<Object?, Object?> block({
      int cols = 6, int rows = 6,
      int c0 = 0, int c1 = 3, int r0 = 0, int r1 = 5,
    }) => {
      'cols': cols, 'rows': rows,
      'c0': c0, 'c1': c1, 'r0': r0, 'r1': r1,
    };

    test('opens Shortcuts with the drawn shape waiting', () async {
      SharedPreferences.setMockInitialValues({});
      final t = build(granted: true);
      await t.app.start();

      await t.app.requestSaveRegion(block());

      expect(t.app.screen, AppScreen.settings);
      expect(t.app.settingsTab, SettingsTab.shortcuts);
      expect(t.app.pendingRegion?.c1, 3);
      expect(t.app.pendingRegion?.name, 'Left ⅔',
          reason: 'named from the shape, exactly as the picker would');
      expect(t.wc.calls, contains('show'));
    });

    test('is consumed once, so a rebuild cannot reopen it', () async {
      SharedPreferences.setMockInitialValues({});
      final t = build(granted: true);
      await t.app.start();
      await t.app.requestSaveRegion(block());

      t.app.consumePendingRegion();
      expect(t.app.pendingRegion, isNull);
    });

    test('the id does not collide with a region already held', () async {
      SharedPreferences.setMockInitialValues({});
      final t = build(granted: true);
      await t.app.start();
      await t.app.saveRegion((
        region: const CustomRegion(
          id: 'r0', name: 'Kept', cols: 2, rows: 2,
          c0: 0, c1: 0, r0: 0, r1: 0),
        keyCode: kUnboundKey,
        modifiers: 0,
      ));

      await t.app.requestSaveRegion(block());
      expect(t.app.pendingRegion!.id, isNot('r0'));
    });

    test('two unsaved handoffs keep distinct ids through saving', () async {
      // The id used to be derived from the *saved* list alone. A ⌘S region
      // sits unsaved in its picker, invisible to that list, so a second handoff
      // computed the very same id — and saving the second overwrote the first.
      // Two shapes the user drew, one row.
      SharedPreferences.setMockInitialValues({});
      final t = build(granted: true);
      await t.app.start();

      await t.app.requestSaveRegion(block());
      final first = t.app.pendingRegion!;
      t.app.consumePendingRegion();

      await t.app.requestSaveRegion(block(c1: 1));
      final second = t.app.pendingRegion!;
      t.app.consumePendingRegion();

      expect(first.id, isNot(second.id));

      // And the ids hold up through the save that used to collapse them.
      await t.app.saveRegion(
          (region: first, keyCode: kUnboundKey, modifiers: 0));
      await t.app.saveRegion(
          (region: second, keyCode: kUnboundKey, modifiers: 0));

      expect(t.app.regions.length, 2, reason: 'the second replaced the first');
      expect(t.app.regions.map((r) => r.id).toSet().length, 2);
    });

    test('a malformed payload costs the offer, not the app', () async {
      // It arrives from a channel, so it is a file we did not write.
      SharedPreferences.setMockInitialValues({});
      final t = build(granted: true);
      await t.app.start();

      await t.app.requestSaveRegion(const {'cols': 6});
      await t.app.requestSaveRegion(const {
        'cols': 'six', 'rows': 6, 'c0': 0, 'c1': 1, 'r0': 0, 'r1': 1,
      });
      // c1 == cols: a block outside its own grid, which the record rejects.
      await t.app.requestSaveRegion(block(cols: 3, c1: 3));

      expect(t.app.pendingRegion, isNull);
      expect(t.app.screen, isNot(AppScreen.settings));
    });
  });
}
