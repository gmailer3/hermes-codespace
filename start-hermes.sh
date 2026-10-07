#!/usr/bin/env bash
# Starts (or stops/restarts/status) the Hermes Codespace services in the
# BACKGROUND: the task runner (+ the Telegram control bot when configured).
# Idempotent: safe to call repeatedly; scripts/auto-start.sh calls it on every
# VM start so no manual command is needed.
#
# Usage: scripts/start-hermes.sh [start|stop|status|restart]   (default: start)
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
export PYTHONPATH="$PWD/src"
ACTION="${1:-start}"
RUN_DIR=".run"; mkdir -p "$RUN_DIR" logs

load_cfg(){ set -a; [ -f config/.env ] && . config/.env; set +a; }

pid_alive(){ # pid_alive PIDFILE GREP_PATTERN
  local f=$1 pat=$2 p
  [ -f "$f" ] || return 1
  p="$(cat "$f" 2>/dev/null)" || return 1
  [ -n "$p" ] || return 1
  kill -0 "$p" 2>/dev/null || return 1
  # guard against pid reuse, but degrade to kill -0 where ps lacks -o args=
  if ps -p "$p" -o args= >/dev/null 2>&1; then
    ps -p "$p" -o args= 2>/dev/null | grep -q "$pat"
  else
    return 0
  fi
}

start_one(){ # start_one NAME MODULE OUTLOG
  local name=$1 mod=$2 out=$3 pidf="$RUN_DIR/$1.pid"
  if pid_alive "$pidf" "$mod"; then
    echo "[..] $name already running (pid $(cat "$pidf"))"
    return 0
  fi
  rm -f "$pidf"
  # setsid: own session, so the Codespace lifecycle hook finishing can't take
  # the service down with it. 9>&- : don't inherit auto-start's lock fd
  # (otherwise the lock stays held for as long as the service lives).
  if command -v setsid >/dev/null 2>&1; then
    setsid nohup python3 -u -m "$mod" </dev/null >>"logs/$out" 2>&1 9>&- &
  else
    nohup python3 -u -m "$mod" </dev/null >>"logs/$out" 2>&1 9>&- &
  fi
  echo $! >"$pidf"
  sleep 1.5
  if pid_alive "$pidf" "$mod"; then
    echo "[OK] $name started (pid $(cat "$pidf"); log logs/$out)"
    return 0
  fi
  echo "[FAIL] $name exited immediately — inspect logs/$out"
  return 1
}

cfg_sig(){ cat "$HOME/.hermes/config.yaml" "$HOME/.hermes/.env" 2>/dev/null | md5sum 2>/dev/null | cut -c1-32; }

start_gateway(){ # Hermes' own Telegram gateway: chat with Hermes from Telegram
  local pidf="$RUN_DIR/gateway.pid" sigf="$RUN_DIR/gateway.sig"
  if pid_alive "$pidf" "gateway"; then
    if [ "$(cat "$sigf" 2>/dev/null)" = "$(cfg_sig)" ]; then
      echo "[..] hermes gateway already running (pid $(cat "$pidf"))"; return 0
    fi
    echo "[..] Hermes config changed, restarting the gateway so Telegram uses it"
    stop_one gateway gateway >/dev/null
  fi
  if ! command -v hermes >/dev/null 2>&1; then
    echo "[WARN] hermes not installed yet, Telegram chat starts on the next VM start"; return 1
  fi
  rm -f "$pidf"
  # foreground mode (no systemd in Codespaces); setsid detaches it from the hook
  if command -v setsid >/dev/null 2>&1; then
    setsid nohup hermes gateway run </dev/null >>logs/gateway.out 2>&1 9>&- &
  else
    nohup hermes gateway run </dev/null >>logs/gateway.out 2>&1 9>&- &
  fi
  echo $! >"$pidf"
  cfg_sig >"$sigf"
  sleep 4
  if pid_alive "$pidf" "gateway"; then
    echo "[OK] hermes gateway started (pid $(cat "$pidf"); Telegram chat -> Hermes; log logs/gateway.out)"
    return 0
  fi
  echo "[FAIL] hermes gateway exited immediately, last log lines:"; tail -n 15 logs/gateway.out
  return 1
}

start_telegram(){ # picks ONE poller per bot token (two pollers = Telegram 409 conflict)
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] || { echo "[--] Telegram disabled (TELEGRAM_BOT_TOKEN not set)"; return 0; }
  case "${TELEGRAM_MODE:-hermes}" in
    hermes)  stop_one telegram telegram_bot.bot >/dev/null; start_gateway ;;
    control) stop_one gateway gateway >/dev/null;           start_one telegram telegram_bot.bot telegram.out ;;
    off)     echo "[--] Telegram disabled (TELEGRAM_MODE=off)" ;;
    *)       echo "[WARN] unknown TELEGRAM_MODE='${TELEGRAM_MODE}' (hermes|control|off)"; return 1 ;;
  esac
}

stop_one(){ # stop_one NAME MODULE
  local name=$1 mod=$2 pidf="$RUN_DIR/$1.pid" p
  if pid_alive "$pidf" "$mod"; then
    p="$(cat "$pidf")"
    kill "$p" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8; do kill -0 "$p" 2>/dev/null || break; sleep 0.4; done
    kill -9 "$p" 2>/dev/null || true
    echo "[OK] $name stopped"
  else
    echo "[..] $name not running"
  fi
  rm -f "$pidf"
}

banner(){
  load_cfg
  RUNNER="$(pid_alive "$RUN_DIR/runner.pid" task_manager.runner && echo "RUNNING (pid $(cat "$RUN_DIR/runner.pid"))" || echo STOPPED)"
  if pid_alive "$RUN_DIR/gateway.pid" gateway; then
    TG="RUNNING: chat with Hermes (gateway pid $(cat "$RUN_DIR/gateway.pid"))"
  elif pid_alive "$RUN_DIR/telegram.pid" telegram_bot.bot; then
    TG="RUNNING: control bot (pid $(cat "$RUN_DIR/telegram.pid"))"
  elif [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
    TG="STOPPED"
  else
    TG="disabled (TELEGRAM_BOT_TOKEN not set)"
  fi
  cat <<BANNER
================================
 Hermes Codespace
================================
Hermes:       $([ -x "$(command -v hermes 2>/dev/null || echo $HOME/.local/bin/hermes)" ] && echo READY || echo MISSING)
AI Provider:  ${MODEL_PROVIDER:-?} / ${MODEL_NAME:-default}
Hermes model: $(python3 -c "import yaml,os;m=(yaml.safe_load(open(os.path.expanduser('~/.hermes/config.yaml'))) or {}).get('model') or {};print((m.get('base_url') or m.get('provider','?'))+' / '+str(m.get('default','?')))" 2>/dev/null || echo "not configured")
Workspace:    $PWD
Task Manager: $RUNNER
Telegram:     $TG
Waiting for tasks... (drop a task JSON in tasks/, or use Telegram /run)
Logs:         logs/runner.out, logs/gateway.out, logs/telegram.out
Stop:         scripts/start-hermes.sh stop
BANNER
}

do_start(){
  local RC=0
  load_cfg
  echo "== Hermes Codespace services =="
  if bash scripts/health-check.sh --quiet; then
    start_one runner task_manager.runner runner.out || RC=1
  else
    echo "[FAIL] health check failed — run 'bash scripts/health-check.sh' for the full report."
    [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && { echo "[..] starting Telegram anyway"; start_telegram || true; }
    exit 1
  fi
  start_telegram || RC=1
  banner
  exit "$RC"
}

do_stop(){
  stop_one gateway gateway
  stop_one telegram telegram_bot.bot
  stop_one runner task_manager.runner
  # sweep any straggler that outlived its pidfile (e.g. after a crash)
  if command -v pkill >/dev/null 2>&1; then
    pkill -f "python3 -u -m task_manager.runner" 2>/dev/null || true
    pkill -f "python3 -u -m telegram_bot.bot" 2>/dev/null || true
    pkill -f "hermes gateway run" 2>/dev/null || true
  fi
  echo "All services stopped."
}

do_status(){
  banner
}

case "$ACTION" in
  start)   do_start ;;
  stop)    do_stop ;;
  status)  do_status ;;
  restart) do_stop; do_start ;;
  *) echo "usage: $0 [start|stop|status|restart]" >&2; exit 2 ;;
esac
