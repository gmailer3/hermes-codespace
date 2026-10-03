#!/usr/bin/env bash
# =============================================================================
#  Hermes Codespace — ZERO-TOUCH BOOTSTRAP
#
#  Fully automatic: no prompts, no menus, no model-setup wizard, no Telegram
#  setup questions. Safe to re-run any time (idempotent). What it does:
#    1. Installs base tooling + the NousResearch Hermes agent (if missing)
#    2. Installs Python dependencies + Chromium (Playwright)
#    3. Detects API keys / Telegram credentials from GitHub Codespaces secrets
#       (injected as environment variables) and writes them to config/.env
#       (project, gitignored) and ~/.hermes/.env (Hermes CLI, chmod 600)
#    4. Auto-configures the model: NVIDIA NIM + moonshotai/kimi-k3 is the
#       default for BOTH the task runner and the Hermes CLI/gateway
#       (~/.hermes/config.yaml). OpenRouter & co. are optional extras, never
#       the default. Override later with HERMES_PROVIDER / HERMES_MODEL or
#       `hermes model` (your manual choice is kept across restarts).
#    5. Telegram is configured purely from TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID
#       secrets — never prompted for.
#    6. Prints a summary; with --launch (or on an interactive terminal) it also
#       starts the task runner + Telegram bot.
#
#  Usage (all optional — normally you never run this by hand):
#    bash bootstrap.sh                 # same as --non-interactive everywhere
#    bash bootstrap.sh --launch        # also start runner + Telegram bot
#
#  In a Codespace you never need this: devcontainer.json runs it on creation,
#  and scripts/auto-start.sh re-runs it on EVERY VM start (installs anything
#  missing, re-detects secrets) and then launches the services automatically.
#
#  On any Linux VM without the repo (replace USER/REPO with yours):
#    curl -fsSL https://raw.githubusercontent.com/USER/REPO/main/bootstrap.sh \
#      | HERMES_CODESPACE_REPO=https://github.com/USER/REPO.git bash
# =============================================================================
set -euo pipefail

NON_INTERACTIVE=0
LAUNCH=0
for a in "$@"; do
  case "$a" in
    --non-interactive|-n|--auto|-a) NON_INTERACTIVE=1 ;;   # default behaviour; kept for compatibility
    --launch|-l)                    LAUNCH=1 ;;
    -h|--help)                      if [ -f "$0" ]; then sed -n '2,30p' "$0" | sed 's/^#\{1,\} \{0,1\}//';
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

step "Hermes Codespace bootstrap (fully automatic — nothing to answer)"
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
# Non-fatal by design: the task runner itself is pure Python, so if the upstream
# installer is unreachable the model/Telegram setup below must still complete.
# The VM-start hook re-runs this script, so a failed install is retried on the
# next start automatically.
step "2/7 Hermes agent"
export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
if have hermes; then
  ok "Hermes already installed: $(command -v hermes)"
else
  warn "Hermes not found — installing from NousResearch/hermes-agent (this can take a few minutes)"
  HERMES_INSTALL_URL="${HERMES_INSTALL_URL:-https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh}"
  if curl -fsSL "$HERMES_INSTALL_URL" | bash -s -- --non-interactive; then :; else
    warn "Hermes install failed — continuing with model/Telegram setup;"
    warn "the install is retried automatically on the next VM start."
  fi
  export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
  if have hermes; then ok "Hermes installed: $(command -v hermes)"
  else warn "Hermes binary not present yet (auto-retry on next start)"; fi
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
browser_ok(){
  python3 - <<'PY'
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    b = p.chromium.launch(headless=True)
    pg = b.new_page(); pg.goto("about:blank"); b.close()
PY
}
if browser_ok >/dev/null 2>&1; then
  ok "Chromium + browser automation (already present)"
else
  if have apt-get && { [ -z "$SUDO" ] || $SUDO -n true >/dev/null 2>&1; }; then
    python3 -m playwright install-deps chromium >/dev/null 2>&1 || true
  fi
  python3 -m playwright install chromium >/dev/null || fail "Chromium install failed"
  browser_ok >/dev/null 2>&1 || fail "Browser automation check failed"
  ok "Chromium + browser automation"
fi

# --- 5/7 config + Codespaces secrets ------------------------------------------
step "5/7 Environment + Codespaces secrets (auto-detected, nothing to type)"
CFG="config/.env"
if [ -f "$CFG" ]; then ok "config/.env exists"; else cp config/config.example.env "$CFG"; ok "created config/.env from example"; fi
sed -i.bak "s#^WORK_DIR=.*#WORK_DIR='$REPO_ROOT'#" "$CFG" || true
rm -f "$CFG.bak"

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
  # note: must not end in a failing `&&` chain — this runs under `set -e`
  if [ "$1" = GEMINI_API_KEY ]; then write_env "$HERMES_ENV" GOOGLE_API_KEY "$2"; fi
  # Hermes' native NVIDIA provider reads NVIDIA_API_KEY (not NVIDIA_NIM_API_KEY)
  if [ "$1" = NVIDIA_NIM_API_KEY ]; then write_env "$HERMES_ENV" NVIDIA_API_KEY "$2"; fi
  return 0
}

# env var -> canonical key (aliases map onto the canonical name). Codespaces
# injects repository secrets as environment variables, so all of these arrive
# with ZERO configuration: the NVIDIA key, the Telegram bot token and the
# authorized chat id are picked up automatically.
DETECT="
NVIDIA_NIM_API_KEY:NVIDIA_NIM_API_KEY
NVIDIA_API_KEY:NVIDIA_NIM_API_KEY
NVIDIA_NIM_KEY:NVIDIA_NIM_API_KEY
NIM_API_KEY:NVIDIA_NIM_API_KEY
NVAPI_KEY:NVIDIA_NIM_API_KEY
GOOGLE_API_KEY:GEMINI_API_KEY
GEMINI_API_KEY:GEMINI_API_KEY
OPENROUTER_API_KEY:OPENROUTER_API_KEY
OPENAI_API_KEY:OPENAI_API_KEY
ANTHROPIC_API_KEY:ANTHROPIC_API_KEY
ZHIPU_API_KEY:GLM_API_KEY
GLM_API_KEY:GLM_API_KEY
CUSTOM_BASE_URL:CUSTOM_BASE_URL
CUSTOM_API_KEY:CUSTOM_API_KEY
AI_API_KEY:AI_API_KEY
WEBSITE_CREDENTIALS:WEBSITE_CREDENTIALS
TELEGRAM_BOT_TOKEN:TELEGRAM_BOT_TOKEN
TELEGRAM_CLIENT_ID:TELEGRAM_CHAT_ID
TELEGRAM_CHAT_ID:TELEGRAM_CHAT_ID
TELEGRAM_ALLOWED_USERS:TELEGRAM_CHAT_ID
TELEGRAM_MODE:TELEGRAM_MODE
HERMES_PROVIDER:HERMES_PROVIDER
HERMES_MODEL:HERMES_MODEL
HERMES_BASE_URL:HERMES_BASE_URL
HERMES_FALLBACK_PROVIDER:HERMES_FALLBACK_PROVIDER
HERMES_FALLBACK_MODEL:HERMES_FALLBACK_MODEL
HERMES_REASONING_EFFORT:HERMES_REASONING_EFFORT
HERMES_CONTEXT_LENGTH:HERMES_CONTEXT_LENGTH
HERMES_FORCE_MODEL:HERMES_FORCE_MODEL
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
  warn "variables -> Codespaces (NVIDIA_NIM_API_KEY, TELEGRAM_BOT_TOKEN,"
  warn "TELEGRAM_CHAT_ID, ...) — they are picked up automatically on the next start."
fi

# --- 6/7 AI provider + model (automatic — the model setup is SKIPPED) ---------
# Priority order: NVIDIA NIM (moonshotai/kimi-k3) first, then the rest. The active
# provider is the configured one if it has a key, otherwise the first provider
# in priority order that does. Model names are auto-filled; nothing is asked.
step "6/7 AI provider + model (auto-configured)"
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
  nvidia_nim) echo "moonshotai/kimi-k3" ;;
  google) echo "gemini-3-flash-preview" ;;
  openrouter) echo "google/gemini-3-flash-preview" ;;
  openai) echo "gpt-4o-mini" ;;
  anthropic) echo "claude-sonnet-4-5" ;;
  glm) echo "glm-4.7" ;;
  *) echo "" ;;
esac }
ORDER="nvidia_nim google openrouter openai anthropic glm custom"

ACTIVE=""
CUR="${MODEL_PROVIDER:-}"
# migrate configs created by older versions of this repo (old GLM default)
if [ "${MODEL_NAME:-}" = "z-ai/glm-5.3" ]; then MODEL_NAME=""; fi
if [ -n "$CUR" ] && has_key "$CUR"; then
  ACTIVE="$CUR"
else
  for p in $ORDER; do has_key "$p" && { ACTIVE="$p"; break; }; done
fi

if [ -n "$ACTIVE" ]; then
  # keep an explicitly chosen model only when the provider itself is unchanged
  if [ "$ACTIVE" = "$CUR" ] && [ -n "${MODEL_NAME:-}" ]; then MN="$MODEL_NAME"
  else MN="$(DEFAULT_MODEL "$ACTIVE")"; fi
  # fallback = next provider in priority order that also has a key
  FALL=""
  for p in $ORDER; do
    [ "$p" = "$ACTIVE" ] && continue
    has_key "$p" && { FALL="$p"; break; }
  done
  sed -i.bak "s#^MODEL_PROVIDER=.*#MODEL_PROVIDER=$ACTIVE#" "$CFG" || true; rm -f "$CFG.bak"
  sed -i.bak "s#^MODEL_NAME=.*#MODEL_NAME=$MN#" "$CFG" || true; rm -f "$CFG.bak"
  sed -i.bak "s#^FALLBACK_PROVIDER=.*#FALLBACK_PROVIDER=$FALL#" "$CFG" || true; rm -f "$CFG.bak"
  sed -i.bak "s#^FALLBACK_MODEL=.*#FALLBACK_MODEL=$(DEFAULT_MODEL "$FALL")#" "$CFG" || true; rm -f "$CFG.bak"
  write_env "$HERMES_ENV" MODEL_PROVIDER "$ACTIVE"
  write_env "$HERMES_ENV" MODEL_NAME "$MN"
  # NOTE: older versions exported OPENAI_BASE_URL/OPENAI_API_KEY here. Hermes
  # ignores those for NIM (and an OPENAI_API_KEY holding the NVIDIA key only
  # confuses its provider auto-detection), so remove any stale copies.
  for k in OPENAI_BASE_URL OPENAI_API_BASE; do
    sed -i.bak "/^$k=/d" "$HERMES_ENV" 2>/dev/null || true; rm -f "$HERMES_ENV.bak"
  done
  if ! grep -q '^OPENAI_API_KEY=' "$CFG"; then   # no real OpenAI secret -> drop the stale copy
    sed -i.bak "/^OPENAI_API_KEY=/d" "$HERMES_ENV" 2>/dev/null || true; rm -f "$HERMES_ENV.bak"
  fi
  set -a; . "$CFG"; set +a
  [ "$ACTIVE" = "$CUR" ] || warn "configured provider '${CUR:-none}' has no key — switched automatically"
  ok "active provider: $ACTIVE / ${MN:-<provider default>}${FALL:+ (fallback: $FALL / $(DEFAULT_MODEL "$FALL"))}"
  [ "$ACTIVE" = nvidia_nim ] && ok "NVIDIA NIM endpoint: https://integrate.api.nvidia.com/v1 (model $MN)"
else
  warn "no AI provider key found yet — services start once a key secret exists"
  warn "(add e.g. NVIDIA_NIM_API_KEY under repo -> Settings -> Secrets -> Codespaces)"
fi

# --- Hermes CLI/gateway model: ~/.hermes/config.yaml ----------------------------
# This is what the `hermes` command actually reads. Without it Hermes launches
# on OpenRouter, which is exactly the bug this block fixes.
# NVIDIA_API_KEY must be in this process env too (configure-hermes checks it)
[ -n "${NVIDIA_NIM_API_KEY:-}" ] && export NVIDIA_API_KEY="${NVIDIA_API_KEY:-$NVIDIA_NIM_API_KEY}"
python3 scripts/configure-hermes.py || warn "could not write ~/.hermes/config.yaml"

# --- Hermes plugin: "!!!!" guard + screenshot-to-Telegram hint -----------------
PLUG_SRC="$REPO_ROOT/hermes-plugins/codespace-guard"
PLUG_DST="$HOME/.hermes/plugins/codespace-guard"
if [ -d "$PLUG_SRC" ]; then
  mkdir -p "$PLUG_DST" && cp -f "$PLUG_SRC"/* "$PLUG_DST"/
  if have hermes; then
    if timeout 60 hermes plugins enable codespace-guard </dev/null >/dev/null 2>&1; then
      ok "Hermes plugin codespace-guard enabled (blocks '!!!!' replies, screenshot hint)"
    else
      warn "could not enable plugin codespace-guard (run: hermes plugins enable codespace-guard)"
    fi
  fi
fi

# --- Hermes browser tools (needed for screenshots sent to Telegram) -------------
if have hermes; then
  if have agent-browser || [ -f "$HOME/.hermes/.codespace-browser-ok" ]; then
    ok "Hermes browser tools present (screenshots -> Telegram photos)"
  elif timeout 900 hermes pm install agent-browser </dev/null >/dev/null 2>&1; then
    touch "$HOME/.hermes/.codespace-browser-ok"
    ok "Hermes browser tools installed (agent-browser + Chromium)"
  else
    warn "Hermes browser tools install failed (retried next start; manual: hermes pm install agent-browser)"
  fi
fi

# --- Telegram for the Hermes gateway (chat with Hermes directly) -----------------
# Hermes' own gateway reads TELEGRAM_BOT_TOKEN + TELEGRAM_ALLOWED_USERS from
# ~/.hermes/.env. For private chats the chat id == your user id.
# Negative ids are groups -> TELEGRAM_GROUP_ALLOWED_CHATS; @names are skipped
# (the gateway needs numeric ids).
if [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
  TG_USERS=""; TG_GROUPS=""
  for id in $(printf '%s' "$TELEGRAM_CHAT_ID" | tr ',' ' '); do
    case "$id" in
      -[0-9]*) TG_GROUPS="${TG_GROUPS:+$TG_GROUPS,}$id" ;;
      [0-9]*)  TG_USERS="${TG_USERS:+$TG_USERS,}$id" ;;
      *) warn "Telegram id '$id' is not numeric, Hermes gateway ignores it (send /start to @userinfobot for your id)" ;;
    esac
  done
  [ -n "$TG_USERS" ]  && write_env "$HERMES_ENV" TELEGRAM_ALLOWED_USERS "$TG_USERS"
  [ -n "$TG_GROUPS" ] && write_env "$HERMES_ENV" TELEGRAM_GROUP_ALLOWED_CHATS "$TG_GROUPS"
  ok "Telegram allow-list for Hermes: ${TG_USERS:-none}${TG_GROUPS:+ (groups: $TG_GROUPS)}"
else
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && warn "TELEGRAM_CHAT_ID not set: Hermes gateway will use DM pairing (first user to DM the bot claims it)"
fi
TELEGRAM_MODE="${TELEGRAM_MODE:-hermes}"
write_env "$CFG" TELEGRAM_MODE "$TELEGRAM_MODE"

# --- terminal hook: every new Codespace terminal shows status + self-heals -----
HOOK_LINE="[ -n \"\${PS1:-}\" ] && [ -f '$REPO_ROOT/scripts/terminal-hook.sh' ] && bash '$REPO_ROOT/scripts/terminal-hook.sh'"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -f "$rc" ] || [ "$rc" = "$HOME/.bashrc" ] || continue
  touch "$rc"
  if ! grep -q 'hermes-codespace terminal hook' "$rc" 2>/dev/null; then
    printf '\n# hermes-codespace terminal hook\n%s\n' "$HOOK_LINE" >> "$rc"
  fi
done
ok "terminal hook installed (new terminals show Hermes status)"

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
if have hermes; then ok "Hermes ($(command -v hermes))"; else warn "Hermes missing — auto-retried on next VM start"; fi
ok "Chromium + Playwright automation"
ok "config/.env ready (secrets: config/.env + ~/.hermes/.env, both chmod 600)"

KEYS=""
for k in NVIDIA_NIM_API_KEY GEMINI_API_KEY OPENROUTER_API_KEY OPENAI_API_KEY \
         ANTHROPIC_API_KEY GLM_API_KEY CUSTOM_API_KEY AI_API_KEY; do
  if [ -n "${!k:-}" ]; then KEYS="$KEYS $k"; fi
done
if [ -n "$KEYS" ]; then ok "API keys present:$KEYS"; else warn "no AI API keys yet"; fi

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then ok "Telegram bot token set (mode: ${TELEGRAM_MODE:-hermes}; hermes = chat with Hermes, control = task bot)"
else echo "[ -- ] TELEGRAM_BOT_TOKEN not set (Telegram control is optional)"; fi
if [ -n "${TELEGRAM_CHAT_ID:-}" ]; then ok "TELEGRAM_CHAT_ID set (${TELEGRAM_CHAT_ID})"
else warn "TELEGRAM_CHAT_ID not set — the bot will only reveal chat ids via /start"; fi

if [ -n "${MODEL_PROVIDER:-}" ] && python3 -m configuration.llm --check; then
  ok "AI provider reachable: ${MODEL_PROVIDER:-?} / ${MODEL_NAME:-default}"
else
  warn "provider probe failed — the key/model/network is re-checked on every VM start"
fi

echo ""
echo "All set — no manual steps. On every Codespace/VM start, scripts/auto-start.sh"
echo "re-checks Hermes, re-detects secrets, re-configures the model and launches"
echo "the task runner + Telegram bot automatically."
if [ "$LAUNCH" = 1 ] || [ "$INTERACTIVE" = 1 ]; then
  bash scripts/start-hermes.sh start || warn "services failed to start (see messages above)"
fi
