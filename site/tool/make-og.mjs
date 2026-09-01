// Renders site/public/og/default.png (1200x630) from an SVG built out of the
// site's own tokens. Run: node tool/make-og.mjs
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { Resvg } from '@resvg/resvg-js';

const ICON = readFileSync(
  '../macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png',
).toString('base64');

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630">
  <rect width="1200" height="630" fill="#FFFFFF"/>
  <g stroke="rgba(0,0,0,0.08)" stroke-width="1">
    ${[1, 2, 3].map((i) => `<line x1="${i * 300}" y1="0" x2="${i * 300}" y2="630"/>`).join('')}
    ${[1, 2].map((i) => `<line x1="0" y1="${i * 210}" x2="1200" y2="${i * 210}"/>`).join('')}
  </g>
  <rect x="0" y="0" width="300" height="630" fill="#007AFF" fill-opacity="0.10"/>
  <rect x="1" y="1" width="298" height="628" fill="none" stroke="#007AFF" stroke-width="2"/>
  <image href="data:image/png;base64,${ICON}" x="380" y="196" width="120" height="120"/>
  <text x="380" y="392" font-family="-apple-system, Helvetica, Arial, sans-serif"
        font-size="76" font-weight="600" fill="rgba(0,0,0,0.90)">Orthant</text>
  <text x="380" y="446" font-family="-apple-system, Helvetica, Arial, sans-serif"
        font-size="30" fill="rgba(0,0,0,0.55)">Grid-based window manager for macOS</text>
</svg>`;

const png = new Resvg(svg, { fitTo: { mode: 'width', value: 1200 } }).render().asPng();
mkdirSync('public/og', { recursive: true });
writeFileSync('public/og/default.png', png);
console.log(`wrote public/og/default.png — ${(png.length / 1024).toFixed(0)} KB`);
