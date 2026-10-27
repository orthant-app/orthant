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

  @override
  String overlaySaveHint(String key) {
    return '$key  将此区域保存为快捷键';
  }

  @override
  String overlayGridHint(String place) {
    return '方向键移动选区。Shift 加方向键扩展选区。$place 放置窗口。Esc 取消。';
  }

  @override
  String overlayOpened(
    String target,
    String columns,
    String rows,
    String place,
  ) {
    return '已为$target打开网格。$columns，$rows。方向键移动，Shift 加方向键扩展，$place 放置，Esc 取消。';
  }

  @override
  String get overlayCapturedWindow => '当前窗口';

  @override
  String overlayColumns(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 列',
    );
    return '$_temp0';
  }

  @override
  String overlayRows(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 行',
    );
    return '$_temp0';
  }

  @override
  String overlayGridLabel(String app, String columns, String rows) {
    return '$app的窗口网格，$columns，$rows';
  }

  @override
  String get overlayGridClosed => '网格已关闭。';

  @override
  String get overlayPlacingWindow => '正在放置窗口。';

  @override
  String get overlayNoCellsSelected => '未选择任何格子。';

  @override
  String overlayRowOne(int row) {
    return '第 $row 行';
  }

  @override
  String overlayRowRange(int first, int last) {
    return '第 $first 至 $last 行';
  }

  @override
  String overlayColumnOne(int column) {
    return '第 $column 列';
  }

  @override
  String overlayColumnRange(int first, int last) {
    return '第 $first 至 $last 列';
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
    return '$rowText，$columnText。目标：x $x，y $y，宽 $width，高 $height，单位为$unit。';
  }

  @override
  String get overlayUnitPoints => '点';

  @override
  String get overlayUnitPixels => '像素';

  @override
  String overlayMove(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'left': '向左移动',
      'right': '向右移动',
      'up': '向上移动',
      'down': '向下移动',
      'other': '移动',
    });
    return '$_temp0';
  }

  @override
  String overlayExtend(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'left': '向左扩展',
      'right': '向右扩展',
      'up': '向上扩展',
      'down': '向下扩展',
      'other': '扩展',
    });
    return '$_temp0';
  }

  @override
  String get overlayPlaceWindow => '放置窗口';

  @override
  String get overlayPlaceAndSave => '放置窗口并保存快捷键';

  @override
  String get overlayCancelGrid => '取消网格';

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
  String keyNumpad(String key) {
    return 'Num $key';
  }

  @override
  String keyListAnyModifier(String a, String b, String c, String d) {
    return '$a、$b、$c 或 $d';
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

  @override
  String overlaySaveHint(String key) {
    return '$key  將此區域儲存為快速鍵';
  }

  @override
  String overlayGridHint(String place) {
    return '方向鍵移動選取範圍。Shift 加方向鍵擴展選取範圍。$place 放置視窗。Esc 取消。';
  }

  @override
  String overlayOpened(
    String target,
    String columns,
    String rows,
    String place,
  ) {
    return '已為$target開啟格線。$columns，$rows。方向鍵移動，Shift 加方向鍵擴展，$place 放置，Esc 取消。';
  }

  @override
  String get overlayCapturedWindow => '目前的視窗';

  @override
  String overlayColumns(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 欄',
    );
    return '$_temp0';
  }

  @override
  String overlayRows(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 列',
    );
    return '$_temp0';
  }

  @override
  String overlayGridLabel(String app, String columns, String rows) {
    return '$app的視窗格線，$columns，$rows';
  }

  @override
  String get overlayGridClosed => '格線已關閉。';

  @override
  String get overlayPlacingWindow => '正在放置視窗。';

  @override
  String get overlayNoCellsSelected => '未選取任何格子。';

  @override
  String overlayRowOne(int row) {
    return '第 $row 列';
  }

  @override
  String overlayRowRange(int first, int last) {
    return '第 $first 至 $last 列';
  }

  @override
  String overlayColumnOne(int column) {
    return '第 $column 欄';
  }

  @override
  String overlayColumnRange(int first, int last) {
    return '第 $first 至 $last 欄';
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
    return '$rowText，$columnText。目標：x $x，y $y，寬 $width，高 $height，單位為$unit。';
  }

  @override
  String get overlayUnitPoints => '點';

  @override
  String get overlayUnitPixels => '像素';

  @override
  String overlayMove(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'left': '向左移動',
      'right': '向右移動',
      'up': '向上移動',
      'down': '向下移動',
      'other': '移動',
    });
    return '$_temp0';
  }

  @override
  String overlayExtend(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'left': '向左擴展',
      'right': '向右擴展',
      'up': '向上擴展',
      'down': '向下擴展',
      'other': '擴展',
    });
    return '$_temp0';
  }

  @override
  String get overlayPlaceWindow => '放置視窗';

  @override
  String get overlayPlaceAndSave => '放置視窗並儲存快速鍵';

  @override
  String get overlayCancelGrid => '取消格線';

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
  String keyNumpad(String key) {
    return 'Num $key';
  }

  @override
  String keyListAnyModifier(String a, String b, String c, String d) {
    return '$a、$b、$c 或 $d';
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

  @override
  String overlaySaveHint(String key) {
    return '$key  將此區域儲存為快速鍵';
  }

  @override
  String overlayGridHint(String place) {
    return '方向鍵移動選取範圍。Shift 加方向鍵擴展選取範圍。$place 放置視窗。Esc 取消。';
  }

  @override
  String overlayOpened(
    String target,
    String columns,
    String rows,
    String place,
  ) {
    return '已為$target開啟格線。$columns，$rows。方向鍵移動，Shift 加方向鍵擴展，$place 放置，Esc 取消。';
  }

  @override
  String get overlayCapturedWindow => '目前的視窗';

  @override
  String overlayColumns(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 欄',
    );
    return '$_temp0';
  }

  @override
  String overlayRows(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 列',
    );
    return '$_temp0';
  }

  @override
  String overlayGridLabel(String app, String columns, String rows) {
    return '$app的視窗格線，$columns，$rows';
  }

  @override
  String get overlayGridClosed => '格線已關閉。';

  @override
  String get overlayPlacingWindow => '正在放置視窗。';

  @override
  String get overlayNoCellsSelected => '未選取任何格子。';

  @override
  String overlayRowOne(int row) {
    return '第 $row 列';
  }

  @override
  String overlayRowRange(int first, int last) {
    return '第 $first 至 $last 列';
  }

  @override
  String overlayColumnOne(int column) {
    return '第 $column 欄';
  }

  @override
  String overlayColumnRange(int first, int last) {
    return '第 $first 至 $last 欄';
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
    return '$rowText，$columnText。目標：x $x，y $y，寬 $width，高 $height，單位為$unit。';
  }

  @override
  String get overlayUnitPoints => '點';

  @override
  String get overlayUnitPixels => '像素';

  @override
  String overlayMove(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'left': '向左移動',
      'right': '向右移動',
      'up': '向上移動',
      'down': '向下移動',
      'other': '移動',
    });
    return '$_temp0';
  }

  @override
  String overlayExtend(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'left': '向左擴展',
      'right': '向右擴展',
      'up': '向上擴展',
      'down': '向下擴展',
      'other': '擴展',
    });
    return '$_temp0';
  }

  @override
  String get overlayPlaceWindow => '放置視窗';

  @override
  String get overlayPlaceAndSave => '放置視窗並儲存快速鍵';

  @override
  String get overlayCancelGrid => '取消格線';

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
  String keyNumpad(String key) {
    return 'Num $key';
  }

  @override
  String keyListAnyModifier(String a, String b, String c, String d) {
    return '$a、$b、$c 或 $d';
  }
}
