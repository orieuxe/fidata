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
  age: number | null;
}

export interface RatingChange {
  fideid: number;
  name: string;
  country: string | null;
  title: string | null;
  start_rating: number;
  end_rating: number;
  delta: number;
  age: number | null;
}

export interface TopPlayer {
  fideid: number;
  name: string;
  country: string | null;
  title: string | null;
  rating: number | null;
  age: number | null;
}

// Matches search_players() -- one row per
// player with all 3 cadences, since the search page has no time control
// picker.
export interface SearchPlayer {
  fideid: number;
  name: string;
  country: string | null;
  title: string | null;
  rating_standard: number | null;
  rating_rapid: number | null;
  rating_blitz: number | null;
  age: number | null;
}

// Matches player_profile(). Rank columns pair
// with a total (not a pre-computed percentile) -- the frontend derives
// "top X%" as rank / total * 100.
export interface PlayerProfile {
  fideid: number;
  name: string;
  country: string | null;
  title: string | null;
  age: number | null;
  rating_standard: number | null;
  rating_rapid: number | null;
  rating_blitz: number | null;
  max_standard: number | null;
  max_rapid: number | null;
  max_blitz: number | null;
  rank_country_standard: number | null;
  rank_world_standard: number | null;
  total_country_standard: number | null;
  total_world_standard: number | null;
  games_this_year: number | null;
  rank_activity_country: number | null;
  rank_activity_world: number | null;
  total_activity_country: number | null;
  total_activity_world: number | null;
}

// Matches player_yearly_stats().
export interface PlayerYearlyStat {
  year: number;
  games_standard: number;
  delta_standard: number | null;
  games_rapid: number;
  delta_rapid: number | null;
  games_blitz: number;
  delta_blitz: number | null;
  games_total: number;
}
