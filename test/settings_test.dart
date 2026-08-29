import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/settings/settings.dart';

void main() {
  test('defaults are the shipped grid with no gaps', () {
    const s = Settings();
    expect(s.gridCols, 6);
    expect(s.gridRows, 6);
    expect(s.gaps, isFalse);
    expect(s.effectiveGap, 0);
  });

  test('effectiveGap is zero unless gaps are on', () {
    // The size survives being switched off, so the value the user chose is
    // still there — and still visible in the pane — when they switch it back on.
    expect(const Settings(gaps: false, gapSize: 12).effectiveGap, 0);
    expect(const Settings(gaps: true, gapSize: 12).effectiveGap, 12);
  });

  test('the default grid still divides by 2 and 3', () {
    // 6 is the smallest axis giving exact halves *and* exact thirds. A user is
    // free to choose 5; the default is not.
    const s = Settings();
    for (final axis in [s.gridCols, s.gridRows]) {
      expect(axis % 2, 0);
      expect(axis % 3, 0);
    }
  });

  test('clamped() pulls out-of-range values into range', () {
    final s = const Settings(gridCols: 99, gridRows: 0, gapSize: -5).clamped();
    expect(s.gridCols, kMaxGridAxis);
    expect(s.gridRows, kMinGridAxis);
    expect(s.gapSize, 0);
  });

  test('a valid value survives clamping unchanged', () {
    const s = Settings(gridCols: 10, gridRows: 4, gaps: true, gapSize: 12);
    expect(s.clamped(), s);
  });

  test('copyWith replaces only what it is given', () {
    const s = Settings();
    expect(s.copyWith(gridCols: 8).gridCols, 8);
    expect(s.copyWith(gridCols: 8).gridRows, s.gridRows);
    expect(s.copyWith(gaps: true).gapSize, s.gapSize);
  });

  test('value equality', () {
    expect(const Settings(gridCols: 8), const Settings(gridCols: 8));
    expect(const Settings(gridCols: 8) == const Settings(gridCols: 4), isFalse);
    expect(const Settings(gridCols: 8).hashCode,
        const Settings(gridCols: 8).hashCode);
  });
}
