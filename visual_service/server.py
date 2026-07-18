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
import threading
from typing import Protocol
from urllib.parse import urlparse
import uuid


PARAMETERS = ("brightness", "warmth", "abstraction", "motion", "tension")
DEFAULT_DIFFUSERS_MODEL = "stabilityai/sdxl-turbo"
DEFAULT_IMAGE_WIDTH = 1024
DEFAULT_IMAGE_HEIGHT = 576
DEFAULT_GENERATION_HISTORY_LIMIT = 16


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

    def health(self) -> dict[str, object]: ...


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
    return (
        f"museum-quality Impressionist oil painting, {light} {temperature} palette, "
        f"layered broken-color paint and {gesture} brush strokes, subtle woven canvas texture, "
        f"{mood} atmosphere, abstraction {state['abstraction']:.2f}, preserve the exact subjects, "
        "horizon, spatial arrangement, and underlying composition of the reference painting, "
        "one continuous evolving artwork, no new scene, no hard scene cut, no text, no frame"
    )


class MockBackend:
    name = "mock"

    def health(self) -> dict[str, object]:
        return {"ok": True, "backend": self.name}

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


@dataclass(frozen=True)
class DiffusionSettings:
    strength: float
    num_inference_steps: int
    guidance_scale: float
    original_weight: float
    seed: int


@dataclass(frozen=True)
class DriftConfiguration:
    original_anchor_low: float = 0.72
    original_anchor_high: float = 0.50
    output_anchor_low: float = 0.16
    output_anchor_high: float = 0.08
    pullback_interval: int = 5
    pullback_boost: float = 0.10

    def __post_init__(self):
        weights = (
            self.original_anchor_low,
            self.original_anchor_high,
            self.output_anchor_low,
            self.output_anchor_high,
            self.pullback_boost,
        )
        if any(not 0 <= value <= 1 for value in weights):
            raise BackendUnavailable("drift-control weights must be within 0...1")
        if self.original_anchor_low < self.original_anchor_high:
            raise BackendUnavailable("low-abstraction original anchor must not be weaker than high-abstraction anchor")
        if self.output_anchor_low < self.output_anchor_high:
            raise BackendUnavailable("low-abstraction output anchor must not be weaker than high-abstraction anchor")
        if self.pullback_interval < 0:
            raise BackendUnavailable("pull-back interval must be zero or positive")


def _interpolate(low_abstraction: float, high_abstraction: float, abstraction: float) -> float:
    return low_abstraction + (high_abstraction - low_abstraction) * abstraction


def diffusion_settings(
    state: dict[str, float],
    sequence: int,
    turbo: bool,
    drift: DriftConfiguration | None = None,
) -> DiffusionSettings:
    """Map normalized world state to bounded, model-safe diffusion controls."""
    drift = drift or DriftConfiguration()
    # Keep Turbo below the two-effective-step boundary. At four inference
    # steps, strength >= 0.5 can replace the scene abruptly instead of evolving
    # its paint surface.
    strength = min(0.49, 0.25 + state["abstraction"] * 0.18 + state["motion"] * 0.06)
    steps = 4 if turbo else max(12, round(16 + state["abstraction"] * 8 + state["motion"] * 4))
    # Turbo checkpoints are explicitly trained without classifier-free guidance.
    guidance = 0.0 if turbo else 3.5 + state["tension"] * 3.0
    original_weight = _interpolate(
        drift.original_anchor_low,
        drift.original_anchor_high,
        state["abstraction"],
    )
    generation_number = sequence + 1
    if drift.pullback_interval and generation_number % drift.pullback_interval == 0:
        original_weight = min(0.90, original_weight + drift.pullback_boost)
    state_key = ":".join(f"{state[key]:.4f}" for key in PARAMETERS)
    seed_key = f"{state_key}:{sequence}:{round(state['motion'] * 1000)}"
    seed = int(hashlib.sha256(seed_key.encode()).hexdigest()[:8], 16)
    return DiffusionSettings(strength, steps, guidance, original_weight, seed)


def model_load_source(model_id: str) -> str:
    """Resolve a downloaded Hub ID to its concrete snapshot in offline mode."""
    expanded = Path(model_id).expanduser()
    if expanded.exists():
        return str(expanded)
    if os.environ.get("HF_HUB_OFFLINE") != "1" or "/" not in model_id:
        return model_id
    default_home = Path.home() / ".cache" / "huggingface"
    hub_root = Path(os.environ.get("HF_HUB_CACHE", Path(os.environ.get("HF_HOME", default_home)) / "hub"))
    repository = hub_root / f"models--{model_id.replace('/', '--')}"
    reference = repository / "refs" / "main"
    try:
        revision = reference.read_text().strip()
    except OSError:
        return model_id
    snapshot = repository / "snapshots" / revision
    return str(snapshot) if (snapshot / "model_index.json").is_file() else model_id


class DiffusersBackend:
    name = "diffusers"

    def __init__(
        self,
        model_id: str = DEFAULT_DIFFUSERS_MODEL,
        *,
        width: int = DEFAULT_IMAGE_WIDTH,
        height: int = DEFAULT_IMAGE_HEIGHT,
        drift: DriftConfiguration | None = None,
        pipeline=None,
        torch_module=None,
        device: str | None = None,
    ):
        if width < 64 or height < 64 or width % 8 or height % 8:
            raise BackendUnavailable("diffusion dimensions must be multiples of 8 and at least 64 pixels")
        self.model_id = model_id
        self.width = width
        self.height = height
        self.turbo = model_id.rstrip("/").endswith("turbo")
        self.drift = drift or DriftConfiguration()
        self._sequence = 0
        self._lock = threading.Lock()

        if pipeline is not None:
            self.pipeline = pipeline
            self._torch = torch_module
            self.device = device or "test"
            return
        try:
            import torch
            from diffusers import AutoPipelineForImage2Image
            from PIL import Image  # noqa: F401 - verify the complete runtime at startup
        except ImportError as error:
            raise BackendUnavailable("diffusers backend requires torch, diffusers, transformers, accelerate, and Pillow") from error
        self._torch = torch
        self.device = device or ("mps" if torch.backends.mps.is_available() else "cpu")
        dtype = torch.float16 if self.device == "mps" else torch.float32
        load_options = {"torch_dtype": dtype, "use_safetensors": True}
        if dtype == torch.float16:
            load_options["variant"] = "fp16"
        try:
            self.pipeline = AutoPipelineForImage2Image.from_pretrained(model_load_source(model_id), **load_options)
            self.pipeline.to(self.device)
            if self.device == "mps" and os.environ.get("EVOLVING_ATTENTION_SLICING") == "1":
                self.pipeline.enable_attention_slicing()
        except Exception as error:
            raise BackendUnavailable(f"could not load diffusion model {model_id}: {error}") from error

    def health(self) -> dict[str, object]:
        return {
            "ok": True,
            "backend": self.name,
            "model": self.model_id,
            "device": self.device,
            "width": self.width,
            "height": self.height,
            "mediaType": "image/png",
            "resizeMode": "center-crop",
            "driftControl": {
                "originalAnchorLowAbstraction": self.drift.original_anchor_low,
                "originalAnchorHighAbstraction": self.drift.original_anchor_high,
                "outputAnchorLowAbstraction": self.drift.output_anchor_low,
                "outputAnchorHighAbstraction": self.drift.output_anchor_high,
                "pullbackInterval": self.drift.pullback_interval,
                "pullbackBoost": self.drift.pullback_boost,
            },
        }

    def _source_image(self, state: dict[str, float], original: bytes | None, previous: bytes | None, settings: DiffusionSettings):
        try:
            from PIL import Image, ImageOps, UnidentifiedImageError
        except ImportError as error:
            raise BackendUnavailable("diffusers backend requires Pillow") from error
        if not original and not previous:
            raise RequestError("diffusers mode requires an original image or a previous generation")
        try:
            original_image = Image.open(io.BytesIO(original or previous)).convert("RGB")
            previous_image = Image.open(io.BytesIO(previous or original)).convert("RGB")
        except (UnidentifiedImageError, OSError) as error:
            raise RequestError(f"reference image could not be decoded: {error}") from error

        size = (self.width, self.height)
        original_image = ImageOps.fit(original_image, size, method=Image.Resampling.LANCZOS)
        previous_image = ImageOps.fit(previous_image, size, method=Image.Resampling.LANCZOS)
        source = Image.blend(previous_image, original_image, settings.original_weight)

        return source

    @staticmethod
    def _grade_image(image, state: dict[str, float]):
        from PIL import Image, ImageEnhance

        # Deterministic finishing makes these controls reliable even when a model
        # responds weakly to the equivalent prompt language.
        image = ImageEnhance.Brightness(image).enhance(0.82 + state["brightness"] * 0.36)
        red, green, blue = image.split()
        warmth = state["warmth"] - 0.5
        red = red.point(lambda value: max(0, min(255, value * (1.0 + warmth * 0.22))))
        blue = blue.point(lambda value: max(0, min(255, value * (1.0 - warmth * 0.22))))
        image = Image.merge("RGB", (red, green, blue))
        image = ImageEnhance.Contrast(image).enhance(0.88 + state["tension"] * 0.30)
        return ImageEnhance.Sharpness(image).enhance(0.92 + state["tension"] * 0.22)

    def generate(self, state: dict[str, float], original: bytes | None, previous: bytes | None) -> GenerationResult:
        with self._lock:
            settings = diffusion_settings(state, self._sequence, self.turbo, self.drift)
            self._sequence += 1
            source = self._source_image(state, original, previous, settings)
            options = {
                "prompt": prompt_for(state),
                "image": source,
                "strength": settings.strength,
                "num_inference_steps": settings.num_inference_steps,
                "guidance_scale": settings.guidance_scale,
            }
            if self._torch is not None:
                options["generator"] = self._torch.Generator(device="cpu").manual_seed(settings.seed)
            output = self.pipeline(**options).images[0].convert("RGB")
            if original:
                from PIL import Image, ImageOps

                original_image = Image.open(io.BytesIO(original)).convert("RGB")
                original_image = ImageOps.fit(
                    original_image,
                    (self.width, self.height),
                    method=Image.Resampling.LANCZOS,
                )
                output_anchor = _interpolate(
                    self.drift.output_anchor_low,
                    self.drift.output_anchor_high,
                    state["abstraction"],
                )
                output = Image.blend(output, original_image, output_anchor)
            output = self._grade_image(output, state)
        encoded = io.BytesIO()
        output.save(encoded, format="PNG")
        return GenerationResult(encoded.getvalue(), "image/png", prompt_for(state))


class GenerationStore:
    def __init__(self, limit: int = DEFAULT_GENERATION_HISTORY_LIMIT):
        if limit < 1:
            raise ValueError("generation history limit must be positive")
        self._items: OrderedDict[str, bytes] = OrderedDict()
        self.limit = limit
        self._lock = threading.Lock()

    def put(self, value: bytes) -> str:
        generation_id = uuid.uuid4().hex
        with self._lock:
            self._items[generation_id] = value
            while len(self._items) > self.limit:
                self._items.popitem(last=False)
        return generation_id

    def get(self, generation_id: str | None) -> bytes | None:
        if not generation_id:
            return None
        with self._lock:
            value = self._items.get(generation_id)
            if value is not None:
                self._items.move_to_end(generation_id)
            return value


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
                health = getattr(backend, "health", None)
                self._send(200, health() if health else {"ok": True, "backend": backend.name})
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
                previous = store.get(previous_id)
                result = backend.generate(state, original, previous)
                generation_id = store.put(result.image)
                self._send(200, {
                    "imageBase64": base64.b64encode(result.image).decode(),
                    "mediaType": result.media_type,
                    "generationID": generation_id,
                    "prompt": result.prompt,
                    "backend": backend.name,
                    "referenceUsage": {
                        "originalImage": original is not None,
                        "previousImage": previous is not None,
                    },
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
        model_id = os.environ.get("EVOLVING_MODEL_ID", DEFAULT_DIFFUSERS_MODEL)
        try:
            width = int(os.environ.get("EVOLVING_IMAGE_WIDTH", str(DEFAULT_IMAGE_WIDTH)))
            height = int(os.environ.get("EVOLVING_IMAGE_HEIGHT", str(DEFAULT_IMAGE_HEIGHT)))
            drift = DriftConfiguration(
                original_anchor_low=float(os.environ.get("EVOLVING_ORIGINAL_ANCHOR_LOW", "0.72")),
                original_anchor_high=float(os.environ.get("EVOLVING_ORIGINAL_ANCHOR_HIGH", "0.50")),
                output_anchor_low=float(os.environ.get("EVOLVING_OUTPUT_ANCHOR_LOW", "0.16")),
                output_anchor_high=float(os.environ.get("EVOLVING_OUTPUT_ANCHOR_HIGH", "0.08")),
                pullback_interval=int(os.environ.get("EVOLVING_PULLBACK_INTERVAL", "5")),
                pullback_boost=float(os.environ.get("EVOLVING_PULLBACK_BOOST", "0.10")),
            )
        except ValueError as error:
            raise BackendUnavailable("diffusion dimensions and drift controls must be numeric") from error
        return DiffusersBackend(model_id, width=width, height=height, drift=drift)
    raise BackendUnavailable(f"unknown EVOLVING_BACKEND: {mode}")


if __name__ == "__main__":
    active_backend = configured_backend()
    service = create_server(port=int(os.environ.get("EVOLVING_VISUAL_PORT", "8000")), backend=active_backend)
    print(f"Evolving Impressionist visual service ({active_backend.name}) listening on http://{service.server_address[0]}:{service.server_address[1]}", flush=True)
    try:
        service.serve_forever()
    except KeyboardInterrupt:
        print("Evolving Impressionist visual service stopped", flush=True)
    finally:
        service.server_close()
