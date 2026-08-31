import { describe, expect, it } from 'vitest';
import { resolveDownloadUrl } from './appcast';

const feed = (items: string) =>
  `<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel><title>Orthant</title>${items}</channel>
</rss>`;

const item = (opts: { url: string; short: string; deltas?: boolean }) => `
  <item>
    <title>${opts.short}</title>
    <sparkle:version>5</sparkle:version>
    <sparkle:shortVersionString>${opts.short}</sparkle:shortVersionString>
    <enclosure url="${opts.url}" length="21257025" type="application/octet-stream"/>
    ${opts.deltas ? `<sparkle:deltas><enclosure url="https://github.com/orthant-app/orthant/releases/download/v1.0.1/Orthant5-4.delta" sparkle:deltaFrom="4"/></sparkle:deltas>` : ''}
  </item>`;

const GOOD = 'https://github.com/orthant-app/orthant/releases/download/v1.0.1/Orthant-1.0.1.dmg';

describe('resolveDownloadUrl', () => {
  it('returns the first item\'s full-DMG enclosure', () => {
    expect(resolveDownloadUrl(feed(item({ url: GOOD, short: '1.0.1' })))).toBe(GOOD);
  });

  it('ignores delta enclosures', () => {
    expect(resolveDownloadUrl(feed(item({ url: GOOD, short: '1.0.1', deltas: true })))).toBe(GOOD);
  });

  it('uses the first item only, ignoring older releases', () => {
    const older = item({
      url: 'https://github.com/orthant-app/orthant/releases/download/v1.0.1/Orthant-1.0.0.dmg',
      short: '1.0.0',
    });
    const xml = feed(item({ url: GOOD, short: '1.0.1' }) + older);
    expect(resolveDownloadUrl(xml)).toBe(GOOD);
  });

  it('rejects a feed with no items', () => {
    expect(resolveDownloadUrl(feed(''))).toBeNull();
  });

  it('rejects two full enclosures in one item rather than guessing', () => {
    const two = `<item><sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>
      <enclosure url="${GOOD}"/><enclosure url="${GOOD}"/></item>`;
    expect(resolveDownloadUrl(feed(two))).toBeNull();
  });

  // A first item offering only a delta — a real state during a partial release.
  //
  // This asserts BEHAVIOUR; it does not kill a mutant, and cannot. `full.length
  // !== 1` and `full.length > 1` are equivalent here: with zero enclosures
  // `full[0]` is undefined and `new URL(undefined)` always throws into the
  // catch, so both forms return null for every input. Two independent layers
  // reject this feed, which is defence in depth rather than a gap. Keep the
  // explicit `!== 1` guard regardless — it states the intent that the parse
  // failure only happens to enforce.
  it('rejects an item whose only enclosure is a delta', () => {
    const deltaOnly = `<item><sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>
      <sparkle:deltas><enclosure url="https://github.com/orthant-app/orthant/releases/download/v1.0.1/Orthant5-4.delta"/></sparkle:deltas></item>`;
    expect(resolveDownloadUrl(feed(deltaOnly))).toBeNull();
  });

  // Nothing else exercises the search/hash rejection, so it could be deleted
  // silently — and it is the check that stops an attacker-controlled query
  // string riding along on the redirect.
  it('rejects a query string or fragment on an otherwise valid URL', () => {
    for (const suffix of ['?ref=evil', '#evil']) {
      expect(resolveDownloadUrl(feed(item({ url: GOOD + suffix, short: '1.0.1' })))).toBeNull();
    }
  });

  it.each([
    ['a foreign host', 'https://evil.example/orthant-app/orthant/releases/download/v1.0.1/Orthant-1.0.1.dmg'],
    ['http', 'http://github.com/orthant-app/orthant/releases/download/v1.0.1/Orthant-1.0.1.dmg'],
    ['userinfo', 'https://user:pw@github.com/orthant-app/orthant/releases/download/v1.0.1/Orthant-1.0.1.dmg'],
    ['an explicit port', 'https://github.com:8443/orthant-app/orthant/releases/download/v1.0.1/Orthant-1.0.1.dmg'],
    ['a foreign repo', 'https://github.com/someone/else/releases/download/v1.0.1/Orthant-1.0.1.dmg'],
    ['a non-DMG asset', 'https://github.com/orthant-app/orthant/releases/download/v1.0.1/Orthant-1.0.1.zip'],
    ['a traversal filename', 'https://github.com/orthant-app/orthant/releases/download/v1.0.1/../../Orthant-1.0.1.dmg'],
    ['unparseable garbage', 'not a url'],
  ])('rejects %s', (_name, url) => {
    expect(resolveDownloadUrl(feed(item({ url, short: '1.0.1' })))).toBeNull();
  });

  it('rejects a filename whose version disagrees with shortVersionString', () => {
    expect(resolveDownloadUrl(feed(item({ url: GOOD, short: '9.9.9' })))).toBeNull();
  });

  it('rejects malformed XML', () => {
    expect(resolveDownloadUrl('<rss><channel><item>')).toBeNull();
  });
});
