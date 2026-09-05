/**
 * Add a fullscreen control to the demo video.
 *
 * Progressive enhancement in the same shape as copy.ts's Copy button: the
 * button is only CREATED when a fullscreen route actually exists for this
 * browser, appended nowhere otherwise. A button that does nothing is worse
 * than no button — that is the standing rule this file follows, not a new
 * one for video.
 *
 * Three routes, tried in this order:
 *  1. The standard API (`Element.requestFullscreen`), gated on
 *     `document.fullscreenEnabled` — false inside e.g. a disallowed iframe
 *     even when the method exists.
 *  2. The legacy prefixed element API some older WebKit builds expose
 *     (`webkitRequestFullscreen` + `document.webkitFullscreenEnabled`).
 *  3. Safari on iPhone, which implements neither of the above for an
 *     arbitrary element: `<video>` alone exposes `webkitEnterFullscreen()`,
 *     callable only from a real user gesture — which a click handler is.
 */

interface WebkitVideo extends HTMLVideoElement {
  webkitEnterFullscreen?: () => void;
  webkitRequestFullscreen?: () => void;
}

interface WebkitDocument extends Document {
  webkitFullscreenEnabled?: boolean;
}

type Route = 'standard' | 'webkit-element' | 'webkit-video';

function detectRoute(video: HTMLVideoElement): Route | null {
  const v = video as WebkitVideo;
  const doc = document as WebkitDocument;

  if (document.fullscreenEnabled && typeof video.requestFullscreen === 'function') {
    return 'standard';
  }
  if (doc.webkitFullscreenEnabled && typeof v.webkitRequestFullscreen === 'function') {
    return 'webkit-element';
  }
  if (typeof v.webkitEnterFullscreen === 'function') {
    return 'webkit-video';
  }
  return null;
}

function enter(video: HTMLVideoElement, route: Route): void {
  const v = video as WebkitVideo;
  if (route === 'standard') {
    // A rejection here (permissions policy, no user-activation left, …) is
    // not a bug to surface — the video simply stays as it was, which is the
    // same outcome as never having offered the button.
    video.requestFullscreen().catch(() => {});
  } else if (route === 'webkit-element') {
    v.webkitRequestFullscreen!();
  } else {
    v.webkitEnterFullscreen!();
  }
}

const SVG_NS = 'http://www.w3.org/2000/svg';

/** Four corner brackets pointing outward — the fullscreen glyph, drawn
 *  rather than a Unicode character so it renders identically everywhere
 *  instead of depending on a platform's symbol font coverage. */
function buildIcon(): SVGSVGElement {
  const svg = document.createElementNS(SVG_NS, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('width', '14');
  svg.setAttribute('height', '14');
  svg.setAttribute('aria-hidden', 'true');
  const path = document.createElementNS(SVG_NS, 'path');
  path.setAttribute('fill', 'currentColor');
  path.setAttribute(
    'd',
    'M4 4h6v2H6v4H4V4Zm14 0h-6v2h4v4h2V4ZM4 20h6v-2H6v-4H4v6Zm14 0h-6v-2h4v-4h2v6Z',
  );
  svg.appendChild(path);
  return svg;
}

export function attachDemo(root: HTMLElement): void {
  const video = root.querySelector('video');
  if (!video) return;

  const route = detectRoute(video);
  if (!route) return;

  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'fs-btn';
  button.setAttribute('aria-label', 'Show the demo fullscreen');
  button.appendChild(buildIcon());
  button.addEventListener('click', () => enter(video, route));

  root.appendChild(button);
}
