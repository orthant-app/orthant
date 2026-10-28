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
  String get trayEnableAccessibility => '开启辅助功能权限…';

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
    return 'Orthant: 有可用更新 $version';
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
  String get keySpace => '空格键';

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
  String get generalGroupAccessibility => '辅助功能';

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
  String get generalLanguageRelaunchNoteMac => '菜单栏和更新窗口会在下次启动 Orthant 时切换语言。';

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
  String get generalOpenAccessibilitySettings => '打开辅助功能设置…';

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
    return '有新版本可用：Orthant $name。';
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
    return '左侧 $fraction';
  }

  @override
  String regionNameRight(String fraction) {
    return '右侧 $fraction';
  }

  @override
  String regionNameTop(String fraction) {
    return '顶部 $fraction';
  }

  @override
  String regionNameBottom(String fraction) {
    return '底部 $fraction';
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
    return '“$command”已使用此组合键。';
  }

  @override
  String regionSheetConflictTaking(String command) {
    return '保存后，“$command”将不再使用此组合键。';
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

  @override
  String get commandOpenGrid => '打开网格';

  @override
  String get commandLeftHalf => '左半屏';

  @override
  String get commandRightHalf => '右半屏';

  @override
  String get commandTopHalf => '上半屏';

  @override
  String get commandBottomHalf => '下半屏';

  @override
  String get commandTopLeft => '左上四分之一';

  @override
  String get commandTopRight => '右上四分之一';

  @override
  String get commandBottomLeft => '左下四分之一';

  @override
  String get commandBottomRight => '右下四分之一';

  @override
  String get commandMaximize => '最大化';

  @override
  String get commandCenter => '居中';

  @override
  String get shortcutsTitle => '快捷键';

  @override
  String get shortcutsSubtitle => '打开网格，或将最前面的窗口直接放到它所在显示器的某个区域。';

  @override
  String get shortcutsGroupBuiltIn => '内置';

  @override
  String get shortcutsGroupRegions => '你的区域';

  @override
  String shortcutsRegionsHint(String key) {
    return '为内置项没有的形状绑定快捷键。可在此绘制，也可在网格中选中后按 $key。';
  }

  @override
  String get shortcutsNotGranted =>
      '在 Orthant 获得辅助功能权限之前，这些快捷键都不会生效。你仍然可以更改它们。';

  @override
  String shortcutsListening(String escape) {
    return '正在录制，请按下组合键，或按 $escape 取消。';
  }

  @override
  String shortcutsHint(String modifiers) {
    return '点击快捷键即可更改。组合键须包含 $modifiers 之一。';
  }

  @override
  String shortcutsCollision(String combo, String owner) {
    return '$combo 已被“$owner”使用。再按一次即可在此使用。';
  }

  @override
  String get shortcutsUseHere => '在此使用';

  @override
  String shortcutsDisplaced(String command, String combo) {
    return '“$command”不再使用 $combo。';
  }

  @override
  String get shortcutsUndo => '撤销';

  @override
  String shortcutsRegionDeleted(String name) {
    return '已删除“$name”。';
  }

  @override
  String get shortcutsResetDone => '所有快捷键已恢复为默认设置。';

  @override
  String get shortcutsReset => '重置快捷键';

  @override
  String get shortcutsAddRegion => '添加区域…';

  @override
  String get shortcutsAddRegionLabel => '添加区域';

  @override
  String shortcutsEditRegion(String name) {
    return '编辑 $name';
  }

  @override
  String get shortcutsClickToSet => '点击以设置';

  @override
  String get shortcutsRemove => '移除快捷键';

  @override
  String shortcutsRemoveLabel(String command) {
    return '移除 $command 的快捷键';
  }

  @override
  String shortcutsUnavailableTooltip(String system) {
    return '$system 或其他应用已使用此组合键，因此 Orthant 收不到它。\n点击该快捷键可另选一个。';
  }

  @override
  String shortcutRowBound(String command, String combo) {
    return '$command，$combo';
  }

  @override
  String shortcutRowUnbound(String command) {
    return '$command，未设置快捷键';
  }

  @override
  String shortcutRowUnavailable(String command, String combo) {
    return '$command，$combo，不可用';
  }

  @override
  String shortcutRowListening(String command) {
    return '$command，等待输入组合键';
  }

  @override
  String shortcutRowCollision(String command, String combo, String owner) {
    return '$command，$combo 已被 $owner 使用。再按一次即可在此使用，或按 Esc 取消。';
  }

  @override
  String get refusalKeypad => 'Windows 无法在快捷键中使用小键盘的数字、小数点或 =。';

  @override
  String get refusalUnregistrable => 'Windows 无法在快捷键中使用该按键。';

  @override
  String get onboardingTitle => 'Orthant 需要辅助功能权限';

  @override
  String get onboardingBody =>
      'Orthant 借助 macOS 的辅助功能来移动你的窗口。请在“隐私与安全性 ▸ 辅助功能”中启用“Orthant”，Orthant 会立即检测到。';

  @override
  String get onboardingBodyMac27 =>
      'Orthant 借助 macOS 的无障碍功能来移动你的窗口。请在“隐私与安全 ▸ 设备控制和数据访问”中启用“Orthant”，Orthant 会立即检测到。';

  @override
  String get onboardingOpenAccessibility => '打开辅助功能设置';

  @override
  String get onboardingGranted => '已授权';

  @override
  String get onboardingWaiting => '正在等待授权…';

  @override
  String get readyTitle => 'Orthant 已就绪';

  @override
  String get readySubtitle => '两种方式，把窗口放到你想要的位置。';

  @override
  String readyGridCaption(String shift, String place) {
    return '打开网格。在网格上拖动，就能选取任意区域，三分之一、三分之二都行。也可以用方向键移动，$shift 加方向键扩展，$place 放置。';
  }

  @override
  String get readyDirectCaption =>
      '直接将窗口放到半屏、四分之一屏或全屏，无需瞄准。还可以添加自己的形状，比如图中第三个。';

  @override
  String get readyChangeShortcuts => '更改这些快捷键…';

  @override
  String get readyDone => '完成';

  @override
  String get readyNoShortcutSet => '未设置快捷键';

  @override
  String readyUnavailableTooltip(String system) {
    return '$system 或其他应用已使用此组合键，因此 Orthant 收不到它。\n请在下方另选一个。';
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
  String get trayEnableAccessibility => '啟用輔助使用⋯';

  @override
  String get trayOpenGrid => '開啟格線';

  @override
  String get traySettings => '設定⋯';

  @override
  String get trayAbout => '關於 Orthant';

  @override
  String trayUpdateTo(String version) {
    return '更新至 Orthant $version⋯';
  }

  @override
  String get trayCheckForUpdates => '檢查更新⋯';

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
    return '方向鍵移動選取範圍。Shift 加方向鍵延伸選取範圍。$place 放置視窗。Esc 取消。';
  }

  @override
  String overlayOpened(
    String target,
    String columns,
    String rows,
    String place,
  ) {
    return '已為$target開啟格線。$columns，$rows。方向鍵移動，Shift 加方向鍵延伸，$place 放置，Esc 取消。';
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
      'left': '向左延伸',
      'right': '向右延伸',
      'up': '向上延伸',
      'down': '向下延伸',
      'other': '延伸',
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
  String get generalLanguageRelaunchNoteMac => '選單列和更新視窗會在下次啟動 Orthant 時切換語言。';

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
  String get generalOpenAccessibilitySettings => '開啟輔助使用設定⋯';

  @override
  String generalSummonUnavailable(String system) {
    return '$system 或其他應用程式已在使用此組合鍵，因此 Orthant 接收不到。';
  }

  @override
  String get generalChange => '更改⋯';

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
  String get generalOpenLoginItemsMac13 => '開啟登入項目⋯';

  @override
  String get generalOpenLoginItemsMac15 => '開啟登入項目與延伸功能⋯';

  @override
  String get generalOpenStartupApps => '開啟啟動應用程式⋯';

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
  String get recordingPressKeys => '按下按鍵⋯';

  @override
  String aboutVersion(String version) {
    return '版本 $version';
  }

  @override
  String aboutUpdateAvailable(String name) {
    return '有可用的新版本 Orthant $name。';
  }

  @override
  String get aboutUpdate => '更新⋯';

  @override
  String get aboutCheckForUpdates => '檢查更新⋯';

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
    return '拖曳繪製 · 方向鍵移動，$shift 延伸';
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
    return '「$command」已使用此組合鍵。';
  }

  @override
  String regionSheetConflictTaking(String command) {
    return '儲存後，「$command」將不再使用此組合鍵。';
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

  @override
  String get commandOpenGrid => '開啟格線';

  @override
  String get commandLeftHalf => '左半部';

  @override
  String get commandRightHalf => '右半部';

  @override
  String get commandTopHalf => '上半部';

  @override
  String get commandBottomHalf => '下半部';

  @override
  String get commandTopLeft => '左上四分之一';

  @override
  String get commandTopRight => '右上四分之一';

  @override
  String get commandBottomLeft => '左下四分之一';

  @override
  String get commandBottomRight => '右下四分之一';

  @override
  String get commandMaximize => '最大化';

  @override
  String get commandCenter => '置中';

  @override
  String get shortcutsTitle => '快速鍵';

  @override
  String get shortcutsSubtitle => '開啟格線，或將最前方的視窗直接放到它所在顯示器的某個區域。';

  @override
  String get shortcutsGroupBuiltIn => '內建';

  @override
  String get shortcutsGroupRegions => '你的區域';

  @override
  String shortcutsRegionsHint(String key) {
    return '為內建項目沒有的形狀綁定快速鍵。可在此繪製，也可在格線中選取後按 $key。';
  }

  @override
  String get shortcutsNotGranted =>
      '在 Orthant 取得輔助使用權限之前，這些快速鍵都不會生效。你仍然可以更改它們。';

  @override
  String shortcutsListening(String escape) {
    return '正在錄製⋯按下組合鍵，或按 $escape 取消。';
  }

  @override
  String shortcutsHint(String modifiers) {
    return '按一下快速鍵即可更改。組合鍵須包含 $modifiers 其中之一。';
  }

  @override
  String shortcutsCollision(String combo, String owner) {
    return '$combo 已被「$owner」使用。再按一次即可在此使用。';
  }

  @override
  String get shortcutsUseHere => '在此使用';

  @override
  String shortcutsDisplaced(String command, String combo) {
    return '「$command」不再使用 $combo。';
  }

  @override
  String get shortcutsUndo => '復原';

  @override
  String shortcutsRegionDeleted(String name) {
    return '已刪除「$name」。';
  }

  @override
  String get shortcutsResetDone => '所有快速鍵已還原為預設值。';

  @override
  String get shortcutsReset => '重設快速鍵';

  @override
  String get shortcutsAddRegion => '新增區域⋯';

  @override
  String get shortcutsAddRegionLabel => '新增區域';

  @override
  String shortcutsEditRegion(String name) {
    return '編輯 $name';
  }

  @override
  String get shortcutsClickToSet => '按一下以設定';

  @override
  String get shortcutsRemove => '移除快速鍵';

  @override
  String shortcutsRemoveLabel(String command) {
    return '移除 $command 的快速鍵';
  }

  @override
  String shortcutsUnavailableTooltip(String system) {
    return '$system 或其他應用程式已在使用此組合鍵，因此 Orthant 接收不到。\n按一下該快速鍵可另選一個。';
  }

  @override
  String shortcutRowBound(String command, String combo) {
    return '$command，$combo';
  }

  @override
  String shortcutRowUnbound(String command) {
    return '$command，未設定快速鍵';
  }

  @override
  String shortcutRowUnavailable(String command, String combo) {
    return '$command，$combo，不可用';
  }

  @override
  String shortcutRowListening(String command) {
    return '$command，等待輸入組合鍵';
  }

  @override
  String shortcutRowCollision(String command, String combo, String owner) {
    return '$command，$combo 已被 $owner 使用。再按一次即可在此使用，或按 Esc 取消。';
  }

  @override
  String get refusalKeypad => 'Windows 無法在快速鍵中使用數字鍵盤的數字、小數點或 =。';

  @override
  String get refusalUnregistrable => 'Windows 無法在快速鍵中使用該按鍵。';

  @override
  String get onboardingTitle => 'Orthant 需要輔助使用權限';

  @override
  String get onboardingBody =>
      'Orthant 透過 macOS 的輔助使用功能來移動你的視窗。請在「隱私權與安全性 ▸ 輔助使用」中啟用「Orthant」，Orthant 會立即偵測到。';

  @override
  String get onboardingBodyMac27 =>
      'Orthant 透過 macOS 的輔助使用功能來移動你的視窗。請在「隱私權與安全性 ▸ 裝置控制和資料取用」中啟用「Orthant」，Orthant 會立即偵測到。';

  @override
  String get onboardingOpenAccessibility => '開啟輔助使用設定';

  @override
  String get onboardingGranted => '已授權';

  @override
  String get onboardingWaiting => '正在等待授權⋯';

  @override
  String get readyTitle => 'Orthant 已就緒';

  @override
  String get readySubtitle => '兩種方式，把視窗放到你想要的位置。';

  @override
  String readyGridCaption(String shift, String place) {
    return '開啟格線。在格線上拖曳，就能選取任意區域，三分之一、三分之二都行。也可以用方向鍵移動，$shift 加方向鍵延伸，$place 放置。';
  }

  @override
  String get readyDirectCaption => '直接將視窗放成一半、四分之一或全螢幕。不必瞄準，還可以新增自己的形狀，例如第三個。';

  @override
  String get readyChangeShortcuts => '更改這些快速鍵⋯';

  @override
  String get readyDone => '完成';

  @override
  String get readyNoShortcutSet => '未設定快速鍵';

  @override
  String readyUnavailableTooltip(String system) {
    return '$system 或其他應用程式已在使用此組合鍵，因此 Orthant 接收不到。\n請在下方另選一個。';
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
  String get trayEnableAccessibility => '啟用輔助使用⋯';

  @override
  String get trayOpenGrid => '開啟格線';

  @override
  String get traySettings => '設定⋯';

  @override
  String get trayAbout => '關於 Orthant';

  @override
  String trayUpdateTo(String version) {
    return '更新至 Orthant $version⋯';
  }

  @override
  String get trayCheckForUpdates => '檢查更新⋯';

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
    return '方向鍵移動選取範圍。Shift 加方向鍵延伸選取範圍。$place 放置視窗。Esc 取消。';
  }

  @override
  String overlayOpened(
    String target,
    String columns,
    String rows,
    String place,
  ) {
    return '已為$target開啟格線。$columns，$rows。方向鍵移動，Shift 加方向鍵延伸，$place 放置，Esc 取消。';
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
      'left': '向左延伸',
      'right': '向右延伸',
      'up': '向上延伸',
      'down': '向下延伸',
      'other': '延伸',
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
  String get generalLanguageRelaunchNoteMac => '選單列和更新視窗會在下次啟動 Orthant 時切換語言。';

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
  String get generalOpenAccessibilitySettings => '開啟輔助使用設定⋯';

  @override
  String generalSummonUnavailable(String system) {
    return '$system 或其他應用程式已在使用此組合鍵，因此 Orthant 接收不到。';
  }

  @override
  String get generalChange => '更改⋯';

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
  String get generalOpenLoginItemsMac13 => '開啟登入項目⋯';

  @override
  String get generalOpenLoginItemsMac15 => '開啟登入項目與延伸功能⋯';

  @override
  String get generalOpenStartupApps => '開啟啟動應用程式⋯';

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
  String get recordingPressKeys => '按下按鍵⋯';

  @override
  String aboutVersion(String version) {
    return '版本 $version';
  }

  @override
  String aboutUpdateAvailable(String name) {
    return '有可用的新版本 Orthant $name。';
  }

  @override
  String get aboutUpdate => '更新⋯';

  @override
  String get aboutCheckForUpdates => '檢查更新⋯';

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
    return '拖曳繪製 · 方向鍵移動，$shift 延伸';
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
    return '「$command」已使用此組合鍵。';
  }

  @override
  String regionSheetConflictTaking(String command) {
    return '儲存後，「$command」將不再使用此組合鍵。';
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

  @override
  String get commandOpenGrid => '開啟格線';

  @override
  String get commandLeftHalf => '左半部';

  @override
  String get commandRightHalf => '右半部';

  @override
  String get commandTopHalf => '上半部';

  @override
  String get commandBottomHalf => '下半部';

  @override
  String get commandTopLeft => '左上四分之一';

  @override
  String get commandTopRight => '右上四分之一';

  @override
  String get commandBottomLeft => '左下四分之一';

  @override
  String get commandBottomRight => '右下四分之一';

  @override
  String get commandMaximize => '最大化';

  @override
  String get commandCenter => '置中';

  @override
  String get shortcutsTitle => '快速鍵';

  @override
  String get shortcutsSubtitle => '開啟格線，或將最前方的視窗直接放到它所在顯示器的某個區域。';

  @override
  String get shortcutsGroupBuiltIn => '內建';

  @override
  String get shortcutsGroupRegions => '你的區域';

  @override
  String shortcutsRegionsHint(String key) {
    return '為內建項目沒有的形狀綁定快速鍵。可在此繪製，也可在格線中選取後按 $key。';
  }

  @override
  String get shortcutsNotGranted =>
      '在 Orthant 取得輔助使用權限之前，這些快速鍵都不會生效。你仍然可以更改它們。';

  @override
  String shortcutsListening(String escape) {
    return '正在錄製⋯按下組合鍵，或按 $escape 取消。';
  }

  @override
  String shortcutsHint(String modifiers) {
    return '按一下快速鍵即可更改。組合鍵須包含 $modifiers 其中之一。';
  }

  @override
  String shortcutsCollision(String combo, String owner) {
    return '$combo 已被「$owner」使用。再按一次即可在此使用。';
  }

  @override
  String get shortcutsUseHere => '在此使用';

  @override
  String shortcutsDisplaced(String command, String combo) {
    return '「$command」不再使用 $combo。';
  }

  @override
  String get shortcutsUndo => '復原';

  @override
  String shortcutsRegionDeleted(String name) {
    return '已刪除「$name」。';
  }

  @override
  String get shortcutsResetDone => '所有快速鍵已還原為預設值。';

  @override
  String get shortcutsReset => '重設快速鍵';

  @override
  String get shortcutsAddRegion => '新增區域⋯';

  @override
  String get shortcutsAddRegionLabel => '新增區域';

  @override
  String shortcutsEditRegion(String name) {
    return '編輯 $name';
  }

  @override
  String get shortcutsClickToSet => '按一下以設定';

  @override
  String get shortcutsRemove => '移除快速鍵';

  @override
  String shortcutsRemoveLabel(String command) {
    return '移除 $command 的快速鍵';
  }

  @override
  String shortcutsUnavailableTooltip(String system) {
    return '$system 或其他應用程式已在使用此組合鍵，因此 Orthant 接收不到。\n按一下該快速鍵可另選一個。';
  }

  @override
  String shortcutRowBound(String command, String combo) {
    return '$command，$combo';
  }

  @override
  String shortcutRowUnbound(String command) {
    return '$command，未設定快速鍵';
  }

  @override
  String shortcutRowUnavailable(String command, String combo) {
    return '$command，$combo，不可用';
  }

  @override
  String shortcutRowListening(String command) {
    return '$command，等待輸入組合鍵';
  }

  @override
  String shortcutRowCollision(String command, String combo, String owner) {
    return '$command，$combo 已被 $owner 使用。再按一次即可在此使用，或按 Esc 取消。';
  }

  @override
  String get refusalKeypad => 'Windows 無法在快速鍵中使用數字鍵盤的數字、小數點或 =。';

  @override
  String get refusalUnregistrable => 'Windows 無法在快速鍵中使用該按鍵。';

  @override
  String get onboardingTitle => 'Orthant 需要輔助使用權限';

  @override
  String get onboardingBody =>
      'Orthant 透過 macOS 的輔助使用功能來移動你的視窗。請在「私隱與保安 ▸ 輔助使用」中啟用「Orthant」，Orthant 會立即偵測到。';

  @override
  String get onboardingBodyMac27 =>
      'Orthant 透過 macOS 的輔助使用功能來移動你的視窗。請在「私隱與保安 ▸ 裝置控制和資料取用權限」中啟用「Orthant」，Orthant 會立即偵測到。';

  @override
  String get onboardingOpenAccessibility => '開啟輔助使用設定';

  @override
  String get onboardingGranted => '已授權';

  @override
  String get onboardingWaiting => '正在等待授權⋯';

  @override
  String get readyTitle => 'Orthant 已就緒';

  @override
  String get readySubtitle => '兩種方式，把視窗放到你想要的位置。';

  @override
  String readyGridCaption(String shift, String place) {
    return '開啟格線。在格線上拖曳，就能選取任意區域，三分之一、三分之二都行。也可以用方向鍵移動，$shift 加方向鍵延伸，$place 放置。';
  }

  @override
  String get readyDirectCaption => '直接將視窗放成一半、四分之一或全螢幕。不必瞄準，還可以新增自己的形狀，例如第三個。';

  @override
  String get readyChangeShortcuts => '更改這些快速鍵⋯';

  @override
  String get readyDone => '完成';

  @override
  String get readyNoShortcutSet => '未設定快速鍵';

  @override
  String readyUnavailableTooltip(String system) {
    return '$system 或其他應用程式已在使用此組合鍵，因此 Orthant 接收不到。\n請在下方另選一個。';
  }
}
