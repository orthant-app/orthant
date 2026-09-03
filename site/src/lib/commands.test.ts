import { describe, expect, it } from 'vitest';
import { BINDINGS } from './commands';

describe('BINDINGS', () => {
  // Eleven, not ten: kDefaultBindings opens with showGrid (⌃⌥O), then the ten
  // placements. A map that renders ten is missing the one shortcut a new user
  // needs first.
  it('has the eleven defaults the app ships', () => {
    expect(BINDINGS).toHaveLength(11);
  });

  /*
   * Three kinds, because the app has three shapes and flattening them lies:
   *
   *  - 'block'     nine placements, gridBlock(cols: 2, rows: 2) with fixed
   *                indices (region_commands.dart:17-25)
   *  - 'keepsSize' center, which preserves the captured window's CURRENT size
   *                and centres it (region_commands.dart:28-36) — no fixed shape
   *  - 'summon'    showGrid, which opens the overlay and places nothing at all
   *
   * An earlier draft modelled center and the summon both as `block: null`,
   * which collides two different facts into one absence: center HAS a target
   * rect and no fixed fraction; the summon has no target rect whatsoever.
   */
  it('separates the summon from the command that merely keeps its size', () => {
    expect(BINDINGS.filter((b) => b.kind === 'summon').map((b) => b.id)).toEqual(['showGrid']);
    expect(BINDINGS.filter((b) => b.kind === 'keepsSize').map((b) => b.id)).toEqual(['center']);
    expect(BINDINGS.filter((b) => b.kind === 'block')).toHaveLength(9);
  });

  it('matches the app for the four indices that are easy to transpose', () => {
    const block = (id: string) => {
      const b = BINDINGS.find((x) => x.id === id);
      return b && b.kind === 'block' ? b.block : null;
    };
    expect(block('leftHalf')).toEqual({ c0: 0, c1: 0, r0: 0, r1: 1 });
    expect(block('topHalf')).toEqual({ c0: 0, c1: 1, r0: 0, r1: 0 });
    expect(block('topRight')).toEqual({ c0: 1, c1: 1, r0: 0, r1: 0 });
    expect(block('maximize')).toEqual({ c0: 0, c1: 1, r0: 0, r1: 1 });
  });

  it('gives every binding a label and a ⌃⌥ combo', () => {
    for (const b of BINDINGS) {
      expect(b.label.length, b.id).toBeGreaterThan(0);
      expect(b.combo.startsWith('⌃⌥'), b.id).toBe(true);
    }
  });
});
