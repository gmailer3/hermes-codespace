#!/usr/bin/env bash
# VM-start hook — wired to devcontainer.json "postStartCommand" so the
# Codespace needs ZERO manual commands.
#
#   Hermes installed?  ->  just launch the services (runner + Telegram bot)
#   Hermes missing?     ->  run the full bootstrap (install + secrets + setup),
#                           then launch.
#
# Everything is idempotent; a persistent copy of the transcript lands in
# logs/autostart.log.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs

# show on the codespace terminal AND keep a persistent copy
if command -v tee >/dev/null 2>&1; then
  exec > >(tee -a logs/autostart.log) 2>&1
else
  exec >> logs/autostart.log 2>&1
fi

echo ""
echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) — Hermes Codespace auto-start ==="
export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$PATH"

# never run twice concurrently for the same container start
mkdir -p .run
if command -v flock >/dev/null 2>&1; then
  exec 9>.run/autostart.lock
  flock -n 9 || { echo "[..] auto-start already running — nothing to do"; exit 0; }
fi

if command -v hermes >/dev/null 2>&1; then
  echo "[OK] Hermes installed ($(command -v hermes)) — launching services"
else
  echo "[..] Hermes not installed — running full bootstrap first (one-time)"
  if bash bootstrap.sh --non-interactive; then
    echo "[OK] bootstrap finished"
  else
    echo "[FAIL] bootstrap failed — open logs/autostart.log, fix the reported problem,"
    echo "       then run: bash bootstrap.sh"
    exit 1
  fi
fi

[ -f config/.env ] || { cp config/config.example.env config/.env; echo "[..] created config/.env from example"; }

bash scripts/start-hermes.sh start
rc=$?
if [ "$rc" = 0 ]; then
  echo "[OK] auto-start complete — Hermes services are up (no commands needed)."
else
  echo "[FAIL] services did not start cleanly (exit $rc) — details above / in logs/."
fi
exit "$rc"
