"""Telegram control bot for the Hermes Codespace.

Long-polling controller — no extra dependencies (plain `requests`):
  /start   hello + status (also: reveals your chat id when unauthorized)
  /help    command list
  /status  Hermes CLI, provider, runner process, task counts
  /health  quick env checks
  /tasks   list tasks and their states
  /run <task_id>       re-queue a task (attempts reset)
  /stop <task_id>      cancel a task that has not started yet
  /logs <task_id> [n]  tail a task log (or `runner` for the runner output)

It also watches tasks/*.json and pushes state-change notifications
(started / completed / failed / waiting-for-human) to authorized chats.

Auth: only chats listed in TELEGRAM_CHAT_ID (comma-separated numeric ids or
@channelnames) may send commands. If it is unset, the bot only answers /start
with the sender's chat id and setup instructions. The token comes from the
TELEGRAM_BOT_TOKEN Codespaces secret."""
from __future__ import annotations

import json
import os
import shutil
import signal
import sys
import time
from pathlib import Path

import requests

from configuration.settings import ROOT, settings
from hermes_logging.logger import redact
from task_manager.models import Task, State

TELEGRAM_API = "https://api.telegram.org/bot{token}/{method}"
POLL_TIMEOUT = 15                      # seconds (Telegram long-poll)
HTTP_TIMEOUT = POLL_TIMEOUT + 20        # requests must exceed the long poll
MAX_MSG = 3800                          # stay safely under Telegram's 4096
OFFSET_FILE = ROOT / ".run" / "telegram.offset"

ICONS = {"STARTING": "\U0001F680", "RUNNING": "\u25B6\uFE0F", "COMPLETED": "\u2705",
         "FAILED": "\u274C", "WAITING_FOR_USER": "\u26A0\uFE0F", "CANCELLED": "\u26D4"}


class TelegramConflict(Exception):
    """Another getUpdates poller is using this token (409)."""


class Bot:
    def __init__(self, token: str, allowed_chats: list[str]):
        self.token = token
        self.allowed = allowed_chats
        self.offset = self._load_offset()
        self.last_tasks: dict[str, dict] = {}
        self.started = time.time()
        self._stop = False

    # ---------------------------------------------------------------- plumbing
    def _load_offset(self) -> int:
        try:
            return int(OFFSET_FILE.read_text().strip() or 0)
        except Exception:
            return 0

    def _save_offset(self):
        try:
            OFFSET_FILE.parent.mkdir(exist_ok=True)
            OFFSET_FILE.write_text(str(self.offset))
        except Exception:
            pass

    def api(self, method: str, **params):
        r = requests.post(TELEGRAM_API.format(token=self.token, method=method),
                          json=params, timeout=HTTP_TIMEOUT)
        if r.status_code == 409:
            raise TelegramConflict("409 conflict: another poller holds this token")
        r.raise_for_status()
        d = r.json()
        if not d.get("ok"):
            raise RuntimeError(f"Telegram error: {d.get('description')}")
        return d.get("result", [])

    def send(self, chat_id, text: str):
        text = redact(str(text)).strip() or "(empty)"
        while text:
            chunk, text = text[:MAX_MSG], text[MAX_MSG:]
            try:
                self.api("sendMessage", chat_id=chat_id, text=chunk)
            except requests.RequestException as e:
                print(f"[telegram] send failed: {e.__class__.__name__}", flush=True)
                return

    def broadcast(self, text: str):
        for c in self.allowed:
            self.send(c, text)

    def authorized(self, chat: dict) -> bool:
        cid = str(chat.get("id", ""))
        uname = chat.get("username", "")
        return cid in self.allowed or (uname and f"@{uname}" in self.allowed)

    # ---------------------------------------------------------------- commands
    def runner_alive(self) -> tuple[bool, str]:
        try:
            pid = int((ROOT / ".run" / "runner.pid").read_text().strip())
            os.kill(pid, 0)
            return True, str(pid)
        except Exception:
            return False, ""

    def cmd_start(self, chat_id, args):
        p = settings.provider
        alive, pid = self.runner_alive()
        self.send(chat_id,
                  "\U0001F916 Hermes Codespace bot online.\n"
                  f"Provider: {p} / {settings.model or 'default'}\n"
                  f"Runner: {'RUNNING (pid ' + pid + ')' if alive else 'stopped'}\n"
                  "Send /help for commands, /status for details.")

    def cmd_help(self, chat_id, args):
        self.send(chat_id, "\U0001F527 /status /health /tasks /run <task_id> "
                           "/stop <task_id> /logs <task_id> [lines]\n"
                           "Task notifications (started/completed/failed/human-needed) "
                           "are pushed here automatically.")

    def cmd_status(self, chat_id, args):
        hermes = shutil.which("hermes") or str(Path.home() / ".local" / "bin" / "hermes")
        hermes_ok = "READY" if os.path.exists(hermes) else "NOT INSTALLED"
        try:
            keys = ", ".join(settings.providers_with_keys()) or "none"
        except Exception as e:
            keys = f"unknown ({e.__class__.__name__})"
        alive, pid = self.runner_alive()
        snap = self.snapshot_tasks()
        counts: dict[str, int] = {}
        for t in snap.values():
            counts[t["status"]] = counts.get(t["status"], 0) + 1
        up = time.strftime("%H:%M:%S", time.gmtime(time.time() - self.started))
        self.send(chat_id, "\u2139\uFE0F Hermes Codespace status\n"
                 f"Hermes CLI: {hermes_ok}\n"
                 f"Provider: {settings.provider} / {settings.model or 'default'} (keys: {keys})\n"
                 f"Runner: {'RUNNING (pid ' + pid + ')' if alive else 'STOPPED'}\n"
                 f"Tasks: {', '.join(f'{v} {k}' for k, v in sorted(counts.items())) or 'none'}\n"
                 f"Bot uptime: {up}")

    def cmd_health(self, chat_id, args):
        lines = []
        hermes = shutil.which("hermes") or str(Path.home() / ".local" / "bin" / "hermes")
        lines.append(("[OK] " if os.path.exists(hermes) else "[FAIL] ") + f"Hermes CLI ({hermes})")
        lines.append("[OK] config/.env" if (ROOT / "config" / ".env").exists() else "[FAIL] config/.env missing")
        try:
            cfg = settings.provider_config()
            lines.append("[OK] AI key present" if cfg["api_key"] else "[FAIL] no AI key")
            from configuration import llm
            lines.append("[OK] AI provider reachable" if llm.check(settings.provider)
                         else "[FAIL] AI provider check failed")
        except Exception as e:
            lines.append(f"[FAIL] provider config: {e}")
        alive, _ = self.runner_alive()
        lines.append("[OK] runner process" if alive else "[FAIL] runner not running")
        try:
            probe = ROOT / "logs" / ".bot_hc"; probe.touch(); probe.unlink()
            lines.append("[OK] filesystem writable")
        except Exception:
            lines.append("[FAIL] filesystem not writable")
        self.send(chat_id, "\U0001FA7A Health check\n" + "\n".join(lines))

    def cmd_tasks(self, chat_id, args):
        snap = self.snapshot_tasks()
        if not snap:
            self.send(chat_id, "\U0001F4CB No tasks (create one with "
                              "PYTHONPATH=src python -m task_manager.create_task client_001.json)")
            return
        rows = []
        ordered = sorted(snap.items(), key=lambda kv: kv[1]["mtime"], reverse=True)
        for tid, t in ordered[:25]:
            rows.append(f"{ICONS.get(t['status'], '\u2022')} {tid}: {t['status']}"
                        + (f" (attempt {t['attempts']})" if t["attempts"] else ""))
        self.send(chat_id, "\U0001F4CB Tasks\n" + "\n".join(rows))

    def _find_task(self, ref: str) -> Path | None:
        ref = ref.strip().removesuffix(".json")
        if not ref or not all(c.isalnum() or c in "_-" for c in ref):
            return None
        tasks = ROOT / "tasks"
        for cand in (f"task_{ref}", ref):
            p = tasks / f"{cand}.json"
            if p.exists():
                return p
        return None

    def cmd_run(self, chat_id, args):
        if not args:
            self.send(chat_id, "Usage: /run <task_id>  (e.g. /run task_client_001 or /run client_001)")
            return
        p = self._find_task(args[0])
        if not p:
            self.send(chat_id, f"\u274C task not found: {args[0]}")
            return
        t = Task.load(p)
        was = t.status.value if isinstance(t.status, State) else str(t.status)
        t.attempts = 0
        t.error = None
        t.set(State.QUEUED)
        self.send(chat_id, f"\u267B\uFE0F {t.task_id} queued (was {was}); "
                           "the runner picks it up within a few seconds.")

    def cmd_stop(self, chat_id, args):
        if not args:
            self.send(chat_id, "Usage: /stop <task_id>")
            return
        p = self._find_task(args[0])
        if not p:
            self.send(chat_id, f"\u274C task not found: {args[0]}")
            return
        t = Task.load(p)
        if t.status in (State.COMPLETED, State.FAILED, State.CANCELLED):
            self.send(chat_id, f"\u274C {t.task_id} already finished ({t.status.value})")
        elif t.status == State.QUEUED:
            t.set(State.CANCELLED)
            self.send(chat_id, f"\u26D4 {t.task_id} cancelled before start")
        else:
            self.send(chat_id, f"\u26A0\uFE0F {t.task_id} is currently {t.status.value} — /stop only "
                               "takes effect while a task is QUEUED.")

    def cmd_logs(self, chat_id, args):
        if not args:
            self.send(chat_id, "Usage: /logs <task_id> [lines]  (or /logs runner)")
            return
        try:
            n = max(1, min(int(args[1]), 60))
        except (IndexError, ValueError):
            n = 15
        ref = args[0].removesuffix(".json")
        if ref == "runner":
            path = ROOT / "logs" / "runner.out"
        else:
            p = self._find_task(args[0])
            path = (ROOT / "logs" / f"{p.stem}.log") if p else None
        if not path or not path.exists():
            self.send(chat_id, f"\u274C no log found for '{args[0]}'")
            return
        try:
            tail = path.read_text(errors="replace").splitlines()[-n:]
        except Exception as e:
            self.send(chat_id, f"\u274C cannot read log: {e}")
            return
        self.send(chat_id, f"\U0001F4C4 {path.name} (last {len(tail)} lines)\n" + "\n".join(tail))

    # ---------------------------------------------------------------- watcher
    def snapshot_tasks(self) -> dict[str, dict]:
        snap = {}
        for p in (ROOT / "tasks").glob("*.json"):
            try:
                d = json.loads(p.read_text())
                snap[p.stem] = {"status": d.get("status", "?"),
                                "error": d.get("error") or "",
                                "attempts": d.get("attempts", 0),
                                "mtime": p.stat().st_mtime}
            except Exception:
                continue  # partially-written file; catch it next sweep
        return snap

    def watch_tasks(self):
        snap = self.snapshot_tasks()
        if self.last_tasks:
            for tid, t in snap.items():
                prev = self.last_tasks.get(tid)
                if not prev or prev["status"] == t["status"]:
                    continue
                icon = ICONS.get(t["status"], "\u2022")
                line = f"{icon} {tid}: {prev['status']} \u2192 {t['status']}"
                if t["status"] == "FAILED" and t["error"]:
                    line += f"\n{redact(t['error'])[:400]}"
                if t["status"] == "WAITING_FOR_USER":
                    line += "\nhuman action needed (e.g. CAPTCHA) — check screenshots/ and approve."
                self.broadcast(line)
        self.last_tasks = snap

    # ---------------------------------------------------------------- loop
    def handle(self, update: dict):
        msg = update.get("message") or update.get("edited_message")
        if not msg:
            return
        text = (msg.get("text") or "").strip()
        if not text:
            return
        chat = msg.get("chat", {})
        if not self.authorized(chat):
            # /start doubles as the setup path: tell the sender how to authorize.
            if text.split()[0].split("@")[0] == "/start":
                self.send(chat.get("id"), self._unauth_text(chat))
            return
        cmd, _, rest = text.partition(" ")
        cmd = cmd.split("@")[0].lower()
        args = rest.split()
        handlers = {"/start": self.cmd_start, "/help": self.cmd_help, "/status": self.cmd_status,
                    "/health": self.cmd_health, "/tasks": self.cmd_tasks, "/run": self.cmd_run,
                    "/stop": self.cmd_stop, "/logs": self.cmd_logs}
        h = handlers.get(cmd)
        if h:
            h(chat.get("id"), args)
        else:
            self.send(chat.get("id"), "Unknown command. /help")

    def _unauth_text(self, chat: dict) -> str:
        cid = chat.get("id")
        how = ("GitHub repo \u2192 Settings \u2192 Secrets and variables \u2192 Codespaces "
               "\u2192 new secret TELEGRAM_CHAT_ID") if not self.allowed else "TELEGRAM_CHAT_ID"
        return (f"\U0001F512 Unauthorized. Your chat id is: {cid}\n"
                f"Allow it via {how} (value: {cid}), or add it with 'bash bootstrap.sh' "
                "in the codespace, then restart the bot (scripts/start-hermes.sh restart).")

    def loop(self):
        print(f"[telegram] bot up; authorized chats: {self.allowed or 'NONE — only /start works'}", flush=True)
        backoff = 5
        while not self._stop:
            try:
                updates = self.api("getUpdates", offset=self.offset, timeout=POLL_TIMEOUT)
                backoff = 5
                for u in updates or []:
                    self.offset = max(self.offset, u.get("update_id", 0) + 1)
                    self._save_offset()
                    try:
                        self.handle(u)
                    except Exception as e:
                        print(f"[telegram] handler error: {e}", flush=True)
                self.watch_tasks()
            except TelegramConflict as e:
                print(f"[telegram] {e}; retrying in 30s", flush=True)
                time.sleep(30)
            except (requests.RequestException, RuntimeError) as e:
                print(f"[telegram] poll failed ({e.__class__.__name__}); retry in {backoff}s", flush=True)
                time.sleep(backoff)
                backoff = min(backoff * 2, 120)
        print("[telegram] stopped", flush=True)


def main():
    token = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
    if not token:
        print("[telegram] TELEGRAM_BOT_TOKEN not set — bot disabled"); sys.exit(1)
    chats = [c.strip() for c in os.getenv("TELEGRAM_CHAT_ID", "").split(",") if c.strip()]
    if not chats:
        print("[telegram] WARNING: TELEGRAM_CHAT_ID not set — bot answers /start "
              "(reveals chat id) and refuses all other commands.", flush=True)
    bot = Bot(token, chats)

    def _halt(signum, frame):
        bot._stop = True

    signal.signal(signal.SIGTERM, _halt)
    signal.signal(signal.SIGINT, _halt)
    bot.loop()


if __name__ == "__main__":
    main()
