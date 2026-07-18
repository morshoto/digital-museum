# Real Diffusion verification report

Date: 2026-07-18 (Asia/Tokyo)

## Environment and selected backend

- Apple Silicon arm64, macOS 26.5.1, 64 GB unified memory
- Python 3.13.7
- PyTorch 2.13.0 with `mps` built and available
- Diffusers 0.39.0, Transformers 5.14.1, Accelerate 1.14.0,
  Pillow 12.3.0
- Backend: `diffusers`
- Model: [`stabilityai/sd-turbo`](https://huggingface.co/stabilityai/sd-turbo)
- Pipeline: `AutoPipelineForImage2Image`, fp16, MPS, 512×512, four steps

The reference was the public-domain 425×298 JPEG
[Claude Monet Water Lilies](https://commons.wikimedia.org/wiki/File:Claude_Monet_Water_Lilies.jpg),
SHA-256 `492bdf553c3d4810d27d7f67968e9121b2c8a8c91e5ff4d6f41fece1a7a24366`.

## Installation and launch

The original verification used an equivalent pinned `venv` environment. The
project has since migrated that dependency set to `pyproject.toml` and
`uv.lock`; the current reproduction commands are:

```sh
uv sync --frozen --extra diffusion

HF_HUB_DISABLE_XET=1 \
EVOLVING_BACKEND=diffusers \
EVOLVING_VISUAL_PORT=8891 \
uv run --frozen --extra diffusion python visual_service/server.py
```

The initial fp16 component fetch was approximately 2.6 GB. Model load completed
and `/health` returned:

```json
{"ok":true,"backend":"diffusers","model":"stabilityai/sd-turbo","device":"mps","width":512,"height":512,"mediaType":"image/png"}
```

A later launch with `HF_HUB_OFFLINE=1` resolved the downloaded snapshot and
loaded successfully without Hub access; the final Swift integration run below
used that offline-started service.

## Real and sequential generation

Current equivalent of the command used for the recorded run:

```sh
uv run --frozen --extra diffusion python visual_service/verify_real.py \
  --url http://127.0.0.1:8891 \
  --original /tmp/evolving-diffusion-smoke/original.jpg \
  --output-dir /tmp/evolving-diffusion-final
```

Results from the final warmed run:

| Generation | Previous ID used | Dimensions | PNG bytes | Duration |
| --- | --- | --- | ---: | ---: |
| 1 | none | 512×512 RGB | 425,984 | 0.747 s |
| 2 | generation 1 (`e906f611…`) | 512×512 RGB | 450,710 | 0.738 s |

Both outputs opened successfully with Pillow and the Unix `file` utility.
Generation 2 used generation 1's returned identifier while also sending the
original painting path. Mean absolute RGB pixel differences were 24.078 from
original to generation 1, 37.668 from original to generation 2, and 30.058
between generated frames. The images were visually inspected: water lilies,
willow reflections, palette, and broad composition remained recognizable in
both, while the warmer second WorldState produced a visibly warmer and more
varied frame.

The first ever request after model loading took 3.248 s; subsequent requests
were approximately 0.7–0.8 s. After inference, `footprint` reported 4,722 MB
physical footprint, including 4,258 MB in `IOAccelerator`, with a 4,992 MB peak.
Process RSS was approximately 638 MB. No swap or service crash was observed.

## Swift integration and failure behavior

Executed against the live real backend:

```sh
VISUAL_SERVICE_URL=http://127.0.0.1:8891 \
EXPECTED_VISUAL_BACKEND=diffusers \
EVOLVING_ORIGINAL_IMAGE=/tmp/evolving-diffusion-smoke/original.jpg \
swift run EvolvingImpressionistVerify
```

The verifier completed two Swift `VisualAPIClient` requests, required
`image/png` plus a PNG signature, and decoded both responses with AppKit
`NSImage`. It then sent a deliberately invalid raster reference, received a
controlled HTTP 400 JSON error, and confirmed `/health` remained available.
The verifier then exercised the actual application `VisualService` through an
injected client: one valid raster established `currentImage` and its generation
ID, and the following request failed. It confirmed the same `NSImage` instance,
generation ID, and transition counter remained in place while status changed to
failed. This directly verifies that the prior valid visual is retained.

An injected backend failure test separately confirmed unexpected generation
exceptions return controlled HTTP 500 JSON rather than terminating the server.

## Regression commands

```sh
uv run --frozen --extra diffusion python -m py_compile \
  visual_service/server.py visual_service/verify_real.py \
  visual_service/tests/test_server.py visual_service/tests/test_diffusers_backend.py
uv run --frozen --extra diffusion python -m unittest discover -s visual_service/tests -v
./scripts/verify.sh
```

- Pinned environment: 18 Python tests passed, including three real-backend
  contract/drift tests and bounded LRU history eviction checks.
- Dependency-free environment: 15 tests passed and the three Pillow-only tests
  skipped as intended.
- `swift build` passed for all targets.
- Mock service health, two sequential SVG generations, AppKit SVG decoding,
  parameter checks, OSC checks, and recoverable Swift connection failure all
  passed.

## Remaining limitations

- SD-Turbo was chosen for fast, practical pipeline proof rather than maximum
  prompt fidelity or exhibition image quality.
- Output is center-cropped to a square 512×512 raster. Aspect-ratio-aware model
  selection or compositing is future quality work.
- The SD-Turbo pipeline configuration does not include a safety checker; the
  service is localhost-only and should not be exposed as a public endpoint.
- Model licensing and acceptable-use terms must be reviewed for the final
  exhibition context.
- This verification covers repeated generations but not the planned one-hour
  endurance run.
