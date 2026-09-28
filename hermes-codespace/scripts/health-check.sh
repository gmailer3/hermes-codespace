#!/usr/bin/env bash
cd "$(dirname "$0")/.."
set -a; [ -f config/.env ] && . config/.env; set +a
Q=${1:-}; FAIL=0
chk() { if eval "$2" >/dev/null 2>&1; then [ "$Q" = "--quiet" ] || echo "[OK] $1"; else echo "[FAIL] $1"; FAIL=1; fi; }
chk "Hermes binary"        "command -v hermes || test -x \$HOME/.local/bin/hermes"
chk "Python"               "python3 --version"
chk "Browser"              "python3 -c 'from playwright.sync_api import sync_playwright as s; p=s().start(); p.chromium.launch().close(); p.stop()'"
chk "GEMINI_API_KEY or OPENROUTER_API_KEY set" "test -n \"\${GEMINI_API_KEY:-}\${OPENROUTER_API_KEY:-}\${AI_API_KEY:-}\""
chk "AI provider reachable ($MODEL_PROVIDER)"  "PYTHONPATH=src python3 -m configuration.llm --check"
chk "MODEL_PROVIDER set"   "test -n \"\${MODEL_PROVIDER:-}\""
chk "Filesystem writable"  "touch logs/.hc && rm logs/.hc"
chk "Network"              "curl -sSf -o /dev/null --max-time 5 https://api.github.com"
exit $FAIL
