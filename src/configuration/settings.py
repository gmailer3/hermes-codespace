import os
from dataclasses import dataclass, field
from pathlib import Path
import yaml
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
load_dotenv(ROOT / "config" / ".env")


@dataclass
class Settings:
    provider: str = os.getenv("MODEL_PROVIDER", "google")
    model: str = os.getenv("MODEL_NAME", "")
    fallback_provider: str = os.getenv("FALLBACK_PROVIDER", "")
    fallback_model: str = os.getenv("FALLBACK_MODEL", "")
    browser_mode: str = os.getenv("BROWSER_MODE", "headless")
    target_url: str = os.getenv("TARGET_URL", "")
    allowed_domains: list = field(default_factory=lambda: [d.strip() for d in os.getenv("ALLOWED_DOMAINS", "").split(",") if d.strip()])
    max_retries: int = int(os.getenv("MAX_RETRIES", 3))
    max_retry_delay: int = int(os.getenv("MAX_RETRY_DELAY", 60))
    root: Path = ROOT

    def provider_config(self, name: str | None = None) -> dict:
        name = name or self.provider
        cfg = yaml.safe_load((ROOT / "config" / "models.yaml").read_text())["providers"]
        if name not in cfg:
            raise ValueError(f"Unknown provider '{name}'")
        c = dict(cfg[name]); c["name"] = name
        c["base_url"] = os.path.expandvars(c["base_url"])
        c["api_key"] = os.getenv(c["key_env"], "")
        return c

    def validate(self):
        primary = self.provider_config()
        if not primary["api_key"]:
            raise EnvironmentError(f"{primary['key_env']} missing for provider '{self.provider}' (add it in Codespaces Secrets)")
        if self.fallback_provider and not self.provider_config(self.fallback_provider)["api_key"]:
            print(f"[WARN] fallback '{self.fallback_provider}' has no key; fallback disabled")
            self.fallback_provider = ""
        if not self.allowed_domains:
            raise EnvironmentError("ALLOWED_DOMAINS is empty; refusing to run against unknown sites")

settings = Settings()
