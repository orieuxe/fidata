import AdmZip from "adm-zip";
import type { PlayerRow } from "./parse.js";
import { upsertRatings, finalizeScrapeRun } from "./db.js";
import { toIntOrNull, toStrOrNull, normalizeTitle, VALID_TITLES } from "./backfill-historical.js";

// Fills the gap before backfill-historical.ts's anujdahiya24 mirror starts
// (2001-01) with OlimpBase's bulk export of FIDE's classical rating lists
// back to 1967: https://www.olimpbase.org/Elo/summary.html -- one
// semicolon-delimited CSV, one row per player/period, fideid populated from
// ~1990 on (FIDE didn't assign IDs before that). Standard/classical only --
// FIDE had no separate rapid/blitz lists this far back.
const ZIP_URL = "https://www.olimpbase.org/Elo/data/elo1967-2001.zip";

// Rows from 2001-01 on duplicate the better-sourced anujdahiya24 mirror
// (already loaded by backfill-historical.ts) -- only take what's strictly
// before it. Plain string comparison works: both sides are zero-padded
// YYYYMM.
const CUTOFF = "200101";

// column layout (0-based, `;`-split): 0 blank, 1 name, 2 name (dup), 3
// period YYYYMM, 4 fideid, 5 birthdate YYYY.MM.DD, 6 title, 7 federation,
// 8 rating, 9 change, 10 games, 11 flag, 12 note, 13 federation (dup), 14
// blank. Confirmed by sampling data/elo1967-2001.zip's all.csv directly.
function toPeriodDate(yyyymm: string): string | null {
  const month = yyyymm.slice(4, 6);
  if (month < "01" || month > "12") return null; // a handful of pre-1971 rows have no real month ("00")
  return `${yyyymm.slice(0, 4)}-${month}-01`;
}

function toBirthYear(raw: string): number | null {
  const year = Number(raw.slice(0, 4));
  return year > 0 ? year : null;
}

function parseRow(cells: string[]): { period: string; row: PlayerRow } | null {
  const periodRaw = cells[3];
  if (!periodRaw || periodRaw >= CUTOFF) return null;
  const period = toPeriodDate(periodRaw);
  if (!period) return null;

  const fideid = toIntOrNull(cells[4]);
  const name = toStrOrNull(cells[1]);
  if (fideid === null || !name) return null; // no FIDE id yet (pre-~1990) -- can't join to today's schema

  let title = normalizeTitle(toStrOrNull(cells[6]));
  if (title && !VALID_TITLES.has(title)) title = null; // defunct pre-1990s codes (e.g. "h", Honorary GM) have no modern equivalent

  const birthdayRaw = cells[5];

  return {
    period,
    row: {
      fideid,
      name,
      country: toStrOrNull(cells[7]),
      sex: title?.startsWith("W") ? "F" : null, // no explicit sex column; only titled women are inferrable
      title,
      w_title: null,
      o_title: null,
      birthday: birthdayRaw ? toBirthYear(birthdayRaw) : null,
      rating: toIntOrNull(cells[8]),
      games: toIntOrNull(cells[10]),
      k: null,
      flag: toStrOrNull(cells[11]),
    },
  };
}

async function main(): Promise<void> {
  const res = await fetch(ZIP_URL);
  if (!res.ok) throw new Error(`${ZIP_URL} -> HTTP ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  const zip = new AdmZip(buf);
  const entry = zip.getEntries()[0];
  if (!entry) throw new Error(`${ZIP_URL} -> empty zip`);
  const text = entry.getData().toString("utf-8");

  const byPeriod = new Map<string, Map<number, PlayerRow>>();
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    const parsed = parseRow(line.split(";"));
    if (!parsed) continue;
    let rows = byPeriod.get(parsed.period);
    if (!rows) byPeriod.set(parsed.period, (rows = new Map()));
    rows.set(parsed.row.fideid, parsed.row); // dedupe by fideid within a period, keep last occurrence
  }

  for (const period of [...byPeriod.keys()].sort()) {
    const rows = [...byPeriod.get(period)!.values()];
    await upsertRatings(period, "standard", rows);
    console.log(`  standard ${period}: ${rows.length} players`);
  }
  await finalizeScrapeRun();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
