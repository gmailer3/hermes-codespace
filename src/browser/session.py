from datetime import datetime
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright, Page
from configuration.settings import settings

CHALLENGE_MARKERS = ["captcha", "recaptcha", "hcaptcha", "cf-challenge", "turnstile",
                     "verify you are human", "are you a robot"]

class UnauthorizedSite(Exception): ...
class HumanActionRequired(Exception): ...

class BrowserSession:
    """Thin Playwright wrapper. Enforces the domain allowlist and pauses on challenges
    (never bypasses them)."""
    def __init__(self, task_id: str, log):
        self.task_id, self.log = task_id, log

    def __enter__(self):
        self._pw = sync_playwright().start()
        self.browser = self._pw.chromium.launch(headless=settings.browser_mode != "headed")
        self.context = self.browser.new_context()
        self.page: Page = self.context.new_page()
        self.page.on("dialog", lambda d: (self.log.info(f"dialog: {d.type}"), d.dismiss()))
        self.screenshot("startup")
        return self

    def __exit__(self, *exc):
        try: self.screenshot("final")
        finally:
            self.context.close(); self.browser.close(); self._pw.stop()

    def _check_allowed(self, url: str):
        host = urlparse(url).hostname or ""
        if not any(host == d or host.endswith("." + d) for d in settings.allowed_domains):
            raise UnauthorizedSite(f"{host} is not in ALLOWED_DOMAINS")

    def goto(self, url: str):
        self._check_allowed(url)
        self.page.goto(url, wait_until="domcontentloaded", timeout=30_000)
        self.check_for_challenge()

    def check_for_challenge(self):
        html = self.page.content().lower()
        if any(m in html for m in CHALLENGE_MARKERS):
            self.screenshot("captcha")
            self.log.warning("CAPTCHA detected. Automation paused. Human action required.")
            raise HumanActionRequired("CAPTCHA / verification challenge")

    def fill(self, selector: str, value: str): self.page.fill(selector, value)
    def click(self, selector: str): self.page.click(selector); self.check_for_challenge()
    def upload(self, selector: str, path: str): self.page.set_input_files(selector, path)
    def text(self, selector: str = "body") -> str: return self.page.inner_text(selector)

    def screenshot(self, label: str):
        shots = settings.root / "screenshots"; shots.mkdir(exist_ok=True)
        p = shots / f"{self.task_id}_{label}_{datetime.now():%Y%m%d_%H%M%S}.png"
        self.page.screenshot(path=str(p)); return p
