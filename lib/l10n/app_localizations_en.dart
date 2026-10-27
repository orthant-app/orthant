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
}
