#!/bin/bash
# Polled by fidata-deploy.timer -- pulls and redeploys only if origin/main
# has moved since the last run.
set -euo pipefail
cd /opt/fidata

git fetch origin main
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)
if [ "$LOCAL" = "$REMOTE" ]; then
  exit 0
fi

git pull origin main
docker compose -f docker-compose.yml -f docker-compose.prod.yml --profile cron run --rm migrate
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build web postgrest
