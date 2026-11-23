// @vitest-environment happy-dom
import { readFileSync } from 'node:fs';
import { beforeEach, describe, expect, it } from 'vitest';

// Check the shipped HTML, including its no-script content, rather than Astro
// template text. Actual font sizes and wrapping are checked by tool/sweep.mjs.
let homepage: DocumentFragment;
beforeEach(() => {
  const template = document.createElement('template');
  template.innerHTML = readFileSync('dist/index.html', 'utf8');
  homepage = template.content;
});

function textFor(element: Element, platform: 'macos' | 'windows'): string {
  const copy = element.cloneNode(true) as Element;
  copy.querySelectorAll(platform === 'macos' ? '.only-windows' : '.only-macos')
    .forEach((hidden) => hidden.remove());
  return (copy.textContent ?? '').replace(/\s+/g, ' ').trim();
}

describe('the built homepage shortcut instructions', () => {
  // Catches moving the custom chord back into SVG, where it scales with the
  // diagram, or omitting it from the actual binding instruction.
  it('puts the save and custom chords in prose beside the fraction diagrams', () => {
    const steps = [...homepage.querySelectorAll('.steps > li')];
    expect(steps).toHaveLength(3);
    expect(homepage.querySelectorAll('.steps svg .combo')).toHaveLength(0);
    for (const [platform, save, custom] of [
      ['macos', '⌘S', '⌃⌥2'],
      ['windows', 'Ctrl+S', 'Win+Ctrl+Shift+T'],
    ] as const) {
      const bind = textFor(steps[1].querySelector('p')!, platform);
      expect(bind).toContain(save);
      expect(bind).toContain(custom);
      expect(textFor(steps[2].querySelector('p')!, platform)).toContain(custom);
    }
    expect([...homepage.querySelectorAll('.steps svg text.label')].map((e) => e.textContent))
      .toEqual(['2/3', '2/3', '8/12']);
  });

  // Catches full modifiers returning to every tile, a missing shared
  // instruction, or the Windows Enter spelling leaking into the Mac view.
  it('connects one modifier instruction to eleven terminal keys and actions', () => {
    const list = homepage.querySelector('.keymap')!;
    const instruction = homepage.getElementById(list.getAttribute('aria-describedby') ?? '');
    expect(instruction, 'the key list must reference its shared modifier instruction').not.toBeNull();
    expect(instruction!.compareDocumentPosition(list) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(textFor(instruction!, 'macos')).toContain('⌃⌥');
    expect(textFor(instruction!, 'windows')).toContain('Win+Ctrl+Shift');
    const items = [...list.querySelectorAll('li')];
    expect(items).toHaveLength(11);
    expect(items.map((item) => item.querySelector('.key-label')?.textContent?.trim())).toEqual([
      'Open grid', 'Left half', 'Right half', 'Top half', 'Bottom half',
      'Top-left quarter', 'Top-right quarter', 'Bottom-left quarter',
      'Bottom-right quarter', 'Maximize', 'Center',
    ]);
    for (const [platform, returnKey] of [['macos', 'Return'], ['windows', 'Enter']] as const) {
      expect(items.map((item) => textFor(item.querySelector('kbd')!, platform)))
        .toEqual(['O', '←', '→', '↑', '↓', 'U', 'I', 'J', 'K', returnKey, 'C']);
    }
  });
});
