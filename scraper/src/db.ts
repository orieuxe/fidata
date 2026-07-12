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
}

export async function closeDb(): Promise<void> {
  await sql.end();
}
