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

  @override
  String get trayEnableAccessibility => '启用无障碍…';

  @override
  String get trayOpenGrid => '打开网格';

  @override
  String get traySettings => '设置…';

  @override
  String get trayAbout => '关于 Orthant';

  @override
  String trayUpdateTo(String version) {
    return '更新到 Orthant $version…';
  }

  @override
  String get trayCheckForUpdates => '检查更新…';

  @override
  String get trayQuit => '退出 Orthant';

  @override
  String trayTooltipUpdate(String version) {
    return 'Orthant：有可用更新 $version';
  }
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

  @override
  String get trayEnableAccessibility => '啟用輔助使用…';

  @override
  String get trayOpenGrid => '開啟格線';

  @override
  String get traySettings => '設定…';

  @override
  String get trayAbout => '關於 Orthant';

  @override
  String trayUpdateTo(String version) {
    return '更新至 Orthant $version…';
  }

  @override
  String get trayCheckForUpdates => '檢查更新…';

  @override
  String get trayQuit => '結束 Orthant';

  @override
  String trayTooltipUpdate(String version) {
    return 'Orthant：有可用的更新 $version';
  }
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

  @override
  String get trayEnableAccessibility => '啟用輔助使用…';

  @override
  String get trayOpenGrid => '開啟格線';

  @override
  String get traySettings => '設定…';

  @override
  String get trayAbout => '關於 Orthant';

  @override
  String trayUpdateTo(String version) {
    return '更新至 Orthant $version…';
  }

  @override
  String get trayCheckForUpdates => '檢查更新…';

  @override
  String get trayQuit => '結束 Orthant';

  @override
  String trayTooltipUpdate(String version) {
    return 'Orthant：有可用的更新 $version';
  }
}
