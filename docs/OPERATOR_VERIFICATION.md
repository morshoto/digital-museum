# Phase B operator-runtime verification

Date: 2026-07-18 (Asia/Tokyo)

## Result

The authoritative exhibition path is `./scripts/start-installation.sh`, with
`status-installation.sh` and `stop-installation.sh` owning health reporting and
cleanup. The launcher was cold-started with the real Diffusers backend, the
complete local music stack, isolated OSC ports, and a two-second generation
interval. It required the exact configured backend and a successful first
generation before reporting success.

The cold-start status after twelve additional seconds reported:

```text
OK visual service healthy backend=diffusers
OK Swift app running generations_ok=7 generations_failed=0 osc_sent=625
OK SuperCollider process and SuperDirt startup marker
OK TidalCycles session loaded d1/d2
OK WorldState OSC bridge active forwarded_messages=685
```

`stop-installation.sh` then stopped the tracked app, Tidal session and FIFO
keeper, SuperCollider/SuperDirt, and visual service. The configured TCP/UDP
ports had no remaining listeners. Logs from the run were retained under
`/tmp/evolving-phase-b-smoke/cold-start-logs` on the verification machine.

## Commands

```sh
EVOLVING_BACKEND=mock EVOLVING_REQUIRE_MUSIC=0 ./scripts/install-runtime.sh
./scripts/verify.sh
uv sync --frozen --extra diffusion
uv run --frozen --extra diffusion python -m unittest discover -s backend/tests -v
```

The real cold start used the equivalent of:

```sh
EVOLVING_RUNTIME_DIR=/tmp/evolving-impressionist-phase-b \
EVOLVING_VISUAL_PORT=8870 \
EVOLVING_OSC_PORT=57210 \
EVOLVING_DIRT_PORT=57210 \
EVOLVING_TIDAL_CONTROL_PORT=6020 \
EVOLVING_GENERATION_INTERVAL=2 \
EVOLVING_ORIGINAL_IMAGE=/tmp/evolving-phase-b-smoke/original.jpg \
HF_HUB_OFFLINE=1 \
./scripts/start-installation.sh

EVOLVING_RUNTIME_DIR=/tmp/evolving-impressionist-phase-b \
./scripts/status-installation.sh

EVOLVING_RUNTIME_DIR=/tmp/evolving-impressionist-phase-b \
./scripts/stop-installation.sh
```

The original image was a temporary JPEG conversion of a built-in macOS desktop
thumbnail, used only as a runtime fixture. It is not part of the repository or
the installation's artistic inputs.

The focused real-service verification used:

```sh
EVOLVING_BACKEND=diffusers EVOLVING_VISUAL_PORT=8899 HF_HUB_OFFLINE=1 \
uv run --frozen --extra diffusion python backend/server.py

uv run --frozen --extra diffusion python backend/verify_real.py \
  --url http://127.0.0.1:8899 \
  --original /tmp/evolving-phase-b-smoke/original.jpg \
  --output-dir /tmp/evolving-phase-b-smoke/real-output
```

It returned MPS Diffusers health, generated two sequential 512×512 PNGs in
0.871 and 0.799 seconds, confirmed the original and previous-generation chain,
returned a controlled HTTP 400 for an invalid image, and remained healthy.

## Regression and endurance evidence

- Swift debug build: passed.
- Swift release build: passed.
- Mock Python suite: 18 tests ran successfully with 3 real-extra tests skipped.
- Diffusion-extra Python suite: all 18 tests passed.
- Swift mock HTTP/AppKit recovery and repeated-generation verification: passed.
- Swift UDP capture of all five WorldState OSC messages: passed.
- Tidal source evaluation of both unchanged patterns: passed.
- SuperCollider bridge forwarding/clamping check: passed.
- Real Diffusers health and sequential-generation smoke: passed.
- Shell syntax and `git diff --check`: passed.

A shortened 41-second endurance run exercised the existing outage gate with a
two-second generation interval, a service outage at 12 seconds, and restart at
18 seconds. This is a recovery smoke, not the one-hour exhibition gate.

```text
duration_seconds=41
generations_ok=18
generations_failed=3
recovery_events=1
process_samples=20
rss_initial_kb=82656
rss_final_kb=101920
rss_max_kb=101920
cpu_average_percent=3.26
cpu_max_percent=6.10
```

Seven successful generations occurred before the outage. Three generation
failures were observed while health was unavailable. The service restarted,
the next successful generation was observed two seconds later, and the app
survived the complete run. The one-hour mock command remains
`swift build -c release && ./scripts/endurance.sh`; it was not repeated during
this Phase B implementation window.

## Manual exhibition checks

Initial Tidal `d1`/`d2` evaluation is automated. The remaining manual checks
are physical: confirm the intended display is primary before launch, verify
fullscreen placement after any cable/display rearrangement, select the intended
audio device, confirm safe volume and perceived stereo sound in the room, and
review the model license/installation image. The launcher uses non-persistent
`caffeinate` assertions and does not alter permanent macOS power settings.

## Post-review runtime hardening

The merge review follow-up added current audio-transport health, safe runtime
state parsing, fail-closed custom Tidal boot rewriting, stronger local-model
validation, and explicit `scsynth` lifecycle management.

An isolated full-stack mock smoke used non-default ports and a log directory
containing spaces and a literal shell metacharacter. Startup reported active
Tidal transport with 15 `/dirt/play` events and a one-second-old heartbeat.
After evaluating `hush` while leaving GHCi, SuperCollider, and the Swift app
alive, status correctly failed five seconds later:

```text
OK TidalCycles patterns loaded d1/d2
FAIL audio transport stale SuperDirt_received_dirt_play=15 last_seen_seconds_ago=7
```

This proves status distinguishes loaded/live processes from current Tidal event
flow. A second active check observed 115 events with a one-second heartbeat.
Shutdown was then verified to remove the visual, sclang, `scsynth`, Tidal
control, and Dirt listeners; `scsynth` is now tracked explicitly rather than
being assumed to exit with sclang.

The JSON state round-trip preserved both
`My Logs; literal` and `http://127.0.0.1:8000/?x=$HOME` verbatim with mode
`0600`. A custom Tidal session bound the requested control port `6033` and Dirt
port `57333`; generated BootTidal content now must contain exactly one patched
instance and both requested values or startup fails.
