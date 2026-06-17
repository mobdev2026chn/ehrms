#!/usr/bin/env python3
"""
Compare two face images using DeepFace.
Usage: face_verify.py <path_to_image1> <path_to_image2>
Outputs JSON: {"match": true|false, "error": null|str}
"""
import json
import sys
import os

# Set weights dir before importing deepface so it uses project folder (avoids GitHub download issues)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
os.environ["DEEPFACE_HOME"] = SCRIPT_DIR
# DeepFace stores weights at DEEPFACE_HOME/.deepface/weights/
WEIGHTS_DIR = os.path.join(SCRIPT_DIR, ".deepface", "weights")
os.makedirs(WEIGHTS_DIR, exist_ok=True)

OPENFACE_URL = "https://github.com/serengil/deepface_models/releases/download/v1.0/openface_weights.h5"
OPENFACE_PATH = os.path.join(WEIGHTS_DIR, "openface_weights.h5")


def _ensure_openface_weights():
    if os.path.isfile(OPENFACE_PATH):
        return True
    try:
        import urllib.request
        urllib.request.urlretrieve(OPENFACE_URL, OPENFACE_PATH)
        return os.path.isfile(OPENFACE_PATH)
    except Exception:
        return False


def main():
    if len(sys.argv) < 3:
        out = {"match": False, "error": "Usage: face_verify.py <path1> <path2>"}
        print(json.dumps(out))
        sys.exit(1)

    path1, path2 = sys.argv[1], sys.argv[2]
    
    if not os.path.exists(path1):
        print(json.dumps({"match": False, "error": "Selfie file not found"}))
        sys.exit(1)
    if not os.path.exists(path2):
        print(json.dumps({"match": False, "error": "Profile photo file not found"}))
        sys.exit(1)

    _ensure_openface_weights()

    try:
        from deepface import DeepFace
    except ImportError:
        print(json.dumps({
            "match": False,
            "error": "DeepFace not installed. Run: pip install deepface in face_verify venv."
        }))
        sys.exit(1)

    # Lenient thresholds — match the punch selfie against the previous/profile image
    # without over-rejecting on lighting/angle. (Raised from 0.15; OpenFace for speed.)
    model_name = 'OpenFace'
    threshold = 0.40
    lenient_cap = 0.45

    try:
        result = DeepFace.verify(
            img1_path=path1,
            img2_path=path2,
            model_name=model_name,
            detector_backend='opencv',
            enforce_detection=True,
            threshold=threshold,
            distance_metric='cosine'
        )
        v = result.get('verified', False)
        d = result.get('distance')
        if d is not None and d <= lenient_cap and d <= threshold * 1.15:
            v = True
        if v:
            print(json.dumps({"match": True}))
        else:
            print(json.dumps({"match": False, "error": "Face not matching"}))
        sys.exit(0)
    except ValueError as e:
        error_msg = str(e)
        if 'Face could not be detected' in error_msg or 'no face' in error_msg.lower():
            print(json.dumps({"match": False, "error": "No face detected in one or both images"}))
        else:
            print(json.dumps({"match": False, "error": "Face not matching"}))
        sys.exit(0)
    except Exception as e:
        err = str(e)
        print(json.dumps({"match": False, "error": "Face verification failed. Please try again."}))
        sys.exit(1)


if __name__ == "__main__":
    main()
