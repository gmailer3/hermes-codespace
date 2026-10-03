#!/usr/bin/env bash
# postAttachCommand: runs in a VISIBLE Codespace terminal every time you open
# the Codespace. Streams the auto-start log live until it finishes, makes sure
# the services are really up (starts them if not), then prints the banner.
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
mkdir -p logs .run
touch logs/autostart.log

lock_busy(){ command -v flock >/dev/null 2>&1 && ! flock -n .run/autostart.lock true; }

if lock_busy; then
  echo "== Hermes auto-start in progress (live log) =="
  tail -n 40 -f logs/autostart.log & TP=$!
  for _ in $(seq 1 600); do lock_busy || break; sleep 2; done   # max ~20 min
  sleep 1; kill "$TP" 2>/dev/null
fi

if bash scripts/start-hermes.sh status | grep -q 'Task Manager: RUNNING'; then
  bash scripts/start-hermes.sh status
else
  echo "[..] services not running yet, starting them now"
  bash scripts/start-hermes.sh start || {
    echo "[FAIL] could not start. Full report: bash scripts/health-check.sh"
    echo "       Missing keys? GitHub repo -> Settings -> Secrets -> Codespaces, then rebuild/restart."
  }
fi
echo ""
# Launch Hermes itself in this VS Code terminal (model from ~/.hermes/config.yaml,
# i.e. NVIDIA NIM / kimi-k3 by default). Opt out with HERMES_NO_AUTOCHAT=1.
if [ -z "${HERMES_NO_AUTOCHAT:-}" ] && command -v hermes >/dev/null 2>&1 && [ -t 0 ]; then
  cat /proc/sys/kernel/random/boot_id > .run/autochat.boot 2>/dev/null || echo once > .run/autochat.boot
  echo "Launching Hermes (exit with /quit or Ctrl+D; services keep running)..."
  hermes || echo "[WARN] hermes exited with an error, see above"
  exec bash -l
fi
echo "Live runner log (Ctrl+C to stop watching, services keep running):"
exec tail -n 20 -F logs/runner.out
