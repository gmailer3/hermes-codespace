"""Minimal OpenAI-compatible client for Gemini, OpenRouter, NVIDIA NIM and friends, with fallback.
Usage:  from configuration.llm import chat;  chat([{"role":"user","content":"hi"}])
CLI:    PYTHONPATH=src python -m configuration.llm --check

Note: the --check probe hits `GET {base_url}/models`. Some providers (OpenRouter,
NVIDIA NIM) serve that endpoint publicly, so a 200 there proves reachability,
not key validity — the first real chat call is the true key test."""
import sys
import requests
from configuration.settings import settings

def _call(cfg: dict, model: str, messages: list, **kw) -> str:
    headers = {"Authorization": f"Bearer {cfg['api_key']}", "Content-Type": "application/json"}
    headers.update(cfg.get("headers", {}))
    r = requests.post(cfg["base_url"].rstrip("/") + "/chat/completions", headers=headers, timeout=60,
                      json={"model": model or cfg.get("default_model"), "messages": messages, **kw})
    r.raise_for_status()
    return r.json()["choices"][0]["message"]["content"]

def chat(messages: list, **kw) -> str:
    try:
        return _call(settings.provider_config(), settings.model, messages, **kw)
    except Exception as e:
        if not settings.fallback_provider: raise
        print(f"[WARN] {settings.provider} failed ({e.__class__.__name__}); using {settings.fallback_provider}")
        return _call(settings.provider_config(settings.fallback_provider), settings.fallback_model, messages, **kw)

def check(name: str) -> bool:
    cfg = settings.provider_config(name)
    if not cfg["api_key"]:
        print(f"[SKIP] {name}: no key (set one of {', '.join(cfg['key_envs'])})"); return False
    headers = {"Authorization": f"Bearer {cfg['api_key']}", **cfg.get("headers", {})}
    try:
        r = requests.get(cfg["base_url"].rstrip("/") + "/models", headers=headers, timeout=10)
        ok = r.status_code == 200
        print(f"[{'OK' if ok else 'FAIL'}] {name}: HTTP {r.status_code}"); return ok
    except requests.RequestException as e:
        print(f"[FAIL] {name}: {e.__class__.__name__}"); return False

if __name__ == "__main__" and "--check" in sys.argv:
    names = [settings.provider] + ([settings.fallback_provider] if settings.fallback_provider else [])
    for n in ("google", "openrouter", "nvidia_nim", "openai"):
        if n not in names: names.append(n)
    results = {n: check(n) for n in names}
    sys.exit(0 if results.get(settings.provider) else 1)
