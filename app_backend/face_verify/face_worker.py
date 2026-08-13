#!/usr/bin/env python3
"""
Persistent face worker for EHRMS — NO HTTP PORT.

The Node backend (port 9001) spawns this once and talks to it over stdin/stdout
(one JSON command per line in, one JSON result per line out), exactly like the
face-attendance app's aiEngine. This removes the separate :5005 service: the face
engine runs as a child of the Node process, so there's only one thing to run.

Commands (one JSON object per line):
  {"cmd":"embed","image":"<base64|dataurl>"}        # lenient enroll: rotations, no positioning guards, but blur-gated
      -> {"embedding":[...128 floats...], "error":null}  | {"embedding":null,"error":"..."}
  {"cmd":"embed_live","image":"<base64|dataurl>"}   # STRICT live punch/break: kiosk guards + anti-spoof
      -> {"embedding":[...128 floats...], "error":null}  | {"embedding":null,"error":"<guard msg>"}
  {"cmd":"verify","selfie":"<b64>","reference":"<b64>"}            (or "reference_url":"<url>")
      -> {"match":bool, "distance":float, "error":null|str}
"""
import sys
import os
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Protect the stdout channel: route any import-time noise (warnings, model loads)
# to stderr so it can NEVER corrupt the JSON response stream Node parses.
_real_stdout = sys.stdout
sys.stdout = sys.stderr
try:
    import verify_core
    verify_core.warmup()
    _ENGINE_OK = True
except Exception as e:  # pragma: no cover
    sys.stderr.write(f"[face_worker] engine load failed: {e}\n")
    sys.stderr.flush()
    _ENGINE_OK = False
finally:
    sys.stdout = _real_stdout


def _out(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def _handle(cmd):
    action = cmd.get("cmd")
    if action == "embed":
        # Lenient ENROLL path (rotations, no positioning guards) + sharpness gate, so a
        # blurry capture is rejected and only a clear face is registered.
        img = verify_core.load_from_base64(cmd.get("image", ""))
        if img is None:
            return {"embedding": None, "error": "Could not load image"}
        e, err = verify_core.embed_for_enroll(img)
        if e is None:
            return {"embedding": None, "error": err or "No face detected"}
        return {"embedding": e.tolist(), "error": None}

    if action == "embed_live":
        # STRICT live punch/break path: kiosk guards (single-face/centering/
        # proximity) + optional anti-spoofing, ported from the face-attendance app.
        img = verify_core.load_from_base64(cmd.get("image", ""))
        if img is None:
            return {"embedding": None, "error": "Could not load image"}
        e, err = verify_core.embed_live(img)
        if e is None:
            return {"embedding": None, "error": err or "No face detected"}
        return {"embedding": e.tolist(), "error": None}

    if action == "verify":
        img1 = verify_core.load_from_base64(cmd.get("selfie", "")) if cmd.get("selfie") else None
        if cmd.get("reference"):
            img2 = verify_core.load_from_base64(cmd.get("reference"))
        elif cmd.get("reference_url"):
            img2 = verify_core.load_from_url(cmd.get("reference_url"))
        else:
            img2 = None
        if img1 is None:
            return {"match": False, "error": "Could not load selfie"}
        if img2 is None:
            return {"match": False, "error": "Could not load reference"}
        return verify_core.verify_images(img1, img2)

    return {"error": f"Unknown command: {action}"}


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            cmd = json.loads(line)
        except Exception:
            _out({"error": "Invalid JSON command"})
            continue
        if not _ENGINE_OK:
            _out({"error": "Face engine not available"})
            continue
        try:
            _out(_handle(cmd))
        except Exception as e:
            _out({"error": f"Worker error: {str(e)}"})


if __name__ == "__main__":
    main()
