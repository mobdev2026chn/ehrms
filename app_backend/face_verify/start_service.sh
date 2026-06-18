#!/usr/bin/env bash
# Start the persistent face-verify service (Linux/macOS). Run from this folder.
# Uses the local venv python if present, else system python3.
set -e
cd "$(dirname "$0")"
PORT="${FACE_VERIFY_PORT:-5005}"
if [ -x "venv/bin/python" ]; then PY="venv/bin/python"; else PY="python3"; fi
echo "Starting face-verify service on http://127.0.0.1:${PORT} ..."
exec "$PY" -m uvicorn server:app --host 127.0.0.1 --port "$PORT"
