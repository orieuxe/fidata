export interface CountryEntry {
  code: string;
  name?: string;
  iso2?: string;
}

// flag-icons (CSS classes backed by SVGs) instead of the regional-indicator
// emoji trick: those emoji don't render as flags without a color-emoji font
// (common gap on Linux), falling back to plain two-letter text.
export function flagClass(iso2: string | null | undefined): string | null {
  return iso2 ? `fi fi-${iso2.toLowerCase()}` : null;
}

// FIDE federations ENG/SCO/WLS (England/Scotland/Wales) aren't ISO 3166
// countries -- `countries.iso2` stores flag-icons' non-standard codes for
// them (gb-eng/gb-sct/gb-wls) so flagClass above still works unmodified.
// Intl.DisplayNames only accepts real 2-letter ISO region codes, so guard
// against those before using it, falling back to the stored name.
export function countryName(entry: CountryEntry | undefined, locale: string): string {
  if (!entry) return "";
  if (!entry.iso2 || entry.iso2.length !== 2) return entry.name ?? entry.code;
  return new Intl.DisplayNames([locale], { type: "region" }).of(entry.iso2) ?? entry.name ?? entry.code;
}
