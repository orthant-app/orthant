import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/settings/settings.dart';
import 'package:orthant/settings/shortcuts_screen.dart';
import 'package:orthant/shortcuts/bindings.dart';
import 'package:orthant/shortcuts/command_ref.dart';

/// The site documents behaviour, and behaviour lives in Dart. These assertions
/// are the reason the site shares this repo: a separate repo could not have
/// them, and a stale install command or shortcut table would ship silently.
void main() {
  String read(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path is missing');
    return file.readAsStringSync();
  }

  /// Every tracked file under site/, concatenated. Used for claims that may
  /// appear on any page rather than one known file.
  String allSiteText() {
    final buffer = StringBuffer();
    for (final entity in Directory('site/src').listSync(recursive: true)) {
      if (entity is File && (entity.path.endsWith('.md') || entity.path.endsWith('.astro'))) {
        buffer.writeln(entity.readAsStringSync());
      }
    }
    return buffer.toString();
  }

  // An EXACT map, not a containment check. Containment lets a correct row and a
  // stale duplicate coexist: the right row satisfies `contains`, and the stale
  // one still carries a real label, so a "no unknown commands" check passes it
  // too. Map equality rejects missing rows, extra rows, wrong combos and
  // duplicates in one assertion.
  test('the shortcuts page lists exactly the default bindings', () {
    final page = read('site/src/content/docs/shortcuts.md');
    final documented = <String, String>{};
    final row = RegExp(r'^\|\s*([^|]+?)\s*\|\s*`([^`]+)`\s*\|\s*$', multiLine: true);
    for (final match in row.allMatches(page)) {
      final label = match.group(1)!;
      expect(documented.containsKey(label), isFalse,
          reason: 'shortcuts.md has two rows for "$label"');
      documented[label] = match.group(2)!;
    }

    final expected = {
      for (final b in kDefaultBindings)
        kCommandLabels[(b.command as BuiltIn).command]!:
            formatCombo(b.keyCode, b.modifiers),
    };
    expect(documented, expected);
  });

  test('every stated minimum macOS matches the deployment target', () {
    final pbxproj = read('macos/Runner.xcodeproj/project.pbxproj');
    final target =
        RegExp(r'MACOSX_DEPLOYMENT_TARGET = ([\d.]+);').firstMatch(pbxproj)!.group(1)!;
    final major = target.split('.').first;

    // Every claim, not one. A hardcoded list of *wrong* values fails open the
    // moment the target moves past the end of the list.
    final claims = RegExp(r'macOS (\d+)\+')
        .allMatches(allSiteText())
        .map((m) => m.group(1)!)
        .toSet();
    expect(claims, isNotEmpty, reason: 'the site must state a minimum macOS');
    expect(claims, {major},
        reason: 'the deployment target is $major; the site also claims $claims');
  });

  test('every install command names the real cask', () {
    final text = allSiteText();
    // `<` is excluded from the capture, not just whitespace and backticks:
    // inside an .astro file the command sits in `<code>…</code>`, and without
    // it the closing tag is swallowed into the captured cask token. The
    // failure looks like a wrong cask name, which sends you hunting in the
    // page instead of in this regex.
    final commands = RegExp(r'brew install --cask ([^\s`\n<]+)').allMatches(text);
    expect(commands, isNotEmpty, reason: 'the site must show the install command');
    for (final match in commands) {
      expect(match.group(1), 'orthant-app/tap/orthant');
    }
  });

  test('every stated numeric range is the grid range the validator enforces', () {
    final ranges = RegExp(r'\b(\d+)–(\d+)\b')
        .allMatches(allSiteText())
        .map((m) => '${m.group(1)}–${m.group(2)}')
        .toSet();
    final grid = '$kMinGridAxis–$kMaxGridAxis';
    expect(ranges, contains(grid),
        reason: 'the site must state the grid range as $grid');
    // Requiring ONE correct occurrence permits a contradictory one elsewhere.
    // Every en-dash range on the site must be the grid range; if a future page
    // needs a different range, write it without an en dash rather than
    // weakening this.
    expect(ranges, {grid},
        reason: 'an en-dash range other than $grid appeared on the site: $ranges');
  });

  test('exactly one changelog entry is the version pubspec declares', () {
    final pubspec = read('pubspec.yaml');
    final declared =
        RegExp(r'^version:\s*(\S+)\+(\d+)\s*$', multiLine: true).firstMatch(pubspec)!;
    final version = declared.group(1)!;
    final build = declared.group(2)!;

    final entries = <String, String>{};
    for (final entity in Directory('site/src/content/changelog').listSync()) {
      if (entity is File && entity.path.endsWith('.md')) {
        entries[entity.path] = entity.readAsStringSync();
      }
    }

    // NOTE: the brief's literal text has `\\s\$` here (a single, *required*
    // trailing whitespace char before end-of-line). That cannot match a normal
    // frontmatter line: `\s` has only the line's own newline to consume, and
    // multiline `$` matches *before* a newline, not after one — so after `\s`
    // eats it, `$` has nothing left to anchor to. Confirmed with a standalone
    // probe (`RegExp('^version:\\s*1.0.1\\s\$').hasMatch('version: 1.0.1\n...')`
    // → false; the starred form → true) and with this suite: the changelog test
    // failed against Task 5's already-matching `1.0.1.md`, contradicting the
    // brief's own Step 4 ("only the macOS/cask/grid-range tests still FAIL").
    // Starred to match the sibling `published` regex two lines below, which
    // already uses `\s*$`.
    bool declares(String text, String key, String value) =>
        RegExp('^$key:\\s*$value\\s*\$', multiLine: true).hasMatch(text);

    final matching = entries.entries
        .where((e) => declares(e.value, 'version', version) && declares(e.value, 'build', build))
        .toList();

    // The omission this catches: bump pubspec, forget the changelog entry. A
    // guard that only inspects *unpublished* entries returns happily when there
    // are none, which is exactly the state a forgotten entry produces.
    expect(matching, hasLength(1),
        reason: 'pubspec.yaml declares $version+$build — write '
            'site/src/content/changelog/$version.md at release prep');

    final unpublished = entries.entries
        .where((e) => RegExp(r'^published:\s*false\s*$', multiLine: true).hasMatch(e.value))
        .toList();
    expect(unpublished.length, lessThanOrEqualTo(1),
        reason: 'a previous release was never marked published: '
            '${unpublished.map((e) => e.key)}');
    if (unpublished.length == 1) {
      expect(unpublished.single.key, matching.single.key,
          reason: 'the only unpublished entry must be the current version');
    }
  });
}
