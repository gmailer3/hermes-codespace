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

# Round 3: "!!!!" right after a screenshot (and on every turn after it)
Cause: Kimi K3 is a vision model, so Hermes fed browser screenshots to it as
an image INSIDE a tool result. NIM's Kimi handles images in user messages
(NVIDIA's own example) but breaks on images in tool results -> "!!!!".
The screenshot stays in the session history, so every later turn re-sends it
and breaks too (that is the 3-minute wait + second "!!!!").
Fix (configure-hermes.py, applied automatically):
  model.supports_vision: false        main model never gets raw pixels
  agent.image_input_mode: text        same for photos you send on Telegram
  auxiliary.vision: nvidia / moonshotai/kimi-k3   a separate plain vision call
                                      describes the screenshot in text
The screenshot file is still sent to you as a photo (MEDIA:).
Overrides: HERMES_IMAGE_MODE, HERMES_VISION_MODEL, HERMES_SUPPORTS_VISION.
After updating: run `bash bootstrap.sh && bash scripts/start-hermes.sh restart`
(or restart the codespace), then send /new in Telegram to drop the poisoned chat.

# Round 4: "!!!!" on browsing tasks without screenshots (YouTube home page)
- codespace-guard now caps browser/web tool results at 12k chars
  (CODESPACE_GUARD_MAX_TOOL_CHARS) and strips invisible unicode. The YouTube
  feed snapshot is 50-150k chars of video cards: the long noisy context where
  NIM-hosted Kimi degenerates. Titles come first, so they survive the cap.
- When a garbage reply happens, ~/.hermes/logs/codespace-guard.log now records
  the request that caused it (message count, size, images, last tools, reasoning).
- scripts/nim-diagnose.py: hits NIM directly with 6 request shapes and reports
  which one returns "!!!!" (plain / reasoning / tools + page 12k / 90k).

# Round 5: GLM 5.3 is the default (Kimi K3 was the source of the "!!!!")
- Hermes + task runner default to z-ai/glm-5.3 on NVIDIA NIM.
- Configs this repo wrote with Kimi are switched to GLM automatically; a model
  you picked yourself with `hermes model` is still kept.
- Override any time: HERMES_MODEL / HERMES_PROVIDER secrets, or `hermes model`.

# Round 6: configure ONCE, never wipe your Hermes setup on restart
- bootstrap.sh configures Hermes on the FIRST start only (marker
  ~/.hermes/.codespace-setup-done). Later starts: install Hermes/deps only if
  missing, then start services. No secrets re-copied, no model/plugin/Telegram
  changes. Re-apply on purpose: `bash bootstrap.sh --reconfigure`.
- ~/.hermes (config, .env, memories, sessions, skills) now lives on the
  persistent disk /workspaces/.hermes-home; ~/.hermes is a link. A Codespace
  rebuild/recovery recreates the home folder, that used to erase Hermes' memory.
- Hermes install detected by its install folder too, so it is never
  reinstalled just because the launcher link vanished.
- NEW ~/.hermes/on-start.d/*.sh: run on every start before the services.
  Codespaces have no systemd and kill all background processes on stop, so
  things like ControlD (ctrld) or /etc/resolv.conf edits must be re-applied.
  The codespace-guard plugin tells Hermes to save such a script itself
  whenever you ask it for DNS/daemon/system changes.
- Fixed: plugin copy aborted the whole setup if a __pycache__ folder existed.
