export function formatNumber(n: number | null, locale: string) {
  return n == null ? "" : new Intl.NumberFormat(locale).format(n);
}

export function formatPercentile(rank: number | null, total: number | null) {
  if (rank == null || !total) return "";
  const pct = (rank / total) * 100;
  return pct < 0.1 ? "<0.1" : pct.toFixed(1);
}
