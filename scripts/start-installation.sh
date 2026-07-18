#!/bin/sh
set -eu

. "$(dirname -- "$0")/runtime-common.sh"
cd "$repo_dir"

if [ -f "$state_file" ]; then
    if "$repo_dir/scripts/status-installation.sh" --quiet >/dev/null 2>&1; then
        fail "installation is already running; use ./scripts/status-installation.sh"
    fi
    "$repo_dir/scripts/stop-installation.sh" --quiet || true
fi

mkdir -p "$runtime_dir" "$runtime_log_dir"
visual_log=$runtime_log_dir/visual-service.log
supercollider_log=$runtime_log_dir/supercollider.log
tidal_log=$runtime_log_dir/tidal.log
app_log=$runtime_log_dir/application.log
: >"$visual_log"
: >"$supercollider_log"
: >"$tidal_log"
: >"$app_log"

visual_pid=
supercollider_pid=
tidal_pid=
tidal_keepalive_pid=
app_pid=

write_state() {
    umask 077
    {
        printf 'visual_pid=%s\n' "$visual_pid"
        printf 'supercollider_pid=%s\n' "$supercollider_pid"
        printf 'tidal_pid=%s\n' "$tidal_pid"
        printf 'tidal_keepalive_pid=%s\n' "$tidal_keepalive_pid"
        printf 'app_pid=%s\n' "$app_pid"
        printf 'runtime_backend=%s\n' "$backend"
        printf 'runtime_visual_url=%s\n' "$visual_url"
        printf 'runtime_require_music=%s\n' "$require_music"
        printf 'runtime_log_dir=%s\n' "$runtime_log_dir"
        printf 'runtime_started_at=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
    } >"$state_file"
}

cleanup_failed_start() {
    result=$?
    trap - EXIT INT TERM
    if [ "$result" -ne 0 ]; then
        say "Startup failed; stopping every process started by this launcher." >&2
        write_state
        "$repo_dir/scripts/stop-installation.sh" --quiet || true
        say "Logs: $runtime_log_dir" >&2
    fi
    exit "$result"
}
trap cleanup_failed_start EXIT INT TERM

say "[1/8] Preflight"
"$repo_dir/scripts/preflight-installation.sh"

say "[2/8] Starting visual service ($backend)"
if [ "$backend" = diffusers ]; then
    EVOLVING_BACKEND="$backend" EVOLVING_MODEL_ID="$model_id" EVOLVING_VISUAL_PORT="$visual_port" \
        uv run --frozen --extra diffusion python -u "$repo_dir/visual_service/server.py" >>"$visual_log" 2>&1 &
else
    EVOLVING_BACKEND="$backend" EVOLVING_VISUAL_PORT="$visual_port" \
        uv run --frozen python -u "$repo_dir/visual_service/server.py" >>"$visual_log" 2>&1 &
fi
visual_pid=$!
write_state

say "[3/8] Waiting for /health and exact backend identity"
if ! wait_for_health "$backend" "$startup_timeout"; then
    tail -n 40 "$visual_log" >&2 || true
    fail "visual service did not become healthy as backend '$backend'"
fi

if [ "$require_music" = 1 ]; then
    say "[4/8] Starting SuperCollider, SuperDirt, and WorldState bridge"
    sc=$(sclang_path)
    EVOLVING_TIDAL_CONTROL_PORT="$tidal_control_port" EVOLVING_DIRT_PORT="$dirt_port" \
        "$sc" -D -u "$osc_port" "$repo_dir/tidal/InstallationStartup.scd" >>"$supercollider_log" 2>&1 &
    supercollider_pid=$!
    write_state
    if ! wait_for_log "$supercollider_log" "INSTALLATION_SUPERDIRT_READY" "$startup_timeout"; then
        tail -n 60 "$supercollider_log" >&2 || true
        fail "SuperCollider/SuperDirt did not report readiness"
    fi

    say "[5/8] Starting TidalCycles and loading the installation patterns"
    tidal_fifo=$runtime_dir/tidal-input.fifo
    rm -f "$tidal_fifo"
    mkfifo "$tidal_fifo"
    tail -f /dev/null >"$tidal_fifo" &
    tidal_keepalive_pid=$!
    EVOLVING_TIDAL_CONTROL_PORT="$tidal_control_port" EVOLVING_DIRT_PORT="$dirt_port" \
        nix develop --command "$repo_dir/scripts/tidal-session.sh" <"$tidal_fifo" >>"$tidal_log" 2>&1 &
    tidal_pid=$!
    write_state
    "$repo_dir/scripts/render-tidal-input.sh" >"$tidal_fifo"
    if ! wait_for_log "$tidal_log" "INSTALLATION_TIDAL_READY" 60; then
        tail -n 60 "$tidal_log" >&2 || true
        fail "TidalCycles did not load both patterns"
    fi
    if grep -Eq '(^|:)([0-9]+:)?[0-9]+: error:|Exception|Not in scope' "$tidal_log"; then
        tail -n 60 "$tidal_log" >&2 || true
        fail "TidalCycles reported an error while loading the patterns"
    fi
else
    say "[4-6/8] Music disabled explicitly with EVOLVING_REQUIRE_MUSIC=0"
fi

say "[6/8] WorldState bridge readiness confirmed with SuperDirt"

say "[7/8] Starting Swift exhibition application"
app_command=$repo_dir/.build/release/EvolvingImpressionist
if [ "$prevent_sleep" = 1 ]; then
    EVOLVING_VISUAL_URL="$visual_url" EVOLVING_OSC_HOST="$osc_host" EVOLVING_OSC_PORT="$osc_port" \
        EVOLVING_GENERATION_INTERVAL="$generation_interval" EVOLVING_DIAGNOSTICS=1 \
        caffeinate -dimsu "$app_command" >>"$app_log" 2>&1 &
else
    EVOLVING_VISUAL_URL="$visual_url" EVOLVING_OSC_HOST="$osc_host" EVOLVING_OSC_PORT="$osc_port" \
        EVOLVING_GENERATION_INTERVAL="$generation_interval" EVOLVING_DIAGNOSTICS=1 \
        "$app_command" >>"$app_log" 2>&1 &
fi
app_pid=$!
write_state
sleep 2
is_pid_running "$app_pid" || fail "Swift application exited during startup"
if ! wait_for_generation "$app_log" "$initial_generation_timeout"; then
    tail -n 40 "$app_log" >&2 || true
    fail "Swift application did not complete an initial generation"
fi

say "[8/8] Runtime health"
if ! "$repo_dir/scripts/status-installation.sh"; then
    fail "runtime status check failed"
fi

trap - EXIT INT TERM
say "Installation started. Logs: $runtime_log_dir"
say "Run ./scripts/status-installation.sh or ./scripts/stop-installation.sh"
