import 'dart:ui';

import 'app_localizations.dart';

// Which language Orthant shows, and the list the Settings picker offers.
//
// Orthant resolves its own locale rather than leaving it to Flutter's
// `basicLocaleListResolution`, which breaks two rules the spec needs: it defers
// a language-only match (so a list of an unsupported language, then English,
// then `zh-TW` would reach Traditional Chinese although English ranks above
// it), and it matches language plus country before script (so `zh-Hans-HK`
// would reach Hong Kong Traditional).
//
// The language choice is a BCP-47 tag (`String?`, null for System), never an
// enum, and the picker is built from the supported locales: shipping a new ARB
// file is all it takes to make a new language selectable. The one piece of
// language-specific code is [normalizeLocale]'s Chinese rule.

/// The language of the template ARB. The picker lists it first.
const Locale _template = Locale('en');

final RegExp _separator = RegExp('[-_]');
final RegExp _languageSubtag = RegExp(r'^[a-zA-Z]{2,3}$');
final RegExp _scriptSubtag = RegExp(r'^[a-zA-Z]{4}$');
final RegExp _regionSubtag = RegExp(r'^(?:[a-zA-Z]{2}|[0-9]{3})$');
final RegExp _extraSubtag = RegExp(r'^[a-zA-Z0-9]{1,8}$');

/// The locale a BCP-47 [tag] names, with `-` or `_` between its subtags: a
/// language, then an optional 4-letter script, then an optional region (2
/// letters or 3 digits). Variants and extensions after those are accepted and
/// ignored.
///
/// A tag that does not parse (an empty one, `!!`) never throws: it gives
/// `Locale('und')`, which no supported locale matches, so a stored choice that
/// has gone bad behaves as System.
Locale parseLanguageTag(String tag) {
  const unmatchable = Locale('und');
  final parts = tag.split(_separator);
  if (!_languageSubtag.hasMatch(parts.first)) return unmatchable;
  var next = 1;
  String? script;
  String? region;
  if (next < parts.length && _scriptSubtag.hasMatch(parts[next])) {
    final s = parts[next++];
    script = s[0].toUpperCase() + s.substring(1).toLowerCase();
  }
  if (next < parts.length && _regionSubtag.hasMatch(parts[next])) {
    region = parts[next++].toUpperCase();
  }
  for (; next < parts.length; next++) {
    if (!_extraSubtag.hasMatch(parts[next])) return unmatchable;
  }
  return Locale.fromSubtags(
    languageCode: parts.first.toLowerCase(),
    scriptCode: script,
    countryCode: region,
  );
}

/// [l] with the script it implies filled in, for matching. This is the only
/// language-specific code here: a script-less Chinese locale is Traditional for
/// the regions that write Traditional (`TW`, `HK`, `MO`, which is how Windows
/// sends them) and Simplified otherwise. Every other locale is returned as is.
///
/// Supported locales are normalized the same way, so `zh` is `zh-Hans` and
/// `zh_Hant_HK` is `zh-Hant-HK`. The result is for comparing only: what
/// [resolveAppLocale] returns is always an element of `supported` as given.
Locale normalizeLocale(Locale l) {
  final script = l.scriptCode;
  if (l.languageCode != 'zh' || (script != null && script.isNotEmpty)) {
    return l;
  }
  const traditionalRegions = <String>{'TW', 'HK', 'MO'};
  return Locale.fromSubtags(
    languageCode: 'zh',
    scriptCode: traditionalRegions.contains(l.countryCode) ? 'Hant' : 'Hans',
    countryCode: l.countryCode,
  );
}

/// Whether [have] covers [want] in language and script, both normalized. A
/// locale with no script covers every script of its language.
bool _covers(Locale have, Locale want) {
  final h = normalizeLocale(have);
  final w = normalizeLocale(want);
  return h.languageCode == w.languageCode &&
      (h.scriptCode == null || h.scriptCode == w.scriptCode);
}

/// The element of [supported] that serves [wanted], or null. Language and
/// script must match; the region then only chooses among those: the variant
/// with [wanted]'s region first, else the region-less one.
Locale? _bestMatch(Locale wanted, List<Locale> supported) {
  final matches = supported.where((s) => _covers(s, wanted)).toList();
  if (matches.isEmpty) return null;
  final region = normalizeLocale(wanted).countryCode;
  if (region != null) {
    for (final s in matches) {
      if (normalizeLocale(s).countryCode == region) return s;
    }
  }
  for (final s in matches) {
    if (normalizeLocale(s).countryCode == null) return s;
  }
  return matches.first;
}

/// The locale Orthant shows.
///
/// A [choice] (a language tag the user picked in Settings; null is System) is
/// resolved first, alone, by the same rule as a system language. One that is
/// empty, does not parse or matches nothing is ignored, so it behaves as
/// System. Otherwise the [preferred] system languages are tried strictly in
/// order: the first one with any match wins and nothing further down the list
/// can beat it. With no match at all the answer is [fallback].
///
/// A region-less choice takes its region from the system, which is how picking
/// Traditional Chinese on a Mac whose first preferred Traditional Chinese is
/// `zh-HK` gets the Hong Kong variant: the first preferred locale of the
/// choice's language and script supplies its region if [supported] has a
/// variant for it, and otherwise the choice stays plain. A later preferred
/// locale never supplies one, so `[zh-TW, zh-HK]` is Taiwan's Traditional, as
/// System shows. Script beats region here as everywhere, so a Simplified choice
/// never takes it.
///
/// The result is an element of [supported] exactly as given (Simplified is
/// `Locale('zh')`), because the main engine sends its `toLanguageTag()` to the
/// overlay engine.
Locale resolveAppLocale(
  List<Locale> preferred, {
  String? choice,
  List<Locale> supported = AppLocalizations.supportedLocales,
  Locale fallback = const Locale('en'),
}) {
  if (choice != null) {
    final parsed = parseLanguageTag(choice);
    final chosen = _bestMatch(parsed, supported);
    if (chosen != null) {
      if (parsed.countryCode != null) return chosen;
      return _withSystemRegion(chosen, preferred, supported) ?? chosen;
    }
  }
  for (final p in preferred) {
    final match = _bestMatch(p, supported);
    if (match != null) return match;
  }
  return fallback;
}

/// The variant of [chosen]'s language and script that the first of [preferred]
/// of that language and script points at, or null.
///
/// Strict in order, like the rest of the resolver: only that first locale can
/// supply a region. If it has none, or [supported] has no variant for it, the
/// answer is null and a later `zh-HK` below a `zh-TW` is not consulted, so the
/// picked language agrees with what System shows on the same machine.
Locale? _withSystemRegion(
  Locale chosen,
  List<Locale> preferred,
  List<Locale> supported,
) {
  final group = normalizeLocale(chosen);
  for (final p in preferred) {
    if (!_covers(chosen, p)) continue;
    final region = normalizeLocale(p).countryCode;
    if (region == null) return null;
    final variant = _bestMatch(p, supported);
    if (variant == null) return null;
    final v = normalizeLocale(variant);
    if (v.countryCode == region &&
        v.languageCode == group.languageCode &&
        v.scriptCode == group.scriptCode) {
      return variant;
    }
    return null;
  }
  return null;
}

/// One entry of the Settings language picker.
class LanguageOption {
  const LanguageOption(this.tag, this.name);

  /// The language and script it stands for (`en`, `zh-Hans`, `zh-Hant`): what
  /// the picker stores as the choice.
  final String tag;

  /// Its own name in its own language and script, so someone stuck in a
  /// language they cannot read can still find theirs.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is LanguageOption && other.tag == tag && other.name == name;

  @override
  int get hashCode => Object.hash(tag, name);

  @override
  String toString() => 'LanguageOption($tag, $name)';
}

/// This locale's own name for itself, from its own translation file.
String defaultNativeName(Locale l) =>
    lookupAppLocalizations(l).languageNativeName;

/// The picker's entries: one per language and (normalized) script in
/// [supported], so Hong Kong folds into Traditional Chinese rather than getting
/// an entry of its own. The template language comes first, then the others in
/// [supported]'s order. Each is named by [nativeName] of its region-less locale.
List<LanguageOption> languageOptions({
  List<Locale> supported = AppLocalizations.supportedLocales,
  String Function(Locale) nativeName = defaultNativeName,
}) {
  final groups = <String, List<Locale>>{};
  for (final s in supported) {
    final n = normalizeLocale(s);
    final script = n.scriptCode;
    final tag = script == null ? n.languageCode : '${n.languageCode}-$script';
    (groups[tag] ??= <Locale>[]).add(s);
  }
  bool isTemplate(String tag) => tag.split('-').first == _template.languageCode;
  final tags = <String>[
    ...groups.keys.where(isTemplate),
    ...groups.keys.where((t) => !isTemplate(t)),
  ];
  return <LanguageOption>[
    for (final tag in tags)
      LanguageOption(
        tag,
        nativeName(groups[tag]!.firstWhere(
          (s) => normalizeLocale(s).countryCode == null,
          orElse: () => groups[tag]!.first,
        )),
      ),
  ];
}

/// The option a stored [choice] belongs to, or null (System) for null or a
/// choice no option covers. A Hong Kong choice and `zh-TW` both belong to
/// `zh-Hant`: the stored tag is kept whole, and the picker shows its group.
String? optionTagFor(String? choice, List<LanguageOption> options) {
  if (choice == null) return null;
  final wanted = parseLanguageTag(choice);
  for (final option in options) {
    if (_covers(parseLanguageTag(option.tag), wanted)) return option.tag;
  }
  return null;
}

/// The language tag WinSparkle takes for [resolved]: Chinese by script (`Hans`
/// is `zh-CN`, `Hant` is `zh-TW`), every other language its own
/// `toLanguageTag()` (`en`, `pt-BR`).
String winSparkleLanguage(Locale resolved) {
  final n = normalizeLocale(resolved);
  if (n.languageCode == 'zh') {
    if (n.scriptCode == 'Hans') return 'zh-CN';
    if (n.scriptCode == 'Hant') return 'zh-TW';
  }
  return resolved.toLanguageTag();
}
