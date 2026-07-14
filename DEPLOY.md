# Deploying fidata

## Why self-hosted on a single VPS

The `ratings` table used to be ~29 GB (100M rows): FIDE publishes a row
per player per month even for months they didn't play (`games = 0`,
rating just carried forward unchanged), which was ~90% of the table.
Those rows are now pruned at the DB layer (see the note in
`db/migrations/committed/000001.sql`), bringing it down to ~2.5 GB
(9.5M rows). Still growing every month, just far more slowly, and still
enough to rule out most managed free tiers:

- **Neon** free plan: 0.5 GB storage per project.
- **Supabase** free plan: 500 MB, paused after a week of inactivity.
- **Fly.io** volumes: $0.15/GB/month -- storage cost is now negligible at
  this size, but still simpler to self-host than to add a managed DB.

A single small VPS running Postgres + PostgREST + Nuxt + the scraper in
Docker Compose is both the cheapest and the simplest option, since
everything talks over localhost/the Docker network instead of paying
egress or cross-service latency.

**Currently running on:** OVH VPS-1 -- $4.54/mo (~4.20 EUR), 2 vCPU / 4 GB
RAM / 40 GB NVMe. 40 GB vs. today's ~2.5 GB DB leaves huge headroom -- the
`games = 0` pruning was the main growth driver, so this should hold for
years without revisiting. Domain: `fide-data.com` (OVH, ~9.59 EUR first
year / ~13.49 EUR/yr after).

SSH: key-only auth (`~/.ssh/oracle-fidata.key`), password auth disabled
server-side (`PasswordAuthentication no` in both `/etc/ssh/sshd_config`
and `/etc/ssh/sshd_config.d/50-cloud-init.conf` -- the cloud-init file is
read first and wins if only the main config is edited).

## Remaining

- [ ] Install the scraper's monthly systemd timer (step 9 below).
- [ ] Confirm TLS cert issued once DNS is fully propagated (Caddy retries
  automatically; check with `docker compose logs caddy`).

## What's not included (and why)

- **Backups**: not set up. The `ratings` data is reproducible from FIDE's
  own published rating lists (that's literally what the scraper does), so
  losing the DB means re-running a backfill, not losing irreplaceable
  data. If that stops being true (e.g. you start storing anything
  original), add `pg_dump` to cron and ship it somewhere off-box.
- **HA / multi-node**: this is a side project on a single box. If it goes
  down, it goes down; Caddy + Docker's `restart: unless-stopped` recovers
  from crashes/reboots automatically, which is enough for this scale.

## One-time setup

1. **Create the VPS** (Ubuntu 24.04, whichever provider from above), point
   a DNS A record at its IP.
2. **Install Docker**: `curl -fsSL https://get.docker.com | sh`
3. **Clone the repo** to `/opt/fidata` on the server.
4. **Configure env**: `cp .env.example .env`, fill in `POSTGRES_PASSWORD`
   (generate one, e.g. `openssl rand -hex 24`), `DOMAIN`, and
   `NUXT_PUBLIC_API_BASE=https://<DOMAIN>/api`.
5. **Bring up Postgres only** first, to load the schema before anything
   else starts querying it:
   ```
   docker compose up -d postgres
   docker compose exec -T postgres psql -U postgres -d fidata < db/migrations/committed/000001.sql
   ```
6. **Transfer the existing data** from your local dev DB (~2.5 GB -- a
   one-time transfer beats re-running the full historical backfill against
   FIDE's servers again):
   ```
   # on your local machine
   pg_dump -Fc --no-owner -d fidata -f fidata.dump
   rsync -avz --progress fidata.dump you@your-server:/opt/fidata/

   # on the server
   docker compose cp fidata.dump postgres:/fidata.dump
   docker compose exec postgres pg_restore --no-owner -U postgres -d fidata /fidata.dump
   ```
7. **Bring up everything else**:
   ```
   docker compose up -d
   ```
   Caddy will request a Let's Encrypt cert for `DOMAIN` automatically on
   first request -- make sure the DNS record is live before this step.
8. **Verify**: `https://<DOMAIN>/` loads the site, `https://<DOMAIN>/api/countries?limit=1`
   returns JSON.
9. **Install the scraper's monthly timer**:
   ```
   sudo cp deploy/fidata-scraper.* /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now fidata-scraper.timer
   ```

## Ongoing deploys (code changes)

```
git pull
docker compose up -d --build web postgrest
```

New DB migrations: `docker compose exec -T postgres psql -U postgres -d fidata < db/migrations/committed/0000NN.sql`,
same as step 5 above.
