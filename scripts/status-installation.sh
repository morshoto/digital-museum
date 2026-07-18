#!/bin/sh
set -u

. "$(dirname -- "$0")/runtime-common.sh"

quiet=0
[ "${1:-}" = --quiet ] && quiet=1
status=0

report() {
    [ "$quiet" -eq 1 ] || say "$*"
}

if ! load_state; then
    report "STOPPED: no runtime state at $state_file"
    exit 1
fi

response=$(curl -fsS --max-time 3 "$runtime_visual_url/health" 2>/dev/null || true)
active_backend=
[ -n "$response" ] && active_backend=$(printf '%s' "$response" | health_backend || true)
if is_pid_running "$visual_pid" && [ "$active_backend" = "$runtime_backend" ]; then
    report "OK visual service healthy backend=$active_backend pid=$visual_pid"
else
    report "FAIL visual service backend_expected=$runtime_backend backend_active=${active_backend:-unavailable} pid=${visual_pid:-none}"
    status=1
fi

if is_pid_running "$app_pid"; then
    generations_ok=$(sed -n 's/.*generations_ok=\([0-9][0-9]*\).*/\1/p' "$runtime_log_dir/application.log" 2>/dev/null | tail -n 1)
    generations_failed=$(sed -n 's/.*generations_failed=\([0-9][0-9]*\).*/\1/p' "$runtime_log_dir/application.log" 2>/dev/null | tail -n 1)
    osc_sent=$(sed -n 's/.*osc_sent=\([0-9][0-9]*\).*/\1/p' "$runtime_log_dir/application.log" 2>/dev/null | tail -n 1)
    report "OK Swift app running pid=$app_pid generations_ok=${generations_ok:-0} generations_failed=${generations_failed:-0} osc_sent=${osc_sent:-0}"
else
    report "FAIL Swift app not running pid=${app_pid:-none}"
    status=1
fi

if [ "$runtime_require_music" = 1 ]; then
    if is_pid_running "$supercollider_pid" && is_pid_running "$scsynth_pid" && grep -F "INSTALLATION_SUPERDIRT_READY" "$runtime_log_dir/supercollider.log" >/dev/null 2>&1; then
        report "OK SuperCollider and scsynth processes with SuperDirt startup marker sclang_pid=$supercollider_pid scsynth_pid=$scsynth_pid (speaker audibility remains an operator check)"
    else
        report "FAIL SuperCollider/SuperDirt startup status"
        status=1
    fi
    if is_pid_running "$tidal_pid" && grep -F "INSTALLATION_TIDAL_READY" "$runtime_log_dir/tidal.log" >/dev/null 2>&1; then
        report "OK TidalCycles patterns loaded d1/d2 pid=$tidal_pid"
    else
        report "FAIL TidalCycles readiness"
        status=1
    fi
    if grep -F "WorldStateBridge ready" "$runtime_log_dir/supercollider.log" >/dev/null 2>&1; then
        forwarded=$(grep -c '^WorldState .* -> Tidal /ctrl$' "$runtime_log_dir/supercollider.log" 2>/dev/null || true)
        if [ "$forwarded" -gt 0 ]; then
            report "OK WorldState OSC bridge active forwarded_messages=$forwarded"
        else
            report "FAIL WorldState OSC bridge loaded but no forwarded messages observed"
            status=1
        fi
    else
        report "FAIL WorldState OSC bridge marker missing"
        status=1
    fi
    if [ -f "$audio_heartbeat_file" ]; then
        heartbeat_modified=$(stat -f '%m' "$audio_heartbeat_file" 2>/dev/null || printf '0')
        heartbeat_now=$(date +%s)
        heartbeat_age=$((heartbeat_now - heartbeat_modified))
        dirt_play_count=$(sed -n 's/^dirt_play_count=\([0-9][0-9]*\)$/\1/p' "$audio_heartbeat_file" | tail -n 1)
        if [ "${dirt_play_count:-0}" -gt 0 ] && [ "$heartbeat_age" -ge 0 ] && [ "$heartbeat_age" -le "$audio_heartbeat_max_age" ]; then
            report "OK audio transport active SuperDirt_received_dirt_play=$dirt_play_count last_seen_seconds_ago=$heartbeat_age"
        else
            report "FAIL audio transport stale SuperDirt_received_dirt_play=${dirt_play_count:-0} last_seen_seconds_ago=$heartbeat_age"
            status=1
        fi
    else
        report "FAIL audio transport has no /dirt/play heartbeat"
        status=1
    fi
else
    report "OPTIONAL UNAVAILABLE music stack disabled by configuration"
fi

report "Runtime started: $runtime_started_at"
report "Logs: $runtime_log_dir"
exit "$status"
