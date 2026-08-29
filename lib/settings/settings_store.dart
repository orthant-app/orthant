import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'settings.dart';

/// Persists [Settings].
///
/// Uses the same legacy `SharedPreferences` API as `BindingsStore` on purpose.
/// `SharedPreferencesAsync` is what the package recommends for new code, but it
/// applies no `flutter.` key prefix — so mixing the two would scatter Orthant's
/// own state across two conventions inside one plist, for no gain at a scale of
/// two keys read once at launch.
class SettingsStore {
  static const _key = 'orthant.settings.v1';
  static const _onboardedKey = 'orthant.onboarded.v1';
  static const _startedKey = 'orthant.onboardingStarted.v1';
  static const _promptedKey = 'orthant.accessibilityPrompted.v1';

  Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const Settings();
    return _decode(raw).clamped();
  }

  Future<void> save(Settings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }

  /// Whether the "you're ready" screen has been shown.
  ///
  /// App state, not a user setting, so it is a separate key rather than a
  /// field on [Settings] — Reset to Defaults must not make onboarding
  /// reappear.
  Future<bool> hasOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardedKey) ?? false;
  }

  Future<void> markOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardedKey, true);
  }

  /// Whether the onboarding screen has ever been *put on screen*.
  ///
  /// The distinction from [hasOnboarded] is what a launch needs to tell two
  /// granted states apart. Finding the grant already in place on a launch that
  /// has never shown anything means the user granted it before Orthant ever
  /// ran, and opening a window at them would be unbidden. Finding it after
  /// onboarding has been shown means they read that window, went to System
  /// Settings and granted — very possibly with Orthant quit in between, which
  /// is an ordinary way to do it — and the ready screen is the answer they were
  /// waiting for. Neither `hasOnboarded` nor the prompt flag separates those:
  /// the first is false in both, and the second stays false for anyone who
  /// granted by hand rather than through our button.
  /// Falls back to the prompt flag for preferences written before this key
  /// existed. That flag is only ever set by the onboarding button, so having it
  /// *proves* onboarding was shown — which makes it a sound, if narrower,
  /// stand-in: it misses an old install that saw the window, never pressed the
  /// button, and granted by hand. Cheap enough to be worth having, and the only
  /// installs it could matter to are development ones, since M8 is the first
  /// build to leave this machine.
  Future<bool> hasStartedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_startedKey) ?? false) return true;
    return prefs.getBool(_promptedKey) ?? false;
  }

  Future<void> markStartedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_startedKey, true);
  }

  /// Whether macOS's own "…would like to control this computer" dialog has been
  /// asked for yet.
  ///
  /// That dialog is the only way an app gets itself listed in the Accessibility
  /// pane without the user adding it by hand, so it has to happen once — but it
  /// used to happen at *launch*, which greeted a first-time user with the system
  /// alert on top of Orthant's own onboarding window: two surfaces asking the
  /// same question before they had done anything. It is now the first thing the
  /// onboarding button does, and only the first time; after that the button
  /// deep-links straight to the pane, because macOS shows the alert at most once
  /// per record and a second request would silently do nothing.
  Future<bool> hasPromptedForAccessibility() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_promptedKey) ?? false;
  }

  Future<void> markPromptedForAccessibility() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_promptedKey, true);
  }
}

/// Decoded **per field**, each falling back on its own.
///
/// All-or-nothing would be wrong here in a way it is not for the bindings list.
/// That is a list, so a rejected entry costs one command its combo; this is a
/// single object, so rejecting it wholesale would discard a grid the user
/// deliberately chose because of an unrelated typo elsewhere in the file.
///
/// Nothing throws. [SettingsStore.load] runs on the launch path, before the
/// grid is pushed to the overlay or a shortcut fires.
Settings _decode(String raw) {
  Object? parsed;
  try {
    parsed = jsonDecode(raw);
  } on FormatException {
    return const Settings();
  }
  if (parsed is! Map) return const Settings();
  // Bound to a final local: type promotion of a mutable local does not reach
  // inside the closure below.
  final map = parsed;

  const fallback = Settings();
  int intOr(String key, int otherwise) {
    final value = map[key];
    return value is int ? value : otherwise;
  }

  final gaps = map['gaps'];
  return Settings(
    gridCols: intOr('gridCols', fallback.gridCols),
    gridRows: intOr('gridRows', fallback.gridRows),
    gaps: gaps is bool ? gaps : fallback.gaps,
    gapSize: intOr('gapSize', fallback.gapSize),
  );
}
