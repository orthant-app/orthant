import { describe, expect, it } from 'vitest';
import { FACTS } from './facts';

/*
 * Spec §3.4 fixes the exact wording of every number on the site, because the
 * figures are real measurements and rounding them loses information: "0%" could
 * be a rounding of 0.4%, where "0.0%" states the precision the measurement has.
 * A previous draft of the site said "0% CPU" for exactly that reason.
 */
describe('FACTS', () => {
  // The WHOLE array, notes included. Pinning only `value` leaves the notes
  // unpinned, and "0 wake-ups while idle" is itself a measured claim with a
  // provenance row — it just happens to live in a note.
  it('is exactly the approved set, in order', () => {
    expect(FACTS).toEqual([
      { value: 'Free · MIT', note: 'open source, no paid tier' },
      { value: 'about 50 ms', note: 'grid on every display, on macOS' },
      { value: '0.0% CPU', note: '0 wake-ups while idle, on macOS' },
      { value: 'macOS 13+', note: 'Ventura and later' },
      { value: 'Windows 10 (1809+)', note: 'and Windows 11, 64-bit' },
    ]);
  });

  /*
   * The latency and idle figures were measured on macOS. Beside a Windows
   * requirement, a bare figure reads as true of both platforms, and the idle
   * one is not: Windows has no 0.0% CPU measurement behind it.
   */
  it('says which platform the measured figures were measured on', () => {
    for (const value of ['about 50 ms', '0.0% CPU']) {
      const fact = FACTS.find((f) => f.value === value);
      expect(fact, value).toBeDefined();
      expect(fact!.note, value).toMatch(/on macOS$/);
    }
  });

  it('never rounds the CPU measurement', () => {
    for (const f of FACTS) expect(f.value).not.toBe('0% CPU');
  });

  it('gives every fact a note, since a bare number explains nothing', () => {
    for (const f of FACTS) expect(f.note.length, f.value).toBeGreaterThan(0);
  });

  // Pipeline vocabulary is barred from the strip (spec §8). It is permitted
  // once, beside the install command, and Step 7 puts it there.
  it('carries no pipeline vocabulary', () => {
    const text = FACTS.map((f) => `${f.value} ${f.note}`).join(' ').toLowerCase();
    expect(text).not.toContain('notariz');
    expect(text).not.toContain('developer id');
  });
});
