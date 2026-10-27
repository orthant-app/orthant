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
}
