import os
from dataclasses import dataclass, field
from pathlib import Path
import yaml
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
load_dotenv(ROOT / "config" / ".env")


@dataclass
class Settings:
    provider: str = os.getenv("MODEL_PROVIDER", "nvidia_nim")
    model: str = os.getenv("MODEL_NAME", "")
    fallback_provider: str = os.getenv("FALLBACK_PROVIDER", "")
    fallback_model: str = os.getenv("FALLBACK_MODEL", "")
    browser_mode: str = os.getenv("BROWSER_MODE", "headless")
    target_url: str = os.getenv("TARGET_URL", "")
    allowed_domains: list = field(default_factory=lambda: [d.strip() for d in os.getenv("ALLOWED_DOMAINS", "").split(",") if d.strip()])
    max_retries: int = int(os.getenv("MAX_RETRIES", "3"))
    max_retry_delay: int = int(os.getenv("MAX_RETRY_DELAY", "60"))
    root: Path = ROOT

    def provider_config(self, name: str | None = None) -> dict:
        name = name or self.provider
        cfg = yaml.safe_load((ROOT / "config" / "models.yaml").read_text())["providers"]
        if name not in cfg:
            raise ValueError(f"Unknown provider '{name}'")
        c = dict(cfg[name]); c["name"] = name
        c["base_url"] = os.path.expandvars(c["base_url"])
        # key_env may be a single name or an ordered list of fallback env vars
        key_envs = c.get("key_env", [])
        c["key_envs"] = [key_envs] if isinstance(key_envs, str) else list(key_envs)
        c["api_key"] = next((os.getenv(k) for k in c["key_envs"] if os.getenv(k)), "")
        return c

    def provider_names(self) -> list:
        return list(yaml.safe_load((ROOT / "config" / "models.yaml").read_text())["providers"])

    def providers_with_keys(self) -> list:
        return [n for n in self.provider_names() if self.provider_config(n)["api_key"]]

    def validate(self):
        primary = self.provider_config()
        if not primary["api_key"]:
            raise EnvironmentError(
                f"No API key for provider '{self.provider}' (none of "
                f"{', '.join(primary['key_envs'])} is set). Add one via GitHub "
                f"Codespaces secrets or run 'bash bootstrap.sh'.")
        if self.fallback_provider and not self.provider_config(self.fallback_provider)["api_key"]:
            print(f"[WARN] fallback '{self.fallback_provider}' has no key; fallback disabled")
            self.fallback_provider = ""
        if not self.allowed_domains:
            raise EnvironmentError("ALLOWED_DOMAINS is empty; refusing to run against unknown sites")


settings = Settings()
