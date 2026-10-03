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


def _transform(response_text="", model="", platform="", **_):
    if not is_garbage(response_text):
        return None                       # pass through untouched
    sample = response_text.strip()[:12] + ("\u2026" if len(response_text.strip()) > 12 else "")
    _log(f"garbage reply replaced model={model} platform={platform} len={len(response_text)}")
    return NOTICE.format(sample=sample)


def _pre_llm(user_message="", platform="", **_):
    if not platform or platform in ("cli", "tui", "acp"):
        return None
    if not _SHOT.search(str(user_message or "")):
        return None
    return ("[codespace hint] The user wants to SEE the screen. Use the browser tools "
            "(browser_navigate if needed, then browser_vision) and include the returned "
            "screenshot_path in your reply on its own line as MEDIA:/absolute/path.png "
            "so it is delivered as a photo.")


def register(ctx):
    ctx.register_hook("transform_llm_output", _transform)
    ctx.register_hook("pre_llm_call", _pre_llm)
