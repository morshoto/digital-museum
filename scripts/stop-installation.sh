#!/bin/sh
set -u

. "$(dirname -- "$0")/runtime-common.sh"

quiet=0
[ "${1:-}" = --quiet ] && quiet=1

if ! load_state; then
    [ "$quiet" -eq 1 ] || say "Installation is already stopped."
    exit 0
fi

stop_pid "${app_pid:-}" "Swift application"
if [ -p "$runtime_dir/tidal-input.fifo" ] && is_pid_running "${tidal_pid:-}"; then
    python3 -c 'import os,sys; fd=os.open(sys.argv[1], os.O_WRONLY | os.O_NONBLOCK); os.write(fd, b"hush\n:quit\n"); os.close(fd)' \
        "$runtime_dir/tidal-input.fifo" 2>/dev/null || true
fi
stop_pid "${tidal_pid:-}" "TidalCycles"
stop_pid "${tidal_keepalive_pid:-}" "Tidal FIFO keepalive"
stop_pid "${supercollider_pid:-}" "SuperCollider"
stop_pid "${visual_pid:-}" "visual service"

rm -f "$runtime_dir/tidal-input.fifo" "$state_file"
[ "$quiet" -eq 1 ] || say "Installation stopped cleanly. Logs retained at $runtime_log_dir"
