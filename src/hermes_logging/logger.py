import json, logging, os, re
from datetime import datetime, timezone
from configuration.settings import settings

_SECRET_PATTERNS = [
    re.compile(r"(?i)(api[_-]?key|token|password|secret)\s*[=:]\s*\S+"),
    re.compile(r"[A-Za-z0-9_\-]{32,}"),                         # long opaque tokens
    re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+"),                      # emails
    re.compile(r"\+?\d[\d\s().-]{7,}\d"),                        # phone numbers
]

def redact(text: str) -> str:
    for s in ("AI_API_KEY", "WEBSITE_CREDENTIALS", "TELEGRAM_BOT_TOKEN", "GITHUB_TOKEN"):
        v = os.getenv(s)
        if v: text = text.replace(v, "[REDACTED]")
    for p in _SECRET_PATTERNS:
        text = p.sub("[REDACTED]", text)
    return text

class _JsonFormatter(logging.Formatter):
    def format(self, r):
        return json.dumps({"ts": datetime.now(timezone.utc).isoformat(), "level": r.levelname,
                           "task": getattr(r, "task_id", None), "msg": redact(r.getMessage())})

def get_logger(task_id: str | None = None) -> logging.LoggerAdapter:
    name = task_id or "hermes"
    log = logging.getLogger(name)
    if not log.handlers:
        log.setLevel(os.getenv("LOG_LEVEL", "INFO"))
        logs = settings.root / "logs"; logs.mkdir(exist_ok=True)
        fh = logging.FileHandler(logs / f"{name}.log"); fh.setFormatter(_JsonFormatter())
        eh = logging.FileHandler(logs / "errors.log"); eh.setLevel(logging.ERROR); eh.setFormatter(_JsonFormatter())
        sh = logging.StreamHandler(); sh.setFormatter(_JsonFormatter())
        for h in (fh, eh, sh): log.addHandler(h)
    return logging.LoggerAdapter(log, {"task_id": task_id})
