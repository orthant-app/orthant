import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';
import 'package:xml/xml.dart';

import 'window_controller.dart';

/// The feed a Windows build checks: the stable Windows feed on the project's
/// own domain, as macOS's `SUFeedURL` is, so hosting can move without
/// orphaning an installed copy. Compiled in; a build made to test the updater
/// against a feed of its own passes `--dart-define=ORTHANT_UPDATE_FEED=...`,
/// which a release build never does.
const kUpdateFeedUrl = String.fromEnvironment('ORTHANT_UPDATE_FEED',
    defaultValue: 'https://updates.orthant.app/appcast-win.xml');

/// The Ed25519 key an update must be signed with: the same key as macOS's
/// `SUPublicEDKey`, since one release job signs both platforms' downloads.
/// Compiled in, and replaced only by `--dart-define=ORTHANT_UPDATE_PUBLIC_KEY`
/// in a build made to test the updater with a key of its own.
const kUpdatePublicKey = String.fromEnvironment('ORTHANT_UPDATE_PUBLIC_KEY',
    defaultValue: 'Oyo4ZcSrr7nWOq3L3vrTmzbQS8efqoGK0ifYh0EB27w=');

/// The tag's own name (`1.1.0`, `1.1.0-beta.1`), given to a release build by
/// `--dart-define=ORTHANT_RELEASE_NAME=...`; empty in every other build. The
/// version resource holds three integers and a build number, so a beta's
/// label has nowhere else to live (macOS's `ORTHANTReleaseName`).
const kReleaseName = String.fromEnvironment('ORTHANT_RELEASE_NAME');

/// How often, in seconds, the app looks whether a check is due, and so how
/// soon a check that failed is made again: an hour, as WinSparkle's own
/// scheduler wakes. A build made to test the updater passes
/// `--dart-define=ORTHANT_UPDATE_RETRY_SECONDS=...`.
const kUpdateRetrySeconds =
    int.fromEnvironment('ORTHANT_UPDATE_RETRY_SECONDS', defaultValue: 3600);

/// The time between scheduled checks: a day, WinSparkle's default.
const kUpdateCheckIntervalSeconds = 86400;

/// Where WinSparkle keeps its settings, under `HKEY_CURRENT_USER`: the key
/// its default would derive from the version resource (`CompanyName`,
/// `ProductName`), named here so it cannot move if those ever change. The
/// uninstaller deletes `Software\Orthant` with everything in it.
const kUpdaterRegistryPath = r'Software\Orthant\Orthant\WinSparkle';

/// Where Orthant keeps its own update settings, beside WinSparkle's: whether
/// it checks on a schedule, when a check last succeeded, and the update that
/// check found.
const kUpdateSettingsPath = r'Software\Orthant\Orthant\Updates';

/// The part of WinSparkle's C API Orthant uses, behind an interface so the
/// suite, which runs on a Mac with no `WinSparkle.dll`, can supply its own.
abstract class SparkleApi {
  void setRegistryPath(String path);
  void setAppcastUrl(String url);

  /// Whether WinSparkle accepted the key as a valid Ed25519 public key.
  bool setEdDsaPublicKey(String key);
  void setAppDetails(String company, String app, String version);
  void setAppBuildVersion(String build);
  void setAutomaticCheck(bool on);
  void setShutdownRequestCallback(void Function() onRequest);

  /// The user chose "Skip this version" in WinSparkle's offer.
  void setSkippedCallback(void Function() onSkipped);

  /// A check of WinSparkle's own found nothing to install.
  void setNotFoundCallback(void Function() onNotFound);
  void init();
  void checkWithUi();
}

/// Orthant's own update settings, and the one value of WinSparkle's it
/// reads. Never throws: a value that cannot be read reads as absent.
abstract class UpdateStore {
  /// Whether checks run on a schedule; null when never set.
  bool? readAutomaticChecks();
  void writeAutomaticChecks(bool on);

  /// When a check last succeeded, in seconds since the epoch; null for never.
  int? readLastCheck();
  void writeLastCheck(int seconds);

  /// The update the last successful check found, kept so a relaunch still
  /// shows it; null for none.
  AvailableUpdate? readFound();
  void writeFound(AvailableUpdate? found);

  /// The build the user told WinSparkle to skip, as WinSparkle stored it.
  String? readSkipped();
}

/// What a request for the feed answered: its HTTP status and its body.
typedef FeedResponse = ({int status, String body});

/// Requests a feed; throws when it cannot be reached at all.
typedef FeedFetch = Future<FeedResponse> Function(String url);

/// The Windows release a feed item can require, from `RtlGetVersion`.
typedef WindowsVersion = ({int major, int minor, int build, int servicePack});

/// This machine's Windows, as `RtlGetVersion` reports it (no compatibility
/// shim applies). Windows only.
WindowsVersion runningWindows() {
  final os = OsVersion.current;
  return (
    major: os.major,
    minor: os.minor,
    build: os.build,
    servicePack: os.pack
  );
}

const _sparkleNs = 'http://www.andymatuschak.org/xml-namespaces/sparkle';

/// The newest update in a Windows feed for this machine, or null when it is
/// not newer than [build] or is the one the user chose to skip.
///
/// Modelled on WinSparkle's own choice: among the items whose enclosure's
/// `sparkle:os` is absent, `windows` or [os] and whose
/// `sparkle:minimumSystemVersion` [system] meets, the one with the highest
/// `sparkle:version` (the build number), and only then compared with [build]
/// and [skip]. The two can differ on inputs our feed generator never writes;
/// there, at worst, the tray offers an update that WinSparkle then declines.
/// An item it cannot read is passed over; WinSparkle reads the feed again,
/// and checks the installer's signature, when the user chooses to install. Throws a [FormatException] for a body that is not a
/// well-formed RSS document, a truncated one or one using a namespace prefix
/// it never declares included, so that a check which reads one fails rather
/// than reporting no update.
AvailableUpdate? newestUpdate(String feed,
    {required int build,
    required WindowsVersion system,
    String os = 'windows-x64',
    String? skip}) {
  // A body that is not well-formed throws here: package:xml's parse errors
  // are FormatExceptions.
  final document = XmlDocument.parse(feed);
  // An undeclared prefix (sparkle: with no xmlns:sparkle) is no error to
  // package:xml, which would then find no version anywhere and report no
  // update; WinSparkle's parser refuses it.
  for (final element in document.descendantElements) {
    if (_unbound(element.name) ||
        element.attributes.any((a) => _unbound(a.name))) {
      throw FormatException('undeclared prefix in ${element.name.qualified}');
    }
  }
  final channel = document.rootElement.name.local == 'rss'
      ? document.rootElement.getElement('channel')
      : null;
  if (channel == null) throw const FormatException('not an RSS feed');
  String? newestText;
  AvailableUpdate? newest;
  for (final item in channel.findElements('item')) {
    String? field(String name) => item
        .findElements(name, namespace: _sparkleNs)
        .firstOrNull
        ?.innerText
        .trim();
    final version = field('version');
    final number = version == null || !RegExp(r'^\d+$').hasMatch(version)
        ? null
        : int.tryParse(version);
    final enclosures = item.findElements('enclosure');
    if (number == null || enclosures.isEmpty) continue;
    final fits = enclosures.any((e) {
      final mark = e.getAttribute('os', namespace: _sparkleNs) ?? '';
      return mark.isEmpty || mark == 'windows' || mark == os;
    });
    if (!fits || !_meets(field('minimumSystemVersion'), system)) continue;
    if (newest != null && number <= newest.build) continue;
    final name = field('shortVersionString');
    newestText = version;
    newest = AvailableUpdate(name == null || name.isEmpty ? version! : name,
        number);
  }
  if (newest == null || newest.build <= build || newestText == skip) {
    return null;
  }
  return newest;
}

bool _unbound(XmlName name) {
  final prefix = name.prefix;
  return prefix != null &&
      prefix != 'xml' &&
      prefix != 'xmlns' &&
      name.namespaceUri == null;
}

/// Whether [system] meets an item's `sparkle:minimumSystemVersion`, read as
/// WinSparkle reads it: `major[.minor[.build]]` or `major.minor-build`, a
/// third part under 100 taken as a service pack, and a value that does not
/// start with a number limiting nothing. Compared as WinSparkle's
/// VerifyVersionInfoW call compares: major, minor and service pack in that
/// order, and the build number on its own.
bool _meets(String? required, WindowsVersion system) {
  final m =
      RegExp(r'^(\d+)(?:\.(\d+)(?:[.-](\d+))?)?').firstMatch(required ?? '');
  if (m == null) return true;
  final major = int.parse(m.group(1)!);
  final minor = int.tryParse(m.group(2) ?? '') ?? 0;
  final third = int.tryParse(m.group(3) ?? '');
  final servicePack = third != null && third < 100 ? third : 0;
  final build = third != null && third >= 100 ? third : 0;
  final ordered = system.major != major
      ? system.major > major
      : system.minor != minor
          ? system.minor > minor
          : system.servicePack >= servicePack;
  return ordered && system.build >= build;
}

/// Orthant's updates on Windows: Orthant checks, WinSparkle installs.
///
/// WinSparkle 0.9.4 has no check that shows no window: whatever finds an
/// update opens its offer and brings it to the front, where an Enter meant
/// for another app would start the download. So its own schedule is never
/// started. Orthant checks the feed itself, on WinSparkle's schedule, and
/// shows what it finds without a window ([found]: the tray and the About
/// pane); WinSparkle's offer opens only when the user asks ([checkNow]).
///
/// Started once, at launch, and never lazily: macOS shipped three releases
/// whose updater nothing started until the settings window did, so they
/// never checked on their own; on Windows the controller's factory starts
/// this before it hands the controller back.
class WindowsUpdater {
  WindowsUpdater(this._api, this._store, this._fetch,
      {required this.feedUrl,
      required this.publicKey,
      required this.system,
      this.log,
      this.interval = kUpdateCheckIntervalSeconds,
      int Function()? clock})
      : _clock = clock ?? _epochSeconds;

  final SparkleApi _api;
  final UpdateStore _store;
  final FeedFetch _fetch;
  final String feedUrl;
  final String publicKey;

  /// This machine's Windows, which an update's minimum version must allow:
  /// read at each check, inside its failure handling, so that a read that
  /// fails costs that check and never the launch.
  final WindowsVersion Function() system;

  /// Seconds between scheduled checks.
  final int interval;

  /// Debug and Profile builds' log line, for a person checking the updater.
  final void Function(String line)? log;

  final int Function() _clock;
  final _found = ValueNotifier<AvailableUpdate?>(null);
  bool _running = false;
  bool _checking = false;
  int _build = 0;

  bool get running => _running;

  /// The update a check found that is still to be installed, skipped or
  /// found gone; null for none.
  ValueListenable<AvailableUpdate?> get found => _found;

  static int _epochSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Configures WinSparkle and starts it. Returns whether it started.
  ///
  /// [build] is the build number an update's `sparkle:version` is compared
  /// with, as Sparkle compares `CFBundleVersion`; [display] is what
  /// WinSparkle's window calls this version. Without a key WinSparkle accepts
  /// it never starts: WinSparkle would then fall back to a key in the
  /// executable's resources, of which this one has none.
  bool start({
    required String build,
    required String display,
    required void Function() onShutdownRequested,
  }) {
    if (_running) return true;
    final number = int.tryParse(build);
    if (number == null) {
      log?.call('updater: not started: no build number to compare');
      return false;
    }
    _api.setRegistryPath(kUpdaterRegistryPath);
    _api.setAppcastUrl(feedUrl);
    if (!_api.setEdDsaPublicKey(publicKey)) {
      log?.call('updater: not started: the public key was refused');
      return false;
    }
    _api.setAppDetails('Orthant', 'Orthant', display);
    _api.setAppBuildVersion(build);
    // Off before init, so WinSparkle never starts its own schedule, nor asks
    // at a second launch whether to.
    _api.setAutomaticCheck(false);
    // A first run checks on a schedule, as macOS does
    // (SUEnableAutomaticChecks), with the switch in the About pane.
    if (_store.readAutomaticChecks() == null) _store.writeAutomaticChecks(true);
    _api.setShutdownRequestCallback(onShutdownRequested);
    _api.setSkippedCallback(_forget);
    _api.setNotFoundCallback(_forget);
    _api.init();
    _running = true;
    _build = number;
    final kept = _store.readFound();
    if (kept != null) {
      if (kept.build > number && '${kept.build}' != _store.readSkipped()) {
        _found.value = kept;
      } else {
        _store.writeFound(null);
      }
    }
    log?.call('updater: started, build $build, checks '
        '${automaticChecks ? 'on' : 'off'}');
    return true;
  }

  /// Whether Orthant checks on a schedule.
  bool get automaticChecks => _store.readAutomaticChecks() ?? false;

  /// Turns scheduled checks on or off, and returns what is then stored.
  /// Turned on, a check that is due is made at once. Nothing of WinSparkle's
  /// is touched, so an update it is downloading or about to install goes on.
  bool setAutomaticChecks(bool on) {
    if (!_running) return automaticChecks;
    _store.writeAutomaticChecks(on);
    if (on) unawaited(check());
    return automaticChecks;
  }

  /// WinSparkle's check, with its window: the About pane's buttons and the
  /// tray's items. It offers what it finds, the found update included.
  void checkNow() {
    if (_running) _api.checkWithUi();
  }

  /// A scheduled check, if one is due: made at launch and every
  /// [kUpdateRetrySeconds]. A check is due a day after the last that
  /// succeeded, or at once when none has or the last is dated later than now
  /// (the clock was moved back); one that fails leaves it due, so it is made
  /// again at the next call. Shows nothing but [found].
  Future<void> check() async {
    if (!_running || _checking || !automaticChecks) return;
    final now = _clock();
    final last = _store.readLastCheck();
    if (last != null && last <= now && now - last < interval) return;
    _checking = true;
    try {
      final response = await _fetch(feedUrl);
      if (response.status != 200) {
        throw StateError('the feed answered ${response.status}');
      }
      final update = newestUpdate(response.body,
          build: _build, system: system(), skip: _store.readSkipped());
      _store.writeLastCheck(now);
      _store.writeFound(update);
      _found.value = update;
      log?.call(update == null
          ? 'updater: checked: up to date'
          : 'updater: checked: $update available');
    } catch (e) {
      log?.call('updater: check failed ($e)');
    } finally {
      _checking = false;
    }
  }

  void _forget() {
    _found.value = null;
    _store.writeFound(null);
  }
}

typedef _VoidNative = Void Function();
typedef _VoidDart = void Function();
typedef _Utf8Native = Void Function(Pointer<Utf8>);
typedef _Utf8Dart = void Function(Pointer<Utf8>);
typedef _KeyNative = Int32 Function(Pointer<Utf8>);
typedef _KeyDart = int Function(Pointer<Utf8>);
typedef _WideNative = Void Function(Pointer<Utf16>);
typedef _WideDart = void Function(Pointer<Utf16>);
typedef _DetailsNative = Void Function(
    Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>);
typedef _DetailsDart = void Function(
    Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>);
typedef _IntNative = Void Function(Int32);
typedef _IntDart = void Function(int);
typedef _CallbackNative = Void Function(Pointer<NativeFunction<_VoidNative>>);
typedef _CallbackDart = void Function(Pointer<NativeFunction<_VoidNative>>);

/// [SparkleApi] over `WinSparkle.dll`, which CMake installs beside the
/// executable. Windows only: the library is opened at the first call.
class FfiSparkleApi implements SparkleApi {
  FfiSparkleApi();

  late final DynamicLibrary _lib = DynamicLibrary.open('WinSparkle.dll');

  /// Kept for the life of the process: WinSparkle holds the pointers.
  final _callbacks = <String, NativeCallable<_VoidNative>>{};

  void _utf8(String name, String value) {
    final p = value.toNativeUtf8();
    try {
      _lib.lookupFunction<_Utf8Native, _Utf8Dart>(name)(p);
    } finally {
      calloc.free(p);
    }
  }

  @override
  void setRegistryPath(String path) =>
      _utf8('win_sparkle_set_registry_path', path);

  @override
  void setAppcastUrl(String url) => _utf8('win_sparkle_set_appcast_url', url);

  @override
  bool setEdDsaPublicKey(String key) {
    final p = key.toNativeUtf8();
    try {
      return _lib.lookupFunction<_KeyNative, _KeyDart>(
              'win_sparkle_set_eddsa_public_key')(p) ==
          1;
    } finally {
      calloc.free(p);
    }
  }

  @override
  void setAppDetails(String company, String app, String version) {
    final c = company.toNativeUtf16();
    final a = app.toNativeUtf16();
    final v = version.toNativeUtf16();
    try {
      _lib.lookupFunction<_DetailsNative, _DetailsDart>(
          'win_sparkle_set_app_details')(c, a, v);
    } finally {
      calloc.free(c);
      calloc.free(a);
      calloc.free(v);
    }
  }

  @override
  void setAppBuildVersion(String build) {
    final b = build.toNativeUtf16();
    try {
      _lib.lookupFunction<_WideNative, _WideDart>(
          'win_sparkle_set_app_build_version')(b);
    } finally {
      calloc.free(b);
    }
  }

  @override
  void setAutomaticCheck(bool on) => _lib.lookupFunction<_IntNative, _IntDart>(
      'win_sparkle_set_automatic_check_for_updates')(on ? 1 : 0);

  /// WinSparkle calls these from a thread of its own; a listener posts each
  /// to this isolate.
  void _callback(String setter, void Function() onCall) {
    _callbacks.remove(setter)?.close();
    final callable = NativeCallable<_VoidNative>.listener(onCall);
    _callbacks[setter] = callable;
    _lib.lookupFunction<_CallbackNative, _CallbackDart>(setter)(
        callable.nativeFunction);
  }

  @override
  void setShutdownRequestCallback(void Function() onRequest) =>
      _callback('win_sparkle_set_shutdown_request_callback', onRequest);

  @override
  void setSkippedCallback(void Function() onSkipped) =>
      _callback('win_sparkle_set_update_skipped_callback', onSkipped);

  @override
  void setNotFoundCallback(void Function() onNotFound) =>
      _callback('win_sparkle_set_did_not_find_update_callback', onNotFound);

  @override
  void init() =>
      _lib.lookupFunction<_VoidNative, _VoidDart>('win_sparkle_init')();

  @override
  void checkWithUi() => _lib.lookupFunction<_VoidNative, _VoidDart>(
      'win_sparkle_check_update_with_ui')();
}

/// [UpdateStore] in the current user's hive: Orthant's values as `REG_SZ`
/// under [kUpdateSettingsPath], as WinSparkle writes its own, and
/// WinSparkle's `SkipThisVersion` under [kUpdaterRegistryPath]. Every call
/// allocates inside its try and frees in the finally, and none throws.
///
/// Windows only.
class RegistryUpdateStore implements UpdateStore {
  const RegistryUpdateStore();

  @override
  bool? readAutomaticChecks() {
    final value = _read(kUpdateSettingsPath, 'AutomaticChecks');
    return value == null ? null : value == '1';
  }

  @override
  void writeAutomaticChecks(bool on) =>
      _write('AutomaticChecks', on ? '1' : '0');

  @override
  int? readLastCheck() =>
      int.tryParse(_read(kUpdateSettingsPath, 'LastCheckTime') ?? '');

  @override
  void writeLastCheck(int seconds) => _write('LastCheckTime', '$seconds');

  @override
  AvailableUpdate? readFound() {
    final name = _read(kUpdateSettingsPath, 'FoundName');
    final build = int.tryParse(_read(kUpdateSettingsPath, 'FoundBuild') ?? '');
    return name == null || build == null ? null : AvailableUpdate(name, build);
  }

  @override
  void writeFound(AvailableUpdate? found) {
    if (found == null) {
      _delete('FoundName');
      _delete('FoundBuild');
    } else {
      _write('FoundName', found.name);
      _write('FoundBuild', '${found.build}');
    }
  }

  @override
  String? readSkipped() => _read(kUpdaterRegistryPath, 'SkipThisVersion');

  String? _read(String key, String value) {
    Pointer<Utf16>? keyPtr;
    Pointer<Utf16>? valuePtr;
    Pointer<Uint32>? size;
    Pointer<Uint16>? data;
    try {
      keyPtr = key.toNativeUtf16();
      valuePtr = value.toNativeUtf16();
      size = calloc<Uint32>()..value = 512;
      data = calloc<Uint16>(256);
      final result = RegGetValue(HKEY_CURRENT_USER, PCWSTR(keyPtr),
          PCWSTR(valuePtr), RRF_RT_REG_SZ, null, data.cast(), size);
      if (result != ERROR_SUCCESS) return null;
      return data.cast<Utf16>().toDartString().trim();
    } catch (_) {
      return null;
    } finally {
      if (data != null) calloc.free(data);
      if (size != null) calloc.free(size);
      if (valuePtr != null) calloc.free(valuePtr);
      if (keyPtr != null) calloc.free(keyPtr);
    }
  }

  void _write(String value, String text) {
    Pointer<Utf16>? keyPtr;
    Pointer<Utf16>? valuePtr;
    Pointer<Utf16>? dataPtr;
    try {
      keyPtr = kUpdateSettingsPath.toNativeUtf16();
      valuePtr = value.toNativeUtf16();
      dataPtr = text.toNativeUtf16();
      // REG_SZ counts its bytes with the terminator.
      RegSetKeyValue(HKEY_CURRENT_USER, PCWSTR(keyPtr), PCWSTR(valuePtr),
          REG_SZ, dataPtr, (text.length + 1) * 2);
    } catch (_) {
      // Unwritten: read back as it was.
    } finally {
      if (dataPtr != null) calloc.free(dataPtr);
      if (valuePtr != null) calloc.free(valuePtr);
      if (keyPtr != null) calloc.free(keyPtr);
    }
  }

  void _delete(String value) {
    Pointer<Utf16>? keyPtr;
    Pointer<Utf16>? valuePtr;
    try {
      keyPtr = kUpdateSettingsPath.toNativeUtf16();
      valuePtr = value.toNativeUtf16();
      RegDeleteKeyValue(HKEY_CURRENT_USER, PCWSTR(keyPtr), PCWSTR(valuePtr));
    } catch (_) {
      // Left: read back as it was.
    } finally {
      if (valuePtr != null) calloc.free(valuePtr);
      if (keyPtr != null) calloc.free(keyPtr);
    }
  }
}

/// [FeedFetch] over WinINet, the HTTP stack WinSparkle itself uses, so the
/// check goes through the same proxy and certificate settings as the update
/// that follows it. WinINet blocks, so each request runs on an isolate of
/// its own; nothing is cached, at most 1 MiB is read, connecting, sending
/// and receiving each have 30 s, and the whole request [kFeedFetchLimit].
Future<FeedResponse> winInetGet(String url) =>
    Isolate.run(() => _winInetGet(url));

/// How long one fetch of the feed may take as a whole. WinINet's timeouts
/// bound each call, not the request, so a server dripping bytes under the
/// 1 MiB cap would otherwise hold the check, and with it every later one,
/// for the rest of the session. Kept inside the read loop rather than as a
/// `.timeout()` on the isolate: that would end the check while the isolate
/// stayed blocked in WinINet, leaking one for every check made after it.
const kFeedFetchLimit = Duration(seconds: 120);

/// The body of a response, read with [next] until it returns no bytes: at
/// most 1 MiB, and only while [elapsed], measured from the start of the
/// request, is within [limit]. A response that ends at the first read past
/// the limit is whole and kept. Throws a [StateError] otherwise, as the
/// fetch's other failures do.
@visibleForTesting
Uint8List readFeedBody(Uint8List Function() next,
    {required Duration Function() elapsed, Duration limit = kFeedFetchLimit}) {
  final bytes = BytesBuilder(copy: false);
  while (true) {
    final chunk = next();
    if (chunk.isEmpty) break;
    bytes.add(chunk);
    if (bytes.length > 1 << 20) throw StateError('the feed is over 1 MiB');
    if (elapsed() > limit) {
      throw StateError('the feed took over ${limit.inSeconds} s');
    }
  }
  return bytes.takeBytes();
}

typedef _OpenNative = IntPtr Function(
    Pointer<Utf16>, Uint32, Pointer<Utf16>, Pointer<Utf16>, Uint32);
typedef _OpenDart = int Function(
    Pointer<Utf16>, int, Pointer<Utf16>, Pointer<Utf16>, int);
typedef _OptionNative = Int32 Function(IntPtr, Uint32, Pointer<Void>, Uint32);
typedef _OptionDart = int Function(int, int, Pointer<Void>, int);
typedef _OpenUrlNative = IntPtr Function(
    IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32, Uint32, IntPtr);
typedef _OpenUrlDart = int Function(
    int, Pointer<Utf16>, Pointer<Utf16>, int, int, int);
typedef _QueryNative = Int32 Function(
    IntPtr, Uint32, Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>);
typedef _QueryDart = int Function(
    int, int, Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>);
typedef _ReadNative = Int32 Function(
    IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>);
typedef _ReadDart = int Function(int, Pointer<Uint8>, int, Pointer<Uint32>);
typedef _CloseNative = Int32 Function(IntPtr);
typedef _CloseDart = int Function(int);

FeedResponse _winInetGet(String url) {
  const preconfig = 0, connectTimeout = 2, sendTimeout = 5;
  const receiveTimeout = 6, statusCode = 19, asNumber = 0x20000000;
  // INTERNET_FLAG_RELOAD, _NO_CACHE_WRITE, _PRAGMA_NOCACHE, _NO_UI and
  // _NO_COOKIES: from the server every time, through any proxy's cache.
  const flags = 0x80000000 | 0x04000000 | 0x00000100 | 0x00000200 | 0x00080000;
  final lib = DynamicLibrary.open('wininet.dll');
  final open = lib.lookupFunction<_OpenNative, _OpenDart>('InternetOpenW');
  final option =
      lib.lookupFunction<_OptionNative, _OptionDart>('InternetSetOptionW');
  final openUrl =
      lib.lookupFunction<_OpenUrlNative, _OpenUrlDart>('InternetOpenUrlW');
  final query = lib.lookupFunction<_QueryNative, _QueryDart>('HttpQueryInfoW');
  final read = lib.lookupFunction<_ReadNative, _ReadDart>('InternetReadFile');
  final close =
      lib.lookupFunction<_CloseNative, _CloseDart>('InternetCloseHandle');
  final agent = 'Orthant'.toNativeUtf16();
  final address = url.toNativeUtf16();
  final timeout = calloc<Uint32>()..value = 30000;
  final number = calloc<Uint32>();
  final length = calloc<Uint32>();
  final chunk = calloc<Uint8>(16384);
  final clock = Stopwatch()..start();
  var session = 0, request = 0;
  try {
    session = open(agent, preconfig, nullptr, nullptr, 0);
    if (session == 0) throw StateError('InternetOpen failed');
    for (final o in [connectTimeout, sendTimeout, receiveTimeout]) {
      option(session, o, timeout.cast(), sizeOf<Uint32>());
    }
    request = openUrl(session, address, nullptr, 0, flags, 0);
    if (request == 0) {
      throw StateError('the feed could not be reached');
    }
    length.value = sizeOf<Uint32>();
    if (query(request, statusCode | asNumber, number.cast(), length,
            nullptr) ==
        0) {
      throw StateError('no HTTP status');
    }
    final body = readFeedBody(() {
      if (read(request, chunk, 16384, length) == 0) {
        throw StateError('the feed was cut off');
      }
      return Uint8List.fromList(chunk.asTypedList(length.value));
    }, elapsed: () => clock.elapsed);
    return (
      status: number.value,
      body: utf8.decode(body, allowMalformed: true),
    );
  } finally {
    if (request != 0) close(request);
    if (session != 0) close(session);
    calloc.free(chunk);
    calloc.free(length);
    calloc.free(number);
    calloc.free(timeout);
    calloc.free(address);
    calloc.free(agent);
  }
}
