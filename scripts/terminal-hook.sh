#!/usr/bin/env bash
# Called from ~/.bashrc / ~/.zshrc for every new interactive terminal.
# Shows Hermes status; if services died, restarts them (no bootstrap, fast).
# Opt out: export HERMES_NO_HOOK=1
[ -n "${HERMES_NO_HOOK:-}" ] && exit 0
cd "$(dirname "$0")/.." || exit 0
mkdir -p .run logs
if command -v flock >/dev/null 2>&1 && ! flock -n .run/autostart.lock true; then
  echo "[..] Hermes auto-start still running: tail -f $PWD/logs/autostart.log"
  exit 0
fi
if bash scripts/start-hermes.sh status | grep -q 'Task Manager: RUNNING'; then
  bash scripts/start-hermes.sh status
else
  echo "[..] Hermes services are down, starting..."
  bash scripts/start-hermes.sh start || echo "[WARN] start failed: bash scripts/health-check.sh"
fi
exit 0
