# Evolving Impressionist

An offline-first macOS generative audiovisual installation. One Swift-owned
`WorldState` drives asynchronous visual generation over HTTP and continuous
music control over OSC.

## Repository structure

- `Sources/EvolvingImpressionistCore`: deterministic parameter engine, visual API contract, and OSC transport.
- `Sources/EvolvingImpressionist`: SwiftUI/AppKit application and exhibition/developer presentation.
- `Sources/EvolvingImpressionistVerify`: framework-free Swift integration checks for Command Line Tools installations.
- `visual_service`: dependency-free mock renderer plus an optional Diffusers Img2Img backend.
- `tidal`: Tidal patterns and a SuperCollider OSC bridge.
- `scripts/verify.sh`: complete automated verification entry point.

## Prerequisites

- Apple Silicon macOS 13 or newer.
- Swift 5.9 or newer (`swift --version`).
- Python 3.10 or newer; mock mode uses only the standard library.
- Optional for music: SuperCollider, SuperDirt, TidalCycles, and suitable samples.
- Optional for real images: PyTorch, Diffusers, Pillow, a local/downloaded
  Img2Img-capable model, and enough memory for that model.

## Run the MVP

Start the visual service in mock mode:

```sh
EVOLVING_BACKEND=mock python3 visual_service/server.py
```

Then launch the macOS application:

```sh
swift run EvolvingImpressionist
```

The application enters fullscreen exhibition presentation automatically.
`Cmd-D` toggles developer mode; `Cmd-F` toggles fullscreen. Developer mode
shows current values, HTTP/OSC status and errors, provides a manual generation
button, allows overrides, and exposes base, primary amplitude, period, and
phase controls for every parameter.

Generation defaults to every 45 seconds. For a faster development loop:

```sh
EVOLVING_GENERATION_INTERVAL=5 swift run EvolvingImpressionist
```

If the visual service is stopped, the last valid artwork remains visible and
later cycles retry. UDP does not require a receiver, so an absent music stack
does not stop the app.

## Visual service

The service exposes `GET /health` and `POST /generate`. Requests include the
five normalized parameters plus `originalImagePath` and
`previousGenerationID`. Responses contain base64 image data, media type,
backend name, prompt, and a generation ID. The service retains a bounded cache
of recent frames so each generation can use its predecessor.

To anchor mock or real generations to an original painting:

```sh
EVOLVING_ORIGINAL_IMAGE=/absolute/path/to/painting.jpg swift run EvolvingImpressionist
```

To use the optional real backend:

```sh
EVOLVING_BACKEND=diffusers \
EVOLVING_MODEL_ID=/absolute/path/to/local-img2img-model \
python3 visual_service/server.py
```

The backend blends the original with the previous frame according to
`abstraction`, uses `abstraction`/`motion` for Img2Img strength, `brightness`
for source illumination, and `tension` for guidance. Prompt language carries
warmth, motion, and tension. Swift is coupled only to the HTTP contract.

## OSC, SuperCollider, and TidalCycles

The app sends OSC float messages at approximately 10 Hz:

```text
/brightness  /warmth  /abstraction  /motion  /tension
```

The default destination is `127.0.0.1:57120`; override it with
`EVOLVING_OSC_HOST` and `EVOLVING_OSC_PORT`.

The live music signal path is:

```text
Swift WorldState
  → OSC floats on sclang port 57120
  → WorldStateBridge state
  → /ctrl name/value messages on Tidal port 6010
  → cF/cT values inside the running Tidal patterns
  → /dirt/play Tidal events on sclang port 57120
  → SuperDirt samples/synths and effects
  → scsynth audio
```

The bridge creates no synth and produces no musical events. It converts the
five existing OSC paths into Tidal's native `/ctrl <name> <float>` input. The
running patterns read the latest controls with `cF`/`cT`, so the composition
keeps running while its pattern and sound parameters change.

| WorldState value | Tidal-generated musical behavior |
| --- | --- |
| `brightness` | Opens the Tidal `lpf` control from 650 Hz to 12 kHz. |
| `warmth` | Crossfades Tidal's warm `superpiano`/kick/clap voices against its cool `arpy`/hi-hat voices. |
| `abstraction` | Raises the probability of four-step `iter` transformations, increasing motif and rhythm variation. |
| `motion` | Scales both patterns from `fast 0.55` to `fast 2.2`, continuously changing note/event density without a restart. |
| `tension` | Adds pitched-voice detuning, rhythmic `nudge`, and increasingly coarse `crush`. |

### Live music smoke test

This is the acceptance test for audible integration:

1. Start SuperCollider and evaluate `SuperDirt.start`.
2. Evaluate all of [`tidal/WorldStateBridge.scd`](tidal/WorldStateBridge.scd).
   Confirm it reports forwarding controls to `127.0.0.1:6010`.
3. Start a TidalCycles session and evaluate all definitions and both patterns
   in [`tidal/EvolvingImpressionist.hs`](tidal/EvolvingImpressionist.hs).
4. Launch `swift run EvolvingImpressionist`, press `Cmd-D`, enable an override
   for one parameter, and alternate it between `0` and `1`. Hold all other
   overrides at `0.5` so each comparison is independent.
5. For each parameter, confirm the corresponding row in the table is audible.
   Evaluate `~worldState.postln` in SuperCollider to confirm bridge reception.
   For an observable check, temporarily evaluate `OSCFunc.trace(true)`: the
   returning Tidal `/dirt/play` messages should show changing `lpf`, `gain`,
   `detune`, `nudge`, and `crush` controls while event frequency changes with
   `motion`. Disable the trace with `OSCFunc.trace(false)`.
6. Confirm the Tidal layers continue throughout the changes; no `hush`, `d1`,
   or `d2` re-evaluation should be needed. Evaluate `hush` only when finished.

If `superpiano` is unavailable in the local SuperDirt installation, replace it
with another sustained local sound in the first `d1` voice.

## Verification

Run all automated checks:

```sh
./scripts/verify.sh
```

This runs six Python service tests, compiles every Swift target, starts the
mock service, checks parameter bounds/change/configuration/phase/determinism/
override behavior, captures all five messages with a real local UDP receiver,
performs two successive Swift-to-service generations, decodes both results
with AppKit, and verifies a service connection failure is recoverable. When
`sclang` is installed, it also receives all five Swift-side OSC paths and
asserts the five normalized `/ctrl` messages forwarded to Tidal's port. Run
that focused check directly with:

```sh
/Applications/SuperCollider.app/Contents/MacOS/sclang -D tidal/VerifyWorldStateBridge.scd
```

This machine currently has Apple Command Line Tools without Xcode's XCTest
runtime, so the Swift checks use a repository-owned executable that exits
nonzero on failure. The checks remain automated and require no GUI.

## Known limitations

- Artistic quality in mock mode is intentionally simple SVG, not ML output.
- The Diffusers backend is implemented but requires a compatible local model
  and was not exercised by the dependency-free verification suite.
- The automated SuperCollider check proves the bridge through Tidal's input
  port but does not prove `/dirt/play` output or audible sound; the live music
  smoke test above remains manual unless a complete TidalCycles session is
  available.
- Modulation edits are in-memory only.
- No one-hour endurance run is part of the quick verification command.
- A signed `.app` bundle, launch-at-login setup, display selection, and power/
  sleep management are not included in this SwiftPM MVP.
