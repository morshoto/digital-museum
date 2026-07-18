# Evolving Impressionist

An offline-first macOS generative audiovisual installation. The SwiftUI app
owns one continuously evolving `WorldState`; its values drive both OSC output
for TidalCycles/SuperCollider and a local visual-generation service.

## Run

Start the visual service in one terminal:

```sh
python3 visual_service/server.py
```

Build and launch the macOS app:

```sh
swift build
swift run
```

The app starts fullscreen and can be toggled with `Cmd-F`. `Cmd-D` opens
developer mode, where each parameter can be overridden. If the visual
service is unavailable, the app continues evolving with its built-in fallback
gradient; restarting the service enables generated frames.

OSC messages are sent as `/brightness`, `/warmth`, `/abstraction`, `/motion`,
and `/tension` float messages to `127.0.0.1:57120`. See
[`tidal/EvolvingImpressionist.hs`](tidal/EvolvingImpressionist.hs) for the
starting Tidal pattern.
