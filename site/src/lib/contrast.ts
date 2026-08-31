/** Parse #RRGGBB or #RRGGBBAA into sRGB 0..1 plus alpha. */
function parse(hex: string): { r: number; g: number; b: number; a: number } {
  const h = hex.replace('#', '');
  const n = (i: number) => parseInt(h.slice(i, i + 2), 16) / 255;
  return { r: n(0), g: n(2), b: n(4), a: h.length === 8 ? n(6) : 1 };
}

function linear(c: number): number {
  return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

function luminance(r: number, g: number, b: number): number {
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
}

/**
 * WCAG 2.1 contrast ratio. A translucent foreground is composited over the
 * background first, which is how the app's label tokens are actually drawn —
 * they are black or white at a fractional alpha, not opaque greys.
 */
export function contrastRatio(foreground: string, background: string): number {
  const f = parse(foreground);
  const b = parse(background);
  const over = (fc: number, bc: number) => fc * f.a + bc * (1 - f.a);
  const lf = luminance(over(f.r, b.r), over(f.g, b.g), over(f.b, b.b));
  const lb = luminance(b.r, b.g, b.b);
  const [hi, lo] = lf > lb ? [lf, lb] : [lb, lf];
  return (hi + 0.05) / (lo + 0.05);
}
