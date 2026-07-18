<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.9 or newer" />
  <img src="https://img.shields.io/badge/Python-3.13-3776AB?logo=python&logoColor=white" alt="Python 3.13" />
  <img src="https://img.shields.io/badge/platform-Apple%20Silicon%20macOS-000000?logo=apple&logoColor=white" alt="Apple Silicon macOS" />
</p>

# Evolving Impressionist

Evolving Impressionist is an offline-first macOS generative audiovisual
installation. A Swift-owned `WorldState` continuously drives SDXL image
generation over HTTP and TidalCycles music control over OSC.

The application starts from a bundled public-domain Claude Monet painting,
evolves it while retaining the original as a drift-control anchor, and presents
the generated frames in a full-screen SwiftUI experience.

## Installation

Requirements:

- Apple Silicon macOS 13 or newer
- Swift 5.9 or newer
- `uv` 0.10 or newer
- Enough unified memory and disk space for SDXL Turbo
- Optional music runtime: Nix, SuperCollider, SuperDirt, and SC3-Plugins

```bash
cp .env.example .env
./scripts/install-runtime.sh
```

## Quick Start

```bash
# Start the visual service and desktop application
./scripts/start-installation.sh
# Inspect service, generation, and optional music health
./scripts/status-installation.sh
# Stop every process tracked by the launcher
./scripts/stop-installation.sh
# Run the automated regression suite
./scripts/verify.sh
```

The default `.env.example` starts the Diffusers visual service without the
optional music stack. `Cmd-D` toggles Developer Mode and `Cmd-F` toggles the
borderless exhibition presentation.

## Further Docs

- [Documentation index](./docs/README.md)
- [Operator guide](./docs/OPERATOR_GUIDE.md)
- [Architecture](./docs/ARCHITECTURE.md)
- [Painting provenance](./application/EvolvingImpressionistCore/Resources/Paintings/README.md)

## Development

For manual backend startup, music development, verification, endurance testing,
and repository structure, see [Development](./docs/DEVELOPMENT.md).
