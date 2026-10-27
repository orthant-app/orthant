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
  String get keyMacEscape => 'esc';

  @override
  String get keyMacReturn => 'Return';

  @override
  String keyNumpad(String key) {
    return 'Num $key';
  }

  @override
  String keyListAnyModifier(String a, String b, String c, String d) {
    return '$a、$b、$c 或 $d';
  }

  @override
  String get settingsTabGeneral => '通用';

  @override
  String get settingsTabShortcuts => '快捷键';

  @override
  String get settingsTabAbout => '关于';

  @override
  String settingsTabLabel(String tab) {
    return '$tab标签页';
  }

  @override
  String get generalGroupAccessibility => '无障碍';

  @override
  String get generalGroupOpenGrid => '打开网格';

  @override
  String get generalGroupGrid => '网格';

  @override
  String get generalGroupGaps => '间距';

  @override
  String get generalGroupStartup => '启动';

  @override
  String get generalGroupLanguage => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get generalLanguageUpdaterNote => '更新窗口会在下次启动 Orthant 时切换语言。';

  @override
  String get generalColumns => '列数';

  @override
  String get generalRows => '行数';

  @override
  String get generalGapSize => '大小';

  @override
  String get generalLeaveGaps => '留出间距';

  @override
  String get generalResetGridAndGaps => '重置网格与间距';

  @override
  String get generalAccessibilityGranted => '已授权';

  @override
  String get generalAccessibilityNotGranted => '未授权。快捷键和网格不会起作用。';

  @override
  String get generalOpenAccessibilitySettings => '打开无障碍设置…';

  @override
  String generalSummonUnavailable(String system) {
    return '$system 或其他应用已使用此组合键，因此 Orthant 收不到它。';
  }

  @override
  String get generalChange => '更改…';

  @override
  String get shortcutNotSet => '未设置';

  @override
  String get generalLaunchAtLogin => '登录时启动';

  @override
  String get generalLoginUnrecognisedMac =>
      'macOS 报告了 Orthant 无法识别的登录项状态。仍可尝试开启。';

  @override
  String get generalLoginUnrecognisedWindows =>
      'Windows 报告了 Orthant 无法识别的启动状态。仍可尝试开启。';

  @override
  String get generalLoginTurnedOffMac13 =>
      '已在“系统设置 ▸ 通用 ▸ 登录项”中关闭，因此 Orthant 不会自动启动。';

  @override
  String get generalLoginTurnedOffMac15 =>
      '已在“系统设置 ▸ 通用 ▸ 登录项与扩展”中关闭，因此 Orthant 不会自动启动。';

  @override
  String get generalLoginTurnedOffWindows =>
      '已在“设置 ▸ 应用 ▸ 启动”中关闭，因此 Orthant 不会自动启动。';

  @override
  String get generalOpenLoginItemsMac13 => '打开登录项…';

  @override
  String get generalOpenLoginItemsMac15 => '打开登录项与扩展…';

  @override
  String get generalOpenStartupApps => '打开启动应用…';

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
    return '$label，增加';
  }

  @override
  String stepperDecrease(String label) {
    return '$label，减少';
  }

  @override
  String gridPreviewCaptionGaps(int cols, int rows, int gap, String unit) {
    String _temp0 = intl.Intl.pluralLogic(
      gap,
      locale: localeName,
      other: '$cols × $rows · 间距最多 $gap $unit',
    );
    return '$_temp0';
  }

  @override
  String get recordingPressKeys => '按下按键…';

  @override
  String aboutVersion(String version) {
    return '版本 $version';
  }

  @override
  String aboutUpdateAvailable(String name) {
    return '有可用的新版本 Orthant $name。';
  }

  @override
  String get aboutUpdate => '更新…';

  @override
  String get aboutCheckForUpdates => '检查更新…';

  @override
  String get aboutAutomaticChecks => '自动检查更新';

  @override
  String get aboutTagline => '基于网格的窗口管理工具。';

  @override
  String get regionNameFullScreen => '全屏';

  @override
  String regionNameLeft(String fraction) {
    return '左 $fraction';
  }

  @override
  String regionNameRight(String fraction) {
    return '右 $fraction';
  }

  @override
  String regionNameTop(String fraction) {
    return '上 $fraction';
  }

  @override
  String regionNameBottom(String fraction) {
    return '下 $fraction';
  }

  @override
  String get regionNameCustom => '自定义区域';

  @override
  String get regionSheetTitleNew => '新建区域';

  @override
  String get regionSheetTitleEdit => '编辑区域';

  @override
  String regionSheetHint(String shift) {
    return '拖动绘制 · 方向键移动，$shift 扩展';
  }

  @override
  String get regionSheetName => '名称';

  @override
  String get regionSheetShortcut => '快捷键';

  @override
  String get regionSheetRecordNone => '录制快捷键，当前未设置';

  @override
  String regionSheetRecordCurrent(String combo) {
    return '录制快捷键，当前为 $combo';
  }

  @override
  String get regionSheetClickToRecord => '点击以录制';

  @override
  String regionSheetConflict(String command) {
    return '$command 已使用此组合键。';
  }

  @override
  String regionSheetConflictTaking(String command) {
    return '保存后，$command 将不再使用此组合键。';
  }

  @override
  String get regionSheetUseHere => '在此使用';

  @override
  String get regionSheetUseHereLabel => '在此使用该组合键';

  @override
  String get regionSheetCancel => '取消';

  @override
  String get regionSheetDelete => '删除';

  @override
  String get regionSheetDeleteLabel => '删除区域';

  @override
  String get regionSheetAdd => '添加';

  @override
  String get regionSheetAddLabel => '添加区域';

  @override
  String get regionSheetSave => '保存';

  @override
  String get regionSheetSaveLabel => '保存区域';
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
  String get keyMacEscape => 'esc';

  @override
  String get keyMacReturn => 'Return';

  @override
  String keyNumpad(String key) {
    return 'Num $key';
  }

  @override
  String keyListAnyModifier(String a, String b, String c, String d) {
    return '$a、$b、$c 或 $d';
  }

  @override
  String get settingsTabGeneral => '一般';

  @override
  String get settingsTabShortcuts => '快速鍵';

  @override
  String get settingsTabAbout => '關於';

  @override
  String settingsTabLabel(String tab) {
    return '$tab標籤頁';
  }

  @override
  String get generalGroupAccessibility => '輔助使用';

  @override
  String get generalGroupOpenGrid => '開啟格線';

  @override
  String get generalGroupGrid => '格線';

  @override
  String get generalGroupGaps => '間距';

  @override
  String get generalGroupStartup => '啟動';

  @override
  String get generalGroupLanguage => '語言';

  @override
  String get languageSystem => '跟隨系統';

  @override
  String get generalLanguageUpdaterNote => '更新視窗會在下次啟動 Orthant 時切換語言。';

  @override
  String get generalColumns => '欄數';

  @override
  String get generalRows => '列數';

  @override
  String get generalGapSize => '大小';

  @override
  String get generalLeaveGaps => '留出間距';

  @override
  String get generalResetGridAndGaps => '重設格線與間距';

  @override
  String get generalAccessibilityGranted => '已授權';

  @override
  String get generalAccessibilityNotGranted => '未授權。快速鍵和格線不會有作用。';

  @override
  String get generalOpenAccessibilitySettings => '開啟輔助使用設定…';

  @override
  String generalSummonUnavailable(String system) {
    return '$system 或其他應用程式已使用此組合鍵，因此 Orthant 收不到它。';
  }

  @override
  String get generalChange => '更改…';

  @override
  String get shortcutNotSet => '未設定';

  @override
  String get generalLaunchAtLogin => '登入時啟動';

  @override
  String get generalLoginUnrecognisedMac =>
      'macOS 回報了 Orthant 無法辨識的登入項目狀態。仍可嘗試開啟。';

  @override
  String get generalLoginUnrecognisedWindows =>
      'Windows 回報了 Orthant 無法辨識的啟動狀態。仍可嘗試開啟。';

  @override
  String get generalLoginTurnedOffMac13 =>
      '已在「系統設定 ▸ 一般 ▸ 登入項目」中關閉，因此 Orthant 不會自動啟動。';

  @override
  String get generalLoginTurnedOffMac15 =>
      '已在「系統設定 ▸ 一般 ▸ 登入項目與延伸功能」中關閉，因此 Orthant 不會自動啟動。';

  @override
  String get generalLoginTurnedOffWindows =>
      '已在「設定 ▸ 應用程式 ▸ 啟動」中關閉，因此 Orthant 不會自動啟動。';

  @override
  String get generalOpenLoginItemsMac13 => '開啟登入項目…';

  @override
  String get generalOpenLoginItemsMac15 => '開啟登入項目與延伸功能…';

  @override
  String get generalOpenStartupApps => '開啟啟動應用程式…';

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
    return '$label，增加';
  }

  @override
  String stepperDecrease(String label) {
    return '$label，減少';
  }

  @override
  String gridPreviewCaptionGaps(int cols, int rows, int gap, String unit) {
    String _temp0 = intl.Intl.pluralLogic(
      gap,
      locale: localeName,
      other: '$cols × $rows · 間距最多 $gap $unit',
    );
    return '$_temp0';
  }

  @override
  String get recordingPressKeys => '按下按鍵…';

  @override
  String aboutVersion(String version) {
    return '版本 $version';
  }

  @override
  String aboutUpdateAvailable(String name) {
    return '有可用的新版本 Orthant $name。';
  }

  @override
  String get aboutUpdate => '更新…';

  @override
  String get aboutCheckForUpdates => '檢查更新…';

  @override
  String get aboutAutomaticChecks => '自動檢查更新';

  @override
  String get aboutTagline => '以格線為基礎的視窗管理工具。';

  @override
  String get regionNameFullScreen => '全螢幕';

  @override
  String regionNameLeft(String fraction) {
    return '左 $fraction';
  }

  @override
  String regionNameRight(String fraction) {
    return '右 $fraction';
  }

  @override
  String regionNameTop(String fraction) {
    return '上 $fraction';
  }

  @override
  String regionNameBottom(String fraction) {
    return '下 $fraction';
  }

  @override
  String get regionNameCustom => '自訂區域';

  @override
  String get regionSheetTitleNew => '新增區域';

  @override
  String get regionSheetTitleEdit => '編輯區域';

  @override
  String regionSheetHint(String shift) {
    return '拖曳繪製 · 方向鍵移動，$shift 擴展';
  }

  @override
  String get regionSheetName => '名稱';

  @override
  String get regionSheetShortcut => '快速鍵';

  @override
  String get regionSheetRecordNone => '錄製快速鍵，目前未設定';

  @override
  String regionSheetRecordCurrent(String combo) {
    return '錄製快速鍵，目前為 $combo';
  }

  @override
  String get regionSheetClickToRecord => '按一下以錄製';

  @override
  String regionSheetConflict(String command) {
    return '$command 已使用此組合鍵。';
  }

  @override
  String regionSheetConflictTaking(String command) {
    return '儲存後，$command 將不再使用此組合鍵。';
  }

  @override
  String get regionSheetUseHere => '在此使用';

  @override
  String get regionSheetUseHereLabel => '在此使用該組合鍵';

  @override
  String get regionSheetCancel => '取消';

  @override
  String get regionSheetDelete => '刪除';

  @override
  String get regionSheetDeleteLabel => '刪除區域';

  @override
  String get regionSheetAdd => '新增';

  @override
  String get regionSheetAddLabel => '新增區域';

  @override
  String get regionSheetSave => '儲存';

  @override
  String get regionSheetSaveLabel => '儲存區域';
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
  String get keyMacEscape => 'esc';

  @override
  String get keyMacReturn => 'Return';

  @override
  String keyNumpad(String key) {
    return 'Num $key';
  }

  @override
  String keyListAnyModifier(String a, String b, String c, String d) {
    return '$a、$b、$c 或 $d';
  }

  @override
  String get settingsTabGeneral => '一般';

  @override
  String get settingsTabShortcuts => '快速鍵';

  @override
  String get settingsTabAbout => '關於';

  @override
  String settingsTabLabel(String tab) {
    return '$tab標籤頁';
  }

  @override
  String get generalGroupAccessibility => '輔助使用';

  @override
  String get generalGroupOpenGrid => '開啟格線';

  @override
  String get generalGroupGrid => '格線';

  @override
  String get generalGroupGaps => '間距';

  @override
  String get generalGroupStartup => '啟動';

  @override
  String get generalGroupLanguage => '語言';

  @override
  String get languageSystem => '跟隨系統';

  @override
  String get generalLanguageUpdaterNote => '更新視窗會在下次啟動 Orthant 時切換語言。';

  @override
  String get generalColumns => '欄數';

  @override
  String get generalRows => '列數';

  @override
  String get generalGapSize => '大小';

  @override
  String get generalLeaveGaps => '留出間距';

  @override
  String get generalResetGridAndGaps => '重設格線與間距';

  @override
  String get generalAccessibilityGranted => '已授權';

  @override
  String get generalAccessibilityNotGranted => '未授權。快速鍵和格線不會有作用。';

  @override
  String get generalOpenAccessibilitySettings => '開啟輔助使用設定…';

  @override
  String generalSummonUnavailable(String system) {
    return '$system 或其他應用程式已使用此組合鍵，因此 Orthant 收不到它。';
  }

  @override
  String get generalChange => '更改…';

  @override
  String get shortcutNotSet => '未設定';

  @override
  String get generalLaunchAtLogin => '登入時啟動';

  @override
  String get generalLoginUnrecognisedMac =>
      'macOS 回報了 Orthant 無法辨識的登入項目狀態。仍可嘗試開啟。';

  @override
  String get generalLoginUnrecognisedWindows =>
      'Windows 回報了 Orthant 無法辨識的啟動狀態。仍可嘗試開啟。';

  @override
  String get generalLoginTurnedOffMac13 =>
      '已在「系統設定 ▸ 一般 ▸ 登入項目」中關閉，因此 Orthant 不會自動啟動。';

  @override
  String get generalLoginTurnedOffMac15 =>
      '已在「系統設定 ▸ 一般 ▸ 登入項目與延伸功能」中關閉，因此 Orthant 不會自動啟動。';

  @override
  String get generalLoginTurnedOffWindows =>
      '已在「設定 ▸ 應用程式 ▸ 啟動」中關閉，因此 Orthant 不會自動啟動。';

  @override
  String get generalOpenLoginItemsMac13 => '開啟登入項目…';

  @override
  String get generalOpenLoginItemsMac15 => '開啟登入項目與延伸功能…';

  @override
  String get generalOpenStartupApps => '開啟啟動應用程式…';

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
    return '$label，增加';
  }

  @override
  String stepperDecrease(String label) {
    return '$label，減少';
  }

  @override
  String gridPreviewCaptionGaps(int cols, int rows, int gap, String unit) {
    String _temp0 = intl.Intl.pluralLogic(
      gap,
      locale: localeName,
      other: '$cols × $rows · 間距最多 $gap $unit',
    );
    return '$_temp0';
  }

  @override
  String get recordingPressKeys => '按下按鍵…';

  @override
  String aboutVersion(String version) {
    return '版本 $version';
  }

  @override
  String aboutUpdateAvailable(String name) {
    return '有可用的新版本 Orthant $name。';
  }

  @override
  String get aboutUpdate => '更新…';

  @override
  String get aboutCheckForUpdates => '檢查更新…';

  @override
  String get aboutAutomaticChecks => '自動檢查更新';

  @override
  String get aboutTagline => '以格線為基礎的視窗管理工具。';

  @override
  String get regionNameFullScreen => '全螢幕';

  @override
  String regionNameLeft(String fraction) {
    return '左 $fraction';
  }

  @override
  String regionNameRight(String fraction) {
    return '右 $fraction';
  }

  @override
  String regionNameTop(String fraction) {
    return '上 $fraction';
  }

  @override
  String regionNameBottom(String fraction) {
    return '下 $fraction';
  }

  @override
  String get regionNameCustom => '自訂區域';

  @override
  String get regionSheetTitleNew => '新增區域';

  @override
  String get regionSheetTitleEdit => '編輯區域';

  @override
  String regionSheetHint(String shift) {
    return '拖曳繪製 · 方向鍵移動，$shift 擴展';
  }

  @override
  String get regionSheetName => '名稱';

  @override
  String get regionSheetShortcut => '快速鍵';

  @override
  String get regionSheetRecordNone => '錄製快速鍵，目前未設定';

  @override
  String regionSheetRecordCurrent(String combo) {
    return '錄製快速鍵，目前為 $combo';
  }

  @override
  String get regionSheetClickToRecord => '按一下以錄製';

  @override
  String regionSheetConflict(String command) {
    return '$command 已使用此組合鍵。';
  }

  @override
  String regionSheetConflictTaking(String command) {
    return '儲存後，$command 將不再使用此組合鍵。';
  }

  @override
  String get regionSheetUseHere => '在此使用';

  @override
  String get regionSheetUseHereLabel => '在此使用該組合鍵';

  @override
  String get regionSheetCancel => '取消';

  @override
  String get regionSheetDelete => '刪除';

  @override
  String get regionSheetDeleteLabel => '刪除區域';

  @override
  String get regionSheetAdd => '新增';

  @override
  String get regionSheetAddLabel => '新增區域';

  @override
  String get regionSheetSave => '儲存';

  @override
  String get regionSheetSaveLabel => '儲存區域';
}
