#!/usr/bin/env python3
"""
One-shot face comparison (CLI) — the FALLBACK used when the persistent service
(server.py) is unreachable. Slow (reloads the model each run); the service is the
fast path.

Usage: face_verify.py <path_to_image1> <path_to_image2>
Outputs JSON: {"match": true|false, "error": null|str}
"""
import json
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def _out(obj, code=0):
    print(json.dumps(obj))
    sys.exit(code)


def main():
    if len(sys.argv) < 3:
        _out({"match": False, "error": "Usage: face_verify.py <path1> <path2>"}, 1)

    path1, path2 = sys.argv[1], sys.argv[2]
    if not os.path.exists(path1):
        _out({"match": False, "error": "Selfie file not found"}, 1)
    if not os.path.exists(path2):
        _out({"match": False, "error": "Reference photo file not found"}, 1)

    try:
        import verify_core
    except Exception:
        _out({"match": False, "error": "Face verification not available"}, 1)

    verify_core.ensure_weights()
    try:
        img1 = verify_core.load_from_path(path1)
        img2 = verify_core.load_from_path(path2)
        result = verify_core.verify_images(img1, img2)
        _out({
            "match": bool(result.get("match")),
            "distance": result.get("distance"),
            "error": result.get("error"),
        })
    except Exception:
        _out({"match": False, "error": "Face verification failed. Please try again."}, 1)


if __name__ == "__main__":
    main()
