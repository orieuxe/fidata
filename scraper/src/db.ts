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
// A player whose last-ever row for a rating_type is more than 2 years old
// has no such carry-forward row in this table at all, so their last
// real-game row looks "current" and slips past every `flag not like '%i%'`
// filter (top_players, search_players, player_profile's rank via
// latest_ratings -- see fideid 4100018, Garry Kasparov, who briefly
// re-entered the standard top players list after the historical backfill
// for this exact reason). Tag that row here instead.
//
// Runs after every scrape (not just the one-off historical backfill) --
// otherwise a player who goes quiet between two regular monthly runs never
// gets flagged and keeps climbing the rankings as if still active.
export async function flagInactivePlayers(): Promise<void> {
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
      and r.period < current_date - interval '2 years'
      and coalesce(r.flag, '') not like '%i%'
  `;
  console.log(`  flagged ${result.count} inactive (2+ years) rows as inactive`);
}

export async function refreshLatestRatings(): Promise<void> {
  await sql`refresh materialized view concurrently latest_ratings`;
}

// player_activity_12m and player_ranks both read from latest_ratings (ranks
// also read player_activity_12m), so must refresh in this order, after it.
export async function refreshDerivedViews(): Promise<void> {
  await sql`refresh materialized view concurrently player_activity_12m`;
  await sql`refresh materialized view concurrently player_ranks`;
  await refreshRatingChangeSnapshots();
}

// Rolling 12-month rating-change snapshot for the "movers" page (see
// rating_change.sql), rewritten every scrape. The window matches
// web/app/utils/filterOptions.ts' yearFilterRange("last12") exactly, so
// rating_change() can recognize and reuse it.
//
// The scraper runs on the 3rd of the month (deploy/fidata-scraper.timer),
// after the 1st -- so in December this window already lands exactly on
// Jan-Dec of the current year (excludes last December's row, includes this
// one, both already scraped). Freeze it under its own year bucket then,
// once -- `on conflict do nothing` makes this safe to leave running every
// December going forward without ever overwriting a frozen year.
async function refreshRatingChangeSnapshots(): Promise<void> {
  await sql`delete from rating_change_snapshots where bucket = 'rolling'`;
  await sql`
    insert into rating_change_snapshots
      (bucket, fideid, rating_type, name, country, title, birthday, start_rating, end_rating)
    select
      'rolling', fideid, rating_type,
      (array_agg(name order by period desc))[1],
      (array_agg(country order by period desc))[1],
      (array_agg(title order by period desc))[1],
      (array_agg(birthday order by period desc))[1],
      (array_agg(rating order by period asc))[1],
      (array_agg(rating order by period desc))[1]
    from ratings
    where games > 0
      and period >= (date_trunc('month', current_date) + interval '1 month' - interval '12 months')::date
    group by fideid, rating_type
  `;

  if (new Date().getMonth() === 11) {
    const year = String(new Date().getFullYear());
    await sql`
      insert into rating_change_snapshots
        (bucket, fideid, rating_type, name, country, title, birthday, start_rating, end_rating)
      select ${year}, fideid, rating_type, name, country, title, birthday, start_rating, end_rating
      from rating_change_snapshots
      where bucket = 'rolling'
      on conflict (bucket, fideid, rating_type) do nothing
    `;
  }
}

export async function closeDb(): Promise<void> {
  await sql.end();
}
