# Local visual service

The service keeps two interchangeable backends behind the same HTTP contract:

- `mock` is the dependency-free SVG fallback and remains the default.
- `diffusers` is real Img2Img generation. The proven Apple Silicon model is
  [`stabilityai/sd-turbo`](https://huggingface.co/stabilityai/sd-turbo), using
  PyTorch MPS at 512×512 and four inference steps.

## Mock backend

From the repository root:

```sh
uv sync --frozen
EVOLVING_BACKEND=mock uv run --frozen python visual_service/server.py
```

## Reproducible Diffusers installation

`uv` selects the pinned Python 3.13 runtime and resolves the versions exercised
by the verification report from `pyproject.toml` and `uv.lock`. The diffusion
stack remains an optional extra, so mock mode still installs no third-party
packages.

```sh
uv sync --frozen --extra diffusion
```

Start the real backend:

```sh
HF_HUB_DISABLE_XET=1 \
EVOLVING_BACKEND=diffusers \
uv run --frozen --extra diffusion python visual_service/server.py
```

The first launch downloads approximately 2.6 GB of fp16 model components.
Later launches reuse the Hugging Face cache and can run offline; set
`HF_HUB_OFFLINE=1` to force the cached snapshot path. Override the
default only when intentionally testing another Img2Img-compatible checkpoint:

```sh
EVOLVING_MODEL_ID=/absolute/path/or/hugging-face-id \
EVOLVING_BACKEND=diffusers \
uv run --frozen --extra diffusion python visual_service/server.py
```

`EVOLVING_IMAGE_WIDTH` and `EVOLVING_IMAGE_HEIGHT` default to 512 and must be
multiples of eight. `EVOLVING_ATTENTION_SLICING=1` trades speed for lower peak
memory pressure on smaller Macs.

Pass an original painting path to Swift:

```sh
EVOLVING_ORIGINAL_IMAGE=/absolute/path/to/painting.jpg \
swift run EvolvingImpressionist
```

The path is read by the local Python service. The Swift request also carries
the prior `generationID`, allowing the service to combine the original and
previous generated raster on later cycles.

Generated raster history is a thread-safe, bounded LRU containing at most 16
frames. The normal chain only needs the latest predecessor; the additional
entries tolerate retries or slightly delayed requests without allowing memory
usage to grow over a long-running exhibition.

## WorldState mapping and drift control

| State | Diffusion mapping |
| --- | --- |
| brightness | Source exposure plus prompt illumination |
| warmth | Red/blue source color-temperature scaling plus palette prompt |
| abstraction | Img2Img strength and reduced—but never removed—original anchor |
| motion | Img2Img strength, changing deterministic seed, and brush-motion prompt |
| tension | Source contrast, atmosphere prompt, and CFG for non-Turbo models |

For SD-Turbo, classifier-free guidance is correctly disabled. Four steps and a
minimum strength of 0.25 satisfy the model's Img2Img requirement that
`steps × strength >= 1`.

Each sequential source is a blend of the previous generated image and the
original painting. The original weight ranges from 55% at low abstraction to
30% at maximum abstraction, so iterative generations cannot silently lose the
anchor. Brightness, temperature, and contrast adjustments are applied after
the blend. A backend lock prevents concurrent access to the non-thread-safe
MPS pipeline.

## API and verification

`GET /health` identifies the active backend. Diffusers mode also reports the
model, device, output dimensions, and raster media type.

`POST /generate` accepts:

```json
{"state":{"brightness":0.6,"warmth":0.7,"abstraction":0.3,"motion":0.4,"tension":0.2},"reference":{"originalImagePath":"/absolute/path/to/painting.jpg","previousGenerationID":null}}
```

Successful responses include `referenceUsage.originalImage` and
`referenceUsage.previousImage`. These backend-neutral booleans let verification
confirm that the service resolved each requested source; Swift does not need to
know which model or drift-control algorithm consumed them.

Run backend tests in the real environment:

```sh
uv run --frozen --extra diffusion python -m py_compile visual_service/server.py visual_service/verify_real.py
uv run --frozen --extra diffusion python -m unittest discover -s visual_service/tests -v
```

With the real service running, exercise two sequential generations, assert the
original/prior-frame reference chain, decode the returned PNGs with Pillow, send
an invalid raster reference, and confirm the service remains healthy:

```sh
uv run --frozen --extra diffusion python visual_service/verify_real.py \
  --original /absolute/path/to/painting.jpg
```

Verify the same real responses through Swift and AppKit:

```sh
VISUAL_SERVICE_URL=http://127.0.0.1:8000 \
EXPECTED_VISUAL_BACKEND=diffusers \
EVOLVING_ORIGINAL_IMAGE=/absolute/path/to/painting.jpg \
swift run EvolvingImpressionistVerify
```

The service converts invalid references into controlled JSON errors. Swift's
`VisualService` changes `currentImage` and `previousGenerationID` only after a
response has decoded successfully, so an HTTP/model/decode failure preserves
the last valid frame. Selecting `EVOLVING_BACKEND=mock` remains the explicit,
dependency-free fallback.
