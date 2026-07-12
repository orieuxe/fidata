export interface CountryEntry {
  code: string;
  name: string | null;
  iso2: string | null;
}

// flag-icons (CSS classes backed by SVGs) instead of the regional-indicator
// emoji trick: those emoji don't render as flags without a color-emoji font
// (common gap on Linux), falling back to plain two-letter text.
export function flagClass(iso2: string | null | undefined): string | null {
  return iso2 ? `fi fi-${iso2.toLowerCase()}` : null;
}

export function countryName(entry: CountryEntry | undefined, locale: string): string {
  if (!entry) return "";
  if (!entry.iso2) return entry.name ?? entry.code;
  return new Intl.DisplayNames([locale], { type: "region" }).of(entry.iso2) ?? entry.name ?? entry.code;
}
