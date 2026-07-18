# Architecture

## Repository map

- `Sources/EvolvingImpressionistCore` — deterministic parameter engine, visual
  API contract, bundled painting catalog, and OSC transport.
- `Sources/EvolvingImpressionist` — SwiftUI/AppKit exhibition and Developer Mode.
- `Sources/EvolvingImpressionistVerify` — framework-free Swift integration checks.
- `visual_service` — dependency-free mock renderer and Diffusers img2img backend.
- `tidal` — TidalCycles patterns and SuperCollider WorldState bridge.
- `scripts` — installation lifecycle, verification, and endurance automation.

## Shared state and visual generation

Swift owns five normalized parameters: brightness, warmth, abstraction, motion,
and tension. The visual service exposes `GET /health` and `POST /generate`.
Generation requests include those parameters, `originalImagePath`, and
`previousGenerationID`; responses include a bounded generation ID, PNG data,
backend identity, prompt, and reference-resolution flags.

The first generation combines the bundled original painting with WorldState.
Later generations combine the same original, the previous generation, and the
current WorldState. The original remains a persistent drift-control anchor and
is never replaced by only the previous frame.

Swift resolves `EVOLVING_ORIGINAL_IMAGE` first as a fail-closed override. When
it is unset, `PaintingCatalog` selects Monet's *Water Lilies* (1906) from the
SwiftPM resource bundle. `Bundle.module` provides a real filesystem URL that
the local Python process can read independently of the working directory.

The SDXL Turbo backend blends original and previous inputs, pulls more strongly
toward the original every fifth frame, and applies a small post-generation
anchor. Raw abstraction remains the hard upper bound on visual divergence.
See [Shared artistic state](SHARED_ARTISTIC_STATE.md) and the
[visual-service guide](../visual_service/README.md) for the mappings and drift
controls.

## Music signal path

```text
Swift WorldState
  -> OSC floats on sclang port 57120
  -> WorldStateBridge state
  -> /ctrl name/value messages on Tidal port 6010
  -> cF/cT values inside running Tidal patterns
  -> /dirt/play events on sclang port 57120
  -> SuperDirt and scsynth audio
```

The bridge produces no musical events itself. It converts the five Swift OSC
paths into Tidal's native controls while the patterns continue running.

| Shared quality | Tidal behavior |
| --- | --- |
| `luminosity` | Opens the low-pass filter. |
| `fluidity` | Expands room and size and contributes to event flow. |
| `instability` | Raises mutation, detuning, rhythmic nudge, and crush. |
| `serenity` | Lengthens pitched-event legato. |
| `density` | Scales both patterns' event activity. |

Raw warmth preserves a constant-sum crossfade between warm and cool voices.
The app sends the five OSC values at approximately 10 Hz; the default
destination is `127.0.0.1:57120`.

## Managed startup

`start-installation.sh` performs preflight, starts the configured visual
service, verifies exact backend identity, optionally boots SuperCollider and
SuperDirt, loads the WorldState bridge and Tidal patterns, launches the release
Swift application under `caffeinate`, waits for the first generation, and runs
the status check. Shutdown proceeds in reverse dependency order.
