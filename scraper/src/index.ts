import { fetchRatingXml } from "./fetch.js";
import { parsePlayers } from "./parse.js";
import { upsertRatings, refreshLatestRatings, closeDb } from "./db.js";
import { allPeriods, currentPeriod, parsePeriodArg, type Period } from "./periods.js";

const KINDS = ["standard", "rapid", "blitz"] as const;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function loadPeriod(p: Period): Promise<void> {
  for (const kind of KINDS) {
    const xml = await fetchRatingXml(kind, p.token);
    if (!xml) {
      console.log(`  ${kind} ${p.period}: not found, skipping`);
      continue;
    }
    const rows = parsePlayers(xml);
    await upsertRatings(p.period, kind, rows);
    console.log(`  ${kind} ${p.period}: ${rows.length} players`);
    await sleep(500); // be polite to ratings.fide.com
  }
}

async function main(): Promise<void> {
  const arg = process.argv[2];
  const periods = arg === "--backfill" ? allPeriods()
    : arg?.startsWith("--period=") ? [parsePeriodArg(arg.slice("--period=".length))]
    : [currentPeriod()];

  for (const p of periods) {
    console.log(`period ${p.period}`);
    await loadPeriod(p);
  }
  console.log("refreshing latest_ratings...");
  await refreshLatestRatings();
  await closeDb();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
