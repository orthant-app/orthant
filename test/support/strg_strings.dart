import 'package:orthant/l10n/app_localizations_en.dart';

/// English with a German keyboard's legends for a few keys, standing in for a
/// language that prints its own key words. Ctrl reads `STRG`, Enter `Eingabe`,
/// Delete `Entf`, the keypad `Ziff`, and the list of modifiers says `oder`;
/// macOS's two words become `Abbruch` (esc) and `Zeilenumbruch` (Return), which
/// no real keyboard prints and which differ from Windows' on purpose, so one
/// platform's words leaking into the other shows.
///
/// Set it as `appStrings` to prove the key words are read from the strings at
/// use rather than fixed in code; every other key keeps its English legend, so
/// `Win+STRG+Shift+←` is the one chord that shows the difference.
class StrgStrings extends AppLocalizationsEn {
  @override
  String get keyCtrl => 'STRG';

  @override
  String get keyEnter => 'Eingabe';

  @override
  String get keyDelete => 'Entf';

  @override
  String get keyMacEscape => 'Abbruch';

  @override
  String get keyMacReturn => 'Zeilenumbruch';

  @override
  String keyNumpad(String key) => 'Ziff $key';

  @override
  String keyListAnyModifier(String a, String b, String c, String d) =>
      '$a, $b, $c oder $d';
}
