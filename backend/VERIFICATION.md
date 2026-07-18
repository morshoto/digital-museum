# Phase A real Diffusion verification report

Date: 2026-07-18 (Asia/Tokyo)

## Environment and selected backend

- Apple M4 Pro (20 GPU cores), arm64, macOS 26.5.1, 64 GB unified memory
- Attached installation display: 1920×1080 at 60 Hz
- Python 3.13.7
- PyTorch 2.13.0 with MPS available
- Diffusers 0.39.0, Transformers 5.14.1, Accelerate 1.14.0,
  Pillow 12.3.0
- Backend/device: `diffusers` / `mps`, fp16
- Model: [`stabilityai/sdxl-turbo`](https://huggingface.co/stabilityai/sdxl-turbo)
- Pipeline: `AutoPipelineForImage2Image`, 1024×576, four inference steps,
  guidance scale 0
- Resize strategy: aspect-preserving LANCZOS center crop to the configured
  output ratio; no stretching

The prior SD-Turbo model card recommends SDXL Turbo for increased quality and
prompt understanding. SDXL Turbo retains low-step Img2Img and ran comfortably
inside the original Phase A 45-second generation interval; the update below
records the current five-second stream. Its first fp16 download occupied
approximately 6.5 GB in the Hugging Face cache.

## Continuous-stream verification update

The five-second continuous-stream tuning was verified on the same MPS path
after the original Phase A measurements. The persistent service generated a
20-frame linked sequence at 1024×576, followed by all six controlled variants
and the invalid-reference recovery check:

```sh
uv run --frozen --extra diffusion python backend/verify_real.py \
  --url http://127.0.0.1:8895 \
  --original application/EvolvingImpressionistCore/Resources/Paintings/monet-water-lilies.png \
  --output-dir /tmp/evolving-continuous-stream-real \
  --generations 20
```

- Average generation latency: 3.492 seconds; range 2.779–3.897 seconds.
- All frames used the original, and frames 2–20 resolved the exact predecessor.
- Adjacent-frame mean absolute difference averaged 8.813.
- Original-image difference stayed bounded from 13.380 at generation 1 to
  13.837 at generation 20; edge correlation moved from 0.7160 to 0.7087.
- Health reported pullback interval 18 before and after the controlled failure.
- The report and PNG sequence are under
  `/tmp/evolving-continuous-stream-real/` on the verification machine.

The Swift application then ran the same service with
`EVOLVING_GENERATION_INTERVAL=5` for 50 successful displayed generations with
zero failures. PID-matched fullscreen captures showed repeated real painting
changes without blank frames or unrelated imagery. The app used a 1.2-second
blend and the bounded `1.00...1.005`/two-point presentation accent. A concurrent
verifier request caused one interval to be skipped rather than queued, then the
next application interval resumed from its latest state as designed.

The reference was the public-domain 425×298 JPEG
[Claude Monet Water Lilies](https://commons.wikimedia.org/wiki/File:Claude_Monet_Water_Lilies.jpg),
SHA-256 `492bdf553c3d4810d27d7f67968e9121b2c8a8c91e5ff4d6f41fece1a7a24366`.

## Architecture and generation parameters

The Swift request/response contract did not change. Each real request resolves
the original path and the bounded-cache predecessor ID. The backend then:

1. Center-crops both references to 1024×576.
2. Blends previous → original with a 72%→50% abstraction-based original
   weight, plus up to 4% additional preservation from serenity.
3. Adds a 10% original pull-back every eighteenth successful inference.
4. Runs SDXL Turbo Img2Img at four steps. Abstraction sets a hard strength cap
   of `0.28 + abstraction×0.14`; fluidity and instability shape strength only
   inside that allowance, with a global ceiling of 0.42.
5. Blends 16%→8% of the original back into the generated raster.
6. Applies deterministic brightness, temperature, contrast, and sharpness
   finishing derived from WorldState.

The final normal/default temporal state was:

```json
{"brightness":0.55,"warmth":0.50,"abstraction":0.30,"motion":0.35,"tension":0.30}
```

The current five-second-stream mapping gives this state an Img2Img strength of
0.302, continuous original input weight of 0.682 (0.782 every eighteenth
frame), and output
original weight of 0.136. Seeds change deterministically with state and backend
sequence.

The recorded real run below preceded the final shared-artistic-state integration
and used strength 0.325 and input weights 0.63/0.73. It verifies the SDXL model,
resolution, two-stage anchoring, pull-back cadence, and temporal behavior; the
exact merged equations are covered by the automated regression suite rather
than a newly recorded 20-frame live run.

The first tuning used a 0.68 strength ceiling and a 42%/4% high-abstraction
input/output anchor. The default 20-frame chain was coherent, but manual review
found that the 0.90-abstraction controlled sample changed the water-lily pond
into a woodland. That result was rejected. The recorded rerun below used the
then-final 0.49 ceiling and 50%/8% high-abstraction anchors. The later
continuous-stream tuning lowers the ceiling further to 0.42; its exact bounds
are covered by the current automated suite and live five-second smoke test.

## Sequential generation result

Command:

```sh
uv run --frozen --extra diffusion python backend/verify_real.py \
  --url http://127.0.0.1:8893 \
  --original /tmp/evolving-diffusion-smoke/original.jpg \
  --output-dir /tmp/evolving-sdxl-temporal-final
```

All 20 linked generations decoded as 1024×576 RGB PNGs. Every request resolved
the original; generations 2–20 resolved the exact prior returned identifier.
The service remained healthy after 26 total real outputs (20 temporal plus six
controlled variants) and a deliberately invalid raster request.

| Checkpoint | Generation ID | PNG bytes | Duration | Original MAE | Original edge correlation |
| ---------- | ------------- | --------: | -------: | -----------: | ------------------------: |
| 0          | original      |         — |        — |            0 |                       1.0 |
| 1          | `ea00d6dc…`   |   893,068 |  2.169 s |       22.203 |                    0.6181 |
| 5          | `68979fb0…`   |   845,165 |  1.939 s |       22.854 |                    0.6090 |
| 10         | `18698d51…`   |   851,898 |  1.926 s |       23.101 |                    0.6445 |
| 20         | `5045fe27…`   |   847,110 |  1.930 s |       23.062 |                    0.6242 |

- Average temporal generation time: 1.943 s
- Median: 1.926 s
- Range: 1.923–2.169 s
- Adjacent-frame mean absolute pixel difference: average 14.956, range
  13.866–22.203
- Checkpoints and all intermediate PNGs:
  `/tmp/evolving-sdxl-temporal-final/`
- Contact sheet:
  `/tmp/evolving-sdxl-temporal-final/checkpoints-0-1-5-10-20.jpg`
- Machine-readable report:
  `/tmp/evolving-sdxl-temporal-final/report.json`

The bounded generation store holds 16 frames, but the 20-frame chain succeeded
because only the immediate predecessor is required. Older checkpoints being
evicted does not interrupt forward evolution.

## Controlled WorldState evidence

The verifier generated each controlled sample directly from the same original
with the other four values held at the default above.

| Check                    | Automated result                       | Manual result                                                                                                                             |
| ------------------------ | -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Abstraction 0.05 vs 0.90 | Original MAE 21.673 vs 23.343          | Low retained finer source layout; high used broader, freer paint while retaining pond, lilies, reflections, and hanging willow structure. |
| Brightness 0.05 vs 0.95  | Mean luminance 118.002 vs 164.507      | Clearly darker vs luminous without a composition change.                                                                                  |
| Warmth 0.05 vs 0.95      | Mean red-minus-blue −75.285 vs −16.859 | Clearly cool blue vs warm pink/gold atmosphere without a composition change.                                                              |

Motion changes the deterministic seed and contributes to fluidity and density.
Tension contributes to instability and serenity. Fluidity and instability may
increase Img2Img strength only below the abstraction-defined cap; instability
also changes final contrast/sharpness, prompt atmosphere, and non-Turbo CFG.
Turbo guidance remains zero as required by the model.

## Automated versus manual visual assessment

Automated verification proves raster validity, dimensions, reference-chain
usage, stability, non-identical evolution, relative abstraction preservation,
and separated brightness/warmth statistics. Pixel difference and edge
correlation do not prove semantic continuity.

Manual inspection was therefore required. Across checkpoints 0, 1, 5, 10, and
20, the lower lily field, open reflective water, upper lily band, and hanging
willow boundaries remain consistently placed. Generation 20 still reads
immediately as the same Monet water-lily visual world. Brush marks and individual
lilies evolve between frames; no checkpoint introduces a new subject, horizon,
or unrelated scene. The final high-abstraction sample also remains in that
visual world. The first rejected high-abstraction tuning is documented above so
the subjective correction is auditable.

## Memory observations

Immediately after cached model load, macOS `footprint` reported 7.71 GB physical
footprint, including 7.28 GB in `IOAccelerator`; process RSS was approximately
336 MB. After the two long real runs, controlled variants, and Swift real-output
verification, `footprint` reported 12 GB, process RSS approximately 660 MB, and
12 GB in `IOAccelerator`. System-wide free-memory percentage was 87%. System
swap usage was 618 MB at observation time, but no before/after attribution was
available, so it is not claimed as service-created. There was no MPS out-of-
memory error, request timeout, service crash, or increasing per-frame latency.

## Swift integration and failure behavior

Executed against the same final real service:

```sh
VISUAL_SERVICE_URL=http://127.0.0.1:8893 \
EXPECTED_VISUAL_BACKEND=diffusers \
EVOLVING_ORIGINAL_IMAGE=/tmp/evolving-diffusion-smoke/original.jpg \
swift run EvolvingImpressionistVerify
```

The verifier completed two Swift `VisualAPIClient` requests, required PNG media
types and signatures, and decoded both with AppKit `NSImage`. It verified
original/previous reference resolution, received a controlled HTTP 400 for an
invalid raster, and confirmed the service remained healthy. Injected network
and undecodable-response failures retained the last valid application frame and
generation ID; recovery advanced exactly one transition.

## Regression commands and results

```sh
uv run --frozen --extra diffusion python -m py_compile \
  backend/server.py backend/verify_real.py \
  backend/tests/test_server.py backend/tests/test_diffusers_backend.py
uv run --frozen --extra diffusion python -m unittest discover \
  -s backend/tests -v
./scripts/verify.sh
```

- Diffusion environment: 30 Python tests passed, including shared golden
  vectors, abstraction hard constraints, reference blending,
  pull-back cadence, high-abstraction strength ceiling, final color grading,
  raster contract, health metadata, offline model resolution, and LRU eviction.
- Dependency-free mock environment: 26 tests passed and four Pillow-only tests
  skipped as intended.
- `swift build` passed for all targets.
- Two mock HTTP generations decoded with AppKit and failure recovery passed.
- Tidal source evaluation and the SuperCollider five-control bridge regression
  also passed unchanged; no audio code was modified.

## Remaining visual-quality limitations

- SDXL Turbo's one-effective-step normal path is less nuanced than a slower
  full-step SDXL fine-art checkpoint. It is selected as the best verified local
  balance of painterly quality, 16:9 resolution, temporal safety, and latency.
- Center crop intentionally fills the display and may remove edge content when
  a source ratio differs substantially from the installation. A future curator-
  selected crop or content-aware framing stage would give more artistic control.
- Deterministic final grading makes WorldState legible but can clip extreme
  source highlights at maximum brightness/warmth.
- The selected pipeline has no safety checker. Keep it localhost-only, review
  source imagery, and review the model license for the final exhibition use.
- Manual assessment used one Monet reference and one normal 20-frame trajectory.
  A broader painting set and curator scoring remain necessary before locking the
  final installation palette.

## Recommended next artistic tuning

1. Curate three to five representative paintings and record preferred crop,
   default abstraction, and warmth range per work.
2. Compare the current SDXL Turbo result with a fine-art checkpoint that can
   stay inside the five-second generation budget at 1024×576 on this M4 Pro.
3. Tune the periodic pull-back cadence between 12 and 24 frames with a curator
   watching the continuous stream, not isolated stills.
4. Add perceptual/semantic monitoring only as a guardrail; retain checkpoint
   contact-sheet review as the artistic acceptance gate.
