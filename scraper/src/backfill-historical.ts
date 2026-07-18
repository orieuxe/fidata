import type { RatingKind } from "./fetch.js";
import type { PlayerRow } from "./parse.js";
import { upsertRatings, flagInactivePlayers, refreshLatestRatings, closeDb } from "./db.js";

// FIDE's official archive only goes back to Feb 2015 (see periods.ts). This
// backs that up with anujdahiya24/FIDE's "Step 2 - Reformat" mirror, which
// scraped FIDE's site monthly/quarterly back to 2001. Only pulls periods
// before our own scraper's EARLIEST (2015-02) -- anything from Feb 2015 on
// is already covered by `npm run scrape -- --backfill`.

const BASE_URL =
  "https://raw.githubusercontent.com/anujdahiya24/FIDE/main/Step%202%20-%20Reformat";

const FOLDER: Record<RatingKind, string> = {
  standard: "Standard",
  rapid: "Rapid",
  blitz: "Blitz",
};

// Standard was scraped as `*`-delimited fixed-width text; Blitz/Rapid (which
// only exist from Sep 2012, when FIDE introduced those rating lists) were
// scraped as regular quoted CSV. Confirmed by sampling files across each
// folder's date range.
const DELIM: Record<RatingKind, "*" | ","> = {
  standard: "*",
  blitz: ",",
  rapid: ",",
};

interface HistoricalFile {
  period: string;
  token: string;
}

const FILES: Record<RatingKind, HistoricalFile[]> = {
  standard: [
    { period: "2001-01-01", token: "JAN01" },
    { period: "2001-04-01", token: "APR01" },
    { period: "2001-07-01", token: "JUL01" },
    { period: "2001-10-01", token: "OCT01" },
    { period: "2002-01-01", token: "JAN02" },
    { period: "2002-04-01", token: "APR02" },
    { period: "2002-07-01", token: "JUL02" },
    { period: "2002-10-01", token: "OCT02" },
    { period: "2003-01-01", token: "JAN03" },
    { period: "2003-04-01", token: "APR03" },
    { period: "2003-07-01", token: "JUL03" },
    { period: "2003-10-01", token: "OCT03" },
    { period: "2004-01-01", token: "JAN04" },
    { period: "2004-04-01", token: "APR04" },
    { period: "2004-07-01", token: "JUL04" },
    { period: "2004-10-01", token: "OCT04" },
    { period: "2005-01-01", token: "JAN05" },
    { period: "2005-04-01", token: "APR05" },
    { period: "2005-07-01", token: "JUL05" },
    { period: "2005-10-01", token: "OCT05" },
    { period: "2006-01-01", token: "JAN06" },
    { period: "2006-04-01", token: "APR06" },
    { period: "2006-07-01", token: "JUL06" },
    { period: "2006-10-01", token: "OCT06" },
    { period: "2007-01-01", token: "JAN07" },
    { period: "2007-04-01", token: "APR07" },
    { period: "2007-07-01", token: "JUL07" },
    { period: "2007-10-01", token: "OCT07" },
    { period: "2008-01-01", token: "JAN08" },
    { period: "2008-04-01", token: "APR08" },
    { period: "2008-07-01", token: "JUL08" },
    { period: "2008-10-01", token: "OCT08" },
    { period: "2009-01-01", token: "JAN09" },
    { period: "2009-04-01", token: "APR09" },
    { period: "2009-07-01", token: "JUL09" },
    { period: "2009-09-01", token: "SEP09" },
    { period: "2009-11-01", token: "NOV09" },
    { period: "2010-01-01", token: "JAN10" },
    { period: "2010-03-01", token: "MAR10" },
    { period: "2010-05-01", token: "MAY10" },
    { period: "2010-07-01", token: "JUL10" },
    { period: "2010-09-01", token: "SEP10" },
    { period: "2010-11-01", token: "NOV10" },
    { period: "2011-01-01", token: "JAN11" },
    { period: "2011-03-01", token: "MAR11" },
    { period: "2011-05-01", token: "MAY11" },
    { period: "2011-07-01", token: "JUL11" },
    { period: "2011-09-01", token: "SEP11" },
    { period: "2011-11-01", token: "NOV11" },
    { period: "2012-01-01", token: "JAN12" },
    { period: "2012-03-01", token: "MAR12" },
    { period: "2012-05-01", token: "MAY12" },
    { period: "2012-07-01", token: "JUL12" },
    { period: "2012-08-01", token: "AUG12" },
    { period: "2012-09-01", token: "SEP12" },
    { period: "2012-10-01", token: "OCT12" },
    { period: "2012-11-01", token: "NOV12" },
    { period: "2012-12-01", token: "DEC12" },
    { period: "2013-01-01", token: "JAN13" },
    { period: "2013-02-01", token: "FEB13" },
    { period: "2013-03-01", token: "MAR13" },
    { period: "2013-04-01", token: "APR13" },
    { period: "2013-05-01", token: "MAY13" },
    { period: "2013-06-01", token: "JUN13" },
    { period: "2013-07-01", token: "JUL13" },
    { period: "2013-08-01", token: "AUG13" },
    { period: "2013-09-01", token: "SEP13" },
    { period: "2013-10-01", token: "OCT13" },
    { period: "2013-11-01", token: "NOV13" },
    { period: "2013-12-01", token: "DEC13" },
    { period: "2014-01-01", token: "JAN14" },
    { period: "2014-02-01", token: "FEB14" },
    { period: "2014-03-01", token: "MAR14" },
    { period: "2014-04-01", token: "APR14" },
    { period: "2014-05-01", token: "MAY14" },
    { period: "2014-06-01", token: "JUN14" },
    { period: "2014-07-01", token: "JUL14" },
    { period: "2014-08-01", token: "AUG14" },
    { period: "2014-09-01", token: "SEP14" },
    { period: "2014-10-01", token: "OCT14" },
    { period: "2014-11-01", token: "NOV14" },
    { period: "2014-12-01", token: "DEC14" },
    { period: "2015-01-01", token: "JAN15" },
  ],
  blitz: [
    { period: "2012-09-01", token: "SEP12" },
    { period: "2012-10-01", token: "OCT12" },
    { period: "2012-11-01", token: "NOV12" },
    { period: "2012-12-01", token: "DEC12" },
    { period: "2013-01-01", token: "JAN13" },
    { period: "2013-02-01", token: "FEB13" },
    { period: "2013-03-01", token: "MAR13" },
    { period: "2013-04-01", token: "APR13" },
    { period: "2013-05-01", token: "MAY13" },
    { period: "2013-06-01", token: "JUN13" },
    { period: "2013-07-01", token: "JUL13" },
    { period: "2013-08-01", token: "AUG13" },
    { period: "2013-09-01", token: "SEP13" },
    { period: "2013-10-01", token: "OCT13" },
    { period: "2013-11-01", token: "NOV13" },
    { period: "2013-12-01", token: "DEC13" },
    { period: "2014-01-01", token: "JAN14" },
    { period: "2014-02-01", token: "FEB14" },
    { period: "2014-03-01", token: "MAR14" },
    { period: "2014-04-01", token: "APR14" },
    { period: "2014-05-01", token: "MAY14" },
    { period: "2014-06-01", token: "JUN14" },
    { period: "2014-07-01", token: "JUL14" },
    { period: "2014-08-01", token: "AUG14" },
    { period: "2014-09-01", token: "SEP14" },
    { period: "2014-10-01", token: "OCT14" },
    { period: "2014-11-01", token: "NOV14" },
    { period: "2014-12-01", token: "DEC14" },
    { period: "2015-01-01", token: "JAN15" },
  ],
  rapid: [
    { period: "2012-09-01", token: "SEP12" },
    { period: "2012-10-01", token: "OCT12" },
    { period: "2012-11-01", token: "NOV12" },
    { period: "2012-12-01", token: "DEC12" },
    { period: "2013-01-01", token: "JAN13" },
    { period: "2013-02-01", token: "FEB13" },
    { period: "2013-03-01", token: "MAR13" },
    { period: "2013-04-01", token: "APR13" },
    { period: "2013-05-01", token: "MAY13" },
    { period: "2013-06-01", token: "JUN13" },
    { period: "2013-07-01", token: "JUL13" },
    { period: "2013-08-01", token: "AUG13" },
    { period: "2013-09-01", token: "SEP13" },
    { period: "2013-10-01", token: "OCT13" },
    { period: "2013-11-01", token: "NOV13" },
    { period: "2013-12-01", token: "DEC13" },
    { period: "2014-01-01", token: "JAN14" },
    { period: "2014-02-01", token: "FEB14" },
    { period: "2014-03-01", token: "MAR14" },
    { period: "2014-04-01", token: "APR14" },
    { period: "2014-05-01", token: "MAY14" },
    { period: "2014-06-01", token: "JUN14" },
    { period: "2014-07-01", token: "JUL14" },
    { period: "2014-08-01", token: "AUG14" },
    { period: "2014-09-01", token: "SEP14" },
    { period: "2014-10-01", token: "OCT14" },
    { period: "2014-11-01", token: "NOV14" },
    { period: "2014-12-01", token: "DEC14" },
    { period: "2015-01-01", token: "JAN15" },
  ],
};

function toIntOrNull(v: string | undefined): number | null {
  const s = v?.trim();
  if (!s || s === "0000") return null; // "0000" is FIDE's unknown-birthday sentinel
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

function toStrOrNull(v: string | undefined): string | null {
  const s = v?.trim();
  return s ? s : null;
}

// Pre-2015 archives abbreviate titles as single/double lowercase letters
// (g/m/f/c, wg/wm/wf/wc) instead of FIDE's standard GM/IM/FM/CM/WGM/WIM/
// WFM/WCM codes the live XML feed (parse.ts) already uses -- normalize so
// both sources agree.
const TITLE_ABBREVIATIONS: Record<string, string> = {
  g: "GM", m: "IM", f: "FM", c: "CM", gm: "GM",
  wg: "WGM", wm: "WIM", wf: "WFM", wc: "WCM",
};

function normalizeTitle(raw: string | null): string | null {
  if (!raw) return raw;
  return TITLE_ABBREVIATIONS[raw.toLowerCase()] ?? raw;
}

const VALID_TITLES = new Set(["GM", "IM", "FM", "CM", "WGM", "WIM", "WFM", "WCM"]);

function splitCsvLine(line: string): string[] {
  const cells: string[] = [];
  let cur = "";
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inQuotes) {
      if (ch === '"') {
        if (line[i + 1] === '"') { cur += '"'; i++; }
        else inQuotes = false;
      } else cur += ch;
    } else if (ch === '"') {
      inQuotes = true;
    } else if (ch === ",") {
      cells.push(cur);
      cur = "";
    } else {
      cur += ch;
    }
  }
  cells.push(cur);
  return cells;
}

// FIDE's column layout for this archive changed 3 times across 2001-2015
// (7 cols pre-2008, 8 cols 2008-2012, 12 cols 2013+) and Blitz/Rapid use
// entirely different header names than Standard -- matched by regex instead
// of fixed positions. The rating column itself can't be regex-matched (it's
// named after the period, e.g. "JAN01", "jan13", and some Standard files'
// header even has the wrong month baked in -- MAR10.csv says "Jan10",
// JAN11.csv says "Nov10", confirmed by fetching them directly) so it's
// resolved as whichever header cell nothing else claims.
const COLUMN_MATCHERS: [RegExp, string][] = [
  [/^id.?number$/i, "fideid"],
  [/^name$/i, "name"],
  [/^(fed|country)$/i, "country"],
  [/^sex$/i, "sex"],
  [/^w.?tit(le)?$/i, "w_title"],
  [/^(o.?tit(le)?|other.?titles?)$/i, "o_title"],
  [/^tit(le)?$/i, "title"],
  [/^(b-?day|born|age.?birthday)$/i, "birthday"],
  [/^(flag|activity)$/i, "flag"],
  [/^k(.?factor)?$/i, "k"],
  [/^g/i, "games"], // GAMES / Game / Gms / Games -- only header starting with G
  [/^rating$/i, "rating"],
];

function buildColumnMap(header: string[]): Record<string, number> {
  const col: Record<string, number> = {};
  let leftover: number | undefined;
  header.forEach((cell, i) => {
    const hit = COLUMN_MATCHERS.find(([re]) => re.test(cell));
    if (hit) col[hit[1]] = i;
    else if (cell !== "") leftover = i;
  });
  if (col.rating === undefined && leftover !== undefined) col.rating = leftover;
  return col;
}

function parseHistoricalFile(text: string, delim: "*" | ","): PlayerRow[] {
  const lines = text.split("\n").filter((l) => l.trim() !== "");
  if (lines.length === 0) return [];

  const splitLine = delim === "*"
    ? (l: string) => l.split("*").map((c) => c.trim())
    : (l: string) => splitCsvLine(l).map((c) => c.trim());

  const col = buildColumnMap(splitLine(lines[0]));
  if (col.fideid === undefined || col.rating === undefined) {
    throw new Error(`couldn't resolve fideid/rating columns in header: ${lines[0]}`);
  }

  // A handful of source files have the same fideid twice (e.g. JAN05.csv,
  // confirmed by grepping it directly) -- Postgres' ON CONFLICT DO UPDATE
  // rejects a batch that touches the same (fideid, period, rating_type) row
  // twice, so dedupe by fideid here, keeping the last occurrence.
  const byFideid = new Map<number, PlayerRow>();
  for (const line of lines.slice(1)) {
    const cells = splitLine(line);
    const fideid = toIntOrNull(cells[col.fideid]);
    let name = toStrOrNull(cells[col.name]);
    if (fideid === null || !name) continue;

    // The Standard archive's fixed-width name column is too narrow for some
    // players' full names (e.g. fideid 2211823, "De La Fuente Arias,
    // Fernando J." gets cut to "...Fernando" with "J." spilling into the
    // title column) -- anything left in title that isn't a real title code
    // is that overflow, so reattach it to the name instead of storing it as
    // a fake title.
    let title = normalizeTitle(toStrOrNull(cells[col.title]));
    if (title && !VALID_TITLES.has(title)) {
      name = `${name} ${title}`;
      title = null;
    }

    byFideid.set(fideid, {
      fideid,
      name,
      country: toStrOrNull(cells[col.country]),
      sex: toStrOrNull(cells[col.sex]),
      title,
      w_title: normalizeTitle(toStrOrNull(cells[col.w_title])),
      o_title: normalizeTitle(toStrOrNull(cells[col.o_title])),
      birthday: toIntOrNull(cells[col.birthday]),
      rating: toIntOrNull(cells[col.rating]),
      games: toIntOrNull(cells[col.games]),
      k: toIntOrNull(cells[col.k]),
      flag: toStrOrNull(cells[col.flag]),
    });
  }
  return [...byFideid.values()];
}

const KINDS: RatingKind[] = ["standard", "rapid", "blitz"];
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function loadFile(kind: RatingKind, file: HistoricalFile): Promise<void> {
  const url = `${BASE_URL}/${FOLDER[kind]}/${file.token}.csv`;
  const res = await fetch(url);
  if (!res.ok) {
    console.log(`  ${kind} ${file.period}: HTTP ${res.status}, skipping`);
    return;
  }
  const text = await res.text();
  const rows = parseHistoricalFile(text, DELIM[kind]);
  await upsertRatings(file.period, kind, rows);
  console.log(`  ${kind} ${file.period}: ${rows.length} players`);
}

async function main(): Promise<void> {
  for (const kind of KINDS) {
    for (const file of FILES[kind]) {
      await loadFile(kind, file);
      await sleep(200); // be polite to raw.githubusercontent.com
    }
  }
  console.log("flagging inactive (2+ years) players...");
  await flagInactivePlayers();
  console.log("refreshing latest_ratings...");
  await refreshLatestRatings();
  await closeDb();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
