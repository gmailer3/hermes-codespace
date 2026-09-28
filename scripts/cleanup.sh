#!/usr/bin/env bash
# Deletes completed client data, old screenshots/logs, and stray browsers.
set -euo pipefail
cd "$(dirname "$0")/.."
DAYS=${1:-7}
pkill -f chromium 2>/dev/null || true
find screenshots -type f -name '*.png' -mtime +"$DAYS" -delete
find logs -type f -name '*.log' -mtime +"$DAYS" -delete
for t in tasks/*.json; do
  [ -f "$t" ] || continue
  st=$(jq -r '.status // empty' "$t")
  if [ "$st" = "COMPLETED" ] || [ "$st" = "CANCELLED" ]; then
    f=$(jq -r '.input_file' "$t"); rm -f "client_data/$f"; echo "Removed client_data/$f"
  fi
done
echo "Cleanup done (files older than $DAYS days)."
