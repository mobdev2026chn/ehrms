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
import sys

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


# ── Strict LIVE-scan config (ported from the face-attendance app's kiosk pipeline,
# face/face/backend-node/extract_face_worker.py::process_image) ───────────────────
# These guards gate a LIVE punch/break selfie before it can produce an embedding:
# exactly one face, centered, correct proximity, optional frontal pose, optional
# anti-spoofing liveness. Every threshold mirrors the face app's defaults and is
# env-overridable so a mobile selfie (face fills more of the frame than a kiosk
# feed) can be tuned without code changes. Set FACE_LIVE_GUARDS=0 to fall back to
# the old lenient embedding() path entirely.
def _env_int(name, default):
    try:
        return int(os.environ.get(name, str(default)))
    except (TypeError, ValueError):
        return default


LIVE_GUARDS = os.environ.get("FACE_LIVE_GUARDS", "1") == "1"
# FRAMING (centering + proximity) is a KIOSK guard: it assumes a fixed camera with a
# face-guide overlay. EHRMS is a HANDHELD selfie app — the face fills the frame and
# is rarely centered — so framing is OFF by default here (it was rejecting valid
# punches as "too close"/"off-center"). The valuable live checks (single-face +
# anti-spoof liveness) stay ON. Turn framing on per-kiosk-deployment with
# FACE_FRAMING_CHECK=1.
FRAMING_CHECK = os.environ.get("FACE_FRAMING_CHECK", "0") == "1"
FRONTAL_CHECK = os.environ.get("FACE_FRONTAL_CHECK", "0") == "1"
LIVENESS_CHECK = os.environ.get("FACE_LIVENESS", "1") == "1"
CENTER_TOL_X = _env_int("FACE_CENTER_TOL_X", 210)
CENTER_TOL_Y = _env_int("FACE_CENTER_TOL_Y", 210)
MIN_FACE_W = _env_int("FACE_MIN_WIDTH", 90)
MAX_FACE_W = _env_int("FACE_MAX_WIDTH", 260)
SCAN_MAX_W = _env_int("FACE_SCAN_MAX_WIDTH", 480)

# SHARPNESS gate — reject a blurry / out-of-focus / motion-smeared face so ONLY a
# clear capture produces an embedding, on BOTH recognition (embed_live) and enroll
# (embed_for_enroll). Measured as the variance of the Laplacian on the detected face
# crop, resized to a fixed 160x160 so a single threshold holds regardless of how big
# the face is in frame or which detector downscale (480 scan / 640 enroll) was used.
# Higher variance = more high-frequency detail = sharper. Tunable per deployment:
#   FACE_BLUR_CHECK=0      -> disable the gate entirely
#   FACE_BLUR_MIN_VAR=NN   -> raise to demand sharper faces, lower if it false-rejects
# Every rejection (and the measured variance) is logged to stderr so the threshold
# can be tuned against real kiosk captures.
BLUR_CHECK = os.environ.get("FACE_BLUR_CHECK", "1") == "1"
try:
    BLUR_MIN_VAR = float(os.environ.get("FACE_BLUR_MIN_VAR", "45"))
except (TypeError, ValueError):
    BLUR_MIN_VAR = 45.0
BLUR_MESSAGE = "Face too blurry. Hold steady in good light and try again."

# Anti-spoofing (Silent-Face / MiniFASNet) lives in the face-attendance app repo.
# EHRMS reaches the sibling checkout by default; override with FACE_ANTISPOOF_DIR.
# Loading is lazy + attempted-once, and ALWAYS fail-open: a missing model or a
# missing torch logs one stderr line and lets the punch through (matches the face
# app — better to pass one spoof than brick every punch on a broken model).
_ANTISPOOF_DIR = os.environ.get("FACE_ANTISPOOF_DIR", os.path.abspath(os.path.join(
    SCRIPT_DIR, "..", "..", "..", "face", "face", "integrated-face-attendance",
    "face-attendance-system", "Silent-Face-Anti-Spoofing")))
_anti_spoof_test = None
_antispoof_attempted = False


def _load_antispoof():
    global _anti_spoof_test, _antispoof_attempted
    if _antispoof_attempted:
        return
    _antispoof_attempted = True
    try:
        if os.path.isdir(_ANTISPOOF_DIR) and _ANTISPOOF_DIR not in sys.path:
            sys.path.insert(0, _ANTISPOOF_DIR)
        from test import test as _t  # Silent-Face entrypoint: test(img, model_dir, device_id)
        _anti_spoof_test = _t
    except Exception as e:
        sys.stderr.write(f"[verify_core] anti-spoof unavailable (fail-open): {e}\n")
        sys.stderr.flush()


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


def _is_blurry(rgb, loc):
    """True only when the detected face crop is clearly blurry (variance of the
    Laplacian below BLUR_MIN_VAR). The crop is resized to a fixed 160x160 so one
    threshold is valid regardless of face size / detector downscale. Fail-OPEN: any
    measurement error returns False (never blocks a punch on a broken metric)."""
    if not BLUR_CHECK:
        return False
    import cv2
    try:
        top, right, bottom, left = loc
        top = max(0, top)
        left = max(0, left)
        bottom = max(top + 1, bottom)
        right = max(left + 1, right)
        crop = rgb[top:bottom, left:right]
        if crop.size == 0:
            return False
        gray = cv2.cvtColor(crop, cv2.COLOR_RGB2GRAY)
        gray = cv2.resize(gray, (160, 160), interpolation=cv2.INTER_AREA)
        var = float(cv2.Laplacian(gray, cv2.CV_64F).var())
        if var < BLUR_MIN_VAR:
            sys.stderr.write(
                f"[verify_core] blurry face rejected (lapVar={var:.1f} < {BLUR_MIN_VAR})\n")
            sys.stderr.flush()
            return True
        return False
    except Exception as e:
        sys.stderr.write(f"[verify_core] sharpness check skipped (fail-open): {e}\n")
        sys.stderr.flush()
        return False


def _largest_face_rgb_loc(img, max_w):
    """Downscale [img] (BGR) to [max_w] wide, then try rotations so selfies stored
    upside-down/sideways still resolve. Returns (rgb_used, loc) for the LARGEST face,
    or (None, None) if no face is found. Shared by embedding() and embed_for_enroll()
    so detection/rotation behaviour stays identical across the two."""
    import cv2
    import face_recognition

    h, w = img.shape[:2]
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
        loc = max(locs, key=lambda l: (l[2] - l[0]) * (l[1] - l[3]))
        return rgb, loc
    return None, None


def embedding(img):
    """Largest detected face's 128-D dlib descriptor, trying rotations so selfies
    stored upside-down/sideways still resolve. [img] is a BGR numpy array (as loaded
    by cv2). None if no face is found.

    NOTE: intentionally NOT sharpness-gated — this is the comparison path used by
    verify_images() (selfie vs a STORED reference photo, which may legitimately be
    soft). The blur gate lives in embed_for_enroll() (enroll) and embed_live() (live
    scan), where the capture is fresh and a clear face can always be re-taken."""
    import numpy as np
    import face_recognition

    rgb, loc = _largest_face_rgb_loc(img, 640)
    if loc is None:
        return None
    encs = face_recognition.face_encodings(rgb, [loc], num_jitters=1)
    if encs:
        return np.array(encs[0], dtype=float)
    return None


def embed_for_enroll(img):
    """Lenient ENROLL embedding (rotation retries, no positioning guards) PLUS the
    sharpness gate: a blurry capture is rejected so only a clear face is registered.
    [img] is a BGR numpy array. Returns (embedding|None, error|None)."""
    import numpy as np
    import face_recognition

    if img is None:
        return None, "Could not load image"
    rgb, loc = _largest_face_rgb_loc(img, 640)
    if loc is None:
        return None, "No face detected"
    if _is_blurry(rgb, loc):
        return None, BLUR_MESSAGE
    encs = face_recognition.face_encodings(rgb, [loc], num_jitters=1)
    if not encs:
        return None, "Could not extract face biometrics. Please try again."
    return np.array(encs[0], dtype=float), None


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


def embed_live(img):
    """STRICT live-scan embedding for a punch/break selfie.

    Ported faithfully from the face-attendance app's
    extract_face_worker.process_image: rejects a frame unless it has exactly one
    face that is centered, the right distance away, (optionally) frontal, and
    (optionally) passes anti-spoofing. Only then does it return a descriptor — so
    a spoofed or sloppy capture never yields a usable embedding.

    [img] is a BGR numpy array (cv2). Returns (embedding|None, error|None).

    NOTE: face_recognition is fed RGB here (cv2 gives BGR), unlike the face app
    which feeds BGR internally. This keeps the live descriptor directly comparable
    to the RGB enroll embeddings EHRMS already stored via embedding(); the face app
    is internally self-consistent on BGR, but EHRMS enrolled on RGB.
    """
    import cv2
    import numpy as np
    import face_recognition

    if img is None:
        return None, "Could not load image"

    # Escape hatch: skip the kiosk guards entirely and use the lenient embedding.
    if not LIVE_GUARDS:
        e = embedding(img)
        return (e, None) if e is not None else (None, "No face detected")

    # Resize for fast, predictable detection (guard thresholds are tuned to this).
    h, w = img.shape[:2]
    if w > SCAN_MAX_W:
        scale = SCAN_MAX_W / w
        img = cv2.resize(img, (0, 0), fx=scale, fy=scale)
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    # 1. Exactly one face.
    locs = face_recognition.face_locations(rgb)
    if len(locs) == 0:
        return None, "No face detected in feed. Please align your face inside the guide."
    if len(locs) > 1:
        return None, "Multiple faces detected! Only one person is allowed."

    # 1.5. Sharpness gate — a blurry / out-of-focus / motion-smeared face must not
    # produce a live embedding, so recognition stays accurate. Re-taking a steady,
    # in-focus frame is the fix. Disable/tune via FACE_BLUR_CHECK / FACE_BLUR_MIN_VAR.
    if _is_blurry(rgb, locs[0]):
        return None, BLUR_MESSAGE

    # 2. Centering + proximity — KIOSK-only (off by default; see FRAMING_CHECK).
    top, right, bottom, left = locs[0]
    face_w = right - left
    face_h = bottom - top
    cx = left + face_w // 2
    cy = top + face_h // 2
    if FRAMING_CHECK:
        tx = rgb.shape[1] // 2
        ty = rgb.shape[0] // 2
        if abs(cx - tx) > CENTER_TOL_X:
            return None, "Face off-center horizontally. Align with guide."
        if abs(cy - ty) > CENTER_TOL_Y:
            return None, "Face off-center vertically. Align with guide."
        if face_w < MIN_FACE_W:
            return None, "You are too far. Please move closer."
        if face_w > MAX_FACE_W:
            return None, "You are too close. Step back slightly."

    # 3. Optional frontal-pose symmetry check.
    if FRONTAL_CHECK:
        lm_list = face_recognition.face_landmarks(rgb, locs)
        if lm_list:
            lm = lm_list[0]
            nb = lm.get('nose_bridge', [])
            nose_x = (sum(p[0] for p in nb) / len(nb)) if nb else cx
            le = lm.get('left_eye', [])
            re = lm.get('right_eye', [])
            if le and re:
                left_eye_x = sum(p[0] for p in le) / len(le)
                right_eye_x = sum(p[0] for p in re) / len(re)
                dist_left = nose_x - left_eye_x
                dist_right = right_eye_x - nose_x
                total = dist_left + dist_right
                if total > 0:
                    ratio = dist_left / total
                    if ratio < 0.36 or ratio > 0.64:
                        return None, "Look straight at the camera. Side angles are not allowed."

    # 3.5. Anti-spoofing (passive single-image liveness). Genuine spoof verdict
    # (label != 1) blocks; any model/runtime failure fails OPEN.
    if LIVENESS_CHECK:
        _load_antispoof()
        if _anti_spoof_test is not None:
            try:
                model_dir = os.path.join(_ANTISPOOF_DIR, 'resources', 'anti_spoof_models')
                # Silent-Face expects a cv2 (BGR) frame — pass the un-converted img.
                label = _anti_spoof_test(img, model_dir, 0)
                if label != 1:
                    return None, "Spoof Alert! Digital screens or printed photos are not allowed."
            except Exception as ase:
                sys.stderr.write(f"[verify_core] liveness skipped (fail-open): {ase}\n")
                sys.stderr.flush()

    # 4. Extract the 128-D descriptor (RGB, num_jitters=1 for speed).
    encs = face_recognition.face_encodings(rgb, locs, num_jitters=1)
    if not encs:
        return None, "Could not extract face biometrics. Please try again."
    return np.array(encs[0], dtype=float), None


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
