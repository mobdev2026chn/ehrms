#!/usr/bin/env bash
# One-shot setup for the EHRMS in-process face engine.
# RUN THIS ON THE SERVER THAT HOSTS THE EHRMS BACKEND (e.g. ehrms.askeva.net),
# from the app_backend/face_verify directory. Then restart Node.
#
#   bash setup_engine.sh
#   pm2 restart <ehrms-api>     # or: systemctl restart <service>, etc.
#
# It creates the Python venv the Node backend auto-detects (face_verify/venv) and
# installs the dlib deps. After this + a Node restart, enrollment and punch
# verification work — no separate service, no port.
set -e

cd "$(dirname "$0")"
echo "[setup] dir: $(pwd)"

# Build tools for dlib (Debian/Ubuntu). Skip/adapt if already present or non-apt.
if command -v apt-get >/dev/null 2>&1; then
  echo "[setup] installing build deps (cmake, build-essential, python3-venv)..."
  sudo apt-get update -y && sudo apt-get install -y build-essential cmake python3-venv
fi

echo "[setup] creating venv..."
python3 -m venv venv

echo "[setup] installing python deps (dlib compiles — this can take a few minutes)..."
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -r requirements.txt

echo "[setup] verifying engine imports..."
./venv/bin/python -c "import cv2, numpy, face_recognition; print('OK: cv2', cv2.__version__, '| face_recognition ready')"

echo
echo "[setup] DONE. Now restart the Node backend so it spawns the worker:"
echo "        pm2 restart <ehrms-api>     (or your process manager)"
echo "Then check the Node log for: [FaceEngine] spawning worker: .../face_verify/venv/bin/python"
