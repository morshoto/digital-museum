# Operator Guide

## Installation lifecycle

Create the local configuration and install the locked Python and Swift runtime:

```sh
cp .env.example .env
./scripts/install-runtime.sh
```

The lifecycle scripts load literal `KEY=value` assignments from `.env` without
executing shell expansion or command substitution. `.env` is ignored by Git,
and variables exported by the calling shell take precedence.

Start, inspect, and stop the complete tracked installation with:

```sh
./scripts/start-installation.sh
./scripts/status-installation.sh
./scripts/stop-installation.sh
```

The launcher starts the configured visual service, requires `/health` to report
the exact backend, optionally starts the music stack, launches the release Swift
application, and waits for its first successful generation. A failed startup
stops every process it started. Status only tracks processes launched through
this lifecycle; manually started services do not create runtime state.

Runtime state is stored as mode-`0600` JSON under `EVOLVING_RUNTIME_DIR`.
Component logs are stored under its `logs` directory. Status and stop read JSON
fields directly and never evaluate operator-provided paths or URLs as shell.

## Exhibition controls

The application fills the primary display without creating a separate native
macOS Space. Confirm the intended display is primary before launch.

- `Cmd-D` toggles Developer Mode, including live parameters, generation and OSC
  counters, bounded overrides, and actionable HTTP errors.
- `Cmd-F` toggles the borderless exhibition presentation.

The last valid artwork remains visible during service or decoding failures.
Later cycles retry without advancing the painting world. The warm Diffusion
pipeline produces a new evolution about every five seconds; valid frames blend
for 1.2 seconds over the retained frame. Scale is at most 1.002 and translation
at most one point; zero motion disables both. A replacement arriving during an
active transition starts from the currently visible composite rather than
resetting opacity.

Without an original-image override, one catalog world remains active for two
to eight minutes. Six generation anchors then move gradually into a different
artist's world over about 30 seconds while previous-frame feedback continues.
This is expected Diffusion evolution, not a source-image slideshow. UDP does
not require a receiver, so disabling the music stack does not stop visual
generation.

For unattended operation, the launcher forces `EVOLVING_DIAGNOSTICS=1` and
defaults to `caffeinate -dimsu`. Connect the Mac to AC power and manually verify
the physical display, audio device, speaker level, room audibility, and screen
saver settings before admitting visitors.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `EVOLVING_BACKEND` | `diffusers` | Required visual backend (`diffusers` or explicitly allowed `mock`). |
| `EVOLVING_ALLOW_MOCK_EXHIBITION` | `0` | Must be `1` to acknowledge a mock exhibition run. |
| `EVOLVING_MODEL_ID` | `stabilityai/sdxl-turbo` | Hugging Face ID or local Diffusers directory. |
| `EVOLVING_VISUAL_HOST` / `EVOLVING_VISUAL_PORT` | `127.0.0.1` / `8000` | Visual-service listener. |
| `EVOLVING_VISUAL_URL` | derived from host and port | URL used by Swift and health checks. |
| `EVOLVING_ORIGINAL_IMAGE` | bundled eight-work catalog starting at Monet *Water Lilies* | Optional readable fixed original-painting override; setting it disables catalog rotation. |
| `EVOLVING_IMAGE_WIDTH` / `EVOLVING_IMAGE_HEIGHT` | `1024` / `576` | Diffusers output dimensions; multiples of eight. |
| `EVOLVING_ATTENTION_SLICING` | `0` | Set `1` to lower peak model memory at a speed cost. |
| `EVOLVING_OSC_HOST` / `EVOLVING_OSC_PORT` | `127.0.0.1` / `57120` | Swift WorldState destination and sclang port. |
| `EVOLVING_TIDAL_CONTROL_PORT` | `6010` | Bridge destination for Tidal `/ctrl` messages. |
| `EVOLVING_DIRT_PORT` | `57120` | Tidal `/dirt/play` destination used by SuperDirt. |
| `EVOLVING_REQUIRE_MUSIC` | `1` | Require the complete music runtime during startup. |
| `EVOLVING_GENERATION_INTERVAL` | `5` | Seconds between non-overlapping Swift generation attempts. |
| `EVOLVING_PREVENT_SLEEP` | `1` | Run the app under non-persistent `caffeinate`. |
| `EVOLVING_STARTUP_TIMEOUT` | `180` | Seconds allowed for model and SuperDirt startup. |
| `EVOLVING_INITIAL_GENERATION_TIMEOUT` | `180` | Seconds allowed for the first generation. |
| `EVOLVING_AUDIO_HEARTBEAT_MAX_AGE` | `10` | Maximum age of observed `/dirt/play` activity. |
| `EVOLVING_RUNTIME_DIR` | `/tmp/evolving-impressionist-$UID` | PID, state, and FIFO directory. |
| `EVOLVING_LOG_DIR` | runtime directory `logs` | Component log directory. |
| `HF_HUB_OFFLINE` / `HF_HUB_DISABLE_XET` | upstream defaults | Hugging Face cache and network behavior. |

An explicit invalid `EVOLVING_ORIGINAL_IMAGE` fails closed with an actionable
error. Leave it unset to use the packaged Impressionist painting worlds.

## Mock mode

Exhibition startup never silently falls back from Diffusers to mock. Mock mode
requires both explicit acknowledgements:

```sh
EVOLVING_BACKEND=mock \
EVOLVING_ALLOW_MOCK_EXHIBITION=1 \
EVOLVING_REQUIRE_MUSIC=0 \
./scripts/start-installation.sh
```

## Known limitations

- Mock output is intentionally simple SVG rather than ML-generated artwork.
- The Diffusers extra and model cache require several gigabytes.
- The selected model configuration has no safety checker; keep the service on
  localhost and review the model license before public deployment.
- Physical speaker audibility remains a manual operator check.
- Parameter modulation edits persist only in memory.
- The app has no display chooser or automatic display migration after hot-plug.
- The SwiftPM MVP does not include a signed application bundle, launch agent,
  automatic crash relaunch, or multi-display spanning.
