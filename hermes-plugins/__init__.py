"""codespace-guard: small, fail-open Hermes plugin shipped by hermes-codespace.

transform_llm_output: hosted inference endpoints sometimes return a
"successful" completion made of one repeated punctuation token, e.g.
"!!!!!!!!!!!!". That is the serving backend emitting token id 0 over and over
(numerically broken logits), not something Hermes or Telegram produces.
We swap it for an honest notice so you know to resend, and log it.

pre_llm_call: when you ask for a screenshot on Telegram (or another
messaging platform), add a one-line hint so the model uses browser_vision
and returns the file as MEDIA:<path>, which the gateway uploads as a photo.
"""
import re
import string
import time
from pathlib import Path

_PUNCT = set(string.punctuation) | set(" \t\r\n\u00a0")
_REPEAT = re.compile(r"([!?.\-_*#~=])\1{15,}")
_SHOT = re.compile(r"screen\s?shot|screen\s?cap|\bss\b|snapshot|capture (the )?(screen|page)|"
                   r"show me (the )?(page|screen|browser)", re.I)
_LOG = Path.home() / ".hermes" / "logs" / "codespace-guard.log"

NOTICE = ("\u26a0\ufe0f The model returned a corrupted reply (\"{sample}\"). "
          "That is a glitch on the inference provider's side, not your message. "
          "Please send it again (or use /retry). If it keeps happening, start a "
          "fresh chat with /new.")


def _log(msg):
    try:
        _LOG.parent.mkdir(parents=True, exist_ok=True)
        with _LOG.open("a") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%S ") + msg + "\n")
    except Exception:
        pass


def is_garbage(text):
    t = (text or "").strip()
    if not t:
        return False
    if len(t) >= 4 and all(c in _PUNCT for c in t):
        return True                       # "!!!!!!!!", "?!?!?!", "....."
    m = _REPEAT.search(t)
    # mostly one repeated symbol, e.g. "Sure!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    return bool(m) and len(m.group(0)) >= 0.6 * len(t)


def _transform(response_text="", model="", platform="", **_):  # noqa
    if not is_garbage(response_text):
        return None                       # pass through untouched
    sample = response_text.strip()[:12] + ("\u2026" if len(response_text.strip()) > 12 else "")
    _log(f"garbage reply replaced model={model} platform={platform} len={len(response_text)} "
         f"last_request: {_LAST.get(_.get('session_id') or '?', 'n/a')}")
    return NOTICE.format(sample=sample)


_SYS = re.compile(r"\b(dns|resolver|resolv\.conf|control ?d|ctrld|nextdns|adguard|doh|vpn|tailscale|"
                  r"wireguard|proxy|systemd|systemctl|service|daemon|cron|crontab|startup|on boot|"
                  r"reboot|restart|persist\w*|permanent\w*|iptables|firewall|/etc/|apt(-get)? install|"
                  r"sudo|install)\b", re.I)
_PERSIST = ("[codespace hint] This machine is a GitHub Codespace: there is NO systemd "
            "(systemctl/service won't work), every background process dies when the codespace "
            "stops, and system files like /etc/resolv.conf can be reset on start. Only "
            "~/.hermes and /workspaces survive. So when you set up anything system-level "
            "(DNS resolver such as ControlD/ctrld, daemons, VPN, iptables, packages installed "
            "outside the repo), ALSO save an idempotent bash script to "
            "~/.hermes/on-start.d/<NN-name>.sh that re-applies it (install if missing, start "
            "the daemon in the background with nohup/setsid, rewrite config files; sudo works). "
            "Keep IDs/settings in that script. It runs automatically on every codespace start. "
            "Tell the user you saved it.")


def _pre_llm(user_message="", platform="", **_):
    msg = str(user_message or "")
    hints = []
    if _SYS.search(msg):
        hints.append(_PERSIST)
    if platform and platform not in ("cli", "tui", "acp") and _SHOT.search(msg):
        hints.append("[codespace hint] The user wants to SEE the screen. Use the browser tools "
                     "(browser_navigate if needed, then browser_vision) and include the returned "
                     "screenshot_path in your reply on its own line as MEDIA:/absolute/path.png "
                     "so it is delivered as a photo.")
    return "\n".join(hints) or None


# ---------------------------------------------------------------- page cap
# Pages like the YouTube home feed produce browser snapshots of 50-150k chars
# (hundreds of video cards, emoji, invisible unicode). Fed raw into the chat,
# that is exactly the long, noisy context where NIM-hosted Kimi degenerates
# into "!!!!". We keep the first N chars (titles/channels come first in the
# snapshot) and strip invisible junk characters.
import json, os, unicodedata
MAX_TOOL_CHARS = int(os.getenv("CODESPACE_GUARD_MAX_TOOL_CHARS", "12000"))
_CAP_TOOLS = ("browser_", "web_extract", "web_search")


def _clean(t):
    out = []
    for ch in t:
        cat = unicodedata.category(ch)
        if cat in ("Cc", "Cf", "Co", "Cs", "Cn") and ch not in "\n\t":
            continue                     # control, zero-width, private-use
        out.append(ch)
    return "".join(out)


def _cap(t, limit):
    t = _clean(t)
    if len(t) <= limit:
        return t
    return t[:limit] + f"\n[... page truncated by codespace-guard: {len(t)} chars total, first {limit} kept ...]"


def _tool_result(tool_name="", result=None, **_):
    if not isinstance(result, str) or not str(tool_name).startswith(_CAP_TOOLS):
        return None
    if len(result) <= MAX_TOOL_CHARS and result.isascii():
        return None
    try:
        d = json.loads(result)
    except Exception:
        d = None
    if isinstance(d, dict):
        changed = False
        for k, v in list(d.items()):
            if isinstance(v, str) and (len(v) > 2000 or not v.isascii()):
                nv = _cap(v, MAX_TOOL_CHARS)
                if nv != v:
                    d[k] = nv; changed = True
        if not changed:
            return None
        new = json.dumps(d, ensure_ascii=False)
    else:
        new = _cap(result, MAX_TOOL_CHARS)
        if new == result:
            return None
    _log(f"tool result capped tool={tool_name} {len(result)} -> {len(new)} chars")
    return new


# ---------------------------------------------------------------- diagnostics
_LAST = {}


def _stats(request=None, session_id="", **kw):
    try:
        req = request or kw.get("api_kwargs") or {}
        msgs = req.get("messages") or []
        chars = imgs = 0
        tools_seen = []
        for m in msgs:
            c = m.get("content")
            if isinstance(c, str):
                chars += len(c)
            elif isinstance(c, list):
                for part in c:
                    if isinstance(part, dict):
                        if part.get("type") in ("image_url", "input_image", "image"):
                            imgs += 1
                        chars += len(str(part.get("text") or ""))
            if m.get("role") == "tool" and m.get("name"):
                tools_seen.append(m["name"])
        _LAST[session_id or "?"] = (f"msgs={len(msgs)} chars={chars} images={imgs} "
                                    f"tools_defined={len(req.get('tools') or [])} "
                                    f"stream={req.get('stream')} temp={req.get('temperature')} "
                                    f"reasoning={req.get('reasoning_effort') or (req.get('extra_body') or {}).get('reasoning_effort')} "
                                    f"last_tools={tools_seen[-3:]}")
    except Exception:
        pass


def register(ctx):
    ctx.register_hook("transform_llm_output", _transform)
    ctx.register_hook("pre_llm_call", _pre_llm)
    ctx.register_hook("transform_tool_result", _tool_result)
    ctx.register_hook("pre_api_request", _stats)
