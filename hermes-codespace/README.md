# Hermes Codespace

Reproducible GitHub Codespace for running NousResearch Hermes Agent with browser automation
against **authorized** websites. See `PRD.md` for full requirements.

## Quick start
1. Push this repo to GitHub.
2. Repo → Settings → Secrets and variables → **Codespaces** → add `GEMINI_API_KEY` and/or `OPENROUTER_API_KEY` (plus `WEBSITE_CREDENTIALS`, `TELEGRAM_BOT_TOKEN` if used).
3. Code → Codespaces → **Create codespace**. `setup.sh` runs automatically.
4. Edit `config/.env`: set `MODEL_PROVIDER`, `MODEL_NAME`, `TARGET_URL`, `ALLOWED_DOMAINS`.
5. Edit selectors in `src/task_manager/workflows.py` for your site (use a test site first).
6. Start: `scripts/start-hermes.sh`

## Model providers
| Provider | Secret | Get a key | Example `MODEL_NAME` |
|---|---|---|---|
| Gemini (`google`) | `GEMINI_API_KEY` | aistudio.google.com/apikey | `gemini-3-flash-preview` |
| OpenRouter (`openrouter`) | `OPENROUTER_API_KEY` | openrouter.ai/keys | `google/gemini-3-flash-preview`, `anthropic/claude-sonnet-4.5` |

Set `MODEL_PROVIDER` + `MODEL_NAME` for the primary, `FALLBACK_PROVIDER` + `FALLBACK_MODEL` for automatic failover.
Test both: `PYTHONPATH=src python -m configuration.llm --check`
Keys added after the Codespace was created: rebuild the container or re-run `.devcontainer/setup.sh`.

## Run a task
```bash
cp my_client.json client_data/client_001.json
PYTHONPATH=src python -m task_manager.create_task client_001.json
# runner picks it up; watch logs/task_client_001.log
```

## Scripts
- `scripts/health-check.sh`: checks Hermes, browser, secrets, filesystem, network
- `scripts/cleanup.sh [days]`: deletes completed client data + old logs/screenshots

## Guardrails
- Domain allowlist (`ALLOWED_DOMAINS`), anything else is refused.
- CAPTCHA/verification → task goes to `WAITING_FOR_USER`, never bypassed.
- Max 3 retries, exponential backoff capped at 60s.
- Secrets/emails/phones redacted from logs. Client data, tasks, logs, screenshots are gitignored.

## Hermes install
`setup.sh` uses the upstream installer by default. If it moves, set `HERMES_INSTALL_CMD`.
