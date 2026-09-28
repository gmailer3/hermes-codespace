"""Usage: python -m task_manager.create_task client_001.json [operation]"""
import json, sys
from configuration.settings import settings
from task_manager.client_data import load_client

def main():
    fname = sys.argv[1]; op = sys.argv[2] if len(sys.argv) > 2 else "client_onboarding"
    c = load_client(fname)
    tid = f"task_{c['client_id']}"
    (settings.root / "tasks" / f"{tid}.json").write_text(json.dumps({
        "task_id": tid, "client_id": c["client_id"], "target": "authorized-website",
        "operation": op, "input_file": fname, "status": "QUEUED"}, indent=2))
    print(f"Queued {tid}")

if __name__ == "__main__":
    main()
