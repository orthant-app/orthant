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
      AppVersion make(String s, String b, [String n = '']) =>
          AppVersion(s, b, releaseName: n);
      expect(make('1.0.0', '2'), make('1.0.0', '2'));
      expect(make('1.0.0', '2'), isNot(make('1.0.0', '3')));
      expect(make('1.0.0', '2').hashCode, make('1.0.0', '2').hashCode);
      // Two bundles can agree on both version keys and still be different
      // releases — that is the entire reason the release name exists.
      expect(
        make('1.0.0', '2', '1.0.0-beta.2'),
        isNot(make('1.0.0', '2', '1.0.0')),
      );
    });
  });

  group('AppVersion release name', () {
    test('a stamped release name is what gets shown', () {
      // The point of the whole mechanism: a pre-release label cannot live in
      // CFBundleShortVersionString (Apple requires three integers), so without
      // this an installed beta and the stable after it both render "1.0.0 (n)"
      // and only differ by a number nobody can interpret.
      expect(
        const AppVersion('1.0.0', '5', releaseName: '1.0.1-beta.2').display,
        '1.0.1-beta.2',
      );
      expect(
        const AppVersion('1.0.1', '5', releaseName: '1.0.1').display,
        '1.0.1',
      );
    });

    test('a beta and the stable that follows it are distinguishable', () {
      // Same marketing version, adjacent builds — indistinguishable to a user
      // before the release name, which is what prompted this.
      const beta = AppVersion('1.0.0', '3', releaseName: '1.0.0-beta.3');
      const stable = AppVersion('1.0.0', '4', releaseName: '1.0.0');
      expect(beta.shortVersion, stable.shortVersion);
      expect(beta.display, '1.0.0-beta.3');
      expect(stable.display, '1.0.0');
    });

    test('no release name falls back to marketing version and build', () {
      // Every locally-built bundle. There is no tag to name it after, and the
      // build number is the only thing separating it from the last dev build.
      expect(const AppVersion('1.0.0', '4').display, '1.0.0 (4)');
      expect(const AppVersion('1.0.0', '4').isKnown, isTrue);
    });

    test('a release name alone is enough to be known', () {
      // Defensive rather than expected: a bundle missing both version keys but
      // carrying a stamped name still has something true to say.
      const v = AppVersion('', '', releaseName: '1.0.1');
      expect(v.isKnown, isTrue);
      expect(v.display, '1.0.1');
    });
  });
}
