import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'app/coordinator.dart';
import 'core/window_controller_factory.dart';
import 'overlay/overlay_main.dart';
import 'permission/onboarding_screen.dart';
import 'permission/permission_controller.dart';
import 'permission/ready_screen.dart';
import 'settings/mac_theme.dart';
import 'settings/settings_window.dart';
import 'shortcuts/hotkey_service.dart';

/// Entrypoint for the *second* Flutter engine, the one hosted by OverlayPanel.
///
/// It has to be declared in this library, not next to the overlay's widgets:
/// macOS's `FlutterEngine.run(withEntrypoint:)` resolves the name against the
/// library containing `main()` and — unlike iOS — offers no `libraryURI:`
/// variant. Getting this wrong fails loudly in the engine log but silently in
/// the UI: the engine's threads still spawn, so the app looks healthy while the
/// overlay isolate is dead. The pragma keeps it from being tree-shaken, since
/// nothing in Dart ever calls it.
@pragma('vm:entry-point')
void overlayMain() => runOverlayApp();

/// The app's one coordinator. Everything that used to be a top-level global in
/// this file now lives on it — see [OrthantCoordinator] for why.
late final OrthantCoordinator app;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final wc = createWindowController();

  // The callbacks close over `app`, which is assigned immediately below: the
  // registrar needs the coordinator and the coordinator needs the registrar, and
  // deferring the read through a closure is the whole of the knot.
  final hotkeys = HotkeyService(
    onCommand: (ref) => app.runCommand(ref),
    onSummon: () => app.summon(),
    onPlacementFailed: () => app.recoverIfPermissionLost(),
    onConfigWindowClosed: () => app.onConfigWindowClosed(),
    onSaveRegion: (block) => app.requestSaveRegion(block),
  );
  app = OrthantCoordinator(
    wc: wc,
    permissions: PermissionController(wc),
    hotkeys: hotkeys,
  );

  // isTemplate: the icon is solid black + alpha, so let macOS tint it for the
  // current menu bar (white on dark, black on light). Without this it renders
  // as-is and is effectively invisible on a dark menu bar.
  await trayManager.setIcon('assets/tray_icon.png', isTemplate: true);
  await _syncTray();
  // The tray follows every state change, so nothing has to remember to refresh
  // it after a rebind, a refusal or a permission transition — three places that
  // each had to, and one of which forgot.
  app.addListener(_syncTray);

  await app.start();
  runApp(const OrthantApp());
}

/// Render the coordinator's menu description into `tray_manager`'s objects.
///
/// The combo goes in the label, not a keyEquivalent or a sublabel.
/// tray_manager 0.5.3's macOS plugin reads only label/toolTip/checked/disabled/
/// type/submenu — `sublabel` is silently dropped and it never sets
/// NSMenuItem.keyEquivalent, so a real right-aligned key equivalent is not
/// reachable without forking a pinned package. Inline is what is left.
Future<void> _syncTray() => trayManager.setContextMenu(Menu(items: [
      for (final e in app.trayMenu)
        if (e.isSeparator)
          MenuItem.separator()
        else
          MenuItem(key: e.key, label: e.label, disabled: e.disabled),
    ]));

class OrthantApp extends StatefulWidget {
  const OrthantApp({super.key});
  @override
  State<OrthantApp> createState() => _OrthantAppState();
}

class _OrthantAppState extends State<OrthantApp> with TrayListener {
  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    super.dispose();
  }

  /// Opening the menu is the natural moment to re-check permission: it's the
  /// "re-check on focus" the spec asks for, user-initiated so it costs nothing
  /// while idle, and it keeps the status row honest. Awaited in order, so the
  /// menu is current before it is shown.
  @override
  Future<void> onTrayIconMouseDown() async {
    await app.permissions.refresh();
    await _syncTray();
    await trayManager.popUpContextMenu();
  }

  @override
  Future<void> onTrayMenuItemClick(MenuItem item) async {
    switch (item.key) {
      case 'permission':
        await app.showOnboarding();
      case 'overlay':
        await app.summon();
      case 'settings':
        await app.openSettings();
      case 'updates':
        await app.wc.checkForUpdates();
      case 'quit':
        exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: macTheme(Brightness.light),
      darkTheme: macTheme(Brightness.dark),
      home: ListenableBuilder(
        listenable: app,
        builder: (_, _) => switch (app.screen) {
          AppScreen.onboarding => OnboardingScreen(
              controller: app.permissions,
              onOpenAccessibility: app.openAccessibility,
            ),
          AppScreen.ready => ReadyScreen(
              bindings: app.bindings,
              // So this screen cannot teach a chord macOS already refused — the
              // one screen whose reader has nothing to contradict it.
              unavailable: app.unavailable,
              onDone: app.finishOnboarding,
              onOpenShortcuts: app.openShortcutsFromReady,
            ),
          AppScreen.settings => SettingsWindow(
              initialTab: app.settingsTab,
              settings: app.settings,
              bindings: app.bindings,
              unavailable: app.unavailable,
              permissionGranted: app.permissions.granted,
              loginStatus: app.loginStatus,
              onSettingsChanged: app.settingsChanged,
              onSetLoginItem: app.setLoginItem,
              onOpenLoginItems: app.wc.openLoginItemsSettings,
              onOpenAccessibility: app.openAccessibility,
              onRebound: app.rebind,
              onRestoreBindings: app.restoreBindings,
              onCaptureStart: app.suspendHotkeys,
              onCaptureEnd: app.applyBindings,
              onResetBindings: app.resetBindings,
              regions: app.regions,
              onRegionSaved: app.saveRegion,
              onRegionDeleted: app.deleteRegion,
              pendingRegion: app.pendingRegion,
              onPendingConsumed: app.consumePendingRegion,
            ),
          AppScreen.none => const SizedBox.shrink(),
        },
      ),
    );
  }
}
