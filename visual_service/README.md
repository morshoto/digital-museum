# Local visual service

The service keeps two interchangeable backends behind the same HTTP contract:

- `mock` is the dependency-free SVG fallback and remains the default.
- `diffusers` is real Img2Img generation. The selected Apple Silicon model is
  [`stabilityai/sdxl-turbo`](https://huggingface.co/stabilityai/sdxl-turbo),
  using PyTorch MPS at 1024×576 and four inference steps.

The prior SD-Turbo model card explicitly recommends the larger SDXL Turbo for
increased quality and prompt understanding. SDXL Turbo retains the required
1–4-step distilled inference and supports the same Diffusers Img2Img pipeline,
making it the practical quality upgrade without changing the service contract.

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

The first launch downloads the fp16 SDXL Turbo components (approximately 7 GB).
Later launches reuse the Hugging Face cache and can run offline; set
`HF_HUB_OFFLINE=1` to force the cached snapshot path. Override the
default only when intentionally testing another Img2Img-compatible checkpoint:

```sh
EVOLVING_MODEL_ID=/absolute/path/or/hugging-face-id \
EVOLVING_BACKEND=diffusers \
uv run --frozen --extra diffusion python visual_service/server.py
```

`EVOLVING_IMAGE_WIDTH` and `EVOLVING_IMAGE_HEIGHT` default to 1024 and 576 and
must be multiples of eight. References are resized with a LANCZOS center crop,
never stretched. The default exactly matches a 16:9 installation display;
override both dimensions for another display ratio. `EVOLVING_ATTENTION_SLICING=1`
trades speed for lower peak memory pressure on smaller Macs.

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

The unchanged five-field request is converted into the deterministic shared
artistic state documented in [`../docs/SHARED_ARTISTIC_STATE.md`](../docs/SHARED_ARTISTIC_STATE.md).

| Artistic quality | Diffusion mapping |
| --- | --- |
| luminosity | Final exposure plus prompt illumination |
| fluidity | Bounded Img2Img strength modifier, flowing gesture prompt, and mock stroke deformation |
| instability | Bounded strength modifier, final contrast/sharpness, structural prompt, and non-Turbo CFG |
| serenity | Additional original-image anchoring and composition-preservation prompt |
| density | Non-Turbo step count, texture prompt, and mock stroke count |

Raw `warmth` retains red/blue source color-temperature scaling and palette
language. The generation sequence still changes the deterministic seed so
successive frames evolve without adding an independent artistic-state input.
Abstraction remains a hard divergence constraint: strength is capped by
`0.30 + 0.19 × abstraction` and never reaches the global `0.49` Turbo
scene-replacement boundary. Fluidity and instability shape deformation only
inside that allowance.

For SDXL Turbo, classifier-free guidance is correctly disabled. Four steps and
a minimum strength of 0.25 satisfy the model's Img2Img requirement that
`steps × strength >= 1`.

Each sequential source is a blend of the previous generated image and the
original painting. Continuous original weight ranges from 72% at zero
abstraction to 50% at maximum abstraction, with serenity adding up to four
percentage points of preservation. Every fifth generation adds a 10% pull-back,
and the generated result receives a second 16%→8% original blend before
deterministic artistic-state finishing. These controls stop repeated Img2Img
from becoming an unanchored random walk while still allowing visible evolution.
A backend lock prevents concurrent access to the non-thread-safe MPS pipeline.

Drift behavior is configurable without changing the HTTP contract:

```text
EVOLVING_ORIGINAL_ANCHOR_LOW=0.72
EVOLVING_ORIGINAL_ANCHOR_HIGH=0.50
EVOLVING_OUTPUT_ANCHOR_LOW=0.16
EVOLVING_OUTPUT_ANCHOR_HIGH=0.08
EVOLVING_PULLBACK_INTERVAL=5
EVOLVING_PULLBACK_BOOST=0.10
```

`LOW` and `HIGH` refer to abstraction, not numeric anchor magnitude. Set the
interval to `0` to disable periodic pull-back. `/health` reports the effective
model, dimensions, crop mode, and drift settings.

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

With the real service running, exercise 20 sequential generations plus
controlled abstraction/brightness/warmth variants, assert the original/prior
frame chain, decode every PNG with Pillow, save the required checkpoints and a
contact sheet, send an invalid raster reference, and confirm the service remains
healthy:

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
