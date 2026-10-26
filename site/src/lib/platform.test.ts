// @vitest-environment happy-dom
import { afterEach, describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { attachPlatformSwitch, shownPlatform } from './platform';

function mount(platform?: 'macos' | 'windows'): HTMLElement {
  if (platform) document.documentElement.dataset.platform = platform;
  else delete document.documentElement.dataset.platform;
  document.body.innerHTML = `
    <div id="root">
      <button type="button" data-platform-choice="macos">macOS</button>
      <button type="button" data-platform-choice="windows">Windows</button>
    </div>`;
  return document.getElementById('root') as HTMLElement;
}
const pressed = () =>
  Array.from(document.querySelectorAll<HTMLButtonElement>('[data-platform-choice]')).map(
    (b) => `${b.dataset.platformChoice}=${b.getAttribute('aria-pressed')}`,
  );

afterEach(() => {
  delete document.documentElement.dataset.platform;
  window.history.replaceState(null, '', '/');
});

describe('the platform switch', () => {
  it('says which platform is shown, macOS when the page is unmarked', () => {
    mount();
    expect(shownPlatform()).toBe('macos');
    mount('windows');
    expect(shownPlatform()).toBe('windows');
  });

  it('presses the button of the platform the page already shows', () => {
    attachPlatformSwitch(mount('windows'));
    expect(pressed()).toEqual(['macos=false', 'windows=true']);
  });

  it('shows the chosen platform on the whole page, and says so in the address', () => {
    attachPlatformSwitch(mount('macos'));
    document.querySelector<HTMLButtonElement>('[data-platform-choice="windows"]')!.click();
    expect(document.documentElement.dataset.platform).toBe('windows');
    expect(pressed()).toEqual(['macos=false', 'windows=true']);
    expect(new URL(window.location.href).searchParams.get('platform')).toBe('windows');
    document.querySelector<HTMLButtonElement>('[data-platform-choice="macos"]')!.click();
    expect(document.documentElement.dataset.platform).toBe('macos');
    expect(new URL(window.location.href).searchParams.get('platform')).toBe('macos');
  });

  it('pauses a video that the switch has just hidden', () => {
    const root = mount('macos');
    document.body.insertAdjacentHTML('beforeend', '<video class="only-macos"></video><video class="only-windows"></video>');
    const [mac] = Array.from(document.querySelectorAll('video'));
    let paused = false;
    Object.defineProperty(mac, 'paused', { get: () => paused, configurable: true });
    mac.pause = () => { paused = true; };
    attachPlatformSwitch(root);
    document.querySelector<HTMLButtonElement>('[data-platform-choice="windows"]')!.click();
    expect(paused).toBe(true);
  });
});

/**
 * public/platform.js runs before the page paints, as a plain script, so it is
 * run here as the browser runs it: in a context of its own with a location
 * and a navigator. Its rule must be the Worker's for /download
 * (worker/download.ts, platformOf), so a visitor is never shown one platform
 * and sent the other's download.
 */
describe('public/platform.js', () => {
  // From the site's own folder, where vitest runs: under happy-dom,
  // import.meta.url is not a file URL.
  const source = readFileSync('public/platform.js', 'utf8');
  function decide(search: string, navigator: Record<string, unknown>): string | null {
    let marked: string | null = null;
    const document = { documentElement: { setAttribute: (k: string, v: string) => { if (k === 'data-platform') marked = v; } } };
    runInNewContext(source, { window: { location: { search } }, navigator, document, URLSearchParams });
    return marked;
  }
  const WIN_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
  const MAC_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';

  it('reads the platform hint Chromium gives, over the User-Agent', () => {
    expect(decide('', { userAgentData: { platform: 'Windows' }, userAgent: MAC_UA })).toBe('windows');
    expect(decide('', { userAgentData: { platform: 'macOS' }, userAgent: WIN_UA })).toBe('macos');
  });

  it('reads the User-Agent when there is no hint, as from Firefox or Safari', () => {
    expect(decide('', { userAgent: WIN_UA })).toBe('windows');
    expect(decide('', { userAgent: MAC_UA })).toBe('macos');
  });

  it('shows macOS to anything else', () => {
    expect(decide('', { userAgentData: { platform: 'Linux' }, userAgent: '' })).toBe('macos');
    expect(decide('', { userAgent: 'Mozilla/5.0 (X11; Linux x86_64)' })).toBe('macos');
    expect(decide('', {})).toBe('macos');
  });

  it('lets ?platform= choose, and ignores anything else it says', () => {
    expect(decide('?platform=windows', { userAgent: MAC_UA })).toBe('windows');
    expect(decide('?platform=macos', { userAgent: WIN_UA })).toBe('macos');
    expect(decide('?platform=linux', { userAgent: WIN_UA })).toBe('windows');
  });
});
