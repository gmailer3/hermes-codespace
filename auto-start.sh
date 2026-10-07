#!/usr/bin/env bash
# VM-start hook — wired to devcontainer.json "postStartCommand" so the
# Codespace needs ZERO manual commands.
#
# On EVERY VM start:
#   1. bash bootstrap.sh --non-interactive: installs Hermes / deps ONLY if
#      missing. Configuration happens on the FIRST start only; later starts
#      never touch your Hermes settings (bash bootstrap.sh --reconfigure to
#      re-apply secrets on purpose)
#   2. runs your ~/.hermes/on-start.d/*.sh scripts: things a Codespace forgets
#      on every restart (background daemons like ControlD's ctrld, DNS in
#      /etc/resolv.conf, ...) are re-applied here
#   3. scripts/start-hermes.sh start: task runner + Telegram bot (background)
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

# --- re-apply things a Codespace restart wipes ----------------------------------
# No systemd here, every background process dies on stop, and system files
# such as /etc/resolv.conf can be regenerated on start. Put an idempotent
# script per thing into ~/.hermes/on-start.d/ (Hermes is told to do this
# itself when you ask it to set up DNS/daemons/etc.). Runs before the
# services start, so e.g. the Telegram gateway already uses your DNS.
ONSTART="$HOME/.hermes/on-start.d"
mkdir -p "$ONSTART"
[ -f "$ONSTART/README.txt" ] || cat > "$ONSTART/README.txt" <<'TXT'
Every *.sh file in this folder runs (bash, as your user, sudo available) on
EVERY Codespace start, before Hermes' services start. Use it for anything the
Codespace forgets on restart: daemons (ctrld/ControlD, tailscale...), DNS
settings in /etc/resolv.conf, iptables rules, packages installed outside the
repo. Make scripts idempotent (safe to run again). Output: logs/on-start.log
in the repo. Example (ControlD):  ~/.hermes/on-start.d/10-controld.sh
TXT
for s in "$ONSTART"/*.sh; do
  [ -f "$s" ] || continue
  echo "[..] on-start: $(basename "$s")"
  if timeout 300 bash "$s" >>logs/on-start.log 2>&1; then echo "[OK] on-start: $(basename "$s")"
  else echo "[WARN] on-start: $(basename "$s") failed (see logs/on-start.log)"; fi
done

bash scripts/start-hermes.sh start
rc=$?
if [ "$rc" = 0 ]; then
  echo "[OK] auto-start complete — Hermes services are up (no commands needed)."
else
  echo "[FAIL] services did not start cleanly (exit $rc) — details above / in logs/."
fi
exit "$rc"
