import postgres from "postgres";
import type { RatingKind } from "./fetch.js";
import type { PlayerRow } from "./parse.js";

const sql = postgres(
  process.env.DATABASE_URL ?? "postgres://postgres@localhost:5432/fidata",
);

const CHUNK_SIZE = 4000; // 14 columns/row, stay under Postgres' 65534 param limit

export async function upsertRatings(
  period: string,
  kind: RatingKind,
  rows: PlayerRow[],
): Promise<void> {
  rows = rows.filter((r) => r.games !== 0);

  for (let i = 0; i < rows.length; i += CHUNK_SIZE) {
    const chunk = rows.slice(i, i + CHUNK_SIZE).map((r) => ({
      ...r,
      period,
      rating_type: kind,
    }));
    await sql`
      insert into ratings ${sql(
        chunk,
        "fideid", "period", "rating_type", "name", "country", "sex",
        "title", "w_title", "o_title", "birthday", "rating", "games", "k", "flag",
      )}
      on conflict (fideid, period, rating_type) do update set
        name = excluded.name,
        country = excluded.country,
        sex = excluded.sex,
        title = excluded.title,
        w_title = excluded.w_title,
        o_title = excluded.o_title,
        birthday = excluded.birthday,
        rating = excluded.rating,
        games = excluded.games,
        k = excluded.k,
        flag = excluded.flag
    `;
  }

  const codes = [...new Set(rows.map((r) => r.country).filter((c): c is string => !!c))];
  if (codes.length) {
    await sql`
      insert into countries ${sql(codes.map((code) => ({ code })), "code")}
      on conflict do nothing
    `;
  }
}

// FIDE flags a player inactive on the monthly carry-forward row after they
// stop playing (games = 0) -- exactly the rows upsertRatings prunes above.
// A player whose last-ever row for a rating_type predates our own scraper's
// coverage has no such row in this table at all, so their last real-game
// row looks "current" and slips past every `flag not like '%i%'` filter
// (top_players, search_players, player_profile's rank via latest_ratings --
// see fideid 4100018, Garry Kasparov, who briefly re-entered the standard
// top players list after the historical backfill for this exact reason).
// Tag that row here instead.
export async function flagStaleHistoricalPlayers(periodCutoff: string): Promise<void> {
  const result = await sql`
    with last_period as (
      select fideid, rating_type, max(period) as period
      from ratings
      group by fideid, rating_type
    )
    update ratings r
    set flag = coalesce(nullif(r.flag, ''), '') || 'i'
    from last_period lp
    where r.fideid = lp.fideid
      and r.rating_type = lp.rating_type
      and r.period = lp.period
      and r.period < ${periodCutoff}
      and coalesce(r.flag, '') not like '%i%'
  `;
  console.log(`  flagged ${result.count} stale historical rows as inactive`);
}

export async function refreshLatestRatings(): Promise<void> {
  await sql`refresh materialized view concurrently latest_ratings`;
}

export async function closeDb(): Promise<void> {
  await sql.end();
}
