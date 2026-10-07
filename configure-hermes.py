#!/usr/bin/env python3
"""Writes the Hermes CLI/gateway model config (~/.hermes/config.yaml).

WHY: Hermes reads the model ONLY from ~/.hermes/config.yaml. With no usable
`model:` block it treats itself as "not configured" and falls back to its
OpenRouter default / setup wizard on launch.

Default written here = Hermes' NATIVE NVIDIA NIM provider:
    model:
      provider: nvidia                       # first-class provider in Hermes
      default: z-ai/glm-5.3
      base_url: https://integrate.api.nvidia.com/v1
The key is read by Hermes from NVIDIA_API_KEY in ~/.hermes/.env (bootstrap.sh
copies your Codespaces secret there). The previous version used
`provider: custom` + api_key "${NVIDIA_NIM_API_KEY}"; that relied on ${}
expansion at load time and Hermes could treat the provider as having no
credentials -> OpenRouter on first launch. Native provider = no such gap.

Stays configurable later (Codespaces secrets or config/.env):
    HERMES_PROVIDER   nvidia (default; aliases nvidia_nim/nim) | openrouter |
                      custom | anthropic | gemini | <any Hermes provider slug>
    HERMES_MODEL      default: z-ai/glm-5.3 (for nvidia)
    HERMES_BASE_URL   default: https://integrate.api.nvidia.com/v1 (for nvidia)
    HERMES_FALLBACK_PROVIDER / HERMES_FALLBACK_MODEL   optional fallback
    HERMES_REASONING_EFFORT   default: high
    HERMES_CONTEXT_LENGTH     default: 131072
    HERMES_IMAGE_MODE         default: text (images described, not embedded)
    HERMES_VISION_MODEL       default: same as HERMES_MODEL (screenshot describer)
    HERMES_SUPPORTS_VISION    default: false (see comment in desired())
Or just run `hermes model` / `/model` yourself: a manual change is detected
and kept across VM restarts. HERMES_FORCE_MODEL=1 resets to the default.
"""
import json, os, sys
from pathlib import Path
import yaml

HOME = Path(os.getenv("HERMES_HOME", Path.home() / ".hermes"))
CFG = HOME / "config.yaml"
STAMP = HOME / ".codespace-model.json"   # what WE wrote last time

NIM_URL = "https://integrate.api.nvidia.com/v1"
NIM_HOST = "integrate.api.nvidia.com"
DEFAULT_MODEL = "z-ai/glm-5.3"
# models this script has written as default before (safe to replace)
OUR_MODELS = {DEFAULT_MODEL, "moonshotai/kimi-k3"}
NVIDIA_ALIASES = ("nvidia", "nvidia_nim", "nvidia-nim", "nim", "build-nvidia")
# provider -> env var that must hold its key before we switch to it
KEY_ENV = {"nvidia": "NVIDIA_API_KEY", "custom": "CUSTOM_API_KEY",
           "openrouter": "OPENROUTER_API_KEY"}
AUX_TASKS = ("vision", "web_extract", "compression")


def env(k, d=""):
    return (os.getenv(k) or d).strip()


def desired():
    prov = env("HERMES_PROVIDER", "nvidia").lower()
    if prov in NVIDIA_ALIASES:
        prov = "nvidia"
    model = env("HERMES_MODEL", DEFAULT_MODEL if prov == "nvidia" else "")
    block = {"provider": prov, "default": model}
    if prov == "nvidia":
        block.update(base_url=env("HERMES_BASE_URL", NIM_URL),
                     api_mode="chat_completions",
                     context_length=int(env("HERMES_CONTEXT_LENGTH", "131072")),
                     # NIM's Kimi accepts images in USER messages (your curl
                     # works) but breaks on images inside TOOL results, which
                     # is how Hermes feeds browser screenshots to a "vision"
                     # main model -> "!!!!!!!!" on that turn and every turn
                     # after (the image stays in history). So the main model
                     # is declared text-only; screenshots are described by a
                     # separate plain vision call (auxiliary.vision below).
                     supports_vision=env("HERMES_SUPPORTS_VISION", "false").lower()
                                     in ("1", "true", "yes"))
    elif prov == "custom":
        block.update(base_url=env("HERMES_BASE_URL", env("CUSTOM_BASE_URL")),
                     key_env="CUSTOM_API_KEY", api_mode="chat_completions")
    elif env("HERMES_BASE_URL"):
        block["base_url"] = env("HERMES_BASE_URL")
    return prov, block


def ident(m):
    if isinstance(m, dict):
        return (str(m.get("provider") or ""), str(m.get("default") or m.get("model") or ""),
                str(m.get("base_url") or ""))
    return ("", str(m or ""), "")


def unconfigured(m):
    """Empty sentinel / 'auto' / no model: Hermes would pick OpenRouter itself."""
    p, d, _ = ident(m)
    return not d or p in ("", "auto")


def written_by_us(m, last):
    """Our block, possibly normalised/migrated by Hermes (old custom variant too)."""
    p, d, u = ident(m)
    if last is not None and (p, d, u) == ident(last):
        return True
    return d in OUR_MODELS and (p in ("nvidia", "custom") or NIM_HOST in u)


def main():
    HOME.mkdir(parents=True, exist_ok=True)
    data = {}
    if CFG.exists():
        try:
            data = yaml.safe_load(CFG.read_text()) or {}
        except Exception as e:
            print(f"[WARN] {CFG} unreadable ({e}); leaving it alone")
            return 0
    if not isinstance(data, dict):
        data = {}
    cur = data.get("model")
    try:
        last = json.loads(STAMP.read_text()) if STAMP.exists() else None
    except Exception:
        last = None
    force = env("HERMES_FORCE_MODEL").lower() in ("1", "true", "yes")
    explicit = bool(env("HERMES_PROVIDER") or env("HERMES_MODEL"))
    prov, block = desired()

    take_over = (force or last is None or unconfigured(cur) or written_by_us(cur, last)
                 or (explicit and ident(block)[:2] != ident(cur)[:2]))
    if not take_over:
        p, d, _ = ident(cur)
        print(f"[ OK ] Hermes model kept (you changed it): {p or '?'} / {d}"
              "  (HERMES_FORCE_MODEL=1 resets to NVIDIA NIM / glm-5.3)")
        return 0

    need = KEY_ENV.get(prov)
    if need and not os.getenv(need):
        print(f"[WARN] {need} not set: Hermes model not configured yet "
              "(add the Codespaces secret, it is picked up on the next start)")
        return 0
    if not block.get("default"):
        print("[WARN] HERMES_MODEL empty: Hermes model not configured")
        return 0

    data["model"] = block
    agent = data.setdefault("agent", {})
    if isinstance(agent, dict):
        agent["reasoning_effort"] = env("HERMES_REASONING_EFFORT", "high")

    # images: never embed pixels in the main (tool-calling) request on NIM
    if isinstance(agent, dict):
        agent["image_input_mode"] = env("HERMES_IMAGE_MODE",
                                        "text" if prov == "nvidia" else "auto")

    # side tasks (page extraction, compression) follow the main model instead
    # of Hermes' OpenRouter/Gemini-Flash fallback
    aux = data.get("auxiliary")
    if not isinstance(aux, dict):
        aux = data["auxiliary"] = {}
    for t in AUX_TASKS:
        a = aux.get(t)
        if not isinstance(a, dict):
            a = aux[t] = {}
        ours = (str(a.get("provider") or "auto") in ("auto", "main", "openrouter", "nvidia", "custom")
                and (not a.get("base_url") or NIM_HOST in str(a["base_url"])))
        if t == "vision" and prov == "nvidia":
            # dedicated describer: one plain user-role image request to NIM,
            # exactly the shape of NVIDIA's own example (works)
            if ours:
                a.clear()
                a["provider"] = env("HERMES_VISION_PROVIDER", "nvidia")
                a["model"] = env("HERMES_VISION_MODEL", block["default"])
            continue
        if str(a.get("provider") or "auto") in ("auto", "openrouter") and not a.get("model"):
            a["provider"] = "main"

    fb_p, fb_m = env("HERMES_FALLBACK_PROVIDER"), env("HERMES_FALLBACK_MODEL")
    if fb_p and fb_m:
        data["fallback_providers"] = [{"provider": fb_p, "model": fb_m}]
    elif "fallback_providers" in data and last is not None:
        data.pop("fallback_providers")   # only drop a chain we created

    CFG.write_text(yaml.safe_dump(data, sort_keys=False))
    os.chmod(CFG, 0o600)
    STAMP.write_text(json.dumps(block))
    print(f"[ OK ] Hermes default model: {prov} / {block['default']}"
          + (f" via {block.get('base_url')}" if block.get("base_url") else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
