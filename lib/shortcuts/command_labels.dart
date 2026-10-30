import 'dart:ui' show Locale;

import '../l10n/app_localizations.dart';
import 'command_ref.dart';
import 'custom_region.dart';
import 'shortcut_command.dart';

/// What [ref] is called, in the language of [l].
///
/// **The one place a command gets its name.** The Shortcuts list, the notices
/// that name a command ("Left half lost ⌃⌥←"), the screen reader's labels for a
/// row and the region picker's collision notice all ask here, so a command is
/// the same words wherever it is mentioned in one language, and a new language
/// names the eleven in its ARB file and nowhere else.
///
/// A custom region is named by [regionDisplayName]: a name Orthant generated
/// ("Left ⅔") in the language, and one the user typed exactly as typed.
///
/// A region the list no longer holds falls back to the generic name rather than
/// throwing. The loader drops a binding whose region did not survive, so a
/// nameless row should be unreachable, and a build-time throw in a Release
/// build is a featureless grey box, which is how the last one of these
/// presented.
String commandLabel(
  CommandRef ref,
  List<CustomRegion> regions,
  AppLocalizations l,
) =>
    switch (ref) {
      BuiltIn(:final command) => switch (command) {
          ShortcutCommand.showGrid => l.commandOpenGrid,
          ShortcutCommand.leftHalf => l.commandLeftHalf,
          ShortcutCommand.rightHalf => l.commandRightHalf,
          ShortcutCommand.topHalf => l.commandTopHalf,
          ShortcutCommand.bottomHalf => l.commandBottomHalf,
          ShortcutCommand.topLeft => l.commandTopLeft,
          ShortcutCommand.topRight => l.commandTopRight,
          ShortcutCommand.bottomLeft => l.commandBottomLeft,
          ShortcutCommand.bottomRight => l.commandBottomRight,
          ShortcutCommand.maximize => l.commandMaximize,
          ShortcutCommand.center => l.commandCenter,
        },
      Custom(:final id) => _regionNamed(id, regions, l),
    };

String _regionNamed(String id, List<CustomRegion> regions, AppLocalizations l) {
  for (final r in regions) {
    if (r.id == id) return regionDisplayName(r, l);
  }
  return l.regionNameCustom;
}

/// The eleven commands' names in English, which the site's documentation is
/// written in and `site_docs_test.dart` holds it to. Derived from the English
/// messages, so there is one copy of those words, not two.
final Map<ShortcutCommand, String> kCommandLabels = () {
  final english = lookupAppLocalizations(const Locale('en'));
  return {
    for (final c in ShortcutCommand.values)
      c: commandLabel(BuiltIn(c), const [], english),
  };
}();
