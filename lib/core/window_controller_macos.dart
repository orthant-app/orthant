import 'package:flutter/services.dart';
import 'channel.dart';
import 'geometry.dart';
import 'window_controller.dart';

class MacosWindowController implements WindowController {
  const MacosWindowController();

  static const MethodChannel _channel = MethodChannel(kOrthantChannel);

  @override
  Future<Map<int, String>> keyboardLabels() async {
    // Display data only, so a failure here degrades to Dart's fallback
    // glyphs rather than surfacing anywhere — least of all at launch, where
    // the coordinator awaits this before anything renders.
    final Object? reply;
    try {
      reply = await _channel.invokeMethod<Object?>(kKeyboardLabels);
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
    if (reply is! Map) return const {};
    return Map.unmodifiable({
      for (final entry in reply.entries)
        if (entry.key is int && entry.key >= 0 && entry.key <= 127 &&
            entry.value is String && (entry.value as String).trim().isNotEmpty)
          entry.key as int: entry.value as String,
    });
  }

  @override
  Future<bool> checkPermission() async =>
      await _channel.invokeMethod<bool>(kCheckPermission) ?? false;

  @override
  Future<void> requestPermission() =>
      _channel.invokeMethod<void>(kRequestPermission);

  @override
  Future<CapturedWindow?> captureFrontmost() async {
    final res = await _channel.invokeMapMethod<String, dynamic>(kCaptureFrontmost);
    if (res == null || res['ok'] != true) return null;
    return CapturedWindow(
      res['appName'] as String? ?? '',
      _rectFromMap((res['frame'] as Map).cast<String, dynamic>()),
    );
  }

  @override
  Future<WinRect> activeScreenFrame() async {
    final res = await _channel.invokeMapMethod<String, dynamic>(kActiveScreenFrame);
    return _rectFromMap(res!);
  }

  @override
  Future<bool> applyFrame(WinRect target) async =>
      await _channel.invokeMethod<bool>(kApplyFrame, {
        'x': target.x,
        'y': target.y,
        'w': target.width,
        'h': target.height,
      }) ??
      false;

  @override
  Future<List<WinRect>> screenFrames() async {
    final res = await _channel.invokeListMethod<dynamic>(kScreenFrames);
    if (res == null) return const [];
    return res
        .map((e) => _rectFromMap((e as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod<void>(kOpenAccessibilitySettings);

  @override
  Future<void> showConfigWindow() =>
      _channel.invokeMethod<void>(kShowConfigWindow);

  @override
  Future<void> hideConfigWindow() =>
      _channel.invokeMethod<void>(kHideConfigWindow);

  @override
  Future<void> setOverlayGrid({
    required int cols,
    required int rows,
    required double gap,
    required bool saveHint,
  }) =>
      _channel.invokeMethod<void>(kSetOverlayGrid, {
        'cols': cols,
        'rows': rows,
        'gap': gap,
        'saveHint': saveHint,
      });

  @override
  Future<void> showOverlay() => _channel.invokeMethod<void>(kShowOverlay);

  @override
  Future<void> hideOverlay() => _channel.invokeMethod<void>(kHideOverlay);

  @override
  Future<AppVersion> appVersion() async {
    // Defensive on every field: a reply that is missing, the wrong shape, or
    // half-populated must degrade to "unknown" rather than throw. This is read
    // during the tray build, and a throw there is a menu that never appears.
    final reply = await _channel.invokeMethod<Object?>(kAppVersion);
    if (reply is! Map) return const AppVersion('', '');
    final short = reply['shortVersion'];
    final build = reply['buildNumber'];
    final name = reply['releaseName'];
    return AppVersion(
      short is String ? short : '',
      build is String ? build : '',
      releaseName: name is String ? name : '',
    );
  }

  @override
  Future<bool> automaticUpdateChecks() async =>
      // Defensive: a reply of the wrong shape must not throw into the settings
      // pane's build. Absent or malformed reads as "off", which is the safer
      // way to be wrong about a network call.
      await _channel.invokeMethod<Object?>(kAutomaticUpdateChecks) == true;

  @override
  Future<bool> setAutomaticUpdateChecks(bool enabled) async =>
      await _channel.invokeMethod<Object?>(
        kSetAutomaticUpdateChecks,
        enabled,
      ) ==
      true;

  @override
  Future<LoginItemStatus> loginItemStatus() async =>
      _statusFromReply(await _channel.invokeMethod<Object?>(kLoginItemStatus));

  @override
  Future<LoginItemStatus> setLoginItem(bool enabled) async => _statusFromReply(
      await _channel.invokeMethod<Object?>(kSetLoginItem, enabled));

  @override
  Future<void> openLoginItemsSettings() =>
      _channel.invokeMethod<void>(kOpenLoginItemsSettings);

  @override
  Future<void> checkForUpdates() =>
      _channel.invokeMethod<void>(kCheckForUpdates);

  /// Anything we do not recognise — a newer macOS status, a null reply, a value
  /// that is not even a string — is [LoginItemStatus.unavailable].
  ///
  /// Typed as `Object?` rather than `String?` on purpose: `invokeMethod<String>`
  /// *throws* on a non-string reply, and this is read every time the settings
  /// window opens. Same reasoning as `Binding.tryFromJson` and the channel's
  /// `UInt32(exactly:)` — a boundary must not be able to take the app down over
  /// a value it did not expect. It must also never fall through to `enabled`:
  /// the row would then claim the app starts at login when nothing established
  /// that it does.
  LoginItemStatus _statusFromReply(Object? reply) {
    for (final status in LoginItemStatus.values) {
      if (status.name == reply) return status;
    }
    return LoginItemStatus.unavailable;
  }

  WinRect _rectFromMap(Map<String, dynamic> m) => WinRect(
        (m['x'] as num).toDouble(),
        (m['y'] as num).toDouble(),
        (m['w'] as num).toDouble(),
        (m['h'] as num).toDouble(),
      );
}
