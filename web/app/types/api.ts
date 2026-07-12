import type { components } from "./postgrest";

// Generated from PostgREST's OpenAPI spec — see `npm run gen:api-types`.
export type Rating = components["schemas"]["ratings"];
export type LatestRating = components["schemas"]["latest_ratings"];
export type Country = components["schemas"]["countries"];

// PostgREST's swagger output doesn't describe RPC return columns (only call
// parameters), so this one stays hand-written to match most_active_players()
// in db/migrations/committed/000001.sql.
export interface ActivePlayer {
  fideid: number;
  name: string;
  country: string | null;
  title: string | null;
  total_games: number;
  rating: number | null;
}
