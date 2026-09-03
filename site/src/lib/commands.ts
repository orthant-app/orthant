/**
 * The eleven shortcuts Orthant ships by default, mirroring `kDefaultBindings`
 * in lib/shortcuts/bindings.dart:90 and `rectForCommand` in
 * lib/shortcuts/region_commands.dart.
 *
 * Three kinds, because the app has three shapes:
 *
 *  - `block`     nine placements that are gridBlock(cols: 2, rows: 2) calls
 *                with fixed indices, so their diagrams come from the same
 *                formula the app places windows with.
 *  - `keepsSize` center. It keeps the captured window's CURRENT size and
 *                centres it, so it has a target rect but no fixed fraction and
 *                therefore no honest glyph.
 *  - `summon`    showGrid. It opens the overlay and places nothing.
 *
 * Modelling the last two as one nullable field would merge two different
 * facts: "has a rect, no fixed shape" and "has no rect at all".
 *
 * ⚠️ This list is asserted against the Dart source by
 * test/site_docs_test.dart. Editing it without editing the app fails the
 * Flutter suite, which is the point: a TypeScript copy of Dart data drifts
 * silently otherwise.
 */
export interface Block { c0: number; c1: number; r0: number; r1: number }

interface Common { id: string; label: string; combo: string }
export type Binding =
  | (Common & { kind: 'block'; block: Block })
  | (Common & { kind: 'keepsSize' })
  | (Common & { kind: 'summon' });

export const BINDINGS: Binding[] = [
  { kind: 'summon', id: 'showGrid', label: 'Open grid', combo: '⌃⌥O' },
  { kind: 'block', id: 'leftHalf',    label: 'Left half',            combo: '⌃⌥←', block: { c0: 0, c1: 0, r0: 0, r1: 1 } },
  { kind: 'block', id: 'rightHalf',   label: 'Right half',           combo: '⌃⌥→', block: { c0: 1, c1: 1, r0: 0, r1: 1 } },
  { kind: 'block', id: 'topHalf',     label: 'Top half',             combo: '⌃⌥↑', block: { c0: 0, c1: 1, r0: 0, r1: 0 } },
  { kind: 'block', id: 'bottomHalf',  label: 'Bottom half',          combo: '⌃⌥↓', block: { c0: 0, c1: 1, r0: 1, r1: 1 } },
  { kind: 'block', id: 'topLeft',     label: 'Top-left quarter',     combo: '⌃⌥U', block: { c0: 0, c1: 0, r0: 0, r1: 0 } },
  { kind: 'block', id: 'topRight',    label: 'Top-right quarter',    combo: '⌃⌥I', block: { c0: 1, c1: 1, r0: 0, r1: 0 } },
  { kind: 'block', id: 'bottomLeft',  label: 'Bottom-left quarter',  combo: '⌃⌥J', block: { c0: 0, c1: 0, r0: 1, r1: 1 } },
  { kind: 'block', id: 'bottomRight', label: 'Bottom-right quarter', combo: '⌃⌥K', block: { c0: 1, c1: 1, r0: 1, r1: 1 } },
  { kind: 'block', id: 'maximize',    label: 'Maximize',             combo: '⌃⌥↩', block: { c0: 0, c1: 1, r0: 0, r1: 1 } },
  { kind: 'keepsSize', id: 'center',  label: 'Center',               combo: '⌃⌥C' },
];
