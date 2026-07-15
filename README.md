# fidata

FIDE chess ratings, scraped monthly and served through a small self-hosted
stack: Postgres + PostgREST + Nuxt, behind Caddy in prod.

## Stack

- **`db/`** -- schema + migrations (`db/migrations/committed/`), managed with
  graphile-migrate.
- **`scraper/`** -- Node/TS, pulls FIDE's published rating lists monthly,
  parses and loads them into Postgres. `games = 0` rows (rating carried
  forward unchanged, no games played that month) are pruned at load time --
  brought the `ratings` table from ~29 GB/100M rows down to ~2.5 GB/9.5M
  rows.
- **`postgrest/`** -- auto-generated REST API over the schema.
- **`web/`** -- Nuxt 4 + Vuetify frontend (rankings, most-active, rating
  movers, search, player profiles). i18n in en/fr/es/de/nl.
- **`deploy/`** -- systemd unit + timer, runs monthly (3rd, 4am):
  `docker compose --profile cron run --rm scraper` (the `scraper` service
  in `docker-compose.yml` is `profiles: ["cron"]`, so it's excluded from
  the always-on stack and only runs one-shot like this).

## Local dev

```
cp .env.example .env   # fill in POSTGRES_PASSWORD (openssl rand -hex 24)
npm run dev             # docker compose + docker-compose.local.yml
```

`docker-compose.local.yml` isn't auto-loaded (only a file literally named
`docker-compose.override.yml` would be) -- `npm run dev` passes it with
`-f` explicitly, so prod (which just runs plain `docker compose up`) never
picks it up. Exposes `web` on `:3000`, `postgrest` on `:3001`, `postgres`
on `:5433` directly on the host -- Caddy isn't needed locally, just hit
`http://localhost:3000`.

Starting from an empty DB, seed some data with the scraper (from
`scraper/`):
```
npm run scrape -- --period=2026-06   # one month
npm run scrape -- --backfill         # full history since Feb 2015 (takes ~5 hours, slow FIDE Api)
```

## Migrations (graphile-migrate)

Run from `db/` via `npm run <script>` (`watch`, `commit`, `migrate`,
`status` -- see `db/package.json`).

## Deploying

Live at https://fide-data.com/.

See `TODO.md` for open work.
