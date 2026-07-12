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
  // Skip games = 0 rows (FIDE's monthly carry-forward entry for players who
  // didn't play -- rating just repeats unchanged): keeps `ratings` at one
  // row per period actually played instead of regrowing the ~90% of rows
  // pruned in db/migrations/committed/000001.sql.
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

export async function refreshLatestRatings(): Promise<void> {
  await sql`refresh materialized view concurrently latest_ratings`;
}

export async function closeDb(): Promise<void> {
  await sql.end();
}
