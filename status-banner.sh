#!/usr/bin/env bash
# Compact Hermes status banner. bootstrap.sh installs it into ~/.bashrc so
# EVERY new VS Code terminal in the Codespace shows the current state of the
# Hermes installation and services — nothing stays hidden in log files.
# (Safe to run anywhere: read-only, exits 0.)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_G=$'\e[32m'; C_Y=$'\e[33m'; C_R=$'\e[31m'; C_B=$'\e[1m'; C_D=$'\e[2m'; C_0=$'\e[0m'
else
  C_G=""; C_Y=""; C_R=""; C_B=""; C_D=""; C_0=""
fi

# config, if it exists
unset MODEL_PROVIDER MODEL_NAME NVIDIA_NIM_API_KEY GEMINI_API_KEY OPENROUTER_API_KEY \
      OPENAI_API_KEY ANTHROPIC_API_KEY GLM_API_KEY CUSTOM_API_KEY AI_API_KEY TELEGRAM_BOT_TOKEN
if [ -f "$ROOT/config/.env" ]; then set -a; . "$ROOT/config/.env"; set +a; fi

line(){ printf '  %-13s %s\n' "$1:" "$2"; }

echo ""
echo "${C_B}────────────── Hermes Codespace ──────────────${C_0}"

# Hermes installation status
HB="$(command -v hermes 2>/dev/null || true)"
if [ -z "$HB" ]; then
  for c in "$HOME/.local/bin/hermes" "$HOME/.hermes/bin/hermes"; do
    [ -x "$c" ] && HB="$c" && break
  done
fi
if [ -n "$HB" ]; then
  line "Hermes" "${C_G}INSTALLED${C_0} ($HB)"
else
  line "Hermes" "${C_R}NOT INSTALLED${C_0} — run: bash bootstrap.sh"
fi

# browser (cheap check: playwright cache — no launch on every terminal open)
if ls "$HOME/.cache/ms-playwright"/chromium* >/dev/null 2>&1; then
  line "Browser" "${C_G}Chromium OK${C_0}"
else
  line "Browser" "${C_Y}not found yet${C_0}"
fi

# AI provider / key
PROV="${MODEL_PROVIDER:-nvidia_nim}"
MODEL="${MODEL_NAME:-<default>}"
case "$PROV" in
  nvidia_nim) key="${NVIDIA_NIM_API_KEY:-}" ;;
  google)      key="${GEMINI_API_KEY:-}" ;;
  openrouter)  key="${OPENROUTER_API_KEY:-}" ;;
  openai)      key="${OPENAI_API_KEY:-}${AI_API_KEY:-}" ;;
  anthropic)   key="${ANTHROPIC_API_KEY:-}${AI_API_KEY:-}" ;;
  glm)         key="${GLM_API_KEY:-}${AI_API_KEY:-}" ;;
  custom)      key="${CUSTOM_API_KEY:-}${AI_API_KEY:-}" ;;
  *)           key="" ;;
esac
if [ -n "$key" ]; then
  line "AI provider" "${C_G}READY${C_0} — $PROV / $MODEL"
else
  line "AI provider" "${C_Y}$PROV / $MODEL (no key set)${C_0}"
fi

# services
pid_alive(){
  local f=$1 pat=$2 p
  [ -f "$f" ] || return 1
  p="$(cat "$f" 2>/dev/null)" || return 1
  [ -n "$p" ] || return 1
  kill -0 "$p" 2>/dev/null || return 1
  if ps -p "$p" -o args= >/dev/null 2>&1; then
    ps -p "$p" -o args= 2>/dev/null | grep -q "$pat"
  else
    return 0
  fi
}
if pid_alive "$ROOT/.run/runner.pid" task_manager.runner; then
  line "Task runner" "${C_G}RUNNING${C_0} (pid $(cat "$ROOT/.run/runner.pid"))"
else
  line "Task runner" "${C_Y}stopped${C_0} — start: scripts/start-hermes.sh start"
fi
if pid_alive "$ROOT/.run/telegram.pid" telegram_bot.bot; then
  line "Telegram bot" "${C_G}RUNNING${C_0} (pid $(cat "$ROOT/.run/telegram.pid"))"
elif [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
  line "Telegram bot" "${C_Y}stopped${C_0}"
else
  line "Telegram bot" "${C_D}disabled (TELEGRAM_BOT_TOKEN not set)${C_0}"
fi

# last VM start result
if [ -f "$ROOT/logs/autostart.log" ]; then
  LAST="$(grep -E "auto-start (complete|did not)" "$ROOT/logs/autostart.log" | tail -1 | sed 's/^\[OK\] //; s/^\[FAIL\] //' | cut -c1-64)"
  [ -n "$LAST" ] && line "Last VM start" "$LAST"
fi

echo "  ${C_D}details: tail -30 logs/autostart.log    manage: scripts/start-hermes.sh status${C_0}"
echo "${C_B}──────────────────────────────────────────────${C_0}"
exit 0
