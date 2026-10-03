# Changes (round 2): NIM/Kimi K3 really default, Telegram fixes, screenshots

## Why Hermes still opened on OpenRouter
The previous fix wrote `model.provider: custom` with `api_key: "${NVIDIA_NIM_API_KEY}"`.
Hermes has a NATIVE NVIDIA provider that reads `NVIDIA_API_KEY`; with the custom
variant the key depended on `${}` expansion at load time, so Hermes could see a
provider "without credentials" and drop to its OpenRouter default / setup wizard.
Also, if Hermes normalised that block, the old "you changed it" check froze the
broken config forever.

## Fixes
- scripts/configure-hermes.py now writes the native provider:
  `model: {provider: nvidia, default: moonshotai/kimi-k3, base_url: https://integrate.api.nvidia.com/v1}`
  + `auxiliary.{vision,web_extract,compression}.provider: main` (side tasks no
  longer fall back to OpenRouter/Gemini). Takes over empty / `auto` / old-repo
  configs, keeps a model YOU picked with `hermes model`. Tested 8 scenarios.
- bootstrap.sh mirrors the NIM key into ~/.hermes/.env as NVIDIA_API_KEY.
- Still configurable: secrets HERMES_PROVIDER / HERMES_MODEL (e.g. openrouter),
  HERMES_FALLBACK_PROVIDER/MODEL, HERMES_FORCE_MODEL=1 to reset.

## Telegram
- Bug: the first Codespace terminal opens while setup is still running; the
  terminal hook bailed out, so Hermes never auto-launched. It now streams the
  setup log, waits, then launches Hermes.
- Gateway now restarts itself when ~/.hermes/config.yaml/.env change (it used
  to keep running with the old model).
- "!!!!!!!!" replies: that is the hosted model emitting one garbage token on
  repeat (serving-side glitch on NVIDIA's hosted endpoints, seen with GLM/Kimi),
  not a Telegram bug. New Hermes plugin hermes-plugins/codespace-guard replaces
  such replies with a clear "resend / /retry" notice and logs them to
  ~/.hermes/logs/codespace-guard.log. Installed + enabled automatically.

## Screenshots to Telegram
One bot is enough. Hermes' browser_vision saves a screenshot and the reply
`MEDIA:/path.png` is uploaded by the same gateway as a photo. bootstrap now
installs the browser tools (`hermes pm install agent-browser`) and the plugin
nudges the model to send MEDIA: when you ask for a screenshot.
You only need a 2nd bot if you also want the old task "control" bot running
at the same time (one token = one poller, otherwise Telegram 409).
