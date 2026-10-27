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
