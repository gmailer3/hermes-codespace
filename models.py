import json
from dataclasses import dataclass, asdict, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path

class State(str, Enum):
    QUEUED = "QUEUED"; STARTING = "STARTING"; RUNNING = "RUNNING"
    WAITING_FOR_USER = "WAITING_FOR_USER"; COMPLETED = "COMPLETED"
    FAILED = "FAILED"; CANCELLED = "CANCELLED"

@dataclass
class Task:
    task_id: str
    client_id: str
    target: str
    operation: str
    input_file: str
    status: State = State.QUEUED
    attempts: int = 0
    error: str | None = None
    started_at: str | None = None
    ended_at: str | None = None
    path: Path | None = field(default=None, repr=False)

    @classmethod
    def load(cls, path: Path) -> "Task":
        d = json.loads(path.read_text()); d["status"] = State(d.get("status", "QUEUED"))
        return cls(**d, path=path)

    def save(self):
        d = asdict(self); d.pop("path"); d["status"] = self.status.value
        self.path.write_text(json.dumps(d, indent=2))

    def set(self, state: State, error: str | None = None):
        now = datetime.now(timezone.utc).isoformat()
        if state == State.STARTING: self.started_at = now
        if state in (State.COMPLETED, State.FAILED, State.CANCELLED): self.ended_at = now
        self.status, self.error = state, error; self.save()
