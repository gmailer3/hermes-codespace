# Hermes Codespace

Reproducible GitHub Codespace for running the NousResearch Hermes Agent with
browser automation against **authorized** websites. See `PRD.md` for full
requirements.

**Everything is automatic — zero manual steps, zero questions.** When the
Codespace VM starts, `scripts/auto-start.sh` runs `bootstrap.sh`, which checks
whether Hermes is installed (installs it if not), installs Python deps +
Chromium, detects your secrets (NVIDIA API key, Telegram bot token + chat id),
auto-configures the model (**NVIDIA NIM / GLM-5.3**), and launches the task
runner + Telegram bot. There are **no setup menus and nothing is ever asked** —
you never run a command.

## Quick start (zero commands)

1. Push this repo to GitHub.
2. **Repo → Settings → Secrets and variables → Codespaces** — add the secrets
   you want (names must match exactly). For the standard setup only the first
   three are needed:

   | Secret | What it is | Where to get it |
   |---|---|---|
   | `NVIDIA_NIM_API_KEY` | **Primary AI — NVIDIA NIM, auto-configures GLM-5.3** (`https://integrate.api.nvidia.com/v1`, model `z-ai/glm-5.3`). Aliases `NVIDIA_API_KEY` / `NIM_API_KEY` are also detected. | build.nvidia.com → Get API Key |
   | `TELEGRAM_BOT_TOKEN` | Enables the Telegram control bot — taken straight from secrets, **no setup questions** | @BotFather |
   | `TELEGRAM_CHAT_ID` | Chat id(s) allowed to command the bot (alias `TELEGRAM_CLIENT_ID` also works) | send `/start` to your bot once |
   | `GEMINI_API_KEY` | optional fallback provider (Google Gemini) | aistudio.google.com/apikey |
   | `OPENROUTER_API_KEY` | optional fallback provider | openrouter.ai/keys |
   | `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `GLM_API_KEY` | optional providers | platform.openai.com / console.anthropic.com / open.bigmodel.cn |
   | `CUSTOM_BASE_URL` + `CUSTOM_API_KEY` | any other OpenAI-compatible API | your provider |
   | `AI_API_KEY` | generic fallback key for openai/anthropic/glm/custom | your provider |
   | `WEBSITE_CREDENTIALS` | credentials for the authorized target site (JSON) | yours |

3. **Code → Codespaces → Create codespace.** Done. Setup runs on creation
   (`postCreateCommand`), and **every** VM start re-checks Hermes, re-detects
   secrets, re-configures the model and auto-launches the runner + Telegram bot
   (`postStartCommand`). Secrets added on GitHub later are picked up
   automatically on the next start — nothing to type, ever.

## What happens on every VM boot

```text
Codespace start
  └─ scripts/auto-start.sh          (devcontainer postStartCommand)
       ├─ bash bootstrap.sh --non-interactive   (EVERY start, idempotent)
       │    ├─ Hermes installed?  no → install it (auto-retried each start)
       │    ├─ Python deps + Chromium present?  no → install
       │    ├─ detect Codespaces secrets → config/.env + ~/.hermes/.env (chmod 600)
       │    ├─ auto-configure model: NVIDIA NIM + z-ai/glm-5.3 (top priority;
       │    │   first provider with a key wins, second becomes fallback)
       │    └─ Telegram configured from secrets only — never asked
       └─ scripts/start-hermes.sh start
            ├─ task runner     (src/task_manager/runner.py, background)
            └─ Telegram bot   (src/telegram_bot/bot.py, if TELEGRAM_BOT_TOKEN set)
```

Service control: `scripts/start-hermes.sh [start|stop|status|restart]`.
Startup transcript: `logs/autostart.log`. Health: `bash scripts/health-check.sh`.

## Model providers

Active provider = `MODEL_PROVIDER` in `config/.env`; `FALLBACK_PROVIDER` is
used automatically if the primary fails. `bootstrap.sh` picks them on every
start from the keys present — **NVIDIA NIM has top priority and ships as the
default with `z-ai/glm-5.3`**. No model setup step exists; the standard
OpenAI-compatible variables (`OPENAI_BASE_URL`, `OPENAI_API_KEY`, `MODEL_NAME`)
are also written to `~/.hermes/.env`, so the Hermes CLI's own model setup is
skipped entirely too.

| Provider id | Key env var(s) | Example `MODEL_NAME` |
|---|---|---|
| `nvidia_nim` | `NVIDIA_NIM_API_KEY` (aliases `NVIDIA_API_KEY`, `NIM_API_KEY`) | `z-ai/glm-5.3` (default), `meta/llama-3.3-70b-instruct` |
| `google` | `GEMINI_API_KEY` | `gemini-3-flash-preview` |
| `openrouter` | `OPENROUTER_API_KEY` | `google/gemini-3-flash-preview`, `anthropic/claude-sonnet-4.5` |
| `openai` | `OPENAI_API_KEY` / `AI_API_KEY` | `gpt-4o-mini` |
| `anthropic` | `ANTHROPIC_API_KEY` / `AI_API_KEY` | `claude-sonnet-4-5` |
| `glm` | `GLM_API_KEY` / `AI_API_KEY` | `glm-4.7` |
| `custom` | `CUSTOM_API_KEY` + `CUSTOM_BASE_URL` | any OpenAI-compatible model |

Test the active provider: `PYTHONPATH=src python -m configuration.llm --check`

## Telegram control bot

Runs automatically next to the task runner when the `TELEGRAM_BOT_TOKEN`
secret exists — there is **no Telegram setup option to answer**; both the
token and the authorized chat id come from Codespaces secrets.

- **Auth:** only chats in `TELEGRAM_CHAT_ID` may send commands. If unset, the
  bot answers `/start` with your chat id — add that id as a secret and restart
  the Codespace (picked up automatically).
- Commands: `/start` `/help` `/status` `/health` `/tasks`
  `/run <task_id>` `/stop <task_id>` `/logs <task_id> [lines]` (`/logs runner`).
- Notifications: task started / completed / failed / **human action required**
  are pushed to the authorized chat automatically.

## Run a task

```bash
cp my_client.json client_data/client_001.json
PYTHONPATH=src python -m task_manager.create_task client_001.json
# the auto-started runner picks it up; watch logs/task_client_001.log — or use Telegram /run
```

Then customize `TARGET_URL`, `ALLOWED_DOMAINS` and the selectors in
`src/task_manager/workflows.py` for your authorized site (test site first).

## The single command (normally never needed)

Inside the Codespace (or any clone of this repo):

```bash
bash bootstrap.sh
```

Idempotent and fully automatic: installs **Hermes first** if missing → Python
deps + Chromium → detects secrets → auto-configures the model (NVIDIA/GLM-5.3
first) and Telegram → validates and prints a summary. Add `--launch` to also
start the services immediately (automatic when run on an interactive terminal).

On any Linux VM without the repo (replace `USER/REPO` with yours):

```bash
curl -fsSL https://raw.githubusercontent.com/USER/REPO/main/bootstrap.sh \
  | HERMES_CODESPACE_REPO=https://github.com/USER/REPO.git bash
```

## Scripts

- `bootstrap.sh` — the zero-touch setup (see above)
- `scripts/auto-start.sh` — VM-start hook: install-if-missing → configure → launch
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
`~/.local/bin`). If the installer moves, override `HERMES_INSTALL_URL`. A
failed install never blocks model/Telegram setup — it is retried automatically
on every VM start.
