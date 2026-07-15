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
docker compose up -d --build web postgrest
docker compose --profile cron run --rm migrate
