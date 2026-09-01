// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://orthant.app',
  trailingSlash: 'always',
  integrations: [sitemap()],
  build: {
    // The site's CSP sets `style-src 'self'`, and Astro inlines stylesheets
    // under 4 KB by default. Leaving this at its default ships an unstyled
    // site, because the inline <style> is blocked. See spec §8.2.
    inlineStylesheets: 'never',
    format: 'directory',
  },
  // The script-side counterpart to inlineStylesheets above. Astro treats a
  // processed <script> as a Vite asset for inlining purposes: under Vite's
  // default 4 KB assetsInlineLimit, a small bundled script is emitted as
  // `<script type="module">…</script>` with no `src` instead of an external
  // /_astro/*.js file. The site's CSP sets `script-src 'self'` with no nonce,
  // no hash and no 'unsafe-inline', so an inlined script is silently dropped
  // by the browser — the hero's controller then never runs and "Try the
  // grid" stays hidden forever. Forcing every asset external keeps script on
  // the same footing as style.
  vite: {
    build: { assetsInlineLimit: 0 },
  },
  markdown: {
    // Shiki (Astro's default highlighter) emits `style="…"` on every
    // highlighted code block, dropped by the same `style-src 'self'` CSP —
    // leaving docs code blocks unstyled and without the overflow-x
    // containment the shared `pre` rule (styles/tokens.css) provides. Every
    // fenced block on the site is a shell one-liner, so highlighting buys
    // nothing worth losing that containment for.
    syntaxHighlight: false,
  },
});
