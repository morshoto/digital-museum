#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
service_port=8877
service_log=/tmp/evolving-impressionist-visual-service.log

cd "$repo_dir"
uv sync --frozen
uv run --frozen python -m py_compile visual_service/server.py visual_service/verify_real.py
uv run --frozen python -m unittest discover -s visual_service/tests -v
swift build

EVOLVING_VISUAL_PORT=$service_port EVOLVING_QUIET=1 uv run --frozen python visual_service/server.py >"$service_log" 2>&1 &
service_pid=$!
trap 'kill "$service_pid" 2>/dev/null || true' EXIT INT TERM

attempt=0
until curl -fsS "http://127.0.0.1:$service_port/health" >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 50 ]; then
        printf 'Visual service failed to start; log: %s\n' "$service_log" >&2
        exit 1
    fi
    sleep 0.1
done

VISUAL_SERVICE_URL="http://127.0.0.1:$service_port" swift run EvolvingImpressionistVerify

sclang_path=$(command -v sclang 2>/dev/null || true)
if [ -z "$sclang_path" ] && [ -x /Applications/SuperCollider.app/Contents/MacOS/sclang ]; then
    sclang_path=/Applications/SuperCollider.app/Contents/MacOS/sclang
fi
if [ -n "$sclang_path" ]; then
    if bridge_output=$("$sclang_path" -D tidal/VerifyWorldStateBridge.scd 2>&1); then
        printf '%s\n' "$bridge_output"
    else
        printf '%s\n' "$bridge_output" >&2
        exit 1
    fi
    case "$bridge_output" in
        *"PASS: five controls forwarded"*) ;;
        *)
            printf '%s\n' 'FAIL: SuperCollider OSC regression check exited without its PASS marker' >&2
            exit 1
            ;;
    esac
else
    printf '%s\n' 'SKIP: sclang not found; SuperDirt bridge runtime verification unavailable'
fi
