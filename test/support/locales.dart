import 'dart:ui';

/// The four locales Orthant ships, as `AppLocalizations.supportedLocales`
/// spells them. The resolver hands back one of these exactly as given (never
/// the normalized form), because the main engine sends `toLanguageTag()` of
/// the result to the overlay engine and the wire tags are `zh` and `zh-Hant`.
const kEnglish = Locale('en');
const kSimplified = Locale('zh');
const kTraditional = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
const kHongKong = Locale.fromSubtags(
    languageCode: 'zh', scriptCode: 'Hant', countryCode: 'HK');
