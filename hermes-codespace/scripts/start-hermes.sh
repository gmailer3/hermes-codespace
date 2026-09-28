#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; [ -f config/.env ] && . config/.env; set +a
export PYTHONPATH="$PWD/src"

bash scripts/health-check.sh --quiet || { echo "Health check failed. Fix the above and retry."; exit 1; }

cat <<BANNER
================================
 Hermes Codespace
================================
Hermes: READY
Browser: READY
AI Provider: CONNECTED ($MODEL_PROVIDER / $MODEL_NAME)
Workspace: READY
Task Manager: READY
Waiting for tasks...
BANNER
exec python3 -m task_manager.runner
