#!/bin/sh
set -eu

. "$(dirname -- "$0")/runtime-common.sh"
cd "$repo_dir"

case "$backend" in
    diffusers) uv sync --frozen --extra diffusion ;;
    mock) uv sync --frozen ;;
    *) fail "EVOLVING_BACKEND must be diffusers or mock" ;;
esac

swift build -c debug
swift build -c release

if [ "$require_music" = 1 ]; then
    command -v nix >/dev/null 2>&1 || fail "Nix is required when EVOLVING_REQUIRE_MUSIC=1"
    nix develop --command sh -c 'ghc --version; ghci --version; ghc-pkg latest tidal'
fi

say "Runtime installation complete. Run ./scripts/start-installation.sh"
