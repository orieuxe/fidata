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
- **`deploy/`** -- systemd units + timers:
  - `fidata-scraper.*`: monthly (3rd, 4am), `docker compose --profile cron
    run --rm scraper` (excluded from the always-on stack via `profiles:
    ["cron"]`, one-shot only).
  - `fidata-deploy.*`: polls every 5 min, pulls + rebuilds `web`/`postgrest`
    + runs `migrate` (same `profiles: ["cron"]` pattern) if `origin/main`
    moved. Auto-deploy without a webhook or exposed port.

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

Live at https://fide-data.com/, auto-deployed on push to `main` (see
`fidata-deploy.*` above). One-time setup on the VPS:
```
sudo cp deploy/fidata-deploy.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now fidata-deploy.timer
```

See `TODO.md` for open work.
