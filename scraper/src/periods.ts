const MONTHS = [
  "jan", "feb", "mar", "apr", "may", "jun",
  "jul", "aug", "sep", "oct", "nov", "dec",
];

export interface Period {
  /** first-of-month date, e.g. "2026-07-01" */
  period: string;
  /** FIDE URL month token, e.g. "jul26" */
  token: string;
}

/** FIDE archive starts Feb 2015. */
const EARLIEST = { year: 2015, month: 2 };

export function periodFor(year: number, month: number): Period {
  const mm = String(month).padStart(2, "0");
  const yy = String(year).slice(-2);
  return { period: `${year}-${mm}-01`, token: `${MONTHS[month - 1]}${yy}` };
}

export function currentPeriod(): Period {
  const now = new Date();
  return periodFor(now.getUTCFullYear(), now.getUTCMonth() + 1);
}

/** All months from FIDE's earliest archive up to and including the current month. */
export function allPeriods(): Period[] {
  const out: Period[] = [];
  let { year, month } = EARLIEST;
  const end = currentPeriod();
  while (true) {
    const p = periodFor(year, month);
    out.push(p);
    if (p.period === end.period) break;
    month++;
    if (month > 12) {
      month = 1;
      year++;
    }
  }
  return out;
}

export function parsePeriodArg(arg: string): Period {
  const m = /^(\d{4})-(\d{2})$/.exec(arg);
  if (!m) throw new Error(`--period expects YYYY-MM, got "${arg}"`);
  return periodFor(Number(m[1]), Number(m[2]));
}
