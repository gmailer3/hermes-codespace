#!/usr/bin/env bash
# Called from ~/.bashrc / ~/.zshrc for every new interactive terminal.
# Shows Hermes status; if services died, restarts them (no bootstrap, fast).
# Opt out: export HERMES_NO_HOOK=1
[ -n "${HERMES_NO_HOOK:-}" ] && exit 0
cd "$(dirname "$0")/.." || exit 0
export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
mkdir -p .run logs
# The first Codespace terminal usually opens while auto-start is still
# installing. Previously we bailed out here, so Hermes never auto-launched.
# Now: stream the setup log, wait for it to finish, then continue.
lock_busy(){ command -v flock >/dev/null 2>&1 && ! flock -n .run/autostart.lock true; }
if lock_busy; then
  if [ -t 1 ]; then
    echo "== Hermes setup still running, live log below (Ctrl+C to skip waiting) =="
    tail -n 30 -f logs/autostart.log & TP=$!
    trap 'kill $TP 2>/dev/null; exit 0' INT
    for _ in $(seq 1 600); do lock_busy || break; sleep 2; done
    kill "$TP" 2>/dev/null; trap - INT
  else
    exit 0
  fi
fi
if bash scripts/start-hermes.sh status | grep -q 'Task Manager: RUNNING'; then
  bash scripts/start-hermes.sh status
else
  echo "[..] Hermes services are down, starting..."
  bash scripts/start-hermes.sh start || echo "[WARN] start failed: bash scripts/health-check.sh"
fi
# First interactive terminal after each VM boot drops straight into Hermes chat.
BOOT="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo once)"
if [ -z "${HERMES_NO_AUTOCHAT:-}" ] && [ -t 0 ] && [ -t 1 ] && command -v hermes >/dev/null 2>&1 \
   && [ "$(cat .run/autochat.boot 2>/dev/null)" != "$BOOT" ]; then
  echo "$BOOT" > .run/autochat.boot
  echo "Launching Hermes (exit with /quit or Ctrl+D)... opt out: export HERMES_NO_AUTOCHAT=1"
  hermes </dev/tty || true
fi
exit 0
