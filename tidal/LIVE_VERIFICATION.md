# TidalCycles live verification

Verified on 2026-07-18 on Apple Silicon macOS with the built-in Mac mini
speakers selected as the default output.

## Environment before setup

The initial shell had no `ghc`, `ghci`, `cabal`, `tidal`, `sclang`, or
`scsynth` command on `PATH`. Homebrew already contained the SuperCollider
3.14.1 cask and `/Applications/SuperCollider.app`; its CLI executables were
inside the app bundle. SuperDirt 1.7.3 and Dirt-Samples were already downloaded
and enabled as Quarks. Universal arm64/x86_64 SC3-Plugins were present under
`~/Library/Application Support/SuperCollider/Extensions/SC3plugins`, but
SuperCollider 3.14.1 was scanning `~/.local/share/SuperCollider/Extensions`.

The default audio device was the two-channel, 48 kHz Mac mini speakers.

## Installation and configuration

No additional global Homebrew formula was installed. The repository now pins
GHC/GHCi 9.10.3, Cabal 3.16.1.0, and TidalCycles 1.10.1 in `flake.nix` and
`flake.lock`. Nix downloaded the pinned packages into its content-addressed
store. The existing SC3-Plugins installation was activated through one
reversible symlink.

Commands used:

```sh
nix-shell -p 'haskellPackages.ghcWithPackages (p: [ p.tidal ])' \
  --run 'ghc --version; ghci --version; ghc-pkg latest tidal'
nix flake lock
nix develop --command sh -c \
  'ghc --version; ghci --version; cabal --version; ghc-pkg latest tidal'

mkdir -p "$HOME/.local/share/SuperCollider/Extensions"
ln -s "$HOME/Library/Application Support/SuperCollider/Extensions/SC3plugins" \
  "$HOME/.local/share/SuperCollider/Extensions/SC3plugins"
```

Before the link, live SuperDirt reported that SC3-Plugins were missing and that
no synth or sample named `superpiano` could be found. After the link and a
SuperCollider restart, the extra synth definitions loaded and `superpiano`
events ran without that error.

## Live signal path and source evaluation

The verified path was:

```text
deterministic WorldState OSC sender
  -> WorldStateBridge on sclang
  -> normalized /ctrl name/value messages on UDP 6010
  -> cF/cT in the already-running d1 and d2 patterns
  -> /dirt/play events
  -> SuperDirt 1.7.3
  -> scsynth 3.14.1
  -> Mac mini speakers and a stereo Float32 recording
```

Another worktree was running an endurance test against the standard language
port during the controlled comparison. To prevent its Swift traffic from
changing the held values, the live verification used isolated local ports:
sclang/bridge `57201`, Tidal/SuperDirt `57200`, and the unchanged Tidal control
port `6010`. The bridge implementation itself was not changed.

The first real BootTidal evaluation found a genuine Tidal 1.10.1 compatibility
error: `scale "minor"` had been used as though it were a control parameter.
Changing the two note expressions to `n (scale "minor" pattern)` fixed it.
Both `d1` and `d2`, including
`sometimesBy worldAbstraction (iter 4)`, then evaluated without type or runtime
errors. `scripts/verify-tidal-source.sh` repeats that source-level check.

## Independent parameter results

For each phase the deterministic sender continuously held four parameters at
`0.5`, alternated the selected parameter from `0` to `1`, and did not re-run,
stop, or replace `d1` or `d2`. The audio run held each phase for six seconds.
A separate five-second-per-phase trace assertion produced these results:

| Parameter | `/dirt/play` observation | Musical result |
| --- | --- | --- |
| brightness | `cutoff` changed from `650` to `12000` on both orbits. | Filter changed from dark/closed to bright/open. |
| warmth | `superpiano` gain `0.13 -> 0.52`, `arpy` `0.52 -> 0.13`, kick `0.28 -> 0.52`, hi-hat `0.44 -> 0.08`, clap `0.12 -> 0.24`. | Balance moved from cool arpy/hat emphasis to piano/kick/clap emphasis. |
| abstraction | Pitched order changed from `piano 0, arpy 12, piano 3, piano 7, ...` to `piano 7, arpy 7, piano 10, ...`. | The four-step `iter` transformation changed motif ordering while the pattern continued. |
| motion | Equal five-second windows contained `20` versus `70` events, a `3.50x` density increase. | Both patterns accelerated without restart. |
| tension | `detune 0 -> 0.42`, `nudge 0 -> 0.09`, and `crush 16 -> 5`. | Pitch, timing, and resolution became less stable. |

The trace assertion ended with:

```text
PASS: five independent controls changed running Tidal /dirt/play output
```

## Transport versus actual audio output

Transport verification is proven by the bridge verifier and the independent
trace: all five input paths reached `/ctrl`, the running patterns responded,
and 761 `/dirt/play` messages were observed during the recorded audio run.

Actual audio generation is separate from that transport proof. SuperDirt
booted against the Mac mini speakers at 48 kHz, scsynth ran the pattern events,
and the server recorded `/tmp/evolving-impressionist-isolated.wav`: stereo
Float32, 155.99 seconds including startup, 57 MiB. `ffmpeg astats` measured
nonzero samples on both channels, overall peak `-24.32 dBFS`, phase-region RMS
`-53.88 dBFS`, and no NaNs or infinities. The selected speaker output was
unmuted at macOS volume 56. This proves real SuperDirt audio reached the active
hardware output path, not only OSC transport. Subjective human listening is not
something the automated agent can independently attest; an exhibition
operator should still confirm perceived level in the room.

## Live commands

The controlled live run used:

```sh
EVOLVING_AUDIO_RECORDING=/tmp/evolving-impressionist-isolated.wav \
EVOLVING_DIRT_PORT=57200 \
  /Applications/SuperCollider.app/Contents/MacOS/sclang \
  -D -u 57201 tidal/LiveWorldStateVerification.scd

nix develop --command ghci -ghci-script tidal/BootTidalLiveVerification.hs
# EvolvingImpressionist.hs was evaluated in that session without restarting it.

python3 scripts/send-world-state.py --port 57201 --hold-seconds 6
python3 scripts/verify-tidal-controls.py --phase-seconds 5

afinfo /tmp/evolving-impressionist-isolated.wav
ffmpeg -hide_banner -nostats -ss 90 \
  -i /tmp/evolving-impressionist-isolated.wav \
  -af astats=metadata=0:reset=0 -f null -
```

## Remaining limitations

- The SC3-Plugins activation link is machine-local and intentionally not
  created by repository automation.
- The live verification boot file uses isolated ports and disables the
  SuperDirt handshake so the Python trace receiver can stand in for SuperDirt;
  the audio run itself connected to and used the real SuperDirt instance.
- Recorded signal and active unmuted speakers prove audio output, but final
  perceived loudness depends on the room, speakers, and operator volume.
- The Nix development shell currently targets the product's required
  `aarch64-darwin` platform.
