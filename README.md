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
- `uv` 0.10 or newer. The Python 3.13 runtime and dependency graph are defined
  by `.python-version`, `pyproject.toml`, and `uv.lock`.
- Optional for music: SuperCollider, SuperDirt, TidalCycles, and suitable samples.
- Optional for real images: the `diffusion` project extra and approximately
  5 GB of free runtime memory for the proven SD-Turbo/MPS path.

## Run the MVP

Start the visual service in mock mode:

```sh
uv sync --frozen
EVOLVING_BACKEND=mock uv run --frozen python visual_service/server.py
```

Then launch the macOS application:

```sh
swift run EvolvingImpressionist
```

The application enters a borderless, display-filling exhibition presentation
automatically without relying on a native macOS Space transition.
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
later cycles retry. Valid replacement frames crossfade over the retained frame;
failed or undecodable responses do not advance the transition. UDP does not
require a receiver, so an absent music stack does not stop the app.

## Visual service

The service exposes `GET /health` and `POST /generate`. Requests include the
five normalized parameters plus `originalImagePath` and
`previousGenerationID`. Responses contain base64 image data, media type,
backend name, prompt, a generation ID, and backend-neutral flags confirming
which requested references were resolved. The service retains a bounded cache
of recent frames so each generation can use its predecessor.

To anchor mock or real generations to an original painting:

```sh
EVOLVING_ORIGINAL_IMAGE=/absolute/path/to/painting.jpg swift run EvolvingImpressionist
```

To install and use the real backend:

```sh
uv sync --frozen --extra diffusion

HF_HUB_DISABLE_XET=1 \
EVOLVING_BACKEND=diffusers \
uv run --frozen --extra diffusion python visual_service/server.py
```

The proven default is `stabilityai/sd-turbo` at 512×512 on Apple Silicon MPS.
The backend blends the original with the previous frame using a 30–55% original
anchor, maps `abstraction`/`motion` to Img2Img strength, `brightness` to source
exposure, `warmth` to color temperature, and `tension` to contrast/instability.
Prompt language carries the same state. Swift remains coupled only to the HTTP
contract. See [`visual_service/README.md`](visual_service/README.md) for the
full setup, model override, mapping, and real verification commands.

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
| `warmth` | Constant-sum gain crossfades Tidal's warm `superpiano`/kick/clap voices against its cool `arpy`/hi-hat voices, limiting loudness drift. |
| `abstraction` | Raises the probability of four-step `iter` transformations, increasing motif and rhythm variation. |
| `motion` | Scales both patterns from `fast 0.55` to `fast 2.2`, continuously changing note/event density without a restart. |
| `tension` | Adds pitched-voice detuning, rhythmic `nudge`, and increasingly coarse `crush`. |

### Live music smoke test

This is the acceptance test for audible integration:

1. Start SuperCollider and evaluate `SuperDirt.start`.
2. Evaluate all of [`tidal/WorldStateBridge.scd`](tidal/WorldStateBridge.scd).
   Confirm it reports forwarding controls to `127.0.0.1:6010`.
3. Start a TidalCycles session and evaluate all definitions and both patterns
   in [`tidal/EvolvingImpressionist.hs`](tidal/EvolvingImpressionist.hs). First
   confirm both `d1` and `d2` type-check and evaluate, especially the
   pattern-valued `sometimesBy worldAbstraction (iter 4)` expression.
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

This syncs the locked mock environment with `uv`, compiles and tests the Python
service through `uv`, compiles every Swift target, starts the mock service,
checks parameter bounds/change/configuration/phase/determinism/override
behavior, captures all five messages with a real local UDP receiver, performs
two successive Swift-to-service generations, decodes both results with AppKit,
and verifies a service connection failure is recoverable. When `sclang` is
installed, it also receives all five Swift-side OSC paths and asserts the five
normalized `/ctrl` messages forwarded to Tidal's port. Run that focused check
directly with:

```sh
/Applications/SuperCollider.app/Contents/MacOS/sclang -D tidal/VerifyWorldStateBridge.scd
```

Run the focused bridge verification without an active Tidal controller
listener: both use UDP port 6010. The verifier exits with an explicit bind
error if it cannot reserve that port.

This machine currently has Apple Command Line Tools without Xcode's XCTest
runtime, so the Swift checks use a repository-owned executable that exits
nonzero on failure. The checks remain automated and require no GUI.

Run the one-hour mock-backend endurance test separately after producing the
release build:

```sh
swift build -c release
./scripts/endurance.sh
```

The endurance runner uses `caffeinate -dimsu`, shortens generation cadence to
six seconds, introduces a 30-second service outage after ten minutes, verifies
that generation recovers, samples application RSS/virtual memory/CPU every 30
seconds, checks every logged parameter remains within `0...1`, and writes
`app.log`, `service.log`, `events.log`, `process.csv`, and `summary.txt` under a
reported temporary log directory. Environment variables prefixed with
`EVOLVING_ENDURANCE_` can shorten the run for script smoke testing; a shortened
run is not equivalent to the one-hour exhibition gate.

The default modulation periods and phases do not form a perceptually obvious
one-hour loop. Even the shortest complete per-parameter cycle (`motion`) is
1,336,007 seconds (about 15.46 days); the exact common period across all 15
sine components is approximately `5.54e31` years. Individual short components
repeat within an hour, but their differently phased secondary and low-frequency
components do not realign with them during that window.

The real SD-Turbo/MPS run, sequential identifiers, timings, memory footprint,
controlled failure test, and Swift/AppKit PNG decoding evidence are recorded in
[`visual_service/VERIFICATION.md`](visual_service/VERIFICATION.md).

## Known limitations

- Artistic quality in mock mode is intentionally simple SVG, not ML output.
- The real Diffusers path is an opt-in `uv` extra because its pinned packages
  and model cache are several gigabytes; `scripts/verify.sh` syncs only the
  dependency-free mock environment.
- SD-Turbo is selected for pipeline proof and speed, not maximum image quality.
  Its output is square and its prompt fidelity is below larger current models.
- The selected model configuration has no safety checker. Keep the localhost
  service private and review the model license before public deployment.
- TidalCycles/SuperCollider startup and audio output remain a manual test.
- Modulation edits are in-memory only.
- No one-hour endurance run is part of the quick verification command.
- A signed `.app` bundle, launch-at-login setup, display selection, and power/
  sleep management are not included in this SwiftPM MVP.

## Exhibition operator setup

Connect the Mac to AC power. Disable system sleep, display sleep, and the screen
saver for the operator account, or keep the launch command under
`caffeinate -dimsu`; the application intentionally does not make persistent
power-management changes. Verify those settings again after OS updates and
before every exhibition session.

The initial SwiftUI window opens on the current primary display and the
exhibition presentation fills that window's screen. Confirm the intended
display is primary before launch. There is no display chooser, automatic move
after hot-plug/rearrangement, or multi-display spanning; reconnecting or
rearranging displays during a run requires an operator check and may require an
app relaunch. Menu bar and Dock are set to auto-hide only while exhibition
fullscreen is active.

Start the mock visual service first, then launch the release application. Use
`Cmd-F` to leave or restore the borderless exhibition presentation. Use `Cmd-D`
to inspect the five live values, overrides, modulation controls, and transport/
generation counters, then press it again so no developer controls remain on
the artwork.

This SwiftPM MVP has no launch agent, watchdog, signed application bundle, or
crash relaunch policy. An operator or separately managed supervisor must start
the service and application after login/reboot and restart either process after
an unexpected exit. Test that external supervision on the actual installation
Mac rather than assuming the development shell remains available.
