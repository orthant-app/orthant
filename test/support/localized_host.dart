import 'package:flutter/material.dart';
import 'package:orthant/l10n/app_localizations.dart';
import 'package:orthant/settings/platform_theme.dart';

/// [home] shown in [locale], set up the way `lib/main.dart` sets up the app:
/// the locale it resolved, the supported list and the generated delegates.
///
/// A widget that reads `context.l10n` only speaks Chinese inside this; a host
/// built without the delegates renders English (that is what keeps the older
/// English hosts unmodified). Words read without a context come from
/// `setAppStrings`, which a test sets alongside.
Widget localizedApp(Locale locale, Widget home) => MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: orthantTheme(Brightness.light),
      home: Scaffold(body: home),
    );
