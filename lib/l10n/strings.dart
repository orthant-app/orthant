import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// The strings for code that has no [BuildContext]: the tray menu, the native
/// channel's announcements, the update notices a coordinator composes. It
/// starts English; the app points it at the language it resolves with
/// [setAppStrings].
AppLocalizations appStrings = lookupAppLocalizations(const Locale('en'));

/// Points [appStrings] at [locale]. [locale] must be one of
/// [AppLocalizations.supportedLocales].
void setAppStrings(Locale locale) {
  appStrings = lookupAppLocalizations(locale);
}

extension L10nContext on BuildContext {
  /// The strings for the language this part of the tree is shown in.
  ///
  /// Falls back to [appStrings] when no [AppLocalizations] is in scope, which
  /// is what keeps the many test hosts built without localization delegates
  /// rendering English instead of throwing on a null.
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ?? appStrings;
}
