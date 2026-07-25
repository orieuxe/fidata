import AdmZip from "adm-zip";
import postgres from "postgres";
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
// Two-pass setup:
//   pass 1: CUTOFF=200101 → 1990-2000 with native fideid
//   pass 2: CUTOFF=199001 → 1967-1989 via name+federation cross-ref (default)
const CUTOFF = process.env.OLIMP_CUTOFF ?? "199001";

// column layout (0-based, `;`-split): 0 blank, 1 name, 2 name (dup), 3
// period YYYYMM, 4 fideid, 5 birthdate YYYY.MM.DD, 6 title, 7 federation,
// 8 rating, 9 change, 10 games, 11 flag, 12 note, 13 federation (dup), 14
// blank. Confirmed by sampling data/elo1967-2001.zip's all.csv directly.

function toPeriodDate(yyyymm: string): string {
  const y = yyyymm.slice(0, 4);
  let m = yyyymm.slice(4, 6);
  if (m < "01" || m > "12") m = "01"; // pre-1971 rows sometimes have "00"
  return `${y}-${m}-01`;
}

function toBirthYear(raw: string): number | null {
  const year = Number(raw.slice(0, 4));
  return year > 0 ? year : null;
}

interface OlimpRow {
  name: string;
  period: string;
  fideid: number | null;
  birthdate: string;
  title: string;
  fed: string;
  rating: string;
  games: string;
  flag: string;
}

function parseOlimpRow(cells: string[]): OlimpRow | null {
  const periodRaw = cells[3];
  if (!periodRaw || periodRaw >= CUTOFF) return null;
  const name = toStrOrNull(cells[1]);
  if (!name) return null;
  return {
    name,
    period: toPeriodDate(periodRaw),
    fideid: toIntOrNull(cells[4]),
    birthdate: cells[5] ?? "",
    title: cells[6] ?? "",
    fed: cells[7] ?? "",
    rating: cells[8] ?? "",
    games: cells[10] ?? "",
    flag: cells[11] ?? "",
  };
}

function olimpToPlayerRow(r: OlimpRow, fideid: number): PlayerRow {
  let title = normalizeTitle(toStrOrNull(r.title));
  if (title && !VALID_TITLES.has(title)) title = null;
  return {
    fideid,
    name: r.name,
    country: toStrOrNull(r.fed),
    sex: title?.startsWith("W") ? "F" : null,
    title,
    w_title: null,
    o_title: null,
    birthday: r.birthdate ? toBirthYear(r.birthdate) : null,
    rating: toIntOrNull(r.rating),
    games: toIntOrNull(r.games),
    k: null,
    flag: toStrOrNull(r.flag),
  };
}

const sql = postgres(
  process.env.DATABASE_URL ?? "postgres://postgres:postgres@localhost:5433/fidata",
);

async function buildNameMap(names: { name: string; fed: string }[]): Promise<Map<string, number>> {
  const map = new Map<string, number>();
  // Deduplicate input before querying
  const unique = new Map<string, { name: string; fed: string }>();
  for (const n of names) unique.set(`${n.name}|${n.fed}`, n);
  const pairs = [...unique.values()];

  // Query ratings for matching fideids, picking the most-tracked player
  // when multiple fideids share the same (name, country) pair.
  const rows = await sql<{ sname: string; fed: string; fideid: number }>`
    with inputs as (
      select
        (string_to_array(pair, '|'))[1] as sname,
        (string_to_array(pair, '|'))[2] as fed
      from unnest(${pairs.map((p) => `${p.name}|${p.fed}`)}::text[]) as pair
    ),
    candidates as (
      select i.sname, i.fed, r.fideid, count(*) as nrows
      from inputs i
      join ratings r on lower(r.name) = i.sname and r.country = i.fed
      group by i.sname, i.fed, r.fideid
    ),
    ranked as (
      select *, row_number() over (partition by sname, fed order by nrows desc) as rn
      from candidates
    )
    select sname, fed, fideid from ranked where rn = 1
  `;
  for (const r of rows) map.set(`${r.sname}|${r.fed}`, r.fideid);
  return map;
}

async function main(): Promise<void> {
  const res = await fetch(ZIP_URL);
  if (!res.ok) throw new Error(`${ZIP_URL} -> HTTP ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  const zip = new AdmZip(buf);
  const entry = zip.getEntries()[0];
  if (!entry) throw new Error(`${ZIP_URL} -> empty zip`);
  const text = entry.getData().toString("utf-8");

  // Phase 1: parse all rows.
  const withFideid: OlimpRow[] = [];
  const withoutFideid: OlimpRow[] = [];
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    const r = parseOlimpRow(line.split(";"));
    if (!r) continue;
    (r.fideid !== null ? withFideid : withoutFideid).push(r);
  }
  console.log(`parsed: ${withFideid.length} with fideid, ${withoutFideid.length} without`);

  // Phase 2: resolve pre-1990 rows (no fideid) by name+fed matching.
  if (withoutFideid.length) {
    const nameMap = await buildNameMap(
      withoutFideid.map((r) => ({ name: r.name.toLowerCase().trim(), fed: r.fed })),
    );
    console.log(`  name→fideid map: ${nameMap.size} entries`);
    let matched = 0;
    for (const r of withoutFideid) {
      const fid = nameMap.get(`${r.name.toLowerCase().trim()}|${r.fed}`);
      if (fid) { r.fideid = fid; matched++; }
    }
    console.log(`  matched: ${matched}/${withoutFideid.length} rows (${(matched / withoutFideid.length * 100).toFixed(0)}%)`);
  }

  // Phase 3: group by period, upsert.
  const all = [...withFideid, ...withoutFideid.filter((r) => r.fideid !== null)];
  const byPeriod = new Map<string, Map<number, PlayerRow>>();
  for (const r of all) {
    // Skip rows with invalid ratings (some pre-1971 rows have non-numeric)
    const playerRow = olimpToPlayerRow(r, r.fideid!);
    if (playerRow.rating === null) continue;
    let rows = byPeriod.get(r.period);
    if (!rows) byPeriod.set(r.period, (rows = new Map()));
    rows.set(r.fideid!, playerRow);
  }

  for (const period of [...byPeriod.keys()].sort()) {
    const rows = [...byPeriod.get(period)!.values()];
    await upsertRatings(period, "standard", rows);
    console.log(`  standard ${period}: ${rows.length} players`);
  }
  await finalizeScrapeRun();
  await sql.end();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
