#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
duration=${EVOLVING_ENDURANCE_DURATION:-3600}
generation_interval=${EVOLVING_ENDURANCE_GENERATION_INTERVAL:-6}
outage_at=${EVOLVING_ENDURANCE_OUTAGE_AT:-600}
outage_duration=${EVOLVING_ENDURANCE_OUTAGE_DURATION:-30}
service_port=${EVOLVING_ENDURANCE_PORT:-8900}
log_dir=${EVOLVING_ENDURANCE_LOG_DIR:-$(mktemp -d /tmp/evolving-impressionist-endurance.XXXXXX)}
app_log="$log_dir/app.log"
service_log="$log_dir/service.log"
samples="$log_dir/process.csv"
events="$log_dir/events.log"

mkdir -p "$log_dir"
printf 'elapsed_seconds,pid,rss_kb,vsz_kb\n' >"$samples"
: >"$app_log"
: >"$service_log"
: >"$events"

service_pid=
app_pid=
caffeinate_pid=

timestamp() { date '+%Y-%m-%dT%H:%M:%S%z'; }
event() { printf '%s %s\n' "$(timestamp)" "$*" | tee -a "$events"; }

start_service() {
    EVOLVING_VISUAL_PORT="$service_port" EVOLVING_QUIET=1 \
        stdbuf -oL python3 "$repo_dir/visual_service/server.py" >>"$service_log" 2>&1 &
    service_pid=$!
}

cleanup() {
    if [ -n "$app_pid" ]; then kill "$app_pid" 2>/dev/null || true; fi
    if [ -n "$caffeinate_pid" ]; then kill "$caffeinate_pid" 2>/dev/null || true; fi
    if [ -n "$service_pid" ]; then kill "$service_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT INT TERM

cd "$repo_dir"
start_service
attempt=0
until curl -fsS "http://127.0.0.1:$service_port/health" >/dev/null; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 50 ]; then
        event "FAIL visual service did not start"
        exit 1
    fi
    sleep 0.1
done

EVOLVING_VISUAL_URL="http://127.0.0.1:$service_port" \
EVOLVING_GENERATION_INTERVAL="$generation_interval" \
EVOLVING_DIAGNOSTICS=1 \
    caffeinate -dimsu stdbuf -oL "$repo_dir/.build/release/EvolvingImpressionist" >>"$app_log" 2>&1 &
caffeinate_pid=$!
# With a utility argument, macOS caffeinate execs the utility in its original
# PID and starts a small assertion helper beneath it. Sample the original PID;
# sampling the child would measure the helper instead of the Swift app.
app_pid=$caffeinate_pid
sleep 1
if ! kill -0 "$app_pid" 2>/dev/null; then
    event "FAIL application process did not start"
    exit 1
fi

event "START duration=$duration generation_interval=$generation_interval app_pid=$app_pid log_dir=$log_dir"
started=$(date +%s)
outage_stopped=0
outage_recovered=0

while :; do
    now=$(date +%s)
    elapsed=$((now - started))
    [ "$elapsed" -ge "$duration" ] && break

    if ! kill -0 "$app_pid" 2>/dev/null; then
        event "FAIL application exited at elapsed=$elapsed"
        exit 1
    fi

    if [ "$outage_stopped" -eq 0 ] && [ "$elapsed" -ge "$outage_at" ]; then
        kill "$service_pid" 2>/dev/null || true
        wait "$service_pid" 2>/dev/null || true
        service_pid=
        outage_stopped=1
        event "OUTAGE_STARTED elapsed=$elapsed"
    fi

    if [ "$outage_stopped" -eq 1 ] && [ "$outage_recovered" -eq 0 ] && [ "$elapsed" -ge $((outage_at + outage_duration)) ]; then
        start_service
        outage_recovered=1
        event "OUTAGE_RECOVERY_STARTED elapsed=$elapsed service_pid=$service_pid"
    fi

    set -- $(ps -o rss=,vsz= -p "$app_pid")
    printf '%s,%s,%s,%s\n' "$elapsed" "$app_pid" "$1" "$2" >>"$samples"
    sleep 30
done

if ! kill -0 "$app_pid" 2>/dev/null; then
    event "FAIL application did not survive full duration"
    exit 1
fi

event "PASS application survived elapsed=$(( $(date +%s) - started ))"
exit 0
