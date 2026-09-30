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
  nohup python3 -u -m "$mod" >>"logs/$out" 2>&1 &
  echo $! >"$pidf"
  sleep 1.5
  if pid_alive "$pidf" "$mod"; then
    echo "[OK] $name started (pid $(cat "$pidf"); log logs/$out)"
    return 0
  fi
  echo "[FAIL] $name exited immediately — inspect logs/$out"
  return 1
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
  if pid_alive "$RUN_DIR/telegram.pid" telegram_bot.bot; then
    TG="RUNNING (pid $(cat "$RUN_DIR/telegram.pid"))"
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
Workspace:    $PWD
Task Manager: $RUNNER
Telegram:     $TG
Waiting for tasks... (drop a task JSON in tasks/, or use Telegram /run)
Logs:         logs/runner.out, logs/telegram.out
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
    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
      echo "[..] starting the Telegram bot anyway so you can control the box remotely (/health, /status)"
      start_one telegram telegram_bot.bot telegram.out || true
    fi
    exit 1
  fi
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
    start_one telegram telegram_bot.bot telegram.out || RC=1
  else
    echo "[--] Telegram bot disabled (TELEGRAM_BOT_TOKEN not set)"
  fi
  banner
  exit "$RC"
}

do_stop(){
  stop_one telegram telegram_bot.bot
  stop_one runner task_manager.runner
  # sweep any straggler that outlived its pidfile (e.g. after a crash)
  if command -v pkill >/dev/null 2>&1; then
    pkill -f "python3 -u -m task_manager.runner" 2>/dev/null || true
    pkill -f "python3 -u -m telegram_bot.bot" 2>/dev/null || true
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
