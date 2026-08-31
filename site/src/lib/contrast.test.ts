import { describe, expect, it } from 'vitest';
import { contrastRatio } from './contrast';

describe('contrastRatio', () => {
  it('computes the known white-on-black extreme', () => {
    expect(contrastRatio('#FFFFFF', '#000000')).toBeCloseTo(21, 1);
  });

  it('computes an identity as 1', () => {
    expect(contrastRatio('#4A4A4A', '#4A4A4A')).toBeCloseTo(1, 5);
  });

  // Body copy tokens must clear WCAG AA (4.5:1) against their own surface.
  it.each([
    ['light body', '#000000E6', '#FFFFFF'],
    ['dark body', '#FFFFFFE6', '#1E1E1F'],
    ['light secondary', '#0000008C', '#FFFFFF'],
    ['dark secondary', '#FFFFFF8C', '#1E1E1F'],
  ])('%s clears 4.5:1', (_name, fg, bg) => {
    expect(contrastRatio(fg, bg)).toBeGreaterThanOrEqual(4.5);
  });
});
