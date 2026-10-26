/**
 * The homepage's platform switch.
 *
 * public/platform.js marked <html> with data-platform before the page painted:
 * the visitor's own platform, or what ?platform= asked for. Everything that
 * differs between macOS and Windows is in the page once each way, and
 * tokens.css hides the other platform's (`.only-macos`, `.only-windows`). The
 * switch's buttons change the mark for the whole page, keep aria-pressed true
 * to it, and write the choice into the address, so that a link shows what was
 * shown. Nothing is stored: no cookie, no localStorage (the privacy page says
 * the site sets none).
 */
export type Platform = 'macos' | 'windows';

/** The platform the page shows: macOS when it is unmarked, as without scripting. */
export function shownPlatform(): Platform {
  return document.documentElement.dataset.platform === 'windows' ? 'windows' : 'macos';
}

export function attachPlatformSwitch(root: HTMLElement): void {
  const buttons = Array.from(root.querySelectorAll<HTMLButtonElement>('[data-platform-choice]'));
  const sync = (): void => {
    const shown = shownPlatform();
    for (const b of buttons) b.setAttribute('aria-pressed', String(b.dataset.platformChoice === shown));
  };
  for (const b of buttons) {
    b.addEventListener('click', () => {
      const chosen: Platform = b.dataset.platformChoice === 'windows' ? 'windows' : 'macos';
      document.documentElement.dataset.platform = chosen;
      const url = new URL(window.location.href);
      url.searchParams.set('platform', chosen);
      window.history.replaceState(null, '', url);
      sync();
      // The other platform's demo video is no longer shown; it must not play on unseen.
      const hidden = chosen === 'windows' ? '.only-macos' : '.only-windows';
      for (const v of document.querySelectorAll<HTMLVideoElement>(`video${hidden}, ${hidden} video`)) {
        if (!v.paused) v.pause();
      }
    });
  }
  sync();
}
