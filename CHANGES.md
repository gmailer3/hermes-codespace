# Changes: NIM/Kimi K3 default + Telegram fixes

## Root cause of "Hermes launches on OpenRouter"
bootstrap.sh only exported OPENAI_BASE_URL / OPENAI_API_KEY into ~/.hermes/.env.
Hermes ignores OPENAI_BASE_URL except for its `openai-api` provider and reads the
model ONLY from ~/.hermes/config.yaml, so with no `model:` block it fell back to
OpenRouter. (Putting the NVIDIA key in OPENAI_API_KEY also muddied its auto-detect.)

## Fixes
- NEW scripts/configure-hermes.py: writes model.provider=custom,
  base_url=https://integrate.api.nvidia.com/v1, default=moonshotai/kimi-k3,
  api_key=${NVIDIA_NIM_API_KEY} into ~/.hermes/config.yaml (other settings untouched).
  Respects later manual changes; overridable via HERMES_* env/secrets.
- bootstrap.sh: default model z-ai/glm-5.3 -> moonshotai/kimi-k3 (runner too);
  old configs auto-migrated; stale OPENAI_* lines removed from ~/.hermes/.env;
  HERMES_* and TELEGRAM_MODE secrets detected.
- config.example.env: OpenRouter is no longer the default fallback.

## Telegram bugs found
1. bot.py line 178: backslash inside an f-string expression (`'\u2022'`) is a
   SyntaxError on Python 3.11 (the devcontainer image), so the bot crashed on
   start every time. Fixed.
2. The bot never talked to Hermes: plain messages got "Unknown command". Now the
   default is Hermes' own gateway (`hermes gateway run`) = real chat with Hermes.
3. Hermes gateway needs TELEGRAM_ALLOWED_USERS, which was never written, so it
   would have refused you / used pairing. Now derived from TELEGRAM_CHAT_ID.
4. Running both bots on one token = Telegram 409 conflict. start-hermes.sh now
   runs exactly one (TELEGRAM_MODE=hermes|control|off).

## Launch in the VS Code terminal
terminal-attach.sh / terminal-hook.sh now open `hermes` in the first terminal
after each boot (HERMES_NO_AUTOCHAT=1 to opt out).

## Note on reasoning_effort
Your NIM snippet uses reasoning_effort "max"; Hermes has its own levels, so it's
set to agent.reasoning_effort=high (change with HERMES_REASONING_EFFORT).
