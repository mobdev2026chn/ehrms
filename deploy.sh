#!/usr/bin/env bash
# One-command deploy for the EHRMS backend (run ON the server, from the repo root):
#   bash deploy.sh
# Override the pm2 app name if it differs:  PM2_APP=my-api bash deploy.sh
#
# It pulls the latest code, installs deps ONLY when they changed (or on first run),
# then gracefully reloads pm2 (re-reads .env, respawns the face worker). You do NOT
# restart pm2 by hand or reinstall the engine every time — this decides what's needed.
set -euo pipefail
cd "$(dirname "$0")"

PM2_APP="${PM2_APP:-ektahr-api}"
echo "[deploy] repo: $(pwd)  | pm2 app: $PM2_APP"

OLD=$(git rev-parse HEAD)
git pull --ff-only
NEW=$(git rev-parse HEAD)
CHANGED=$(git diff --name-only "$OLD" "$NEW" || true)
[ "$OLD" = "$NEW" ] && echo "[deploy] code already up to date ($NEW)" || echo "[deploy] $OLD -> $NEW"

# Node deps — only if package.json/lock changed.
if echo "$CHANGED" | grep -q 'app_backend/package'; then
  echo "[deploy] backend Node deps changed -> npm ci"
  (cd app_backend && npm ci --omit=dev)
fi

# Python face engine — install on FIRST run (no venv) or when requirements change.
if [ ! -x app_backend/face_verify/venv/bin/python ]; then
  echo "[deploy] face engine venv missing -> first-time install (setup_engine.sh)"
  (cd app_backend/face_verify && bash setup_engine.sh)
elif echo "$CHANGED" | grep -q 'app_backend/face_verify/requirements.txt'; then
  echo "[deploy] face engine requirements changed -> reinstall"
  (cd app_backend/face_verify && bash setup_engine.sh)
fi

echo "[deploy] reloading pm2 (graceful, re-reads .env)"
pm2 reload "$PM2_APP" --update-env || pm2 restart "$PM2_APP" --update-env
echo "[deploy] done ✓  ($NEW)"
