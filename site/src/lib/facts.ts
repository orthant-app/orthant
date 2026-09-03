/**
 * The spec strip's figures, in one place.
 *
 * Every value here has a row in spec §3.4's provenance table, and the exact
 * wording is part of the claim: "about 50 milliseconds" is the conservative
 * form of a measurement whose median was 44.5 ms and whose worst cold case was
 * 86.1 ms, and "0.0% CPU" states a precision that "0%" does not.
 *
 * Do not add a figure here without adding a row to §3.4 and its source.
 */
export interface Fact {
  value: string;
  note: string;
}

export const FACTS: Fact[] = [
  { value: 'Free · MIT',   note: 'open source, no paid tier' },
  { value: 'about 50 ms',  note: 'grid on every display' },
  { value: '0.0% CPU',     note: '0 wake-ups while idle' },
  { value: 'No account',   note: 'nothing to sign in to' },
  { value: 'No telemetry', note: 'in the app' },
  { value: 'macOS 13+',    note: 'Ventura and later' },
];
