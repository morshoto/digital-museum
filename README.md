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

For unattended-run diagnostics, set `EVOLVING_DIAGNOSTICS=1`. Each completed
generation attempt logs cumulative success/failure and OSC-send counts plus all
five sampled parameter values.

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

Manual smoke test:

1. Start SuperCollider and evaluate `SuperDirt.start`.
2. Evaluate [`tidal/WorldStateBridge.scd`](tidal/WorldStateBridge.scd). Its post window logs every incoming parameter and its synth maps brightness to pitch/filter, warmth to timbre, abstraction to pitch complexity, motion to density, and tension to detuning/instability.
3. Start TidalCycles and evaluate [`tidal/EvolvingImpressionist.hs`](tidal/EvolvingImpressionist.hs). The patterns continue while the bridge changes the shared musical world without restarting them.
4. Launch the app and confirm changing `WorldState` values appear in the SuperCollider post window and are audible.

## Verification

Run all automated checks:

```sh
./scripts/verify.sh
```

This runs six Python service tests, compiles every Swift target, starts the
mock service, checks parameter bounds/change/configuration/phase/determinism/
override behavior, captures all five messages with a real local UDP receiver,
performs two successive Swift-to-service generations, decodes both results
with AppKit, and verifies a service connection failure is recoverable.

This machine currently has Apple Command Line Tools without Xcode's XCTest
runtime, so the Swift checks use a repository-owned executable that exits
nonzero on failure. The checks remain automated and require no GUI.

## Known limitations

- Artistic quality in mock mode is intentionally simple SVG, not ML output.
- The Diffusers backend is implemented but requires a compatible local model
  and was not exercised by the dependency-free verification suite.
- TidalCycles/SuperCollider startup and audio output remain a manual test.
- Modulation edits are in-memory only.
- No one-hour endurance run is part of the quick verification command.
- A signed `.app` bundle, launch-at-login setup, display selection, and power/
  sleep management are not included in this SwiftPM MVP.

## Exhibition operator setup

Connect the Mac to AC power and disable display sleep for the installation
session (or launch the app through `caffeinate -dimsu`). The application does
not change system power settings. Confirm the intended display is primary
before launch, start the visual service first, and use `Cmd-F` as the documented
manual fullscreen fallback. `Cmd-D` remains available to inspect live values
and transport/generation counters, then hides all controls for exhibition.
