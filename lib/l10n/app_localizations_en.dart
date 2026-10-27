// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get l10nProbeLocale => 'en';

  @override
  String get l10nProbeScript => 'Latn';

  @override
  String get languageNativeName => 'English';

  @override
  String get trayEnableAccessibility => 'Enable Accessibility…';

  @override
  String get trayOpenGrid => 'Open Grid';

  @override
  String get traySettings => 'Settings…';

  @override
  String get trayAbout => 'About Orthant';

  @override
  String trayUpdateTo(String version) {
    return 'Update to Orthant $version…';
  }

  @override
  String get trayCheckForUpdates => 'Check for Updates…';

  @override
  String get trayQuit => 'Quit Orthant';

  @override
  String trayTooltipUpdate(String version) {
    return 'Orthant: update $version available';
  }

  @override
  String overlaySaveHint(String key) {
    return '$key  save this shape as a shortcut';
  }

  @override
  String overlayGridHint(String place) {
    return 'Arrow keys move. Shift and arrow keys extend. $place places the window. Escape cancels.';
  }

  @override
  String overlayOpened(
    String target,
    String columns,
    String rows,
    String place,
  ) {
    return 'Grid open for $target. $columns, $rows. Arrow keys move, Shift and arrows extend, $place places, Escape cancels.';
  }

  @override
  String get overlayCapturedWindow => 'the captured window';

  @override
  String overlayColumns(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count columns',
      one: '1 column',
    );
    return '$_temp0';
  }

  @override
  String overlayRows(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rows',
      one: '1 row',
    );
    return '$_temp0';
  }

  @override
  String overlayGridLabel(String app, String columns, String rows) {
    return 'Window grid for $app, $columns, $rows';
  }

  @override
  String get overlayGridClosed => 'Grid closed.';

  @override
  String get overlayPlacingWindow => 'Placing window.';

  @override
  String get overlayNoCellsSelected => 'No cells selected.';

  @override
  String overlayRowOne(int row) {
    return 'Row $row';
  }

  @override
  String overlayRowRange(int first, int last) {
    return 'Rows $first to $last';
  }

  @override
  String overlayColumnOne(int column) {
    return 'column $column';
  }

  @override
  String overlayColumnRange(int first, int last) {
    return 'columns $first to $last';
  }

  @override
  String overlaySelection(
    String rowText,
    String columnText,
    String x,
    String y,
    String width,
    String height,
    String unit,
  ) {
    return '$rowText, $columnText. Target: x $x, y $y, width $width, height $height $unit.';
  }

  @override
  String get overlayUnitPoints => 'points';

  @override
  String get overlayUnitPixels => 'pixels';

  @override
  String overlayMove(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'left': 'Move left',
      'right': 'Move right',
      'up': 'Move up',
      'down': 'Move down',
      'other': 'Move',
    });
    return '$_temp0';
  }

  @override
  String overlayExtend(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'left': 'Extend left',
      'right': 'Extend right',
      'up': 'Extend up',
      'down': 'Extend down',
      'other': 'Extend',
    });
    return '$_temp0';
  }

  @override
  String get overlayPlaceWindow => 'Place window';

  @override
  String get overlayPlaceAndSave => 'Place window and save shortcut';

  @override
  String get overlayCancelGrid => 'Cancel grid';

  @override
  String get keyWin => 'Win';

  @override
  String get keyCtrl => 'Ctrl';

  @override
  String get keyAlt => 'Alt';

  @override
  String get keyShift => 'Shift';

  @override
  String get keyEnter => 'Enter';

  @override
  String get keySpace => 'Space';

  @override
  String get keyTab => 'Tab';

  @override
  String get keyBackspace => 'Backspace';

  @override
  String get keyEsc => 'Esc';

  @override
  String get keyHome => 'Home';

  @override
  String get keyEnd => 'End';

  @override
  String get keyPageUp => 'PgUp';

  @override
  String get keyPageDown => 'PgDn';

  @override
  String get keyDelete => 'Del';

  @override
  String get keyNumLock => 'Num Lock';

  @override
  String get keyNumEnter => 'Num Enter';

  @override
  String get keyMacEscape => 'esc';

  @override
  String get keyMacReturn => 'Return';

  @override
  String keyNumpad(String key) {
    return 'Num $key';
  }

  @override
  String keyListAnyModifier(String a, String b, String c, String d) {
    return '$a, $b, $c or $d';
  }

  @override
  String get settingsTabGeneral => 'General';

  @override
  String get settingsTabShortcuts => 'Shortcuts';

  @override
  String get settingsTabAbout => 'About';

  @override
  String settingsTabLabel(String tab) {
    return '$tab tab';
  }

  @override
  String get generalGroupAccessibility => 'Accessibility';

  @override
  String get generalGroupOpenGrid => 'Open grid';

  @override
  String get generalGroupGrid => 'Grid';

  @override
  String get generalGroupGaps => 'Gaps';

  @override
  String get generalGroupStartup => 'Startup';

  @override
  String get generalGroupLanguage => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get generalLanguageUpdaterNote =>
      'The update window changes language the next time Orthant starts.';

  @override
  String get generalColumns => 'Columns';

  @override
  String get generalRows => 'Rows';

  @override
  String get generalGapSize => 'Size';

  @override
  String get generalLeaveGaps => 'Leave gaps';

  @override
  String get generalResetGridAndGaps => 'Reset Grid & Gaps';

  @override
  String get generalAccessibilityGranted => 'Granted';

  @override
  String get generalAccessibilityNotGranted =>
      'Not granted. Shortcuts and the grid do nothing';

  @override
  String get generalOpenAccessibilitySettings => 'Open Accessibility Settings…';

  @override
  String generalSummonUnavailable(String system) {
    return '$system or another app already uses this combination, so it never reaches Orthant.';
  }

  @override
  String get generalChange => 'Change…';

  @override
  String get shortcutNotSet => 'Not set';

  @override
  String get generalLaunchAtLogin => 'Launch at login';

  @override
  String get generalLoginUnrecognisedMac =>
      'macOS reported a login-item state Orthant does not recognise. Switching this on may still work.';

  @override
  String get generalLoginUnrecognisedWindows =>
      'Windows reported a startup state Orthant does not recognise. Switching this on may still work.';

  @override
  String get generalLoginTurnedOffMac13 =>
      'Turned off in System Settings ▸ General ▸ Login Items, so Orthant will not start automatically.';

  @override
  String get generalLoginTurnedOffMac15 =>
      'Turned off in System Settings ▸ General ▸ Login Items & Extensions, so Orthant will not start automatically.';

  @override
  String get generalLoginTurnedOffWindows =>
      'Turned off in Settings ▸ Apps ▸ Startup, so Orthant will not start automatically.';

  @override
  String get generalOpenLoginItemsMac13 => 'Open Login Items…';

  @override
  String get generalOpenLoginItemsMac15 => 'Open Login Items & Extensions…';

  @override
  String get generalOpenStartupApps => 'Open Startup Apps…';

  @override
  String generalStepperValue(String caption, int value) {
    return '$caption $value';
  }

  @override
  String generalStepperValueUnit(String caption, int value, String unit) {
    return '$caption $value $unit';
  }

  @override
  String stepperIncrease(String label) {
    return '$label, increase';
  }

  @override
  String stepperDecrease(String label) {
    return '$label, decrease';
  }

  @override
  String gridPreviewCaptionGaps(int cols, int rows, int gap, String unit) {
    String _temp0 = intl.Intl.pluralLogic(
      gap,
      locale: localeName,
      other: '$cols × $rows · up to $gap $unit gaps',
    );
    return '$_temp0';
  }

  @override
  String get recordingPressKeys => 'Press keys…';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String aboutUpdateAvailable(String name) {
    return 'Orthant $name is available.';
  }

  @override
  String get aboutUpdate => 'Update…';

  @override
  String get aboutCheckForUpdates => 'Check for Updates…';

  @override
  String get aboutAutomaticChecks => 'Check for updates automatically';

  @override
  String get aboutTagline => 'A grid-based window manager.';

  @override
  String get regionNameFullScreen => 'Full screen';

  @override
  String regionNameLeft(String fraction) {
    return 'Left $fraction';
  }

  @override
  String regionNameRight(String fraction) {
    return 'Right $fraction';
  }

  @override
  String regionNameTop(String fraction) {
    return 'Top $fraction';
  }

  @override
  String regionNameBottom(String fraction) {
    return 'Bottom $fraction';
  }

  @override
  String get regionNameCustom => 'Custom region';

  @override
  String get regionSheetTitleNew => 'New region';

  @override
  String get regionSheetTitleEdit => 'Edit region';

  @override
  String regionSheetHint(String shift) {
    return 'Drag to draw · arrows to move, $shift to extend';
  }

  @override
  String get regionSheetName => 'Name';

  @override
  String get regionSheetShortcut => 'Shortcut';

  @override
  String get regionSheetRecordNone => 'Record shortcut, none set';

  @override
  String regionSheetRecordCurrent(String combo) {
    return 'Record shortcut, currently $combo';
  }

  @override
  String get regionSheetClickToRecord => 'Click to record';

  @override
  String regionSheetConflict(String command) {
    return '$command already uses this combination.';
  }

  @override
  String regionSheetConflictTaking(String command) {
    return '$command will lose this combination when you save.';
  }

  @override
  String get regionSheetUseHere => 'Use it here';

  @override
  String get regionSheetUseHereLabel => 'Use this combination here';

  @override
  String get regionSheetCancel => 'Cancel';

  @override
  String get regionSheetDelete => 'Delete';

  @override
  String get regionSheetDeleteLabel => 'Delete region';

  @override
  String get regionSheetAdd => 'Add';

  @override
  String get regionSheetAddLabel => 'Add region';

  @override
  String get regionSheetSave => 'Save';

  @override
  String get regionSheetSaveLabel => 'Save region';

  @override
  String get commandOpenGrid => 'Open grid';

  @override
  String get commandLeftHalf => 'Left half';

  @override
  String get commandRightHalf => 'Right half';

  @override
  String get commandTopHalf => 'Top half';

  @override
  String get commandBottomHalf => 'Bottom half';

  @override
  String get commandTopLeft => 'Top-left quarter';

  @override
  String get commandTopRight => 'Top-right quarter';

  @override
  String get commandBottomLeft => 'Bottom-left quarter';

  @override
  String get commandBottomRight => 'Bottom-right quarter';

  @override
  String get commandMaximize => 'Maximize';

  @override
  String get commandCenter => 'Center';

  @override
  String get shortcutsTitle => 'Shortcuts';

  @override
  String get shortcutsSubtitle =>
      'Open the grid, or snap the frontmost window straight to a region of its own display.';

  @override
  String get shortcutsGroupBuiltIn => 'Built-in';

  @override
  String get shortcutsGroupRegions => 'Your regions';

  @override
  String shortcutsRegionsHint(String key) {
    return 'Bind a shape the built-ins don\'t cover. Draw it here, or select it in the grid and press $key.';
  }

  @override
  String get shortcutsNotGranted =>
      'None of these will fire until Orthant has Accessibility permission. You can still change them.';

  @override
  String shortcutsListening(String escape) {
    return 'Listening… press a combination, or $escape to cancel.';
  }

  @override
  String shortcutsHint(String modifiers) {
    return 'Click a shortcut to change it. Combinations need $modifiers.';
  }

  @override
  String shortcutsCollision(String combo, String owner) {
    return '$combo is used by $owner. Press it again to use it here.';
  }

  @override
  String get shortcutsUseHere => 'Use it here';

  @override
  String shortcutsDisplaced(String command, String combo) {
    return '$command lost $combo.';
  }

  @override
  String get shortcutsUndo => 'Undo';

  @override
  String shortcutsRegionDeleted(String name) {
    return '$name deleted.';
  }

  @override
  String get shortcutsResetDone => 'All shortcuts reset to their defaults.';

  @override
  String get shortcutsReset => 'Reset Shortcuts';

  @override
  String get shortcutsAddRegion => 'Add region…';

  @override
  String get shortcutsAddRegionLabel => 'Add region';

  @override
  String shortcutsEditRegion(String name) {
    return 'Edit $name';
  }

  @override
  String get shortcutsClickToSet => 'Click to set';

  @override
  String get shortcutsRemove => 'Remove shortcut';

  @override
  String shortcutsRemoveLabel(String command) {
    return 'Remove $command shortcut';
  }

  @override
  String shortcutsUnavailableTooltip(String system) {
    return '$system or another app already uses this combination, so it never reaches Orthant.\nClick the shortcut to pick a different one.';
  }

  @override
  String shortcutRowBound(String command, String combo) {
    return '$command, $combo';
  }

  @override
  String shortcutRowUnbound(String command) {
    return '$command, no shortcut';
  }

  @override
  String shortcutRowUnavailable(String command, String combo) {
    return '$command, $combo, unavailable';
  }

  @override
  String shortcutRowListening(String command) {
    return '$command, listening for a combination';
  }

  @override
  String shortcutRowCollision(String command, String combo, String owner) {
    return '$command, $combo is used by $owner. Press it again to use it here, or escape to cancel.';
  }

  @override
  String get refusalKeypad =>
      'Windows can\'t use the keypad\'s digits, decimal point or = in a shortcut.';

  @override
  String get refusalUnregistrable =>
      'Windows can\'t use that key in a shortcut.';

  @override
  String get onboardingTitle => 'Orthant needs Accessibility permission';

  @override
  String get onboardingBody =>
      'Orthant moves your windows using macOS Accessibility. Enable “Orthant” under Privacy & Security ▸ Accessibility and Orthant will pick it up straight away.';

  @override
  String get onboardingOpenAccessibility => 'Open Accessibility Settings';

  @override
  String get onboardingGranted => 'Permission granted';

  @override
  String get onboardingWaiting => 'Waiting for permission…';

  @override
  String get readyTitle => 'Orthant is ready';

  @override
  String get readySubtitle => 'Two ways to put a window where you want it.';

  @override
  String readyGridCaption(String shift, String place) {
    return 'Opens the grid. Drag across it to pick any block: thirds, two-thirds, anything. Or use the arrow keys, $shift to extend, $place to place.';
  }

  @override
  String get readyDirectCaption =>
      'Snaps straight to a half, a quarter, or full screen. No aiming, and you can add shapes of your own, like the third one.';

  @override
  String get readyChangeShortcuts => 'Change these shortcuts…';

  @override
  String get readyDone => 'Done';

  @override
  String get readyNoShortcutSet => 'No shortcut set';

  @override
  String readyUnavailableTooltip(String system) {
    return '$system or another app already uses this combination, so it never reaches Orthant.\nPick a different one below.';
  }
}
