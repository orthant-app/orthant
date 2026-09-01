import { describe, expect, it } from 'vitest';
import { currentVersion, publishedStable, type ReleaseEntry } from './releases';

const entry = (o: Partial<ReleaseEntry> & { version: string }): ReleaseEntry => ({
  build: 1, channel: 'stable', published: true, date: new Date('2026-08-31'), ...o,
});

describe('publishedStable', () => {
  it('drops unpublished entries', () => {
    const out = publishedStable([entry({ version: '1.0.2', published: false }), entry({ version: '1.0.1' })]);
    expect(out.map((e) => e.version)).toEqual(['1.0.1']);
  });

  it('drops beta entries', () => {
    const out = publishedStable([entry({ version: '1.1.0-beta.1', channel: 'beta' }), entry({ version: '1.0.1' })]);
    expect(out.map((e) => e.version)).toEqual(['1.0.1']);
  });

  it('orders by build descending, newest first', () => {
    const out = publishedStable([
      entry({ version: '1.0.0', build: 4 }),
      entry({ version: '1.0.1', build: 5 }),
    ]);
    expect(out.map((e) => e.version)).toEqual(['1.0.1', '1.0.0']);
  });
});

describe('currentVersion', () => {
  it('is the newest published stable', () => {
    expect(currentVersion([entry({ version: '1.0.0', build: 4 }), entry({ version: '1.0.1', build: 5 })]))
      .toBe('1.0.1');
  });

  it('never advertises an unpublished release', () => {
    expect(currentVersion([entry({ version: '1.0.2', build: 6, published: false }), entry({ version: '1.0.1', build: 5 })]))
      .toBe('1.0.1');
  });

  it('never advertises a beta', () => {
    expect(currentVersion([entry({ version: '1.1.0-beta.1', build: 6, channel: 'beta' }), entry({ version: '1.0.1', build: 5 })]))
      .toBe('1.0.1');
  });

  it('is null when nothing is published', () => {
    expect(currentVersion([entry({ version: '1.0.0', published: false })])).toBeNull();
  });
});
