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
- `scripts/start-installation.sh`: authoritative exhibition startup entry point.
- `scripts/status-installation.sh` / `scripts/stop-installation.sh`: runtime health and cleanup.
- `scripts/verify.sh`: complete automated regression entry point.

## Prerequisites

- Apple Silicon macOS 13 or newer.
- Swift 5.9 or newer (`swift --version`).
- `uv` 0.10 or newer. The Python 3.13 runtime and dependency graph are defined
  by `.python-version`, `pyproject.toml`, and `uv.lock`.
- Optional for music: Nix, Homebrew SuperCollider, SuperDirt, SC3-Plugins, and
  suitable samples. `flake.nix` pins GHC, Cabal, and TidalCycles.
- Optional for real images: the `diffusion` project extra and enough free
  unified memory for the SDXL Turbo/MPS path (see the recorded measurements).

## Operator workflow

Install the locked real-backend runtime and build both Swift configurations:

```sh
./scripts/install-runtime.sh
```

Then use this single authoritative startup command from a stopped state:

```sh
./scripts/start-installation.sh
```

Startup fails closed if a required prerequisite, configured port, exact visual
backend, SuperDirt startup marker, Tidal pattern load, or Swift process is
unavailable. Exhibition startup defaults to the real `diffusers` backend and
never falls back to mock. Mock is permitted only with both explicit settings:

```sh
EVOLVING_BACKEND=mock EVOLVING_ALLOW_MOCK_EXHIBITION=1 \
EVOLVING_REQUIRE_MUSIC=0 ./scripts/start-installation.sh
```

Inspect and stop the tracked runtime with:

```sh
./scripts/status-installation.sh
./scripts/stop-installation.sh
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

The quality-oriented default is `stabilityai/sdxl-turbo` at 1024×576 on Apple
Silicon MPS, matching the attached 1920×1080 installation display's 16:9 ratio.
The backend continuously combines the original with the previous frame, pulls
back more strongly every fifth frame, and applies a small post-generation
original anchor. `abstraction` controls both anchor strength and Img2Img drift;
`motion` adds bounded drift; brightness, warmth, and tension also receive
deterministic finishing so their effect does not depend on prompt response
alone. Swift remains coupled only to the unchanged HTTP contract. See
[`visual_service/README.md`](visual_service/README.md) for configuration and
the full mapping.

## OSC, SuperCollider, and TidalCycles

Enter the pinned TidalCycles environment and start its GHCi session with:

```sh
nix develop
./scripts/tidal-session.sh
```

The verified Apple Silicon environment provides GHC/GHCi 9.10.3, Cabal
3.16.1.0, and TidalCycles 1.10.1. SuperCollider 3.14.1 was installed with
`brew install --cask supercollider`; its CLI is at
`/Applications/SuperCollider.app/Contents/MacOS/sclang`.

If SC3-Plugins already exist in the legacy macOS support directory but current
SuperCollider scans the XDG directory, activate that existing installation
with this reversible link before starting SuperDirt:

```sh
mkdir -p "$HOME/.local/share/SuperCollider/Extensions"
ln -s "$HOME/Library/Application Support/SuperCollider/Extensions/SC3plugins" \
  "$HOME/.local/share/SuperCollider/Extensions/SC3plugins"
```

Do not recreate the link when the target already exists. Without SC3-Plugins,
SuperDirt cannot load the `superpiano` voice used by the composition.

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

The first live verification, including independent parameter evidence,
`/dirt/play` observations, stereo recording measurements, exact setup commands,
and the distinction between transport and audio-output proof, is recorded in
[`tidal/LIVE_VERIFICATION.md`](tidal/LIVE_VERIFICATION.md).

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
that `/health` becomes unavailable, requires a new generation failure during
the outage, and verifies that generation recovers after `/health` returns. It
samples application RSS/virtual memory/CPU every 30 seconds, checks every logged
parameter remains within `0...1`, and writes
`app.log`, `service.log`, `events.log`, `process.csv`, and `summary.txt` under a
reported temporary log directory. Environment variables prefixed with
`EVOLVING_ENDURANCE_` can shorten the run for script smoke testing; a shortened
run is not equivalent to the one-hour exhibition gate.

The configured integer-second modulation periods and phases do not realign
within any practically relevant exhibition duration. The shortest complete
per-parameter cycle is `motion` at 1,336,007 seconds (about 15.46 days), computed
from its `31`, `71`, and `607` second defaults in `WorldState.swift`. Individual
short components repeat within an hour, but their differently phased secondary
and low-frequency components do not realign with them during that window.

The real SDXL Turbo/MPS run, sequential identifiers, timings, memory footprint,
controlled failure test, and Swift/AppKit PNG decoding evidence are recorded in
[`visual_service/VERIFICATION.md`](visual_service/VERIFICATION.md).
The Phase B cold-start, cleanup, real-service, and outage-recovery evidence is
recorded in [`OPERATOR_VERIFICATION.md`](OPERATOR_VERIFICATION.md).

## Known limitations

- Artistic quality in mock mode is intentionally simple SVG, not ML output.
- The real Diffusers path is an opt-in `uv` extra because its pinned packages
  and model cache are several gigabytes; `scripts/verify.sh` syncs only the
  dependency-free mock environment.
- SDXL Turbo balances painterly quality and repeated-generation latency on the
  installation's Apple Silicon hardware; it is not equivalent to a slower
  full-step SDXL fine-art checkpoint.
- The selected model configuration has no safety checker. Keep the localhost
  service private and review the model license before public deployment.
- Physical speaker audibility remains an operator check even though the live
  verification records and measures the real SuperDirt stereo output.
- Modulation edits are in-memory only.
- No one-hour endurance run is part of the quick verification command.
- A signed `.app` bundle, launch-at-login setup, display selection, and power/
  sleep management are not included in this SwiftPM MVP.

## Exhibition operator setup

Connect the Mac to AC power. The launcher defaults to `caffeinate -dimsu` for
the lifetime of the Swift application, preventing idle system and display sleep
without changing permanent system settings. Keep
`EVOLVING_PREVENT_SLEEP=1` for exhibitions. Confirm the screen saver, power
source, physical display, speaker selection, volume, and perceived audio in the
room before admitting visitors.

The initial SwiftUI window opens on the current primary display and the
exhibition presentation fills that window's screen. Confirm the intended
display is primary before launch. There is no display chooser, automatic move
after hot-plug/rearrangement, or multi-display spanning; reconnecting or
rearranging displays during a run requires an operator check and may require an
app relaunch. Menu bar and Dock are set to auto-hide only while exhibition
fullscreen is active.

Run `./scripts/start-installation.sh`. Use `Cmd-F` to leave or restore the
borderless exhibition presentation. Use `Cmd-D`
to inspect the five live values, overrides, modulation controls, and transport/
generation counters, then press it again so no developer controls remain on
the artwork.

The launcher tracks only processes it starts and removes them if any startup
stage fails. It does not install a launch agent, make permanent power changes,
sign an application bundle, or relaunch a component after a crash. Run the
status command during operator rounds and restart the complete installation if
it reports failure.

### Operator configuration

All operator configuration uses environment variables; there is no competing
config file. Export stable site values in the operator shell or launch wrapper.

| Variable | Default | Meaning |
| --- | --- | --- |
| `EVOLVING_BACKEND` | `diffusers` in launcher | Exact required backend (`diffusers` or explicitly allowed `mock`). |
| `EVOLVING_ALLOW_MOCK_EXHIBITION` | `0` | Must be `1` to acknowledge a mock exhibition run. |
| `EVOLVING_MODEL_ID` | `stabilityai/sd-turbo` | Hugging Face ID or local Diffusers directory containing `model_index.json`. |
| `EVOLVING_VISUAL_HOST` / `EVOLVING_VISUAL_PORT` | `127.0.0.1` / `8000` | Visual service listener. |
| `EVOLVING_VISUAL_URL` | derived from host/port | URL passed to Swift and used for health checks. |
| `EVOLVING_ORIGINAL_IMAGE` | unset | Optional readable original painting path. |
| `EVOLVING_IMAGE_WIDTH` / `EVOLVING_IMAGE_HEIGHT` | `512` / `512` | Diffusers output dimensions; multiples of eight. |
| `EVOLVING_ATTENTION_SLICING` | `0` | Set `1` to lower peak model memory at a speed cost. |
| `EVOLVING_OSC_HOST` / `EVOLVING_OSC_PORT` | `127.0.0.1` / `57120` | Swift WorldState destination and sclang language port. |
| `EVOLVING_TIDAL_CONTROL_PORT` | `6010` | Bridge destination for Tidal `/ctrl` messages. |
| `EVOLVING_DIRT_PORT` | `57120` | Tidal `/dirt/play` destination used by SuperDirt. |
| `EVOLVING_REQUIRE_MUSIC` | `1` | Fail closed unless the complete music runtime starts. |
| `EVOLVING_GENERATION_INTERVAL` | `45` | Seconds between Swift generation attempts (minimum 1). |
| `EVOLVING_PREVENT_SLEEP` | `1` | Run the app under non-persistent `caffeinate -dimsu`. |
| `EVOLVING_STARTUP_TIMEOUT` | `180` | Seconds allowed for real model and SuperDirt startup. |
| `EVOLVING_INITIAL_GENERATION_TIMEOUT` | `180` | Seconds allowed for Swift to complete its first generation. |
| `EVOLVING_AUDIO_HEARTBEAT_MAX_AGE` | `10` | Maximum age in seconds for observed `/dirt/play` activity. |
| `EVOLVING_RUNTIME_DIR` | `/tmp/evolving-impressionist-$UID` | PID/state/FIFO directory. |
| `EVOLVING_LOG_DIR` | runtime directory `logs` | Persistent-for-session component logs. |
| `EVOLVING_DIAGNOSTICS` | forced to `1` by launcher | Generation and OSC counters used by status/endurance. |
| `HF_HUB_OFFLINE` / `HF_HUB_DISABLE_XET` | upstream defaults | Hugging Face cache/network behavior. |

`status-installation.sh` distinguishes HTTP/backend health, Swift process and
generation/OSC counters, SuperDirt's completed startup marker, Tidal's loaded
patterns, observed bridge forwarding, and a fresh `/dirt/play` receive
heartbeat written only when SuperCollider sees actual Tidal events. This proves
current audio transport, not physical output: audio-device selection, speaker
level, and perceived audibility remain final manual operator checks.

Runtime process state is stored as mode-`0600` JSON under
`EVOLVING_RUNTIME_DIR`. Status and stop read individual JSON fields and never
evaluate operator-derived paths or URLs as shell source.

### Startup architecture

The launcher performs preflight, starts the selected visual service, requires
`/health` to name that exact backend, boots SuperCollider and SuperDirt, loads
the environment-configured WorldState bridge, starts a persistent pinned Tidal
GHCi session and evaluates both existing patterns, launches the release Swift
application under `caffeinate`, and runs the status check. Tidal remains an
interactive environment, but its initial `d1`/`d2` evaluation is automated;
operators may attach a separate development session only when intentionally
editing a live performance. Shutdown proceeds in reverse dependency order.
