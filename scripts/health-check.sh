#!/usr/bin/env bash
# Verifies everything the runner needs. --quiet prints failures only.
# Exit code 0 = all hard checks pass.
cd "$(dirname "$0")/.."
set -a; [ -f config/.env ] && . config/.env; set +a
export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
Q=""; [ "${1:-}" = "--quiet" ] && Q=1
FAIL=0

chk(){ # chk LABEL SHELL_TEST   (failure -> exit code 1)
  local l="$1" c="$2"
  if eval "$c" >/dev/null 2>&1; then
    [ -n "$Q" ] || echo "[ OK ] $l"
  else
    echo "[FAIL] $l"
    FAIL=1
  fi
}
warnchk(){ # soft check: never fails the run
  local l="$1" c="$2"
  if eval "$c" >/dev/null 2>&1; then
    [ -n "$Q" ] || echo "[ OK ] $l"
  else
    [ -n "$Q" ] || echo "[WARN] $l (non-fatal)"
  fi
}

# The task runner is pure Python; the Hermes CLI is installed/retried by
# bootstrap.sh on every VM start, so a missing binary is a warning, not a blocker.
warnchk "Hermes binary"      "command -v hermes || test -x \$HOME/.local/bin/hermes || test -x \$HOME/.hermes/bin/hermes"
chk "Python 3"              "python3 --version"
chk "Chromium (Playwright)"  "python3 -c 'from playwright.sync_api import sync_playwright as s; p=s().start(); p.chromium.launch().close(); p.stop()'"
chk "AI API key present"     "test -n \"\${GEMINI_API_KEY:-}\${OPENROUTER_API_KEY:-}\${NVIDIA_NIM_API_KEY:-}\${OPENAI_API_KEY:-}\${ANTHROPIC_API_KEY:-}\${GLM_API_KEY:-}\${CUSTOM_API_KEY:-}\${AI_API_KEY:-}\""
chk "MODEL_PROVIDER set"     "test -n \"\${MODEL_PROVIDER:-}\""
chk "AI provider reachable (${MODEL_PROVIDER:-unknown})" "PYTHONPATH=src python3 -m configuration.llm --check"
chk "Workspace writable"     "touch logs/.hc 2>/dev/null && rm -f logs/.hc"
chk "Network (api.github.com)" "curl -sSf -o /dev/null --max-time 8 https://api.github.com"
warnchk "Node.js (Hermes tools)" "node --version"

if [ -z "$Q" ]; then
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
    echo "[ OK ] TELEGRAM_BOT_TOKEN set — bot runs alongside the task runner"
    if [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
      echo "[ OK ] TELEGRAM_CHAT_ID set (${TELEGRAM_CHAT_ID})"
    else
      echo "[WARN] TELEGRAM_CHAT_ID not set — bot answers /start with your chat id and refuses other commands until it is set"
    fi
  else
    echo "[ -- ] TELEGRAM_BOT_TOKEN not set (Telegram control is optional)"
  fi
fi
exit $FAIL
