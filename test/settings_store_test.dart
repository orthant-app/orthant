import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/settings/settings.dart';
import 'package:orthant/settings/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Settings> loadFrom(String? stored) async {
    SharedPreferences.setMockInitialValues(
        stored == null ? {} : {'flutter.orthant.settings.v1': stored});
    return SettingsStore().load();
  }

  test('an empty store yields the defaults', () async {
    expect(await loadFrom(null), const Settings());
  });

  test('round-trips every field', () async {
    SharedPreferences.setMockInitialValues({});
    const written = Settings(gridCols: 8, gridRows: 4, gaps: true, gapSize: 12);
    await SettingsStore().save(written);
    expect(await SettingsStore().load(), written);
  });

  // Everything below is about surviving a preferences file we did not write.
  // load() runs on the launch path, so anything it throws takes the settings
  // down at every start, with no way for the user to recover short of deleting
  // the preferences by hand.

  test('a corrupt file falls back to the defaults rather than throwing',
      () async {
    expect(await loadFrom('{not json at all'), const Settings());
  });

  test('a JSON list where an object belongs yields the defaults', () async {
    expect(await loadFrom('[1,2,3]'), const Settings());
  });

  test('a bad field falls back alone, keeping its valid neighbours', () async {
    // Per-field, not all-or-nothing. Unlike the bindings list — where a bad
    // entry costs one command its combo — this is a single object, so
    // rejecting it wholesale would discard a grid the user deliberately chose
    // because of an unrelated typo.
    final s = await loadFrom(jsonEncode({
      'gridCols': 8,
      'gridRows': 'four', // wrong type
      'gaps': true,
      'gapSize': 10,
    }));
    expect(s.gridCols, 8, reason: 'the good field survives');
    expect(s.gridRows, 6, reason: 'the bad one falls back on its own');
    expect(s.gaps, isTrue);
    expect(s.gapSize, 10);
  });

  test('a missing field takes its default', () async {
    final s = await loadFrom(jsonEncode({'gridCols': 8}));
    expect(s.gridCols, 8);
    expect(s.gridRows, 6);
    expect(s.gaps, isFalse);
    expect(s.gapSize, const Settings().gapSize);
  });

  test('out-of-range numbers are clamped, not rejected', () async {
    // Clamped rather than discarded: someone who hand-edits a 400-column grid
    // wanted a lot of columns, and the largest usable one is a better answer
    // than silently reverting to six.
    final s = await loadFrom(jsonEncode({'gridCols': 400, 'gridRows': 1}));
    expect(s.gridCols, kMaxGridAxis);
    expect(s.gridRows, kMinGridAxis);
  });

  test('a negative gap cannot reach the placement formula', () async {
    // gridBlock subtracts the gap from the frame; a negative one would inflate
    // the target rect past the screen edge instead of insetting it.
    final s = await loadFrom(jsonEncode({'gaps': true, 'gapSize': -40}));
    expect(s.gapSize, 0);
    expect(s.effectiveGap, 0);
  });

  test('a gap larger than the cap is clamped', () async {
    final s = await loadFrom(jsonEncode({'gaps': true, 'gapSize': 9999}));
    expect(s.gapSize, kMaxGapSize);
  });

  group('the onboarded flag', () {
    test('a fresh install has not onboarded', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await SettingsStore().hasOnboarded(), isFalse);
    });

    test('marking is durable', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SettingsStore();
      await store.markOnboarded();
      expect(await store.hasOnboarded(), isTrue);
    });

    test('Reset to Defaults does not make onboarding reappear', () async {
      // The flag is app state, not a user setting, which is why it is a
      // separate key rather than a field on Settings. Saving the defaults must
      // leave it alone.
      SharedPreferences.setMockInitialValues({});
      final store = SettingsStore();
      await store.markOnboarded();
      await store.save(const Settings());
      expect(await store.hasOnboarded(), isTrue);
    });
  });
}
