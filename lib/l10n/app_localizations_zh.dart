// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get l10nProbeLocale => 'zh';

  @override
  String get l10nProbeScript => 'Hans';

  @override
  String get languageNativeName => '简体中文';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get l10nProbeLocale => 'zh_Hant';

  @override
  String get l10nProbeScript => 'Hant';

  @override
  String get languageNativeName => '繁體中文';
}

/// The translations for Chinese, as used in Hong Kong, using the Han script (`zh_Hant_HK`).
class AppLocalizationsZhHantHk extends AppLocalizationsZh {
  AppLocalizationsZhHantHk() : super('zh_Hant_HK');

  @override
  String get l10nProbeLocale => 'zh_Hant_HK';

  @override
  String get l10nProbeScript => 'Hant';

  @override
  String get languageNativeName => '繁體中文';
}
