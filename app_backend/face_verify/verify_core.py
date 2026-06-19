#!/usr/bin/env python3
"""
Shared face-verification core used by BOTH the persistent HTTP service (server.py)
and the one-shot CLI (face_verify.py).

ENGINE: `face_recognition` (dlib) 128-D descriptors with euclidean distance — the
SAME engine the face-attendance app uses (face/face/backend-node/extract_face_worker.py).
EHRMS runs it in-process so it does NOT have to reach across to the face app; each app
stays self-contained on its own domain. Detection retries rotations so selfies stored
upside-down/sideways still resolve.

Previously this used ArcFace (DeepFace). It was swapped to dlib so EHRMS and the face
app validate faces with one identical algorithm.
"""
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# dlib/face_recognition euclidean distance: SAME person is typically < 0.5, different
# people > 0.6 (library default tolerance is 0.6). The face app uses 0.50; we match it
# so the two apps behave identically. Overridable per deployment via FACE_MATCH_THRESHOLD
# (raise toward 0.6 if same-person punches get rejected; lower to cut false accepts).
try:
    THRESHOLD = float(os.environ.get("FACE_MATCH_THRESHOLD", "0.50"))
except (TypeError, ValueError):
    THRESHOLD = 0.50

# Model/weights ship inside the face_recognition package — nothing to download.
MODEL_NAME = "dlib-face_recognition-128d"


def ensure_weights():
    # dlib's models are bundled with face_recognition_models; no download step needed.
    return True


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
    """Largest detected face's 128-D dlib descriptor, trying rotations so selfies
    stored upside-down/sideways still resolve. [img] is a BGR numpy array (as loaded
    by cv2). None if no face is found."""
    import cv2
    import numpy as np
    import face_recognition

    # Downscale wide images so detection stays fast (matches the face app's worker).
    h, w = img.shape[:2]
    max_w = 640
    if w > max_w:
        scale = max_w / w
        img = cv2.resize(img, (0, 0), fx=scale, fy=scale)

    for angle in (0, 180, 90, 270):
        rimg = _rotate(img, angle)
        # face_recognition expects RGB; cv2 gives BGR.
        rgb = cv2.cvtColor(rimg, cv2.COLOR_BGR2RGB)
        try:
            locs = face_recognition.face_locations(rgb)
        except Exception:
            continue
        if not locs:
            continue
        # Largest detected face.
        loc = max(locs, key=lambda l: (l[2] - l[0]) * (l[1] - l[3]))
        encs = face_recognition.face_encodings(rgb, [loc], num_jitters=1)
        if encs:
            return np.array(encs[0], dtype=float)
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
    # dlib face descriptors compare by euclidean distance (same as the face app).
    distance = float(np.linalg.norm(e1 - e2))
    if distance <= THRESHOLD:
        return {"match": True, "distance": distance, "error": None}
    return {"match": False, "distance": distance, "error": "Face not matching"}


def warmup():
    """Import the model once so the first real request is fast."""
    try:
        import numpy as np
        import face_recognition  # noqa: F401  (triggers model load)
        dummy = (np.random.rand(160, 160, 3) * 255).astype("uint8")
        face_recognition.face_locations(dummy)
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
