# Hermes Codespace

Reproducible GitHub Codespace for running the NousResearch Hermes Agent with
browser automation against **authorized** websites. See `PRD.md` for full
requirements.

**Everything is automatic.** When the Codespace is created, `bootstrap.sh`
installs Hermes (first, if missing), dependencies, Chromium, and pulls your
API keys / Telegram token from Codespaces secrets. On **every** VM start,
`scripts/auto-start.sh` runs `bootstrap.sh` again — it is idempotent (only
installs what is missing) and re-detects your secrets, so API keys added on
GitHub after creation are picked up automatically — then it launches the
services. **You never need to run a command on VM start.**

## Quick start (zero commands)

1. Push this repo to GitHub.
2. **Repo → Settings → Secrets and variables → Codespaces** — add the secrets
   you want (names must match exactly):

   | Secret | What it is | Where to get it |
   |---|---|---|
   | `GEMINI_API_KEY` | Google Gemini | aistudio.google.com/apikey |
   | `OPENROUTER_API_KEY` | OpenRouter | openrouter.ai/keys |
   | `NVIDIA_NIM_API_KEY` | NVIDIA NIM | build.nvidia.com → Get API Key |
   | `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `GLM_API_KEY` | optional providers | platform.openai.com / console.anthropic.com / open.bigmodel.cn |
   | `CUSTOM_BASE_URL` + `CUSTOM_API_KEY` | any other OpenAI-compatible API | your provider |
   | `AI_API_KEY` | generic fallback key for openai/anthropic/glm/custom | your provider |
   | `TELEGRAM_BOT_TOKEN` | enables the Telegram control bot | @BotFather |
   | `TELEGRAM_CHAT_ID` | chat id(s) allowed to command the bot | send `/start` to your bot once |
   | `WEBSITE_CREDENTIALS` | credentials for the authorized target site (JSON) | yours |

3. **Code → Codespaces → Create codespace.** Setup runs automatically
   (`postCreateCommand`), and every subsequent start auto-launches the
   runner + Telegram bot (`postStartCommand`). No commands needed.

Secrets added *after* the Codespace was created take effect after a rebuild
(`Codespaces: Rebuild Container`) — or just run the single command below.

## The single command

Inside the Codespace (or any clone of this repo):

```bash
bash bootstrap.sh
```

That one command, in order: installs **Hermes first** if it is not installed →
installs Python deps + Chromium → detects `TELEGRAM_BOT_TOKEN`, `GEMINI_API_KEY`,
`OPENROUTER_API_KEY`, `NVIDIA_NIM_API_KEY`, etc. from the Codespaces
secrets/environment → writes them into `config/.env` and `~/.hermes/.env`
(chmod 600, never printed) → shows a menu to **add or replace API keys**
(Gemini, OpenRouter, NVIDIA NIM, OpenAI, Anthropic, GLM, custom endpoint,
Telegram) → auto-selects the active provider from the keys present → validates
everything and offers to start the services.

On any Linux VM without the repo (replace `USER/REPO` with yours):

```bash
curl -fsSL https://raw.githubusercontent.com/USER/REPO/main/bootstrap.sh \
  | HERMES_CODESPACE_REPO=https://github.com/USER/REPO.git bash
```

## What auto-starts on VM boot

```text
Codespace start
  └─ scripts/auto-start.sh          (devcontainer postStartCommand)
       ├─ bash bootstrap.sh --non-interactive  (EVERY start: installs anything
       │    missing + re-detects secrets/config; only seconds when up to date)
       └─ scripts/start-hermes.sh start
            ├─ task runner     (src/task_manager/runner.py, background)
            └─ Telegram bot   (src/telegram_bot/bot.py, if TELEGRAM_BOT_TOKEN set)
```

Service control: `scripts/start-hermes.sh [start|stop|status|restart]`.
Startup transcript: `logs/autostart.log`. Health: `bash scripts/health-check.sh`.

## Model providers

Active provider = `MODEL_PROVIDER` in `config/.env`; `FALLBACK_PROVIDER` is
used automatically if the primary fails. `bootstrap.sh` picks the first
provider that has a key — NVIDIA NIM has top priority and ships as the
default (`z-ai/glm-5.3`):

| Provider id | Key env var(s) | Example `MODEL_NAME` |
|---|---|---|
| `nvidia_nim` | `NVIDIA_NIM_API_KEY` | `z-ai/glm-5.3` (default), `meta/llama-3.3-70b-instruct` |
| `google` | `GEMINI_API_KEY` | `gemini-3-flash-preview` |
| `openrouter` | `OPENROUTER_API_KEY` | `google/gemini-3-flash-preview`, `anthropic/claude-sonnet-4.5` |
| `openai` | `OPENAI_API_KEY` / `AI_API_KEY` | `gpt-4o-mini` |
| `anthropic` | `ANTHROPIC_API_KEY` / `AI_API_KEY` | `claude-sonnet-4-5` |
| `glm` | `GLM_API_KEY` / `AI_API_KEY` | `glm-4.7` |
| `custom` | `CUSTOM_API_KEY` + `CUSTOM_BASE_URL` | any OpenAI-compatible model |

Test the active provider: `PYTHONPATH=src python -m configuration.llm --check`

## Telegram control bot

Runs automatically next to the task runner when `TELEGRAM_BOT_TOKEN` is set.

- **Auth:** only chats in `TELEGRAM_CHAT_ID` may send commands. If unset, the
  bot answers `/start` with your chat id and instructions — add that id as a
  secret (or via `bash bootstrap.sh` menu) and restart.
- Commands: `/start` `/help` `/status` `/health` `/tasks`
  `/run <task_id>` `/stop <task_id>` `/logs <task_id> [lines]` (`/logs runner`).
- Notifications: task started / completed / failed / **human action required**
  are pushed to the authorized chat automatically.

## Run a task

```bash
cp my_client.json client_data/client_001.json
PYTHONPATH=src python -m task_manager.create_task client_001.json
# the auto-started runner picks it up; watch logs/task_client_001.log
```

Then customize `TARGET_URL`, `ALLOWED_DOMAINS` and the selectors in
`src/task_manager/workflows.py` for your authorized site (test site first).

## Scripts

- `bootstrap.sh` — the one-command setup (see above)
- `scripts/auto-start.sh` — VM-start hook: install-if-missing → launch
- `scripts/start-hermes.sh` — start/stop/status/restart the background services
- `scripts/health-check.sh` — checks Hermes, browser, keys, provider, network
- `scripts/cleanup.sh [days]` — deletes completed client data + old logs/screenshots

## Guardrails

- Domain allowlist (`ALLOWED_DOMAINS`), anything else is refused.
- CAPTCHA/verification → task goes to `WAITING_FOR_USER` and the bot notifies
  you; never bypassed.
- Max 3 retries, exponential backoff capped at 60s.
- Secrets/emails/phones redacted from logs *and* Telegram messages. Client
  data, tasks, logs, screenshots, `config/.env` and `~/.hermes/.env` never
  reach Git.

## Hermes install

`bootstrap.sh` uses the upstream installer
(`NousResearch/hermes-agent/scripts/install.sh`, publishes `hermes` to
`~/.local/bin`). If the installer moves, override `HERMES_INSTALL_URL`.
