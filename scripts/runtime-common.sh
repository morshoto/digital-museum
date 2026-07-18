#!/bin/sh

# Shared operator-runtime defaults and helpers. This file is sourced by the
# lifecycle scripts; operator configuration remains EVOLVING_* environment
# variables rather than a second configuration format.

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
. "$repo_dir/scripts/load-env.sh"

runtime_user_id=$(id -u)
runtime_dir=${EVOLVING_RUNTIME_DIR:-/tmp/evolving-impressionist-$runtime_user_id}
visual_host=${EVOLVING_VISUAL_HOST:-127.0.0.1}
visual_port=${EVOLVING_VISUAL_PORT:-8000}
visual_url=${EVOLVING_VISUAL_URL:-http://$visual_host:$visual_port}
backend=${EVOLVING_BACKEND:-diffusers}
model_id=${EVOLVING_MODEL_ID:-stabilityai/sdxl-turbo}
osc_host=${EVOLVING_OSC_HOST:-127.0.0.1}
osc_port=${EVOLVING_OSC_PORT:-57120}
tidal_control_port=${EVOLVING_TIDAL_CONTROL_PORT:-6010}
dirt_port=${EVOLVING_DIRT_PORT:-57120}
require_music=${EVOLVING_REQUIRE_MUSIC:-1}
prevent_sleep=${EVOLVING_PREVENT_SLEEP:-1}
startup_timeout=${EVOLVING_STARTUP_TIMEOUT:-180}
initial_generation_timeout=${EVOLVING_INITIAL_GENERATION_TIMEOUT:-180}
generation_interval=${EVOLVING_GENERATION_INTERVAL:-45}
audio_heartbeat_max_age=${EVOLVING_AUDIO_HEARTBEAT_MAX_AGE:-10}
runtime_log_dir=${EVOLVING_LOG_DIR:-$runtime_dir/logs}
state_file=$runtime_dir/runtime.json
audio_heartbeat_file=$runtime_dir/dirt-activity.txt

say() { printf '%s\n' "$*"; }
command_path() { command -v "$1" 2>/dev/null || true; }

sclang_path() {
    found=$(command_path sclang)
    if [ -n "$found" ]; then
        printf '%s\n' "$found"
    elif [ -x /Applications/SuperCollider.app/Contents/MacOS/sclang ]; then
        printf '%s\n' /Applications/SuperCollider.app/Contents/MacOS/sclang
    fi
}

is_pid_running() {
    [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}

health_json() {
    curl -fsS --max-time 3 "$visual_url/health" 2>/dev/null
}

health_backend() {
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("backend", "unknown"))' 2>/dev/null
}

wait_for_log() {
    file=$1
    marker=$2
    timeout=$3
    waited=0
    until grep -F "$marker" "$file" >/dev/null 2>&1; do
        [ "$waited" -ge "$timeout" ] && return 1
        sleep 1
        waited=$((waited + 1))
    done
}

wait_for_health() {
    expected=$1
    timeout=$2
    waited=0
    while [ "$waited" -lt "$timeout" ]; do
        response=$(health_json || true)
        if [ -n "$response" ]; then
            active=$(printf '%s' "$response" | health_backend || true)
            [ "$active" = "$expected" ] && return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

wait_for_generation() {
    file=$1
    timeout=$2
    waited=0
    while [ "$waited" -lt "$timeout" ]; do
        count=$(sed -n 's/.*generations_ok=\([0-9][0-9]*\).*/\1/p' "$file" 2>/dev/null | tail -n 1)
        [ "${count:-0}" -gt 0 ] && return 0
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

load_state() {
    [ -f "$state_file" ] || return 1
    state_reader=$repo_dir/scripts/runtime-state.py
    visual_pid=$(python3 "$state_reader" get "$state_file" visual_pid) || return 1
    supercollider_pid=$(python3 "$state_reader" get "$state_file" supercollider_pid) || return 1
    scsynth_pid=$(python3 "$state_reader" get "$state_file" scsynth_pid) || return 1
    tidal_pid=$(python3 "$state_reader" get "$state_file" tidal_pid) || return 1
    tidal_keepalive_pid=$(python3 "$state_reader" get "$state_file" tidal_keepalive_pid) || return 1
    app_pid=$(python3 "$state_reader" get "$state_file" app_pid) || return 1
    runtime_backend=$(python3 "$state_reader" get "$state_file" runtime_backend) || return 1
    runtime_visual_url=$(python3 "$state_reader" get "$state_file" runtime_visual_url) || return 1
    runtime_require_music=$(python3 "$state_reader" get "$state_file" runtime_require_music) || return 1
    runtime_log_dir=$(python3 "$state_reader" get "$state_file" runtime_log_dir) || return 1
    runtime_started_at=$(python3 "$state_reader" get "$state_file" runtime_started_at) || return 1

    for pid in "$visual_pid" "$supercollider_pid" "$scsynth_pid" "$tidal_pid" "$tidal_keepalive_pid" "$app_pid"; do
        case "$pid" in ''|*[!0-9]*) [ -z "$pid" ] || return 1 ;; esac
    done
    case "$runtime_require_music" in 0|1) ;; *) return 1 ;; esac
}

stop_pid() {
    pid=${1:-}
    name=${2:-process}
    [ -n "$pid" ] || return 0
    if ! is_pid_running "$pid"; then return 0; fi
    kill "$pid" 2>/dev/null || true
    waited=0
    while is_pid_running "$pid" && [ "$waited" -lt 10 ]; do
        sleep 1
        waited=$((waited + 1))
    done
    if is_pid_running "$pid"; then
        say "WARN: $name did not exit after 10 seconds; forcing tracked PID $pid to stop"
        kill -KILL "$pid" 2>/dev/null || true
    fi
}
