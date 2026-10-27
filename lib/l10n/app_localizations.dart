import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale.fromSubtags(
      languageCode: 'zh',
      countryCode: 'HK',
      scriptCode: 'Hant',
    ),
  ];

  /// Never shown. Tests use it to prove each language resolves to its own file.
  ///
  /// In en, this message translates to:
  /// **'en'**
  String get l10nProbeLocale;

  /// Never shown. Tests use it to prove each language resolves to its own file.
  ///
  /// In en, this message translates to:
  /// **'Latn'**
  String get l10nProbeScript;

  /// This language's own name, shown in the language picker whatever the UI language is.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageNativeName;

  /// The menu-bar (tray) menu row that opens the onboarding window to ask for the macOS Accessibility permission. Shown only while the permission is missing. Accessibility is the name of the macOS Privacy pane.
  ///
  /// In en, this message translates to:
  /// **'Enable Accessibility…'**
  String get trayEnableAccessibility;

  /// The tray menu row that opens the grid overlay. The grid shortcut, if it has one, is added after this text by the app.
  ///
  /// In en, this message translates to:
  /// **'Open Grid'**
  String get trayOpenGrid;

  /// The tray menu row that opens the Settings window.
  ///
  /// In en, this message translates to:
  /// **'Settings…'**
  String get traySettings;

  /// The tray menu row that opens Settings on the About pane. Orthant is the app name and stays as written.
  ///
  /// In en, this message translates to:
  /// **'About Orthant'**
  String get trayAbout;

  /// The tray menu row that offers an update a check found. {version} is the new version, such as 1.1.2.
  ///
  /// In en, this message translates to:
  /// **'Update to Orthant {version}…'**
  String trayUpdateTo(String version);

  /// The tray menu row that checks for a new version of the app.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates…'**
  String get trayCheckForUpdates;

  /// The tray menu row that quits the app. Orthant is the app name and stays as written.
  ///
  /// In en, this message translates to:
  /// **'Quit Orthant'**
  String get trayQuit;

  /// The tray icon's tooltip on Windows while an update is waiting to be installed. {version} is the new version, such as 1.1.2.
  ///
  /// In en, this message translates to:
  /// **'Orthant: update {version} available'**
  String trayTooltipUpdate(String version);

  /// The small caption under the grid panel, shown until the user has a custom region. {key} is the chord that places the window and offers the shape as a shortcut, such as ⌘S or Ctrl+S, and stays as written. Two spaces follow it.
  ///
  /// In en, this message translates to:
  /// **'{key}  save this shape as a shortcut'**
  String overlaySaveHint(String key);

  /// The grid's accessibility hint, read by a screen reader after the grid's label and value. {place} is the key that places the window, such as Return or Enter. Key names stay in English in every language.
  ///
  /// In en, this message translates to:
  /// **'Arrow keys move. Shift and arrow keys extend. {place} places the window. Escape cancels.'**
  String overlayGridHint(String place);

  /// Spoken by a screen reader when the grid opens. {target} is the name of the app whose window will be moved, or the text of "the captured window" when there is no name. {columns} and {rows} are the grid's size, such as "6 columns" and "4 rows". {place} is the key that places the window, such as Return or Enter. Key names stay in English in every language.
  ///
  /// In en, this message translates to:
  /// **'Grid open for {target}. {columns}, {rows}. Arrow keys move, Shift and arrows extend, {place} places, Escape cancels.'**
  String overlayOpened(
    String target,
    String columns,
    String rows,
    String place,
  );

  /// Stands in for the app's name in the spoken opening of the grid when the app has no name: the window the grid is about to move.
  ///
  /// In en, this message translates to:
  /// **'the captured window'**
  String get overlayCapturedWindow;

  /// The number of columns in the grid, as a phrase in the grid's spoken label and its spoken opening. A column runs top to bottom.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 column} other{{count} columns}}'**
  String overlayColumns(int count);

  /// The number of rows in the grid, as a phrase in the grid's spoken label and its spoken opening. A row runs left to right.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 row} other{{count} rows}}'**
  String overlayRows(int count);

  /// The grid's accessibility label, read first by a screen reader. {app} is the app whose window will be moved. {columns} and {rows} are the grid's size, such as "6 columns" and "4 rows".
  ///
  /// In en, this message translates to:
  /// **'Window grid for {app}, {columns}, {rows}'**
  String overlayGridLabel(String app, String columns, String rows);

  /// Spoken by a screen reader when the grid is dismissed without placing a window.
  ///
  /// In en, this message translates to:
  /// **'Grid closed.'**
  String get overlayGridClosed;

  /// Spoken by a screen reader when the user places the window from the grid.
  ///
  /// In en, this message translates to:
  /// **'Placing window.'**
  String get overlayPlacingWindow;

  /// The grid's accessibility value while nothing is selected.
  ///
  /// In en, this message translates to:
  /// **'No cells selected.'**
  String get overlayNoCellsSelected;

  /// Part of the grid's spoken selection: one row is selected. {row} counts from 1, from the top. Joined by the next messages into a sentence.
  ///
  /// In en, this message translates to:
  /// **'Row {row}'**
  String overlayRowOne(int row);

  /// Part of the grid's spoken selection: several rows are selected. {first} and {last} count from 1, from the top.
  ///
  /// In en, this message translates to:
  /// **'Rows {first} to {last}'**
  String overlayRowRange(int first, int last);

  /// Part of the grid's spoken selection: one column is selected. {column} counts from 1, from the left. It follows the row text after a comma.
  ///
  /// In en, this message translates to:
  /// **'column {column}'**
  String overlayColumnOne(int column);

  /// Part of the grid's spoken selection: several columns are selected. {first} and {last} count from 1, from the left.
  ///
  /// In en, this message translates to:
  /// **'columns {first} to {last}'**
  String overlayColumnRange(int first, int last);

  /// The grid's accessibility value and its spoken announcement when the selection changes. {rowText} and {columnText} are the selected rows and columns, such as "Row 2" and "columns 1 to 2". x and y are the left and top of the window's target position, and width and height its size; all four are already formatted numbers. {unit} is "points" or "pixels", the next two messages, and applies to all four numbers.
  ///
  /// In en, this message translates to:
  /// **'{rowText}, {columnText}. Target: x {x}, y {y}, width {width}, height {height} {unit}.'**
  String overlaySelection(
    String rowText,
    String columnText,
    String x,
    String y,
    String width,
    String height,
    String unit,
  );

  /// The unit of the target position and size the grid speaks on macOS: points, the screen's logical units. Used where {unit} appears in the selection sentence.
  ///
  /// In en, this message translates to:
  /// **'points'**
  String get overlayUnitPoints;

  /// The unit of the target position and size the grid speaks on Windows: physical screen pixels. Used where {unit} appears in the selection sentence.
  ///
  /// In en, this message translates to:
  /// **'pixels'**
  String get overlayUnitPixels;

  /// The name of a button in the grid's accessibility tree that moves the selection one cell. {direction} is left, right, up or down.
  ///
  /// In en, this message translates to:
  /// **'{direction, select, left{Move left} right{Move right} up{Move up} down{Move down} other{Move}}'**
  String overlayMove(String direction);

  /// The name of a button in the grid's accessibility tree that grows the selection by one cell. {direction} is left, right, up or down.
  ///
  /// In en, this message translates to:
  /// **'{direction, select, left{Extend left} right{Extend right} up{Extend up} down{Extend down} other{Extend}}'**
  String overlayExtend(String direction);

  /// The name of a button in the grid's accessibility tree that moves the captured window to the selection.
  ///
  /// In en, this message translates to:
  /// **'Place window'**
  String get overlayPlaceWindow;

  /// The name of a button in the grid's accessibility tree that moves the captured window to the selection and offers the selection as a new shortcut.
  ///
  /// In en, this message translates to:
  /// **'Place window and save shortcut'**
  String get overlayPlaceAndSave;

  /// The name of a button in the grid's accessibility tree that closes the grid without moving anything.
  ///
  /// In en, this message translates to:
  /// **'Cancel grid'**
  String get overlayCancelGrid;

  /// The Windows logo key, as written in Windows shortcuts such as Win+Ctrl+Shift+← in Settings, the tray menu and the grid's hints. Use the legend printed on the key.
  ///
  /// In en, this message translates to:
  /// **'Win'**
  String get keyWin;

  /// The Control key, as written in Windows shortcuts such as Win+Ctrl+Shift+← in Settings, the tray menu and the grid's hints. Use the legend printed on the key.
  ///
  /// In en, this message translates to:
  /// **'Ctrl'**
  String get keyCtrl;

  /// The Alt key, as written in Windows shortcuts such as Win+Ctrl+Shift+← in Settings, the tray menu and the grid's hints. Use the legend printed on the key.
  ///
  /// In en, this message translates to:
  /// **'Alt'**
  String get keyAlt;

  /// The Shift key, as written in Windows shortcuts such as Win+Ctrl+Shift+← in Settings, the tray menu and the grid's hints. Use the legend printed on the key.
  ///
  /// In en, this message translates to:
  /// **'Shift'**
  String get keyShift;

  /// The Enter key, as written in Windows shortcuts such as Win+Ctrl+Shift+← in Settings, the tray menu and the grid's hints. Use the legend printed on the key.
  ///
  /// In en, this message translates to:
  /// **'Enter'**
  String get keyEnter;

  /// The Space bar, as written in Windows shortcuts such as Win+Ctrl+Shift+← in Settings, the tray menu and the grid's hints. Use the legend printed on the key.
  ///
  /// In en, this message translates to:
  /// **'Space'**
  String get keySpace;

  /// The Tab key, as written in Windows shortcuts such as Win+Ctrl+Shift+← in Settings, the tray menu and the grid's hints. Use the legend printed on the key.
  ///
  /// In en, this message translates to:
  /// **'Tab'**
  String get keyTab;

  /// The Backspace key, as written in Windows shortcuts such as Win+Ctrl+Shift+← in Settings, the tray menu and the grid's hints. Use the legend printed on the key.
  ///
  /// In en, this message translates to:
  /// **'Backspace'**
  String get keyBackspace;

  /// The Escape key, as written in Windows shortcuts and in the Shortcuts hint "Listening… press a combination, or Esc to cancel." Use the legend printed on the key.
  ///
  /// In en, this message translates to:
  /// **'Esc'**
  String get keyEsc;

  /// The Home key, as written in Windows shortcuts such as Win+Ctrl+Shift+← in Settings, the tray menu and the grid's hints. Use the legend printed on the key.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get keyHome;

  /// The End key, as written in Windows shortcuts such as Win+Ctrl+Shift+← in Settings, the tray menu and the grid's hints. Use the legend printed on the key.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get keyEnd;

  /// The Page Up key, as written in Windows shortcuts such as Win+Ctrl+Shift+← in Settings, the tray menu and the grid's hints. Use the legend printed on the key.
  ///
  /// In en, this message translates to:
  /// **'PgUp'**
  String get keyPageUp;

  /// The Page Down key, as written in Windows shortcuts such as Win+Ctrl+Shift+← in Settings, the tray menu and the grid's hints. Use the legend printed on the key.
  ///
  /// In en, this message translates to:
  /// **'PgDn'**
  String get keyPageDown;

  /// The Delete key, as written in Windows shortcuts such as Win+Ctrl+Shift+← in Settings, the tray menu and the grid's hints. Use the legend printed on the key.
  ///
  /// In en, this message translates to:
  /// **'Del'**
  String get keyDelete;

  /// The Num Lock key, as written in Windows shortcuts such as Win+Ctrl+Shift+← in Settings, the tray menu and the grid's hints. Use the legend printed on the key.
  ///
  /// In en, this message translates to:
  /// **'Num Lock'**
  String get keyNumLock;

  /// The Enter key on the numeric keypad, as written in Windows shortcuts such as Win+Ctrl+Shift+← in Settings, the tray menu and the grid's hints. Use the legend printed on the key.
  ///
  /// In en, this message translates to:
  /// **'Num Enter'**
  String get keyNumEnter;

  /// The Escape key as macOS shortcut hints write it, lowercase as the key is printed on Mac keyboards, in the Shortcuts hint "Listening… press a combination, or esc to cancel." Chinese keeps the English word, because that is what the key says.
  ///
  /// In en, this message translates to:
  /// **'esc'**
  String get keyMacEscape;

  /// The Return key as the grid names it on macOS, as the key that places the window, in the grid's accessibility hint and spoken announcement ("Return places the window"). Windows says Enter. Chinese keeps the English word, because that is what the key says.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get keyMacReturn;

  /// A key on the numeric keypad, as written in shortcuts on both macOS and Windows, such as Num 5 or Num /. {key} is the character on the key. Use the legend printed on the keypad.
  ///
  /// In en, this message translates to:
  /// **'Num {key}'**
  String keyNumpad(String key);

  /// The four modifier keys as a list in a sentence, in the Shortcuts hint "Click a shortcut to change it. Combinations need Win, Ctrl, Alt or Shift." Each placeholder is one key name (a glyph such as ⌃ on macOS). Use your language's list pattern, ending with its word for "or".
  ///
  /// In en, this message translates to:
  /// **'{a}, {b}, {c} or {d}'**
  String keyListAnyModifier(String a, String b, String c, String d);

  /// The Settings window's first tab, for everything that is not a keyboard shortcut. On macOS it is also the name of a System Settings pane, so use Apple's word for General.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsTabGeneral;

  /// The Settings window's second tab, the list of keyboard shortcuts.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get settingsTabShortcuts;

  /// The Settings window's third tab, showing the version and the update check.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsTabAbout;

  /// What a screen reader calls one tab of the Settings window. Never drawn on screen. {tab} is the tab's name, written by the three messages above.
  ///
  /// In en, this message translates to:
  /// **'{tab} tab'**
  String settingsTabLabel(String tab);

  /// The label of the General tab's row that shows whether Orthant has the macOS Accessibility permission. It is the name of a macOS Privacy & Security pane, so use Apple's word for Accessibility. Shown on macOS only.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get generalGroupAccessibility;

  /// The label of the General tab's row that shows the shortcut which opens the grid.
  ///
  /// In en, this message translates to:
  /// **'Open grid'**
  String get generalGroupOpenGrid;

  /// The label of the General tab's group of two steppers that set the grid's columns and rows.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get generalGroupGrid;

  /// The label of the General tab's group that sets the space left between windows and the screen's edge when a window is placed.
  ///
  /// In en, this message translates to:
  /// **'Gaps'**
  String get generalGroupGaps;

  /// The label of the General tab's group holding the launch-at-login checkbox.
  ///
  /// In en, this message translates to:
  /// **'Startup'**
  String get generalGroupStartup;

  /// The caption of the General tab's stepper for the number of columns in the grid. A column runs top to bottom. Keep it short: the caption has room for about five characters.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get generalColumns;

  /// The caption of the General tab's stepper for the number of rows in the grid. A row runs left to right. Keep it short: the caption has room for about five characters.
  ///
  /// In en, this message translates to:
  /// **'Rows'**
  String get generalRows;

  /// The caption of the General tab's stepper for how large a gap is, beside the unit (pt on macOS, px on Windows).
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get generalGapSize;

  /// The label of the General tab's checkbox that turns gaps between placed windows and the screen's edge on or off.
  ///
  /// In en, this message translates to:
  /// **'Leave gaps'**
  String get generalLeaveGaps;

  /// The button at the foot of the General tab that puts the grid size and the gaps back to their defaults. It changes nothing else, and the name says so.
  ///
  /// In en, this message translates to:
  /// **'Reset Grid & Gaps'**
  String get generalResetGridAndGaps;

  /// Beside a green dot on the General tab, when Orthant has the macOS Accessibility permission. Shown on macOS only.
  ///
  /// In en, this message translates to:
  /// **'Granted'**
  String get generalAccessibilityGranted;

  /// Beside a warning dot on the General tab, when Orthant lacks the macOS Accessibility permission. It has no final full stop in English. Shown on macOS only.
  ///
  /// In en, this message translates to:
  /// **'Not granted. Shortcuts and the grid do nothing'**
  String get generalAccessibilityNotGranted;

  /// The button under the missing-permission warning that opens the macOS Accessibility pane. Accessibility is the name of that pane. Shown on macOS only.
  ///
  /// In en, this message translates to:
  /// **'Open Accessibility Settings…'**
  String get generalOpenAccessibilitySettings;

  /// The tooltip on the warning icon beside the grid shortcut on the General tab, when the system refused to give Orthant that key combination. {system} is the operating system's name, macOS or Windows, and stays as written.
  ///
  /// In en, this message translates to:
  /// **'{system} or another app already uses this combination, so it never reaches Orthant.'**
  String generalSummonUnavailable(String system);

  /// The link beside the grid shortcut on the General tab that opens the Shortcuts tab, where it is changed.
  ///
  /// In en, this message translates to:
  /// **'Change…'**
  String get generalChange;

  /// Shown where a command has no keyboard shortcut yet, such as the grid shortcut on the General tab.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get shortcutNotSet;

  /// The label of the General tab's checkbox that starts Orthant when the user signs in, on macOS and on Windows.
  ///
  /// In en, this message translates to:
  /// **'Launch at login'**
  String get generalLaunchAtLogin;

  /// A note under the Launch at login checkbox on macOS, when the system answered with a state Orthant does not know. macOS stays as written.
  ///
  /// In en, this message translates to:
  /// **'macOS reported a login-item state Orthant does not recognise. Switching this on may still work.'**
  String get generalLoginUnrecognisedMac;

  /// A note under the Launch at login checkbox on Windows, when the system answered with a state Orthant does not know. Windows stays as written.
  ///
  /// In en, this message translates to:
  /// **'Windows reported a startup state Orthant does not recognise. Switching this on may still work.'**
  String get generalLoginUnrecognisedWindows;

  /// A note under the Launch at login checkbox on macOS 13 and 14, when the user has switched Orthant off in System Settings. One whole sentence: it names three System Settings screens in order, joined by ▸, and each name is copied exactly from Apple's own words for that macOS version. The macOS 15 and later version is the next message.
  ///
  /// In en, this message translates to:
  /// **'Turned off in System Settings ▸ General ▸ Login Items, so Orthant will not start automatically.'**
  String get generalLoginTurnedOffMac13;

  /// A note under the Launch at login checkbox on macOS 15 and later, when the user has switched Orthant off in System Settings. One whole sentence: it names three System Settings screens in order, joined by ▸, and each name is copied exactly from Apple's own words for macOS 15 and later, where the last screen is called Login Items & Extensions.
  ///
  /// In en, this message translates to:
  /// **'Turned off in System Settings ▸ General ▸ Login Items & Extensions, so Orthant will not start automatically.'**
  String get generalLoginTurnedOffMac15;

  /// A note under the Launch at login checkbox on Windows, when the user has switched Orthant off in Windows Settings. One whole sentence: it names three Windows Settings screens in order, joined by ▸, and each name is copied exactly from that Windows language's own Settings.
  ///
  /// In en, this message translates to:
  /// **'Turned off in Settings ▸ Apps ▸ Startup, so Orthant will not start automatically.'**
  String get generalLoginTurnedOffWindows;

  /// The link under the macOS note that opens the System Settings pane for Login Items, on macOS 13 and 14. It names that pane exactly as the previous note does.
  ///
  /// In en, this message translates to:
  /// **'Open Login Items…'**
  String get generalOpenLoginItemsMac13;

  /// The link under the macOS note that opens the System Settings pane for Login Items & Extensions, on macOS 15 and later. It names that pane exactly as the previous note does.
  ///
  /// In en, this message translates to:
  /// **'Open Login Items & Extensions…'**
  String get generalOpenLoginItemsMac15;

  /// The link under the Windows note that opens the Windows Settings page for startup apps (Settings, Apps, Startup).
  ///
  /// In en, this message translates to:
  /// **'Open Startup Apps…'**
  String get generalOpenStartupApps;

  /// What a screen reader says for a stepper that has no unit: its caption, then its value, such as "Columns 6". Never drawn on screen.
  ///
  /// In en, this message translates to:
  /// **'{caption} {value}'**
  String generalStepperValue(String caption, int value);

  /// What a screen reader says for a stepper that has a unit: its caption, its value and the unit, such as "Size 8 pt". {unit} is pt on macOS and px on Windows and stays as written. Never drawn on screen.
  ///
  /// In en, this message translates to:
  /// **'{caption} {value} {unit}'**
  String generalStepperValueUnit(String caption, int value, String unit);

  /// What a screen reader calls the up arrow of a stepper. {label} is what the stepper announces (its caption and value), such as "Columns 6". Never drawn on screen.
  ///
  /// In en, this message translates to:
  /// **'{label}, increase'**
  String stepperIncrease(String label);

  /// What a screen reader calls the down arrow of a stepper. {label} is what the stepper announces (its caption and value), such as "Columns 6". Never drawn on screen.
  ///
  /// In en, this message translates to:
  /// **'{label}, decrease'**
  String stepperDecrease(String label);

  /// The caption under the grid preview on the General tab when gaps are on: the grid's size and the largest gap a placement keeps (it shrinks for a window too small to keep it). {cols} and {rows} are the grid's size, and the × between them stays. {gap} is the gap, a whole number, and {unit} is pt on macOS and px on Windows and stays as written. English says "gaps" even for 1, because the word counts the gaps between cells; a language whose plural needs a form for one may add it.
  ///
  /// In en, this message translates to:
  /// **'{gap, plural, other{{cols} × {rows} · up to {gap} {unit} gaps}}'**
  String gridPreviewCaptionGaps(int cols, int rows, int gap, String unit);

  /// Shown inside a shortcut field while it listens for a key combination and no modifier key is held yet.
  ///
  /// In en, this message translates to:
  /// **'Press keys…'**
  String get recordingPressKeys;

  /// The version line on the About tab. {version} is the release name, such as 1.1.2 or 1.1.2-beta.1, or the version with its build number in brackets for a development build.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(String version);

  /// A line on the About tab when an update check found a newer release, above the Update button. {name} is the new version, such as 1.1.3. Orthant stays as written.
  ///
  /// In en, this message translates to:
  /// **'Orthant {name} is available.'**
  String aboutUpdateAvailable(String name);

  /// The button on the About tab that opens the updater's offer, shown only while an update is waiting.
  ///
  /// In en, this message translates to:
  /// **'Update…'**
  String get aboutUpdate;

  /// The button on the About tab that checks for a new version of the app.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates…'**
  String get aboutCheckForUpdates;

  /// The label of the About tab's checkbox that lets the app look for new versions on its own schedule.
  ///
  /// In en, this message translates to:
  /// **'Check for updates automatically'**
  String get aboutAutomaticChecks;

  /// The one-line description of the app at the foot of the About tab. It names no operating system.
  ///
  /// In en, this message translates to:
  /// **'A grid-based window manager.'**
  String get aboutTagline;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script+country codes are specified.
  switch (locale.toString()) {
    case 'zh_Hant_HK':
      return AppLocalizationsZhHantHk();
  }

  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
