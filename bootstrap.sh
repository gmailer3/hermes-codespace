#!/usr/bin/env bash
# =============================================================================
#  Hermes Codespace — ONE-COMMAND BOOTSTRAP
#
#  What it does (idempotent — safe to re-run any time):
#    1. Installs the NousResearch Hermes agent  — FIRST, if not already installed
#    2. Installs Python dependencies + Chromium (Playwright)
#    3. Detects API keys / Telegram token from GitHub Codespaces secrets
#       (Codespaces injects them as environment variables) and writes them to
#       config/.env (project, gitignored) and ~/.hermes/.env (Hermes CLI, 0600)
#    4. Interactive only: menu to add/replace keys — Gemini, OpenRouter,
#       NVIDIA NIM, OpenAI, Anthropic, GLM, custom OpenAI-compatible endpoint,
#       Telegram bot token + authorized chat id
#    5. Auto-selects the AI provider based on which keys are present
#    6. Validates everything and prints a summary; can start services
#
#  Usage:
#    bash bootstrap.sh                     # interactive (menu to add API keys)
#    bash bootstrap.sh --non-interactive   # unattended (Codespace create / hooks)
#    bash bootstrap.sh --launch            # also start runner + Telegram bot
#
#  On any Linux VM without the repo (replace USER/REPO with yours):
#    curl -fsSL https://raw.githubusercontent.com/USER/REPO/main/bootstrap.sh \
#      | HERMES_CODESPACE_REPO=https://github.com/USER/REPO.git bash
#
#  In a Codespace you normally never need to run this by hand:
#  devcontainer.json runs it on create, and scripts/auto-start.sh runs it on
#  VM start when Hermes is missing — then launches everything automatically.
# =============================================================================
set -euo pipefail

NON_INTERACTIVE=0
LAUNCH=0
for a in "$@"; do
  case "$a" in
    --non-interactive|-n) NON_INTERACTIVE=1 ;;
    --launch|-l)          LAUNCH=1 ;;
    -h|--help)            if [ -f "$0" ]; then sed -n '2,29p' "$0" | sed 's/^#\{1,\} \{0,1\}//';
                          else echo "Run 'bash bootstrap.sh --help' from inside the repo."; fi
                          exit 0 ;;
    *) echo "unknown option: $a (see --help)" >&2; exit 2 ;;
  esac
done

# --- locate the repository ---------------------------------------------------
if [ -f "${BASH_SOURCE[0]:-}" ]; then
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [ -n "${HERMES_CODESPACE_REPO:-}" ]; then
  # piped via curl: clone the repo first
  dest="hermes-codespace"
  [ -d "$dest/.git" ] || git clone --depth 1 "$HERMES_CODESPACE_REPO" "$dest"
  REPO_ROOT="$(cd "$dest" && pwd)"
else
  echo "This bootstrap normally lives inside the hermes-codespace repo." >&2
  echo "Run it from the repo, or pipe it with HERMES_CODESPACE_REPO=<git-url>." >&2
  exit 1
fi
cd "$REPO_ROOT"

# --- output helpers -----------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  ok()   { printf '[\e[32m OK \e[0m] %s\n' "$*"; }
  warn() { printf '[\e[33mWARN\e[0m] %s\n' "$*"; }
  fail() { printf '[\e[31mFAIL\e[0m] %s\n' "$*" >&2; exit 1; }
  step() { printf '\n\e[1m== %s ==\e[0m\n' "$*"; }
else
  ok()   { echo "[ OK ] $*"; }
  warn() { echo "[WARN] $*"; }
  fail() { echo "[FAIL] $*" >&2; exit 1; }
  step() { echo ""; echo "== $* =="; }
fi
have(){ command -v "$1" >/dev/null 2>&1; }
SUDO=""; [ "$(id -u)" = 0 ] || SUDO="sudo"
apt_install(){ # apt_install PKG...
  have apt-get || return 1
  $SUDO apt-get update -qq >/dev/null 2>&1 || true
  $SUDO apt-get install -y -qq "$@" >/dev/null 2>&1
}

INTERACTIVE=0
[ "$NON_INTERACTIVE" = 0 ] && [ -t 0 ] && [ -t 1 ] && INTERACTIVE=1

step "Hermes Codespace bootstrap"
echo "OS: $(uname -s) ($(uname -m)) — repo: $REPO_ROOT"
[ "$(uname -s)" = "Linux" ] || warn "not Linux — continuing best-effort"

# --- 1/7 base tooling ---------------------------------------------------------
step "1/7 Base tooling"
for c in python3 git curl; do
  if ! have "$c"; then
    apt_install "$c" || fail "$c missing — install it and re-run"
  fi
  ok "$c"
done
if ! have jq; then apt_install jq && ok "jq installed" || warn "jq missing (optional)"; else ok "jq"; fi
if have node; then ok "Node.js $(node --version)"; else warn "Node.js missing (some Hermes tools need it)"; fi
if ! python3 -m pip --version >/dev/null 2>&1; then
  apt_install python3-pip || python3 -m ensurepip --user >/dev/null 2>&1 || fail "pip unavailable"
fi
ok "pip $(python3 -m pip --version 2>/dev/null | awk '{print $2}')"

# --- 2/7 Hermes agent (installed FIRST, only if missing) ----------------------
step "2/7 Hermes agent"
export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
if have hermes; then
  ok "Hermes already installed: $(command -v hermes)"
else
  warn "Hermes not found — installing from NousResearch/hermes-agent (this can take a few minutes)"
  HERMES_INSTALL_URL="${HERMES_INSTALL_URL:-https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh}"
  if [ "$INTERACTIVE" = 1 ]; then
    curl -fsSL "$HERMES_INSTALL_URL" | bash || fail "Hermes install failed — see output above"
  else
    curl -fsSL "$HERMES_INSTALL_URL" | bash -s -- --non-interactive \
      || fail "Hermes install failed — see output above and ~/.hermes/logs/install.log"
  fi
  export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
  have hermes || fail "installer finished but 'hermes' is still missing (check ~/.hermes/logs/install.log)"
  ok "Hermes installed: $(command -v hermes)"
fi

# --- 3/7 Python dependencies --------------------------------------------------
step "3/7 Python dependencies"
if   python3 -m pip install -q -r requirements.txt 2>/dev/null; then :
elif python3 -m pip install -q --user -r requirements.txt 2>/dev/null; then :
elif python3 -m pip install -q --user --break-system-packages -r requirements.txt 2>/dev/null; then :
else fail "pip install -r requirements.txt failed"; fi
ok "requirements installed"

# --- 4/7 browser --------------------------------------------------------------
step "4/7 Browser (Chromium via Playwright)"
if have apt-get && { [ -z "$SUDO" ] || $SUDO -n true >/dev/null 2>&1; }; then
  python3 -m playwright install-deps chromium >/dev/null 2>&1 || true
fi
python3 -m playwright install chromium >/dev/null || fail "Chromium install failed"
python3 - <<'PY' || fail "Browser automation check failed"
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    b = p.chromium.launch(headless=True)
    pg = b.new_page(); pg.goto("about:blank"); b.close()
PY
ok "Chromium + browser automation"

# --- 5/7 config + Codespaces secrets ------------------------------------------
step "5/7 Environment + Codespaces secrets"
CFG="config/.env"
if [ -f "$CFG" ]; then ok "config/.env exists"; else cp config/config.example.env "$CFG"; ok "created config/.env from example"; fi
sed -i.bak "s#^WORK_DIR=.*#WORK_DIR='$REPO_ROOT'#" "$CFG" && rm -f "$CFG.bak"

HERMES_ENV="$HOME/.hermes/.env"
mkdir -p "$HOME/.hermes"
touch "$HERMES_ENV" "$CFG"
chmod 600 "$HERMES_ENV" "$CFG"

write_env(){ # write_env FILE KEY VALUE — idempotent, single-quoted value
  local f=$1 k=$2 v=$3 esc
  esc="${v//\'/\'\\\'\'}"
  if [ -f "$f" ]; then
    sed -i.bak "/^$k=/d" "$f" || true
    rm -f "$f.bak"
  fi
  printf "%s='%s'\n" "$k" "$esc" >> "$f"
}
save_secret(){ # save_secret KEY VALUE — project config + Hermes CLI config
  write_env "$CFG" "$1" "$2"
  write_env "$HERMES_ENV" "$1" "$2"
  [ "$1" = GEMINI_API_KEY ] && write_env "$HERMES_ENV" GOOGLE_API_KEY "$2"
}

# env var -> canonical key (aliases map onto the canonical name)
DETECT="
GOOGLE_API_KEY:GEMINI_API_KEY
GEMINI_API_KEY:GEMINI_API_KEY
OPENROUTER_API_KEY:OPENROUTER_API_KEY
NVIDIA_API_KEY:NVIDIA_NIM_API_KEY
NIM_API_KEY:NVIDIA_NIM_API_KEY
NVIDIA_NIM_API_KEY:NVIDIA_NIM_API_KEY
OPENAI_API_KEY:OPENAI_API_KEY
ANTHROPIC_API_KEY:ANTHROPIC_API_KEY
ZHIPU_API_KEY:GLM_API_KEY
GLM_API_KEY:GLM_API_KEY
CUSTOM_BASE_URL:CUSTOM_BASE_URL
CUSTOM_API_KEY:CUSTOM_API_KEY
AI_API_KEY:AI_API_KEY
WEBSITE_CREDENTIALS:WEBSITE_CREDENTIALS
TELEGRAM_BOT_TOKEN:TELEGRAM_BOT_TOKEN
TELEGRAM_CHAT_ID:TELEGRAM_CHAT_ID
TARGET_URL:TARGET_URL
ALLOWED_DOMAINS:ALLOWED_DOMAINS
"
FOUND=0
while read -r pair; do
  [ -n "$pair" ] || continue
  src="${pair%%:*}"; dst="${pair##*:}"
  v="${!src:-}"
  [ -n "$v" ] || continue
  save_secret "$dst" "$v"
  ok "$dst detected (Codespaces secret / environment) -> config/.env + ~/.hermes/.env"
  FOUND=1
done <<< "$DETECT"
if [ "$FOUND" = 0 ]; then
  warn "no secrets detected. Add them in GitHub: repo -> Settings -> Secrets and"
  warn "variables -> Codespaces (GEMINI_API_KEY, OPENROUTER_API_KEY, NVIDIA_NIM_API_KEY,"
  warn "TELEGRAM_BOT_TOKEN, ...) then re-run 'bash bootstrap.sh' — or use the menu below."
fi

# --- 5b interactive key menu (only on a TTY) ----------------------------------
if [ "$INTERACTIVE" = 1 ]; then
  step "Add / update API keys (optional)"
  cat <<'MENU'
Detected keys are shown above. You can add or replace one now (input is hidden).
  1) Gemini        GEMINI_API_KEY       aistudio.google.com/apikey
  2) OpenRouter    OPENROUTER_API_KEY   openrouter.ai/keys
  3) NVIDIA NIM    NVIDIA_NIM_API_KEY   build.nvidia.com -> Get API Key
  4) OpenAI        OPENAI_API_KEY       platform.openai.com
  5) Anthropic     ANTHROPIC_API_KEY    console.anthropic.com
  6) GLM (Zhipu)   GLM_API_KEY          open.bigmodel.cn
  7) Custom OpenAI-compatible endpoint (base URL + key)
  8) Telegram bot  TELEGRAM_BOT_TOKEN (from @BotFather) + TELEGRAM_CHAT_ID
  9) Done / continue
MENU
  read_secret(){ # read_secret KEY LABEL
    local k=$1 label=$2 v
    if read -rsp "$label (hidden, blank = skip): " v; then :; else v=""; fi
    echo ""
    if [ -n "$v" ]; then
      save_secret "$k" "$v"
      ok "$k saved to config/.env and ~/.hermes/.env"
    else
      warn "$k skipped (empty input)"
    fi
  }
  while true; do
    printf 'Choice [9]: '
    read -r ch || break
    ch="${ch:-9}"
    case "$ch" in
      1) read_secret GEMINI_API_KEY "Gemini API key" ;;
      2) read_secret OPENROUTER_API_KEY "OpenRouter API key" ;;
      3) read_secret NVIDIA_NIM_API_KEY "NVIDIA NIM API key" ;;
      4) read_secret OPENAI_API_KEY "OpenAI API key" ;;
      5) read_secret ANTHROPIC_API_KEY "Anthropic API key" ;;
      6) read_secret GLM_API_KEY "GLM API key" ;;
      7) BU=""
         if read -rp "Custom base URL (OpenAI-compatible, e.g. https://host/v1): " BU && [ -n "$BU" ]; then
           write_env "$CFG" CUSTOM_BASE_URL "$BU"; write_env "$HERMES_ENV" CUSTOM_BASE_URL "$BU"
           read_secret CUSTOM_API_KEY "Custom endpoint API key"
           ok "custom endpoint saved"
         fi ;;
      8) read_secret TELEGRAM_BOT_TOKEN "Telegram bot token"
         TCI=""
         if read -rp "Authorized Telegram chat id(s), comma-separated (optional): " TCI && [ -n "$TCI" ]; then
           write_env "$CFG" TELEGRAM_CHAT_ID "$TCI"; write_env "$HERMES_ENV" TELEGRAM_CHAT_ID "$TCI"
           ok "TELEGRAM_CHAT_ID saved"
         fi ;;
      9|q|Q) break ;;
      *) echo "invalid choice" ;;
    esac
  done
  set -a; . "$CFG"; set +a   # pick up keys just entered
fi

# --- 6/7 AI provider selection -------------------------------------------------
step "6/7 AI provider selection"
set -a; . "$CFG"; set +a
has_key(){ case "$1" in
  google)     [ -n "${GEMINI_API_KEY:-}" ] ;;
  openrouter) [ -n "${OPENROUTER_API_KEY:-}" ] ;;
  nvidia_nim) [ -n "${NVIDIA_NIM_API_KEY:-}" ] ;;
  openai)     [ -n "${OPENAI_API_KEY:-}${AI_API_KEY:-}" ] ;;
  anthropic)  [ -n "${ANTHROPIC_API_KEY:-}${AI_API_KEY:-}" ] ;;
  glm)        [ -n "${GLM_API_KEY:-}${AI_API_KEY:-}" ] ;;
  custom)     [ -n "${CUSTOM_API_KEY:-}${AI_API_KEY:-}" ] && [ -n "${CUSTOM_BASE_URL:-}" ] ;;
  *) return 1 ;;
esac }
DEFAULT_MODEL(){ case "$1" in
  google) echo "gemini-3-flash-preview" ;;
  openrouter) echo "google/gemini-3-flash-preview" ;;
  nvidia_nim) echo "meta/llama-3.3-70b-instruct" ;;
  openai) echo "gpt-4o-mini" ;;
  anthropic) echo "claude-sonnet-4-5" ;;
  glm) echo "glm-4.7" ;;
  *) echo "" ;;
esac }
ORDER="google openrouter nvidia_nim openai anthropic glm custom"

CUR="${MODEL_PROVIDER:-google}"
if has_key "$CUR"; then
  ok "provider '$CUR' has a key (MODEL_NAME=${MODEL_NAME:-<default>})"
else
  PICK=""; FALL=""
  for p in $ORDER; do
    has_key "$p" || continue
    if [ -z "$PICK" ]; then PICK="$p"; else FALL="$p"; break; fi
  done
  if [ -n "$PICK" ]; then
    warn "configured provider '$CUR' has no key — switching to '$PICK'"
    sed -i.bak "s#^MODEL_PROVIDER=.*#MODEL_PROVIDER=$PICK#" "$CFG" && rm -f "$CFG.bak"
    sed -i.bak "s#^MODEL_NAME=.*#MODEL_NAME=$(DEFAULT_MODEL "$PICK")#" "$CFG" && rm -f "$CFG.bak"
    if [ -n "$FALL" ]; then
      sed -i.bak "s#^FALLBACK_PROVIDER=.*#FALLBACK_PROVIDER=$FALL#" "$CFG" && rm -f "$CFG.bak"
      sed -i.bak "s#^FALLBACK_MODEL=.*#FALLBACK_MODEL=$(DEFAULT_MODEL "$FALL")#" "$CFG" && rm -f "$CFG.bak"
    fi
    set -a; . "$CFG"; set +a
    ok "provider: $PICK${FALL:+ (fallback: $FALL)}"
  else
    warn "no AI provider key found yet — services will wait until one is added"
  fi
fi

# --- 7/7 validation ------------------------------------------------------------
step "7/7 Validation"
export PYTHONPATH="$REPO_ROOT/src"
chmod +x scripts/*.sh 2>/dev/null || true

echo ""
echo "=================================="
echo " Hermes Codespace — Setup Summary"
echo "=================================="
ok "Python $(python3 --version 2>/dev/null | cut -d' ' -f2)"
if have node; then ok "Node.js $(node --version)"; else warn "Node.js missing"; fi
have hermes && ok "Hermes ($(command -v hermes))" || fail "Hermes missing"
ok "Chromium + Playwright automation"
ok "config/.env ready (secrets: config/.env + ~/.hermes/.env, both chmod 600)"

KEYS=""
for k in GEMINI_API_KEY OPENROUTER_API_KEY NVIDIA_NIM_API_KEY OPENAI_API_KEY \
         ANTHROPIC_API_KEY GLM_API_KEY CUSTOM_API_KEY AI_API_KEY; do
  [ -n "${!k:-}" ] && KEYS="$KEYS $k"
done
if [ -n "$KEYS" ]; then ok "API keys present:$KEYS"; else warn "no AI API keys yet"; fi

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then ok "Telegram bot token set"
else echo "[ -- ] TELEGRAM_BOT_TOKEN not set (Telegram control is optional)"; fi
if [ -n "${TELEGRAM_CHAT_ID:-}" ]; then ok "TELEGRAM_CHAT_ID set (${TELEGRAM_CHAT_ID})"
else warn "TELEGRAM_CHAT_ID not set — the bot will only reveal chat ids via /start"; fi

if python3 -m configuration.llm --check; then
  ok "AI provider reachable: ${MODEL_PROVIDER:-?} / ${MODEL_NAME:-default}"
else
  warn "provider probe failed — fix the key/model/network later and re-run 'bash bootstrap.sh'"
fi

echo ""
echo "All set. Services start automatically whenever this Codespace/VM starts"
echo "(scripts/auto-start.sh -> no commands needed)."
if [ "$LAUNCH" = 1 ]; then
  bash scripts/start-hermes.sh start || warn "services failed to start (see messages above)"
elif [ "$INTERACTIVE" = 1 ]; then
  ans=""
  if read -rp "Start Hermes services now? [Y/n]: " ans; then :; else ans="y"; fi
  case "${ans:-y}" in
    [nN]*) echo "Skipped. Start later with: scripts/start-hermes.sh" ;;
    *) bash scripts/start-hermes.sh start || warn "services failed to start (see messages above)" ;;
  esac
fi
