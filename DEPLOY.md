# Deploying fidata

## Why self-hosted on a single VPS

The `ratings` table is ~29 GB (100M rows) and growing every month. That
alone rules out every managed free tier that could otherwise run this
stack for free:

- **Neon** free plan: 0.5 GB storage per project.
- **Supabase** free plan: 500 MB, paused after a week of inactivity.
- **Fly.io** volumes: $0.15/GB/month -- ~$4.35/month for storage alone,
  before compute, and that's before it grows further.

A single small VPS running Postgres + PostgREST + Nuxt + the scraper in
Docker Compose is both the cheapest and the simplest option, since
everything talks over localhost/the Docker network instead of paying
egress or cross-service latency.

**Recommended, in order:**

1. **Oracle Cloud Always Free** -- genuinely $0/month forever, 200 GB
   block storage (unaffected by their mid-2026 compute-tier cut) is
   comfortable headroom well past what this DB needs for years. Downside:
   Ampere A1 free-tier capacity is notoriously hard to get in some regions
   right now (`Out of capacity` errors on signup) -- worth trying first
   since it's free, but don't count on it working immediately.
2. **OVH VPS-1** -- $4.54/mo (~4.20 EUR), 2 vCPU / 4 GB RAM / 40 GB NVMe.
   Fits the budget, EU-based. 40 GB vs. today's 29 GB DB leaves ~11 GB of
   headroom -- fine for now, but worth checking `docker system df` /
   `df -h` every few months as the scraper keeps backfilling.
3. **Hetzner CX22** -- ~3.79-5.49 EUR/mo depending on region/timing, same
   specs ballpark as OVH VPS-1. Equally good if OVH doesn't have capacity
   in your preferred region.

Any of the three run the exact same Docker Compose stack below -- only the
"create a VPS" step differs per provider.

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
   docker compose exec -T postgres psql -U postgres -d fidata < db/migrations/committed/000002.sql
   ```
6. **Transfer the existing data** from your local dev DB (29 GB -- a
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
