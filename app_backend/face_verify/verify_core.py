#!/usr/bin/env python3
"""
Shared face-verification core (ArcFace) used by BOTH the persistent HTTP service
(server.py) and the one-shot CLI (face_verify.py).

ArcFace is far more discriminative than the old OpenFace setup, so different people
no longer match. Detection retries rotations so legacy upside-down selfies resolve.
"""
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
# Keep model weights inside the project folder.
os.environ.setdefault("DEEPFACE_HOME", SCRIPT_DIR)
os.makedirs(os.path.join(SCRIPT_DIR, ".deepface", "weights"), exist_ok=True)

MODEL_NAME = "ArcFace"
DETECTOR = "opencv"  # bundled with opencv; no extra download
# ArcFace+cosine calibrated threshold is 0.68 (distance below = same person). We use
# a stricter value to cut false accepts. Raise toward 0.68 if same-person punches get
# rejected; lower (e.g. 0.55) if different people still slip through.
THRESHOLD = 0.60

ARCFACE_URL = "https://github.com/serengil/deepface_models/releases/download/v1.0/arcface_weights.h5"
ARCFACE_PATH = os.path.join(SCRIPT_DIR, ".deepface", "weights", "arcface_weights.h5")


def ensure_weights():
    if os.path.isfile(ARCFACE_PATH):
        return True
    try:
        import urllib.request
        urllib.request.urlretrieve(ARCFACE_URL, ARCFACE_PATH)
        return os.path.isfile(ARCFACE_PATH)
    except Exception:
        return False


def _rotate(img, angle):
    import cv2
    if angle == 90:
        return cv2.rotate(img, cv2.ROTATE_90_CLOCKWISE)
    if angle == 180:
        return cv2.rotate(img, cv2.ROTATE_180)
    if angle == 270:
        return cv2.rotate(img, cv2.ROTATE_90_COUNTERCLOCKWISE)
    return img


def embedding(img):
    """Largest detected face's ArcFace embedding, trying rotations so legacy
    upside-down/sideways selfies still resolve. None if no face is found."""
    import numpy as np
    from deepface import DeepFace
    for angle in (0, 180, 90, 270):
        try:
            reps = DeepFace.represent(
                _rotate(img, angle),
                model_name=MODEL_NAME,
                detector_backend=DETECTOR,
                enforce_detection=True,
                align=True,
            )
        except Exception:
            continue
        if reps:
            reps.sort(
                key=lambda r: (r.get("facial_area", {}).get("w", 0)
                               * r.get("facial_area", {}).get("h", 0)),
                reverse=True,
            )
            emb = reps[0].get("embedding")
            if emb:
                return np.array(emb, dtype=float)
    return None


def verify_images(img1, img2):
    """img1/img2 are BGR numpy arrays. Returns {match, distance, error}."""
    import numpy as np
    if img1 is None or img2 is None:
        return {"match": False, "error": "Could not load one or both images"}
    e1 = embedding(img1)
    e2 = embedding(img2)
    if e1 is None or e2 is None:
        return {"match": False, "error": "No face detected in one or both images"}
    denom = float(np.linalg.norm(e1) * np.linalg.norm(e2))
    if denom == 0:
        return {"match": False, "error": "Face not matching"}
    distance = 1.0 - float(np.dot(e1, e2) / denom)
    if distance <= THRESHOLD:
        return {"match": True, "distance": distance, "error": None}
    return {"match": False, "distance": distance, "error": "Face not matching"}


def warmup():
    """Build/load the model once so the first real request is fast."""
    try:
        import numpy as np
        ensure_weights()
        dummy = (np.random.rand(160, 160, 3) * 255).astype("uint8")
        from deepface import DeepFace
        DeepFace.represent(
            dummy, model_name=MODEL_NAME, detector_backend=DETECTOR,
            enforce_detection=False, align=False,
        )
    except Exception:
        pass


# ── image loaders ─────────────────────────────────────────────────────────────
def load_from_path(p):
    import cv2
    return cv2.imread(p)


def load_from_base64(s):
    import base64, cv2, numpy as np
    if not s:
        return None
    if s.startswith("data:"):
        s = s.split(",", 1)[1] if "," in s else s
    buf = np.frombuffer(base64.b64decode(s), np.uint8)
    return cv2.imdecode(buf, cv2.IMREAD_COLOR)


def load_from_url(u, timeout=15):
    import urllib.request, cv2, numpy as np
    with urllib.request.urlopen(u, timeout=timeout) as resp:
        data = resp.read()
    buf = np.frombuffer(data, np.uint8)
    return cv2.imdecode(buf, cv2.IMREAD_COLOR)
