# Phase C audiovisual verification

Verified on 2026-07-18 on Apple Silicon macOS. The original Phase C live test
used the then-current cached SD-Turbo/MPS backend, TidalCycles 1.10.1,
SuperDirt 1.7.3, SuperCollider 3.14.1, and the Mac mini speaker output selected
at 48 kHz. Current visual-coherence defaults and their separate real-backend
evidence are recorded in [`../backend/VERIFICATION.md`](../backend/VERIFICATION.md).

## Automated regression

`./scripts/verify.sh` passed 30 Python tests in the dependency-free environment
(four Pillow-only backend tests skipped), all Swift build and executable
checks, two mock visual generations and failure recovery, all five original
OSC addresses through a local UDP receiver, both Tidal patterns evaluated in
the pinned GHCi environment, and all five paths through the real SuperCollider
bridge. The Swift verifier explicitly checked deterministic derived state,
`0...1` bounds, expected directional effects, and six shared golden vectors.
Python checked the same vectors plus visual consumption, abstraction divergence
limits, and distinct outputs for A/B/C. The Tidal source verifier evaluates the
same six vectors through the pure functions used by its patterns and checks
that all five derived qualities connect to their intended pattern controls.

## Live audiovisual calibration states

The real visual backend rendered three sequential 512×512 PNG frames, retaining
the original painting and previous generation references:

| State            | Visual observation                                                                                                     | Live Tidal behavior represented in `/dirt/play`                                                                  |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| A calm/dark      | Cool, subdued light; quiet water-lily structure remained clearest and darkest.                                         | Low 2.52 kHz cutoff, sparse density, long 1.47 legato, small room/size, minimal detune/nudge/crush disturbance.  |
| B luminous/fluid | Clearly brightest and warmest frame; soft open light and flowing surface variation while composition remained legible. | Open 10.43 kHz cutoff, medium-high density and room, connected 1.22 legato, low instability, warm voice balance. |
| C tense/abstract | Strongest deformation and contrast; water and horizon became broad turbulent structures with denser marks.             | Dense event flow, large room, short 0.74 legato, strong motif mutation, detune/nudge, and crush disturbance.     |

The descriptions of music are based on real Tidal-generated event controls and
recorded output, not an agent claim of subjective hearing. An exhibition
operator still needs to judge room-level perceptual balance.

The live session evaluated `d1` and `d2` once, then held A, B, and C for four
seconds each and sent a continuous A→B→C→A interpolation at 20 Hz. The session
produced 739 `/dirt/play` events; the calibration phases continued without
re-evaluating, stopping, or replacing either pattern. During the ramp the trace
showed continuously changing cutoff, room/size, legato, detune, nudge, crush,
gain, and event delta values. There were no pattern commands in the sender and
no music restart in the trace.

SuperCollider recorded `/tmp/evolving-phase-c.wav`: stereo Float32, 48 kHz,
61.1307 seconds, 22 MiB. `ffmpeg astats` found finite nonzero signal on the
recording, overall peak -34.55 dBFS and RMS -61.44 dBFS, with zero NaNs,
infinities, or denormals.

Those levels prove signal-path integrity, not exhibition loudness. In
particular, `-61.44 dBFS` RMS may be effectively inaudible in a gallery. Phase C
does not add a master-gain or limiter stage; curatorial tuning must validate
ambient, normal, and tense loudness through the actual room speakers without
allowing state changes to create excessive level jumps.

## Exact live commands

```sh
EVOLVING_AUDIO_RECORDING=/tmp/evolving-phase-c.wav \
EVOLVING_DIRT_PORT=57200 \
  /Applications/SuperCollider.app/Contents/MacOS/sclang \
  -D -u 57201 tidal/LiveWorldStateVerification.scd

nix develop --command ghci -ghci-script tidal/BootTidalLiveVerification.hs
# Evaluate tidal/EvolvingImpressionist.hs once in this session.

python3 scripts/verify-artistic-states.py \
  --port 57201 --hold-seconds 4 --transition-seconds 4

afinfo /tmp/evolving-phase-c.wav
ffmpeg -hide_banner -nostats -i /tmp/evolving-phase-c.wav \
  -af astats=metadata=0:reset=0 -f null -

uv sync --frozen --extra diffusion
HF_HUB_OFFLINE=1 EVOLVING_BACKEND=diffusers EVOLVING_VISUAL_PORT=8892 \
  uv run --frozen --extra diffusion python backend/server.py

python3 scripts/verify-artistic-states.py \
  --port 57201 --hold-seconds 0.01 --transition-seconds 0.01 \
  --visual-url http://127.0.0.1:8892 \
  --original /tmp/evolving-diffusion-smoke/original.jpg \
  --output-dir /tmp/evolving-phase-c-visuals
```

For a simultaneous operator test, leave the Tidal/SuperDirt session running,
start the visual service, and run the final command with the default eight
second holds and transitions. View each emitted image while listening to its
held phase, then judge the continuous transition in the room. Do not evaluate
`d1`, `d2`, or `hush` until the procedure sends its final stop marker.

## Remaining artistic limitations

- Warmth still uses a raw-value timbral crossfade because it is a useful stable
  compatibility mapping; luminosity supplies the higher-level coupling.
- Turbo prompt fidelity and its low effective denoising-step count limit subtle
  deformation control. Model selection and resolution remain outside Phase C.
- Tidal's control reads are continuous, but probabilistic `sometimesBy`
  outcomes are pattern-cycle dependent; instability is perceptible over a
  phrase rather than guaranteed on each event.
- Four-second calibration holds prove response and contrast, not final gallery
  pacing. The 45-second visual cadence and mix ranges still require long-form
  curatorial tuning on the actual display and speakers.
- The independent-motion event-ratio gate is intentionally `1.7`, down from the
  pre-derived `2.5` mapping. It proves a material event-rate response but does
  not prove that high motion sounds sufficiently dynamic to listeners.
- Future audio tuning should place an explicitly calibrated master gain and
  limiter after the generative mix, then compare integrated loudness and peaks
  for the A/B/C anchors on the installation speakers.
