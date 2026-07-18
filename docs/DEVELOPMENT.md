# Development

## Visual development

For a faster direct Swift development loop against an already-running service:

```sh
EVOLVING_GENERATION_INTERVAL=5 swift run EvolvingImpressionist
```

Start the real visual service manually when debugging its terminal output:

```sh
uv sync --frozen --extra diffusion

HF_HUB_DISABLE_XET=1 \
EVOLVING_BACKEND=diffusers \
uv run --frozen --extra diffusion python visual_service/server.py
```

Swift uses the bundled Monet *Water Lilies* reference unless
`EVOLVING_ORIGINAL_IMAGE` supplies a readable override. Provenance for every
bundled painting is recorded in the
[painting catalog](../Sources/EvolvingImpressionistCore/Resources/Paintings/README.md).

## Music development

Enter the pinned TidalCycles environment and start GHCi with:

```sh
nix develop
./scripts/tidal-session.sh
```

The app sends `/brightness`, `/warmth`, `/abstraction`, `/motion`, and
`/tension` as normalized OSC floats. To smoke-test the live path:

1. Start SuperCollider and evaluate `SuperDirt.start`.
2. Evaluate `tidal/WorldStateBridge.scd` and confirm forwarding to port `6010`.
3. Evaluate the definitions and both patterns in `tidal/EvolvingImpressionist.hs`.
4. Launch the Swift app, open Developer Mode with `Cmd-D`, and vary one bounded
   override at a time while holding the others at `0.5`.
5. Confirm the Tidal layers continue without re-evaluating `d1` or `d2`.

If SuperCollider only finds SC3-Plugins in its legacy support directory, create
the XDG-compatible link once:

```sh
mkdir -p "$HOME/.local/share/SuperCollider/Extensions"
ln -s "$HOME/Library/Application Support/SuperCollider/Extensions/SC3plugins" \
  "$HOME/.local/share/SuperCollider/Extensions/SC3plugins"
```

Do not recreate the link if it already exists. See
[Live music verification](../tidal/LIVE_VERIFICATION.md) for recorded transport
and audio-output evidence.

## Automated verification

Run the complete regression entry point:

```sh
./scripts/verify.sh
```

It tests the Python service, builds Swift, starts the mock backend, verifies
parameter behavior and bundled PNGs, captures OSC, performs two sequential
Swift-to-service generations, decodes images with AppKit, and exercises failure
recovery. When available, it also validates Tidal source and the SuperCollider
bridge.

Run the focused bridge check without another controller bound to UDP port 6010:

```sh
/Applications/SuperCollider.app/Contents/MacOS/sclang \
  -D tidal/VerifyWorldStateBridge.scd
```

## Endurance testing

After a release build, run the one-hour mock-backend endurance gate separately:

```sh
swift build -c release
./scripts/endurance.sh
```

The runner introduces a controlled service outage, requires a generation
failure during the outage and recovery afterward, checks parameter bounds, and
records process samples and logs in a reported temporary directory. Shortened
`EVOLVING_ENDURANCE_*` runs are useful script checks but are not equivalent to
the one-hour exhibition gate.

Recorded real-backend timings, memory measurements, sequential generation IDs,
failure recovery, and AppKit decoding are in
[Real Diffusers verification](../visual_service/VERIFICATION.md).
