#!/usr/bin/env python3
"""Local visual generation service with mock and optional Diffusers backends."""
from __future__ import annotations

import base64
from collections import OrderedDict
from dataclasses import dataclass
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import math
import os
from pathlib import Path
import random
from typing import Protocol
from urllib.parse import urlparse
import uuid


PARAMETERS = ("brightness", "warmth", "abstraction", "motion", "tension")


class RequestError(ValueError):
    pass


class BackendUnavailable(RuntimeError):
    pass


@dataclass(frozen=True)
class GenerationResult:
    image: bytes
    media_type: str
    prompt: str


class VisualBackend(Protocol):
    name: str

    def generate(self, state: dict[str, float], original: bytes | None, previous: bytes | None) -> GenerationResult: ...


def parse_request(payload: object) -> tuple[dict[str, float], str | None, str | None]:
    if not isinstance(payload, dict):
        raise RequestError("request body must be a JSON object")
    state = payload.get("state")
    reference = payload.get("reference")
    if not isinstance(state, dict) or not isinstance(reference, dict):
        raise RequestError("state and reference objects are required")
    parsed: dict[str, float] = {}
    for key in PARAMETERS:
        value = state.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise RequestError(f"{key} must be numeric")
        value = float(value)
        if not math.isfinite(value) or not 0 <= value <= 1:
            raise RequestError(f"{key} must be within 0...1")
        parsed[key] = value
    original_path = reference.get("originalImagePath")
    previous_id = reference.get("previousGenerationID")
    if original_path is not None and not isinstance(original_path, str):
        raise RequestError("originalImagePath must be a string or null")
    if previous_id is not None and not isinstance(previous_id, str):
        raise RequestError("previousGenerationID must be a string or null")
    return parsed, original_path, previous_id


def prompt_for(state: dict[str, float]) -> str:
    light = "soft moonlit" if state["brightness"] < .35 else "luminous golden" if state["brightness"] > .65 else "diffused daylight"
    temperature = "cool blue-green" if state["warmth"] < .4 else "amber and rose" if state["warmth"] > .65 else "pearl and lavender"
    gesture = "restless sweeping" if state["motion"] > .65 else "slow visible" if state["motion"] > .35 else "quiet delicate"
    mood = "unsettled high-contrast" if state["tension"] > .65 else "serene balanced" if state["tension"] < .35 else "expectant"
    return f"{light} {temperature} impressionist painting, {gesture} brush strokes, {mood} atmosphere, abstraction {state['abstraction']:.2f}, preserve the original composition, no hard scene cut"


class MockBackend:
    name = "mock"

    def generate(self, state: dict[str, float], original: bytes | None, previous: bytes | None) -> GenerationResult:
        reference_digest = hashlib.sha256((original or b"original") + (previous or b"previous")).hexdigest()
        seed_material = json.dumps(state, sort_keys=True) + reference_digest
        rng = random.Random(int(hashlib.sha256(seed_material.encode()).hexdigest()[:12], 16))
        width, height = 1600, 1000
        light = int(40 + 52 * state["brightness"])
        warmth = int(150 * state["warmth"])
        blue = int(180 - 110 * state["warmth"])
        contrast = 0.55 + state["tension"] * .5
        strokes = []
        count = int(55 + state["abstraction"] * 100)
        for _ in range(count):
            x, y = rng.uniform(-.05, 1.05) * width, rng.uniform(-.08, 1.08) * height
            radius = rng.uniform(25, 130) * (.75 + state["motion"])
            alpha = rng.uniform(.08, .25) * contrast
            hue = rng.randint(-20, 20)
            color = f"rgb({max(0,min(255, light + warmth//2 + hue))},{max(0,min(255, light + warmth//3 + hue))},{max(0,min(255, blue + light//3))})"
            strokes.append(f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="{radius:.1f}" ry="{radius*rng.uniform(.35,.9):.1f}" fill="{color}" opacity="{alpha:.3f}" transform="rotate({rng.uniform(-35,35):.1f} {x:.1f} {y:.1f})"/>')
        svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<defs><linearGradient id="sky" x1="0" y1="0" x2="1" y2="1"><stop stop-color="rgb({light+warmth//2},{light+warmth//3},{blue})"/><stop offset="1" stop-color="rgb({max(10,light//3)},{max(15,light//4)},{max(30,blue//2)})"/></linearGradient><filter id="blur"><feGaussianBlur stdDeviation="{3+state['abstraction']*8:.1f}"/></filter></defs>
<rect width="100%" height="100%" fill="url(#sky)"/><g filter="url(#blur)">{''.join(strokes)}</g>
<path d="M0 {height*.72:.0f} Q{width*.25:.0f} {height*.58:.0f} {width*.5:.0f} {height*.72:.0f} T{width} {height*.65:.0f} V{height} H0Z" fill="rgb({30+warmth//3},{40+warmth//4},{80+blue//3})" opacity=".48"/>
</svg>'''.encode()
        return GenerationResult(svg, "image/svg+xml", prompt_for(state))


class DiffusersBackend:
    name = "diffusers"

    def __init__(self, model_id: str):
        try:
            import torch
            from diffusers import AutoPipelineForImage2Image
        except ImportError as error:
            raise BackendUnavailable("diffusers backend requires torch, diffusers, and Pillow") from error
        dtype = torch.float16 if torch.backends.mps.is_available() else torch.float32
        self.pipeline = AutoPipelineForImage2Image.from_pretrained(model_id, torch_dtype=dtype)
        self.pipeline.to("mps" if torch.backends.mps.is_available() else "cpu")

    def generate(self, state: dict[str, float], original: bytes | None, previous: bytes | None) -> GenerationResult:
        try:
            from PIL import Image, ImageEnhance
        except ImportError as error:
            raise BackendUnavailable("diffusers backend requires Pillow") from error
        if not original and not previous:
            raise RequestError("diffusers mode requires EVOLVING_ORIGINAL_IMAGE or a previous generation")
        original_image = Image.open(io.BytesIO(original or previous)).convert("RGB")
        previous_image = Image.open(io.BytesIO(previous or original)).convert("RGB").resize(original_image.size)
        # Low abstraction repeatedly anchors more strongly to the original.
        source = Image.blend(original_image, previous_image, 0.25 + state["abstraction"] * 0.65)
        source = ImageEnhance.Brightness(source).enhance(0.7 + state["brightness"] * 0.6)
        strength = 0.18 + state["abstraction"] * 0.55 + state["motion"] * 0.08
        output = self.pipeline(prompt=prompt_for(state), image=source, strength=min(.85, strength), guidance_scale=4 + state["tension"] * 4).images[0]
        encoded = io.BytesIO()
        output.save(encoded, format="PNG")
        return GenerationResult(encoded.getvalue(), "image/png", prompt_for(state))


class GenerationStore:
    def __init__(self, limit: int = 12):
        self._items: OrderedDict[str, bytes] = OrderedDict()
        self.limit = limit

    def put(self, value: bytes) -> str:
        generation_id = uuid.uuid4().hex
        self._items[generation_id] = value
        while len(self._items) > self.limit:
            self._items.popitem(last=False)
        return generation_id

    def get(self, generation_id: str | None) -> bytes | None:
        return self._items.get(generation_id) if generation_id else None


def handler_for(backend: VisualBackend, store: GenerationStore):
    class Handler(BaseHTTPRequestHandler):
        def _send(self, status: int, body: dict):
            encoded = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

        def do_GET(self):
            if urlparse(self.path).path == "/health":
                self._send(200, {"ok": True, "backend": backend.name})
            else:
                self._send(404, {"error": "not found"})

        def do_POST(self):
            if urlparse(self.path).path != "/generate":
                self._send(404, {"error": "not found"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                payload = json.loads(self.rfile.read(length))
                state, original_path, previous_id = parse_request(payload)
                original = Path(original_path).expanduser().read_bytes() if original_path else None
                result = backend.generate(state, original, store.get(previous_id))
                generation_id = store.put(result.image)
                self._send(200, {
                    "imageBase64": base64.b64encode(result.image).decode(),
                    "mediaType": result.media_type,
                    "generationID": generation_id,
                    "prompt": result.prompt,
                    "backend": backend.name,
                })
            except (RequestError, ValueError, TypeError, json.JSONDecodeError) as error:
                self._send(400, {"error": str(error)})
            except FileNotFoundError as error:
                self._send(400, {"error": f"reference image not found: {error.filename}"})
            except BackendUnavailable as error:
                self._send(503, {"error": str(error)})
            except Exception as error:
                self._send(500, {"error": f"generation failed: {error}"})

        def log_message(self, format, *args):
            if os.environ.get("EVOLVING_QUIET") != "1":
                print(f"[visual-service] {format % args}", flush=True)

    return Handler


def create_server(host: str = "127.0.0.1", port: int = 8000, backend: VisualBackend | None = None):
    backend = backend or MockBackend()
    return ThreadingHTTPServer((host, port), handler_for(backend, GenerationStore()))


def configured_backend() -> VisualBackend:
    mode = os.environ.get("EVOLVING_BACKEND", "mock").lower()
    if mode == "mock":
        return MockBackend()
    if mode == "diffusers":
        model_id = os.environ.get("EVOLVING_MODEL_ID")
        if not model_id:
            raise BackendUnavailable("EVOLVING_MODEL_ID is required for diffusers mode")
        return DiffusersBackend(model_id)
    raise BackendUnavailable(f"unknown EVOLVING_BACKEND: {mode}")


if __name__ == "__main__":
    service = create_server(port=int(os.environ.get("EVOLVING_VISUAL_PORT", "8000")), backend=configured_backend())
    print(f"Evolving Impressionist visual service ({service.RequestHandlerClass.__name__}) listening on http://{service.server_address[0]}:{service.server_address[1]}", flush=True)
    try:
        service.serve_forever()
    except KeyboardInterrupt:
        print("Evolving Impressionist visual service stopped", flush=True)
    finally:
        service.server_close()
