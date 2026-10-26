/**
 * The spec strip's figures, in one place.
 *
 * Every value here has a row in spec §3.4's provenance table, and the exact
 * wording is part of the claim: "about 50 milliseconds" is the conservative
 * form of a measurement whose median was 44.5 ms and whose worst cold case was
 * 86.1 ms, and "0.0% CPU" states a precision that "0%" does not.
 *
 * Both of those were measured on macOS, and their notes say so: beside a
 * Windows requirement, a bare figure reads as true of both platforms. The
 * Windows floor is the installer's MinVersion, asserted by
 * test/site_docs_test.dart as the macOS one is against the deployment target.
 *
 * Do not add a figure here without adding a row to §3.4 and its source.
 */
export interface Fact {
  value: string;
  note: string;
}

export const FACTS: Fact[] = [
  { value: 'Free · MIT',   note: 'open source, no paid tier' },
  { value: 'about 50 ms',  note: 'grid on every display, on macOS' },
  { value: '0.0% CPU',     note: '0 wake-ups while idle, on macOS' },
  { value: 'macOS 13+',    note: 'Ventura and later' },
  { value: 'Windows 10 (1809+)', note: 'and Windows 11, 64-bit' },
];
