import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/shortcuts/region_commands.dart';
import 'package:orthant/shortcuts/shortcut_command.dart';

void main() {
  test('every region command has a shortcut command', () {
    // The mapping is built by *name*, so this fails loudly the moment someone
    // adds a RegionCommand without its counterpart — rather than silently
    // shipping a placement nobody can bind, or worse, one that maps onto the
    // wrong region because the indices drifted.
    for (final r in RegionCommand.values) {
      expect(ShortcutCommand.values.map((c) => c.region), contains(r),
          reason: '$r has no ShortcutCommand');
    }
  });

  test('showGrid is the only command without a region', () {
    final regionless =
        ShortcutCommand.values.where((c) => c.region == null).toList();
    expect(regionless, [ShortcutCommand.showGrid]);
  });

  test('the mapping is one-to-one', () {
    // Two shortcut commands sharing a region would mean one of them can never
    // be dispatched distinctly — the id round trip would collapse them.
    final regions = ShortcutCommand.values
        .map((c) => c.region)
        .whereType<RegionCommand>()
        .toList();
    expect(regions.toSet().length, regions.length);
    expect(regions.length, RegionCommand.values.length);
  });

  test('showGrid is index 0, well clear of the reserved native ids', () {
    // Hotkey ids are enum indices; HotkeyManager reserves 900+ for the
    // overlay's own Esc/Return grabs. The two ranges must not be able to meet.
    expect(ShortcutCommand.showGrid.index, 0);
    expect(ShortcutCommand.values.length, lessThan(900));
  });
}
