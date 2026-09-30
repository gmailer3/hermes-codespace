#!/usr/bin/env bash
# VM-start hook — wired to devcontainer.json "postStartCommand" so the
# Codespace needs ZERO manual commands.
#
# On EVERY VM start:
#   1. bash bootstrap.sh --non-interactive — idempotent: installs Hermes
#      (first, if missing), refreshes Python deps + Chromium, and RE-DETECTS
#      Codespaces secrets, so API keys added on GitHub after creation are
#      picked up automatically
#   2. scripts/start-hermes.sh start — task runner + Telegram bot (background)
#
# Re-running bootstrap when everything is already installed only takes a few
# seconds (it skips what is in place). A persistent transcript lands in
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

# bootstrap on EVERY start (installs anything missing, refreshes secrets/config)
if bash bootstrap.sh --non-interactive; then
  echo "[OK] bootstrap complete"
else
  echo "[WARN] bootstrap reported a failure — trying to launch services anyway"
  echo "       (run 'bash bootstrap.sh' in a terminal to see the full report)"
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
