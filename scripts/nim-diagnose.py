#!/usr/bin/env python3
"""Pinpoints WHICH request shape makes NVIDIA NIM / Kimi K3 answer "!!!!".
Talks to NIM directly (no Hermes), streaming like Hermes does.

    python3 scripts/nim-diagnose.py            # ~2-6 min, 6 probes
Prints one line per probe: OK / GARBAGE / EMPTY / ERROR. Paste the output back.
"""
import json, os, re, string, sys, time
import requests

URL = os.getenv("HERMES_BASE_URL", "https://integrate.api.nvidia.com/v1").rstrip("/") + "/chat/completions"
KEY = os.getenv("NVIDIA_API_KEY") or os.getenv("NVIDIA_NIM_API_KEY") or os.getenv("NIM_API_KEY")
MODEL = os.getenv("HERMES_MODEL", "z-ai/glm-5.3")
if not KEY:
    sys.exit("no NVIDIA_API_KEY / NVIDIA_NIM_API_KEY in env")

def card(i):
    return (f'- link "Video {i}: Lofi beats \U0001F3A7 study session #{i} \u2022 4K\u200b" [ref=e{i}]\n'
            f'  - text "Channel {i} \u00b7 1.{i % 9}M views \u00b7 {i % 11} days ago"\n')

def snapshot(n_chars):
    out, i = [], 0
    while sum(map(len, out)) < n_chars:
        i += 1; out.append(card(i))
    return "".join(out)

TOOLS = [{"type": "function", "function": {"name": "browser_navigate",
          "description": "Open a URL and return an accessibility snapshot",
          "parameters": {"type": "object", "properties": {"url": {"type": "string"}}, "required": ["url"]}}}]

def tool_convo(snap):
    return [
        {"role": "system", "content": "You are Hermes, a helpful agent with a browser."},
        {"role": "user", "content": "Open youtube and tell me the titles of the videos on the home page."},
        {"role": "assistant", "content": None, "tool_calls": [{"id": "call_1", "type": "function",
            "function": {"name": "browser_navigate", "arguments": json.dumps({"url": "https://youtube.com"})}}]},
        {"role": "tool", "tool_call_id": "call_1", "name": "browser_navigate",
         "content": json.dumps({"success": True, "url": "https://www.youtube.com/", "snapshot": snap}, ensure_ascii=False)},
    ]

PROBES = [
    ("1 plain hello",                   {"messages": [{"role": "user", "content": "Reply with exactly: OK"}]}),
    ("2 plain + reasoning high",        {"messages": [{"role": "user", "content": "Reply with exactly: OK"}], "reasoning_effort": "high"}),
    ("3 tools + 12k page (capped)",     {"messages": tool_convo(snapshot(12000)), "tools": TOOLS}),
    ("4 tools + 12k page + reasoning",  {"messages": tool_convo(snapshot(12000)), "tools": TOOLS, "reasoning_effort": "high"}),
    ("5 tools + 90k page (uncapped)",   {"messages": tool_convo(snapshot(90000)), "tools": TOOLS}),
    ("6 tools + 90k page + reasoning",  {"messages": tool_convo(snapshot(90000)), "tools": TOOLS, "reasoning_effort": "high"}),
]

def garbage(t):
    t = t.strip()
    return len(t) >= 4 and (all(c in string.punctuation + " \n" for c in t) or
                            bool(re.search(r"([!?.])\1{15,}", t)))

def run(name, body):
    body = {"model": MODEL, "max_tokens": 1024, "stream": True, "temperature": 1, **body}
    t0 = time.time(); content = reasoning = ""; finish = None
    try:
        with requests.post(URL, headers={"Authorization": f"Bearer {KEY}", "Accept": "text/event-stream"},
                           json=body, stream=True, timeout=(15, 240)) as r:
            if r.status_code != 200:
                return print(f"[ERROR  ] {name}: HTTP {r.status_code} {r.text[:150]!r}")
            for line in r.iter_lines():
                if not line.startswith(b"data:"):
                    continue
                data = line[5:].strip()
                if data == b"[DONE]":
                    break
                try:
                    ch = json.loads(data)["choices"][0]
                except Exception:
                    continue
                d = ch.get("delta") or {}
                content += d.get("content") or ""
                reasoning += d.get("reasoning_content") or d.get("reasoning") or ""
                tc = d.get("tool_calls")
                if tc: content += f"<tool_call {tc[0].get('function', {}).get('name')}>"
                finish = ch.get("finish_reason") or finish
    except Exception as e:
        return print(f"[ERROR  ] {name}: {e.__class__.__name__} after {time.time()-t0:.0f}s")
    tag = "GARBAGE" if garbage(content) or garbage(reasoning[-200:]) else ("EMPTY  " if not content.strip() else "OK     ")
    print(f"[{tag}] {name}: {time.time()-t0:.0f}s finish={finish} reasoning={len(reasoning)}ch "
          f"content={content.strip()[:70]!r}")

print(f"NIM diagnose: {MODEL} @ {URL}")
for n, b in PROBES:
    run(n, b)
print("done. Paste these lines back.")
