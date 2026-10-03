#!/usr/bin/env python3
"""Writes the Hermes CLI/gateway model config (~/.hermes/config.yaml).

WHY: the Hermes agent ignores OPENAI_BASE_URL for anything but its own
`openai-api` provider and reads the model ONLY from ~/.hermes/config.yaml.
With no `model:` block there it falls back to OpenRouter on launch. This
script pins the default to NVIDIA NIM + moonshotai/kimi-k3 (or whatever the
env says) without touching any other Hermes setting.

Stays configurable later:
  * env overrides (Codespaces secrets or config/.env):
      HERMES_PROVIDER   nvidia_nim (default) | openrouter | custom | <any hermes provider slug>
      HERMES_MODEL      default: moonshotai/kimi-k3
      HERMES_BASE_URL   default: https://integrate.api.nvidia.com/v1 (for nvidia_nim)
      HERMES_FALLBACK_PROVIDER / HERMES_FALLBACK_MODEL  optional (e.g. openrouter)
      HERMES_REASONING_EFFORT  default: high
      HERMES_CONTEXT_LENGTH    default: 131072
  * if you change the model yourself (`hermes model`, /model, editing the
    yaml) we detect it and leave it alone on the next VM start.
    Force a reset with HERMES_FORCE_MODEL=1.
"""
import json, os, sys
from pathlib import Path
import yaml

HOME = Path(os.getenv("HERMES_HOME", Path.home() / ".hermes"))
CFG = HOME / "config.yaml"
STAMP = HOME / ".codespace-model.json"   # what WE wrote last time

NIM_URL = "https://integrate.api.nvidia.com/v1"
KEY_ENV = {"nvidia_nim": "NVIDIA_NIM_API_KEY", "custom": "CUSTOM_API_KEY"}

def env(k, d=""):
    return (os.getenv(k) or d).strip()

def desired():
    prov = env("HERMES_PROVIDER", "nvidia_nim")
    model = env("HERMES_MODEL", "moonshotai/kimi-k3" if prov == "nvidia_nim" else "")
    block = {"default": model}
    if prov in ("nvidia_nim", "nvidia", "nim"):
        # NIM is OpenAI-compatible: use Hermes' first-class `custom` provider
        block.update(provider="custom", base_url=env("HERMES_BASE_URL", NIM_URL),
                     api_key="${NVIDIA_NIM_API_KEY}", key_env="NVIDIA_NIM_API_KEY",
                     api_mode="chat_completions",
                     context_length=int(env("HERMES_CONTEXT_LENGTH", "131072")))
    elif prov == "custom":
        block.update(provider="custom", base_url=env("HERMES_BASE_URL", env("CUSTOM_BASE_URL")),
                     api_key="${CUSTOM_API_KEY}", key_env="CUSTOM_API_KEY",
                     api_mode="chat_completions")
    else:  # openrouter, anthropic, gemini, nous ... -> Hermes resolves them natively
        block.update(provider=prov)
        if env("HERMES_BASE_URL"): block["base_url"] = env("HERMES_BASE_URL")
    return prov, block

def main():
    HOME.mkdir(parents=True, exist_ok=True)
    data = {}
    if CFG.exists():
        try: data = yaml.safe_load(CFG.read_text()) or {}
        except Exception as e:
            print(f"[WARN] {CFG} unreadable ({e}); leaving it alone"); return 0
    cur = data.get("model")
    last = json.loads(STAMP.read_text()) if STAMP.exists() else None
    force = env("HERMES_FORCE_MODEL") in ("1", "true", "yes")
    # first run: take over (fixes the OpenRouter default). Later runs: only
    # rewrite if the block is still exactly what we wrote last time.
    # compare only the identity fields: Hermes may normalise/migrate the rest
    ident = lambda m: (m.get("provider"), m.get("default") or m.get("model"), m.get("base_url") or "") \
        if isinstance(m, dict) else (None, m, "")
    user_changed = last is not None and ident(cur) != ident(last)
    if user_changed and not force:
        c = cur if isinstance(cur, dict) else {"default": cur}
        print(f"[ OK ] Hermes model kept (changed by you): {c.get('provider')} / {c.get('default')}"
              "  (set HERMES_FORCE_MODEL=1 to reset to the default)")
        return 0

    prov, block = desired()
    if prov in KEY_ENV and not os.getenv(KEY_ENV[prov]):
        print(f"[WARN] {KEY_ENV[prov]} not set, Hermes model not configured yet"); return 0
    if not block.get("default"):
        print("[WARN] HERMES_MODEL empty, Hermes model not configured"); return 0
    data["model"] = block
    data.setdefault("agent", {})
    if isinstance(data["agent"], dict):
        data["agent"]["reasoning_effort"] = env("HERMES_REASONING_EFFORT", "high")

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
