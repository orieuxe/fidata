export const TITLE_OPTIONS = ["GM", "IM", "FM", "CM", "WGM", "WIM", "WFM", "WCM", "UNTITLED"];

export const LIMIT_OPTIONS = [25, 50, 100];
export const LIMIT_OPTIONS_WIDE = [10, 15, 25, 50, 100, 200];

export type YearFilterValue = number | "last12" | null;

// Rolling 12 calendar months (current month included), rather than the
// current calendar year -- matches how the "12 derniers mois" filter option
// is described, and how the ratings data is periodized (monthly rows).
export function yearFilterRange(value: YearFilterValue): { from: string | null; to: string | null } {
  if (value === "last12") {
    const now = new Date();
    const to = new Date(now.getFullYear(), now.getMonth() + 1, 1);
    const from = new Date(to.getFullYear(), to.getMonth() - 12, 1);
    return { from: toISODate(from), to: toISODate(to) };
  }
  if (value == null) return { from: null, to: null };
  return { from: `${value}-01-01`, to: `${value + 1}-01-01` };
}

function toISODate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
