#!/bin/sh
set -eu

. "$(dirname -- "$0")/runtime-common.sh"
cd "$repo_dir"

required_failures=0
optional_warnings=0

required_ok() { say "REQUIRED OK: $*"; }
required_fail() { say "REQUIRED UNAVAILABLE: $*" >&2; required_failures=$((required_failures + 1)); }
optional_ok() { say "OPTIONAL OK: $*"; }
optional_missing() { say "OPTIONAL UNAVAILABLE: $*"; optional_warnings=$((optional_warnings + 1)); }

case "$backend" in
    diffusers|mock) ;;
    *) required_fail "EVOLVING_BACKEND must be diffusers or mock (received '$backend')" ;;
esac
case "$require_music" in 0|1) ;; *) required_fail "EVOLVING_REQUIRE_MUSIC must be 0 or 1" ;; esac
case "$prevent_sleep" in 0|1) ;; *) required_fail "EVOLVING_PREVENT_SLEEP must be 0 or 1" ;; esac

for setting in "$visual_port" "$osc_port" "$tidal_control_port" "$dirt_port"; do
    case "$setting" in ''|*[!0-9]*) required_fail "all port settings must be integers"; break ;; esac
done
if python3 -c 'import sys; values = map(float, sys.argv[1:]); assert all(value >= 1 for value in values)' \
    "$generation_interval" "$startup_timeout" "$initial_generation_timeout" "$audio_heartbeat_max_age" 2>/dev/null; then
    required_ok "positive generation and startup timing configuration"
else
    required_fail "generation, startup, and audio heartbeat timing values must be numeric and at least 1"
fi

if [ "$backend" = mock ] && [ "${EVOLVING_ALLOW_MOCK_EXHIBITION:-0}" != 1 ]; then
    required_fail "mock exhibition startup requires explicit EVOLVING_ALLOW_MOCK_EXHIBITION=1"
fi

if command -v uv >/dev/null 2>&1; then
    required_ok "uv $(uv --version 2>/dev/null)"
else
    required_fail "uv is not installed"
fi

if command -v uv >/dev/null 2>&1; then
    if [ "$backend" = diffusers ]; then
        if uv run --frozen --extra diffusion python -c 'import accelerate,diffusers,PIL,torch,transformers' >/dev/null 2>&1; then
            required_ok "locked Python diffusion dependencies"
        else
            required_fail "diffusion dependencies are unavailable; run ./scripts/install-runtime.sh"
        fi
    elif uv run --frozen python -c 'import backend.server' >/dev/null 2>&1; then
        required_ok "locked Python mock environment"
    else
        required_fail "Python environment is unavailable; run ./scripts/install-runtime.sh"
    fi
fi

if [ "$backend" = diffusers ]; then
    if [ -e "$model_id" ]; then
        if [ -d "$model_id" ] && [ -r "$model_id/model_index.json" ]; then
            required_ok "local Diffusers model path $model_id"
        else
            required_fail "local model path must be a directory containing readable model_index.json: $model_id"
        fi
    else
        cache_name=$(printf '%s' "$model_id" | sed 's|/|--|g')
        cache_root=${HF_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/huggingface}/hub/models--$cache_name
        if [ -d "$cache_root/snapshots" ] && find "$cache_root/snapshots" -mindepth 1 -maxdepth 1 -type d -print -quit | grep . >/dev/null; then
            required_ok "cached model $model_id"
        elif [ "${HF_HUB_OFFLINE:-0}" = 1 ]; then
            required_fail "model $model_id is not cached but HF_HUB_OFFLINE=1"
        else
            required_ok "model $model_id may be downloaded on first start (network required)"
        fi
    fi
fi

if [ -x "$repo_dir/.build/release/EvolvingImpressionist" ]; then
    required_ok "Swift release executable"
else
    required_fail "Swift release executable is missing; run ./scripts/install-runtime.sh"
fi

if command -v python3 >/dev/null 2>&1; then
    if python3 "$repo_dir/scripts/check-ports.py" --tcp "$visual_host:$visual_port" --udp "$osc_host:$osc_port" --udp "127.0.0.1:$tidal_control_port" --udp "127.0.0.1:$dirt_port"; then
        required_ok "visual and OSC ports are available"
    else
        required_fail "one or more runtime ports are already occupied"
    fi
else
    required_fail "python3 is required for preflight port checks"
fi

sc=$(sclang_path)
if [ -n "$sc" ]; then
    if [ "$require_music" = 1 ]; then required_ok "SuperCollider $sc"; else optional_ok "SuperCollider $sc"; fi
else
    if [ "$require_music" = 1 ]; then required_fail "SuperCollider sclang"; else optional_missing "SuperCollider sclang (music disabled)"; fi
fi

superdirt_found=0
for path in \
    "$HOME/.local/share/SuperCollider/downloaded-quarks/SuperDirt" \
    "$HOME/Library/Application Support/SuperCollider/downloaded-quarks/SuperDirt"; do
    [ -d "$path" ] && superdirt_found=1
done
if [ "$superdirt_found" -eq 1 ]; then
    if [ "$require_music" = 1 ]; then required_ok "SuperDirt Quark"; else optional_ok "SuperDirt Quark"; fi
else
    if [ "$require_music" = 1 ]; then required_fail "SuperDirt Quark"; else optional_missing "SuperDirt Quark"; fi
fi

sc3_found=0
for path in \
    "$HOME/.local/share/SuperCollider/Extensions/SC3plugins" \
    "$HOME/Library/Application Support/SuperCollider/Extensions/SC3plugins"; do
    [ -e "$path" ] && sc3_found=1
done
if [ "$sc3_found" -eq 1 ]; then
    if [ "$require_music" = 1 ]; then required_ok "SC3-Plugins (required by superpiano)"; else optional_ok "SC3-Plugins"; fi
else
    if [ "$require_music" = 1 ]; then required_fail "SC3-Plugins required by the composition's superpiano voice"; else optional_missing "SC3-Plugins"; fi
fi

if command -v nix >/dev/null 2>&1 && nix develop --command sh -c 'command -v ghci >/dev/null && ghc-pkg latest tidal >/dev/null' >/dev/null 2>&1; then
    if [ "$require_music" = 1 ]; then required_ok "pinned TidalCycles runtime"; else optional_ok "pinned TidalCycles runtime"; fi
else
    if [ "$require_music" = 1 ]; then required_fail "Nix TidalCycles runtime"; else optional_missing "Nix TidalCycles runtime"; fi
fi

if [ "$prevent_sleep" = 1 ]; then
    if command -v caffeinate >/dev/null 2>&1; then required_ok "caffeinate sleep prevention"; else required_fail "caffeinate"; fi
else
    optional_missing "sleep prevention disabled by EVOLVING_PREVENT_SLEEP=0"
fi

if [ -n "${EVOLVING_ORIGINAL_IMAGE:-}" ]; then
    if [ -r "$EVOLVING_ORIGINAL_IMAGE" ]; then required_ok "original image $EVOLVING_ORIGINAL_IMAGE"; else required_fail "EVOLVING_ORIGINAL_IMAGE is not readable"; fi
else
    bundled_reference=$(find -H "$repo_dir/.build/release" -path '*/Paintings/monet-water-lilies.png' -type f -print -quit 2>/dev/null || true)
    if [ -n "$bundled_reference" ] && [ -r "$bundled_reference" ]; then
        required_ok "bundled default original image $bundled_reference"
    else
        required_fail "bundled Monet reference is missing from the Swift release resources; run ./scripts/install-runtime.sh"
    fi
fi

say "PREFLIGHT SUMMARY: required_failures=$required_failures optional_unavailable=$optional_warnings backend=$backend music_required=$require_music"
[ "$required_failures" -eq 0 ]
