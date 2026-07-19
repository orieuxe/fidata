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
  await refreshLeaderboardSnapshots();
}

// Precomputed tables behind the "movers" (rating_change_snapshots) and
// "active"/"top players" (rating_change_snapshots' total_games column,
// top_players_snapshots) pages -- see rating_change.sql,
// most_active_players.sql, top_players.sql.
//
// Rolling 12-month and all-time buckets are rewritten every scrape. The
// rolling window matches web/app/utils/filterOptions.ts'
// yearFilterRange("last12") exactly, so rating_change()/most_active_players()
// can recognize and reuse it.
//
// The scraper runs on the 3rd of the month (deploy/fidata-scraper.timer),
// after the 1st -- so in December the rolling window already lands exactly
// on Jan-Dec of the current year (excludes last December's row, includes
// this one, both already scraped). Freeze both snapshot tables under their
// own year bucket then, once -- `on conflict do nothing` makes this safe to
// leave running every December going forward without ever overwriting a
// frozen year.
async function refreshLeaderboardSnapshots(): Promise<void> {
  await sql`delete from rating_change_snapshots where bucket = 'rolling'`;
  const rolling = await sql`
    insert into rating_change_snapshots
      (bucket, fideid, rating_type, name, country, sex, title, birthday, start_rating, end_rating, total_games)
    select
      'rolling', fideid, rating_type,
      (array_agg(name order by period desc))[1],
      (array_agg(country order by period desc))[1],
      (array_agg(sex order by period desc))[1],
      (array_agg(title order by period desc))[1],
      (array_agg(birthday order by period desc))[1],
      (array_agg(rating order by period asc))[1],
      (array_agg(rating order by period desc))[1],
      sum(coalesce(games, 0))
    from ratings
    where games > 0
      and period >= (date_trunc('month', current_date) + interval '1 month' - interval '12 months')::date
    group by fideid, rating_type
  `;
  console.log(`  rating_change_snapshots 'rolling': ${rolling.count} rows`);

  // "all time" bucket for most_active_players (see 000013.sql) -- only the
  // current year's totals can still change between scrapes, but the whole
  // aggregate is cheap enough (~seconds) to just redo in full every run
  // rather than tracking which fideids actually changed.
  await sql`delete from rating_change_snapshots where bucket = 'all'`;
  const all = await sql`
    insert into rating_change_snapshots
      (bucket, fideid, rating_type, name, country, sex, title, birthday, start_rating, end_rating, total_games)
    select
      'all', fideid, rating_type,
      (array_agg(name order by period desc))[1],
      (array_agg(country order by period desc))[1],
      (array_agg(sex order by period desc))[1],
      (array_agg(title order by period desc))[1],
      (array_agg(birthday order by period desc))[1],
      (array_agg(rating order by period asc))[1],
      (array_agg(rating order by period desc))[1],
      sum(coalesce(games, 0))
    from ratings
    where games > 0
    group by fideid, rating_type
  `;
  console.log(`  rating_change_snapshots 'all': ${all.count} rows`);

  if (new Date().getMonth() === 11) {
    const year = String(new Date().getFullYear());
    const frozen = await sql`
      insert into rating_change_snapshots
        (bucket, fideid, rating_type, name, country, sex, title, birthday, start_rating, end_rating, total_games)
      select ${year}, fideid, rating_type, name, country, sex, title, birthday, start_rating, end_rating, total_games
      from rating_change_snapshots
      where bucket = 'rolling'
      on conflict (bucket, fideid, rating_type) do nothing
    `;
    console.log(`  rating_change_snapshots '${year}' freeze: ${frozen.count} rows inserted`);

    // top_players_snapshots (see 000014.sql) -- same year-end freeze, same
    // 2-years-of-activity requirement as the one-time backfill used. Reads
    // latest_ratings instead of a DISTINCT ON over ratings for the "latest
    // rating" part: it's already been refreshed earlier in
    // refreshDerivedViews, and in a December run its latest period is this
    // year's December scrape -- exactly the year-end snapshot we want.
    const yearEnd = new Date().getFullYear();
    const topFrozen = await sql`
      insert into top_players_snapshots
        (bucket, fideid, rating_type, name, country, sex, title, birthday, rating)
      select ${year}, l.fideid, l.rating_type, l.name, l.country, l.sex, l.title, l.birthday, l.rating
      from latest_ratings l
      join (
        select distinct fideid, rating_type
        from ratings
        where games > 0
          and period > make_date(${yearEnd}, 12, 1) - interval '2 years'
          and period <= make_date(${yearEnd}, 12, 1)
      ) a using (fideid, rating_type)
      where l.rating is not null
      on conflict (bucket, fideid, rating_type) do nothing
    `;
    console.log(`  top_players_snapshots '${year}' freeze: ${topFrozen.count} rows inserted`);
  }
}

export async function closeDb(): Promise<void> {
  await sql.end();
}
