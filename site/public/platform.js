// Which platform the page shows, decided before it paints: loaded by a plain
// <script src> in <head> (the CSP admits no inline script), so there is no
// flash of the other platform. `?platform=windows` or `?platform=macos` wins;
// otherwise the browser's own platform, judged exactly as the Worker judges
// it for /download (worker/download.ts, platformOf): the platform hint, then
// "Windows NT" in the User-Agent, macOS for anything else. Without scripting
// the page shows macOS, as it always has. Nothing is stored.
(function () {
  var platform = null;
  try {
    var asked = new URLSearchParams(window.location.search).get('platform');
    if (asked === 'windows' || asked === 'macos') platform = asked;
  } catch (e) {
    // An old browser without URLSearchParams: judged by its platform alone.
  }
  if (platform === null) {
    var hint = navigator.userAgentData && navigator.userAgentData.platform;
    var windows = typeof hint === 'string'
      ? hint.trim().toLowerCase() === 'windows'
      : /\bWindows NT\b/.test(navigator.userAgent || '');
    platform = windows ? 'windows' : 'macos';
  }
  document.documentElement.setAttribute('data-platform', platform);
})();
