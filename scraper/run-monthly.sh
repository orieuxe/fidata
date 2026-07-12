#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export DATABASE_URL="postgres://postgres@localhost:5432/fidata"
export PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v26.5.0/bin:$PATH"
npm run scrape >> cron.log 2>&1
