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
});
