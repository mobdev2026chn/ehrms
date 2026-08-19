#!/usr/bin/env python3
"""
Persistent face-verification HTTP service. Loads ArcFace ONCE at startup and answers
/verify in ~0.2-0.4s, so the punch flow can keep a hard face-match gate without
spawning Python and reloading the model on every punch.

Run:  uvicorn server:app --host 127.0.0.1 --port 5005   (cwd = this folder)
The Node backend posts to FACE_VERIFY_URL (default http://127.0.0.1:5005).
"""
from typing import Optional

from fastapi import FastAPI
from pydantic import BaseModel

import verify_core

app = FastAPI(title="EHRMS Face Verify")


class VerifyRequest(BaseModel):
    # Selfie: send either inline base64/data-url or a URL.
    selfie: Optional[str] = None
    selfie_url: Optional[str] = None
    # Reference (rolling face image): inline base64/data-url or a URL.
    reference: Optional[str] = None
    reference_url: Optional[str] = None


@app.on_event("startup")
def _startup():
    verify_core.warmup()


@app.get("/health")
def health():
    return {"ok": True, "model": verify_core.MODEL_NAME, "threshold": verify_core.THRESHOLD}


def _load(inline: Optional[str], url: Optional[str]):
    if inline:
        return verify_core.load_from_base64(inline)
    if url:
        return verify_core.load_from_url(url)
    return None


@app.post("/verify")
def verify(req: VerifyRequest):
    try:
        img1 = _load(req.selfie, req.selfie_url)
        img2 = _load(req.reference, req.reference_url)
        if img1 is None:
            return {"match": False, "error": "Could not load selfie"}
        if img2 is None:
            return {"match": False, "error": "Could not load reference"}
        return verify_core.verify_images(img1, img2)
    except Exception:
        return {"match": False, "error": "Face verification failed. Please try again."}


class EmbedRequest(BaseModel):
    # Image to embed: inline base64/data-url or a URL.
    image: Optional[str] = None
    image_url: Optional[str] = None


@app.post("/embed")
def embed(req: EmbedRequest):
    """Returns the 128-D dlib descriptor for the largest face in [image]. Used by the
    EHRMS face-enrollment flow (store the embedding once) and by verify-against-
    enrollment (embed the live selfie, compare to the stored samples)."""
    try:
        img = _load(req.image, req.image_url)
        if img is None:
            return {"embedding": None, "error": "Could not load image"}
        e = verify_core.embedding(img)
        if e is None:
            return {"embedding": None, "error": "No face detected"}
        return {"embedding": e.tolist(), "error": None}
    except Exception:
        return {"embedding": None, "error": "Face embedding failed. Please try again."}
