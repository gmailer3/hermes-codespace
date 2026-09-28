"""Authorized workflows. Each maps an `operation` to steps against TARGET_URL.
Replace the selectors with your authorized site's real ones (test site first!)."""
from configuration.settings import settings

def client_onboarding(browser, client: dict, log):
    browser.goto(settings.target_url)
    log.info("navigated to target")
    # --- EXAMPLE: adjust selectors for your authorized site ---
    # browser.fill("#first_name", client["first_name"])
    # browser.fill("#last_name",  client["last_name"])
    # browser.fill("#email",      client["email"])
    # browser.click("button[type=submit]")
    # if "Thank you" not in browser.text(): raise RuntimeError("Website workflow changed")
    log.info("workflow steps complete")

WORKFLOWS = {"client_onboarding": client_onboarding}
