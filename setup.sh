#!/usr/bin/env bash
# Thin wrapper: the real setup lives in the repo-root bootstrap.sh (single
# source of truth, and the one-command entrypoint for the whole project).
# Runs automatically on Codespace creation via devcontainer.json
# "postCreateCommand".
cd "$(dirname "$0")/.."
exec bash bootstrap.sh "$@"
