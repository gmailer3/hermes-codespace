"""Polls tasks/ for QUEUED tasks and runs them one at a time with bounded retries."""
import time
from playwright.sync_api import TimeoutError as PWTimeout
from configuration.settings import settings
from hermes_logging.logger import get_logger
from browser.session import BrowserSession, HumanActionRequired, UnauthorizedSite
from task_manager.models import Task, State
from task_manager.client_data import load_client, InvalidClientData
from task_manager.workflows import WORKFLOWS

RECOVERABLE = (PWTimeout, ConnectionError, TimeoutError)
FATAL = (InvalidClientData, UnauthorizedSite, KeyError, FileNotFoundError)

def run_task(task: Task):
    log = get_logger(task.task_id)
    task.set(State.STARTING); log.info(f"starting {task.operation}")
    try:
        client = load_client(task.input_file)
        workflow = WORKFLOWS[task.operation]
    except FATAL as e:
        log.error(f"non-recoverable: {e}"); return task.set(State.FAILED, str(e))

    delay = 2
    while True:
        task.attempts += 1; task.set(State.RUNNING)
        try:
            with BrowserSession(task.task_id, log) as b:
                workflow(b, client, log)
            log.info("COMPLETED"); return task.set(State.COMPLETED)
        except HumanActionRequired as e:
            log.warning(str(e)); return task.set(State.WAITING_FOR_USER, str(e))
        except FATAL as e:
            log.error(f"non-recoverable: {e}"); return task.set(State.FAILED, str(e))
        except RECOVERABLE as e:
            if task.attempts > settings.max_retries:
                log.error(f"retries exhausted: {e}"); return task.set(State.FAILED, str(e))
            log.warning(f"recoverable error, retry {task.attempts}/{settings.max_retries} in {delay}s: {e}")
            time.sleep(delay); delay = min(delay * 2, settings.max_retry_delay)
        except Exception as e:
            log.exception("unexpected failure"); return task.set(State.FAILED, repr(e))

def main():
    settings.validate()
    log = get_logger()
    tasks_dir = settings.root / "tasks"
    while True:
        for p in sorted(tasks_dir.glob("*.json")):
            t = Task.load(p)
            if t.status == State.QUEUED:
                run_task(t)
        time.sleep(3)

if __name__ == "__main__":
    main()
