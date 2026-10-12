const String kOrthantChannel = 'app.orthant/window';

const String kCheckPermission = 'checkAccessibilityPermission';
const String kRequestPermission = 'requestAccessibilityPermission';
const String kCaptureFrontmost = 'captureFrontmostWindow';
const String kActiveScreenFrame = 'getActiveScreenFrame';
const String kScreenFrames = 'getScreenFrames';
const String kApplyFrame = 'applyFrameToCapturedWindow';

const String kOpenAccessibilitySettings = 'openAccessibilitySettings';
const String kShowConfigWindow = 'showConfigWindow';
const String kHideConfigWindow = 'hideConfigWindow';

const String kSetOverlayGrid = 'setOverlayGrid';
const String kShowOverlay = 'showOverlay';
const String kHideOverlay = 'hideOverlay';

const String kLoginItemStatus = 'loginItemStatus';
const String kSetLoginItem = 'setLoginItem';
const String kOpenLoginItemsSettings = 'openLoginItemsSettings';

const String kCheckForUpdates = 'checkForUpdates';
const String kAutomaticUpdateChecks = 'automaticUpdateChecks';
const String kSetAutomaticUpdateChecks = 'setAutomaticUpdateChecks';

const String kAppVersion = 'appVersion';
const String kKeyboardLabels = 'keyboardLabels';
const String kKeyboardLayoutChanged = 'onKeyboardLayoutChanged';

// macOS only: Windows reads the accent over FFI, never through the runner.
const String kAccentColor = 'accentColor';

// Windows only: the overlay's commit comes back to Dart, which owns the
// captured window there.
const String kOverlayCommit = 'onOverlayCommit';
const String kOverlaySaveRegion = 'onOverlaySaveRegion';

// Windows only: the captured app's icon, read off the summon path and sent to
// the grid it belongs to once it is read.
const String kSetAppIcon = 'setAppIcon';

// Windows only: launch has registered the hotkeys and built the tray, so the
// runner may start the overlay's engines.
const String kStartOverlay = 'startOverlay';

// Windows only: `{running}`, the command queue's burst of commands starting
// (true) and ending (false). The runner starts no overlay engine attach in
// between, up to a ceiling of its own.
const String kSetCommandsRunning = 'setCommandsRunning';
