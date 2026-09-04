// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from 'vitest';
import { attachDemo } from './demo';

/**
 * happy-dom implements none of the Fullscreen API by default (`'requestFullscreen'
 * in video` is false, `document.fullscreenEnabled` is undefined) but the
 * properties are plain, assignable fields — no getter blocks a test from
 * standing in for each of the three real routes browsers take. Reset after
 * every test so a route stubbed in one case cannot leak into the next.
 */
function mount(): HTMLElement {
  document.body.innerHTML = `
    <div id="root">
      <video><source src="/demo.webm" type="video/webm" /></video>
    </div>`;
  return document.getElementById('root') as HTMLElement;
}

function mountWithoutVideo(): HTMLElement {
  document.body.innerHTML = '<div id="root"></div>';
  return document.getElementById('root') as HTMLElement;
}

afterEach(() => {
  delete (document as { fullscreenEnabled?: boolean }).fullscreenEnabled;
  delete (document as { webkitFullscreenEnabled?: boolean }).webkitFullscreenEnabled;
});

const button = () => document.querySelector<HTMLButtonElement>('.fs-btn');

// `fullscreenEnabled` is `readonly` in TypeScript's own DOM lib (correctly —
// it is read-only in real browsers too), which is exactly why happy-dom's
// plain, assignable property is useful here: these two casts are the only
// way to stand in for the real getter from a test.
const setFullscreenEnabled = (value: boolean) => {
  (document as { fullscreenEnabled?: boolean }).fullscreenEnabled = value;
};
const setWebkitFullscreenEnabled = (value: boolean) => {
  (document as { webkitFullscreenEnabled?: boolean }).webkitFullscreenEnabled = value;
};

describe('attachDemo — the fullscreen control it adds', () => {
  it('does nothing, and does not throw, when the root has no video', () => {
    const root = mountWithoutVideo();
    expect(() => attachDemo(root)).not.toThrow();
    expect(button()).toBeNull();
  });

  it('adds no button at all when no fullscreen route exists', () => {
    // Deliberately nothing stubbed: this is happy-dom's real, unsupported
    // baseline, standing in for a browser with no fullscreen route. A dead
    // button is worse than no button — the whole point of feature-detecting
    // first, matching copy.ts's rule for its own Copy button.
    const root = mount();
    attachDemo(root);
    expect(button()).toBeNull();
  });

  describe('the standard route', () => {
    it('adds a reachable button that calls Element.requestFullscreen()', () => {
      const root = mount();
      const video = root.querySelector('video') as HTMLVideoElement & {
        requestFullscreen: () => Promise<void>;
      };
      setFullscreenEnabled(true);
      const request = vi.fn().mockResolvedValue(undefined);
      video.requestFullscreen = request;

      attachDemo(root);

      const btn = button();
      expect(btn).not.toBeNull();
      expect(btn!.tagName).toBe('BUTTON');
      expect(btn!.getAttribute('type')).toBe('button');
      expect(btn!.getAttribute('aria-label')).toBeTruthy();
      expect(btn!.hasAttribute('tabindex')).toBe(false); // default tab order, not opted out
      expect(btn!.hasAttribute('disabled')).toBe(false);

      btn!.click();
      expect(request).toHaveBeenCalledTimes(1);
    });

    it('does not throw synchronously when the returned promise rejects', () => {
      const root = mount();
      const video = root.querySelector('video') as HTMLVideoElement & {
        requestFullscreen: () => Promise<void>;
      };
      setFullscreenEnabled(true);
      video.requestFullscreen = vi.fn().mockRejectedValue(new Error('denied'));

      attachDemo(root);
      expect(() => button()!.click()).not.toThrow();
    });

    // The assertion above is real but weak: a rejection is only ever reported
    // asynchronously, so a click handler that forgets `.catch()` entirely
    // would still pass it — proven by mutation testing (task report), where
    // deleting `.catch(() => {})` left every other test green. This one
    // asserts the thing a missing `.catch` actually breaks: that something
    // was attached to the promise before it could be reported unhandled.
    // (A `process.on('unhandledRejection', …)` + microtask-flush version was
    // tried first and did not catch the same mutation reliably — Node's
    // timing for that event is not guaranteed within one `setTimeout(0)` —
    // so this spies on `Promise.prototype.catch` directly instead, which is
    // deterministic. `mockRestore()` limits the spy to this one test; the
    // default pass-through implementation still lets the real `.catch(() =>
    // {})` run, so the rejection is genuinely handled either way.)
    it('calls .catch on the promise Element.requestFullscreen() returns', () => {
      const root = mount();
      const video = root.querySelector('video') as HTMLVideoElement & {
        requestFullscreen: () => Promise<void>;
      };
      setFullscreenEnabled(true);
      video.requestFullscreen = vi.fn().mockRejectedValue(new Error('denied'));
      const catchSpy = vi.spyOn(Promise.prototype, 'catch');

      try {
        attachDemo(root);
        button()!.click();
        expect(catchSpy).toHaveBeenCalledTimes(1);
      } finally {
        catchSpy.mockRestore();
      }
    });

    it('is not taken when fullscreenEnabled is false even though the method exists', () => {
      // E.g. a disallowed iframe: the method is present but calling it would
      // reject. Deliberately not calling setFullscreenEnabled, and no webkit
      // route stubbed either, so this isolates the `document.fullscreenEnabled`
      // gate rather than falling through to a route that would mask it.
      const root = mount();
      const video = root.querySelector('video') as HTMLVideoElement & {
        requestFullscreen: () => Promise<void>;
      };
      video.requestFullscreen = vi.fn();

      attachDemo(root);
      expect(button()).toBeNull();
    });

    it('is preferred over the webkit routes when both exist', () => {
      const root = mount();
      const video = root.querySelector('video') as HTMLVideoElement & {
        requestFullscreen: () => Promise<void>;
        webkitEnterFullscreen: () => void;
      };
      setFullscreenEnabled(true);
      const request = vi.fn().mockResolvedValue(undefined);
      video.requestFullscreen = request;
      const enterIOS = vi.fn();
      video.webkitEnterFullscreen = enterIOS;

      attachDemo(root);
      button()!.click();

      expect(request).toHaveBeenCalledTimes(1);
      expect(enterIOS).not.toHaveBeenCalled();
    });
  });

  describe('the legacy prefixed-element route', () => {
    it('adds a button that calls webkitRequestFullscreen() when the standard API is absent', () => {
      const root = mount();
      const video = root.querySelector('video') as HTMLVideoElement & {
        webkitRequestFullscreen: () => void;
      };
      setWebkitFullscreenEnabled(true);
      const request = vi.fn();
      video.webkitRequestFullscreen = request;

      attachDemo(root);
      const btn = button();
      expect(btn).not.toBeNull();

      btn!.click();
      expect(request).toHaveBeenCalledTimes(1);
    });
  });

  describe('the iOS Safari route (Element.requestFullscreen does not exist for <video>)', () => {
    it('adds a button that calls video.webkitEnterFullscreen()', () => {
      const root = mount();
      const video = root.querySelector('video') as HTMLVideoElement & {
        webkitEnterFullscreen: () => void;
      };
      // Deliberately no document.fullscreenEnabled and no
      // webkitRequestFullscreen — Safari on iPhone implements neither for an
      // arbitrary element, only the video's own native fullscreen playback.
      const enterIOS = vi.fn();
      video.webkitEnterFullscreen = enterIOS;

      attachDemo(root);
      const btn = button();
      expect(btn).not.toBeNull();

      btn!.click();
      expect(enterIOS).toHaveBeenCalledTimes(1);
    });
  });
});
