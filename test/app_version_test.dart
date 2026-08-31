import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/window_controller.dart';

void main() {
  group('AppVersion formatting', () {
    test('renders the macOS convention, marketing version and build', () {
      // The exact form Sparkle's own prompt uses ("Orthant 1.0.0 (2) is now
      // available"), so the app and its updater describe a version the same way.
      expect(const AppVersion('1.0.0', '2').display, '1.0.0 (2)');
    });

    test('the build number is what distinguishes one beta from the next', () {
      // CFBundleShortVersionString is identical across a whole beta line — Apple
      // requires three integers, so `-beta.N` is not in the bundle at all. Two
      // different betas are therefore indistinguishable without the build.
      const one = AppVersion('1.0.0', '1');
      const two = AppVersion('1.0.0', '2');
      expect(one.shortVersion, two.shortVersion);
      expect(one.display, isNot(two.display));
    });

    test('a version the platform could not supply is not known', () {
      // The failure path that matters: a reply that never arrived, or arrived
      // half-formed, must render nothing rather than "1.0.0 ()" or " ()".
      expect(const AppVersion('', '').isKnown, isFalse);
      expect(const AppVersion('', '').display, isEmpty);
      expect(const AppVersion('1.0.0', '').isKnown, isFalse);
      expect(const AppVersion('', '2').isKnown, isFalse);
    });

    test('value equality, built through a function so const canonicalisation '
        'cannot make the test pass with == deleted', () {
      AppVersion make(String s, String b) => AppVersion(s, b);
      expect(make('1.0.0', '2'), make('1.0.0', '2'));
      expect(make('1.0.0', '2'), isNot(make('1.0.0', '3')));
      expect(make('1.0.0', '2').hashCode, make('1.0.0', '2').hashCode);
    });
  });
}
