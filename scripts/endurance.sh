#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
duration=${EVOLVING_ENDURANCE_DURATION:-3600}
generation_interval=${EVOLVING_ENDURANCE_GENERATION_INTERVAL:-6}
outage_at=${EVOLVING_ENDURANCE_OUTAGE_AT:-600}
outage_duration=${EVOLVING_ENDURANCE_OUTAGE_DURATION:-30}
service_port=${EVOLVING_ENDURANCE_PORT:-8900}
sample_interval=${EVOLVING_ENDURANCE_SAMPLE_INTERVAL:-30}
log_dir=${EVOLVING_ENDURANCE_LOG_DIR:-$(mktemp -d /tmp/evolving-impressionist-endurance.XXXXXX)}
app_log="$log_dir/app.log"
service_log="$log_dir/service.log"
samples="$log_dir/process.csv"
events="$log_dir/events.log"
summary="$log_dir/summary.txt"

mkdir -p "$log_dir"
printf 'elapsed_seconds,pid,rss_kb,vsz_kb,cpu_percent\n' >"$samples"
: >"$app_log"
: >"$service_log"
: >"$events"
: >"$summary"

service_pid=
app_pid=
caffeinate_pid=

timestamp() { date '+%Y-%m-%dT%H:%M:%S%z'; }
event() { printf '%s %s\n' "$(timestamp)" "$*" | tee -a "$events"; }

start_service() {
    EVOLVING_BACKEND=mock EVOLVING_VISUAL_PORT="$service_port" EVOLVING_QUIET=1 \
        uv run --frozen python -u "$repo_dir/backend/server.py" >>"$service_log" 2>&1 &
    service_pid=$!
}

wait_for_unhealthy() {
    health_attempt=0
    while curl -fsS "http://127.0.0.1:$service_port/health" >/dev/null 2>&1; do
        health_attempt=$((health_attempt + 1))
        if [ "$health_attempt" -ge 50 ]; then return 1; fi
        sleep 0.1
    done
}

wait_for_health() {
    health_attempt=0
    until curl -fsS "http://127.0.0.1:$service_port/health" >/dev/null 2>&1; do
        health_attempt=$((health_attempt + 1))
        if [ "$health_attempt" -ge 100 ]; then return 1; fi
        sleep 0.1
    done
}

latest_counter() {
    sed -n "s/.*$1=\([0-9][0-9]*\).*/\1/p" "$app_log" | tail -n 1
}

cleanup() {
    if [ -n "$app_pid" ]; then kill "$app_pid" 2>/dev/null || true; fi
    if [ -n "$caffeinate_pid" ]; then kill "$caffeinate_pid" 2>/dev/null || true; fi
    if [ -n "$service_pid" ]; then kill "$service_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT INT TERM

cd "$repo_dir"
[ -x "$repo_dir/.build/release/EvolvingImpressionist" ] || {
    event "FAIL release application is missing; run swift build -c release"
    exit 1
}
start_service
if ! wait_for_health; then
    event "FAIL visual service did not start"
    exit 1
fi

EVOLVING_VISUAL_URL="http://127.0.0.1:$service_port" \
EVOLVING_GENERATION_INTERVAL="$generation_interval" \
EVOLVING_DIAGNOSTICS=1 \
    caffeinate -dimsu "$repo_dir/.build/release/EvolvingImpressionist" >>"$app_log" 2>&1 &
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
successes_at_outage=0
failures_at_outage=0
successes_at_restart=0
failures_at_restart=0
outage_health_failed=0
outage_failure_observed=0
generation_recovered=0

while :; do
    now=$(date +%s)
    elapsed=$((now - started))
    [ "$elapsed" -ge "$duration" ] && break

    if ! kill -0 "$app_pid" 2>/dev/null; then
        event "FAIL application exited at elapsed=$elapsed"
        exit 1
    fi

    if [ "$outage_stopped" -eq 0 ] && [ "$elapsed" -ge "$outage_at" ]; then
        successes_at_outage=$(latest_counter generations_ok)
        successes_at_outage=${successes_at_outage:-0}
        failures_at_outage=$(latest_counter generations_failed)
        failures_at_outage=${failures_at_outage:-0}
        if [ "$successes_at_outage" -lt 1 ]; then
            event "FAIL outage started before any successful generation"
            exit 1
        fi
        kill "$service_pid" 2>/dev/null || true
        wait "$service_pid" 2>/dev/null || true
        service_pid=
        if ! wait_for_unhealthy; then
            event "FAIL visual service health remained available after stop"
            exit 1
        fi
        outage_health_failed=1
        outage_stopped=1
        event "OUTAGE_STARTED elapsed=$elapsed generations_ok=$successes_at_outage generations_failed=$failures_at_outage health_unavailable=1"
    fi

    if [ "$outage_stopped" -eq 1 ] && [ "$outage_recovered" -eq 0 ] && [ "$elapsed" -ge $((outage_at + outage_duration)) ]; then
        failures_at_restart=$(latest_counter generations_failed)
        failures_at_restart=${failures_at_restart:-0}
        if [ "$failures_at_restart" -le "$failures_at_outage" ]; then
            event "FAIL no generation failure occurred during outage failures_before=$failures_at_outage failures_after=$failures_at_restart"
            exit 1
        fi
        outage_failure_observed=1
        start_service
        if ! wait_for_health; then
            event "FAIL visual service did not restart"
            exit 1
        fi
        successes_at_restart=$(latest_counter generations_ok)
        successes_at_restart=${successes_at_restart:-0}
        outage_recovered=1
        event "OUTAGE_RECOVERY_STARTED elapsed=$elapsed service_pid=$service_pid generations_ok=$successes_at_restart generations_failed=$failures_at_restart"
    fi

    if [ "$outage_recovered" -eq 1 ] && [ "$generation_recovered" -eq 0 ]; then
        current_successes=$(latest_counter generations_ok)
        current_successes=${current_successes:-0}
        if [ "$current_successes" -gt "$successes_at_restart" ]; then
            generation_recovered=1
            event "GENERATION_RECOVERED elapsed=$elapsed generations_ok=$current_successes"
        fi
    fi

    set -- $(ps -o rss=,vsz=,%cpu= -p "$app_pid")
    printf '%s,%s,%s,%s,%s\n' "$elapsed" "$app_pid" "$1" "$2" "$3" >>"$samples"
    sleep "$sample_interval"
done

if ! kill -0 "$app_pid" 2>/dev/null; then
    event "FAIL application did not survive full duration"
    exit 1
fi

success_count=$(latest_counter generations_ok)
failure_count=$(latest_counter generations_failed)
success_count=${success_count:-0}
failure_count=${failure_count:-0}

if [ "$outage_stopped" -eq 1 ] && { [ "$outage_health_failed" -ne 1 ] || [ "$outage_failure_observed" -ne 1 ]; }; then
    event "FAIL outage did not prove both unavailable health and a new generation failure"
    exit 1
fi
if [ "$outage_recovered" -eq 1 ] && [ "$generation_recovered" -ne 1 ]; then
    event "FAIL no successful generation was recorded after service restart"
    exit 1
fi

if ! parameter_summary=$(awk '
    BEGIN { names[1]="brightness"; names[2]="warmth"; names[3]="abstraction"; names[4]="motion"; names[5]="tension" }
    /^\[installation\] generations_ok=/ {
        observations++
        for (field = 1; field <= NF; field++) {
            split($field, pair, "=")
            for (n = 1; n <= 5; n++) {
                if (pair[1] == names[n]) {
                    value = pair[2] + 0
                    if (value < 0 || value > 1) invalid = 1
                    if (!(names[n] in minimum) || value < minimum[names[n]]) minimum[names[n]] = value
                    if (!(names[n] in maximum) || value > maximum[names[n]]) maximum[names[n]] = value
                }
            }
        }
    }
    END {
        if (observations == 0 || invalid) exit 1
        printf "parameter_observations=%d", observations
        for (n = 1; n <= 5; n++) printf " %s_min=%.6f %s_max=%.6f", names[n], minimum[names[n]], names[n], maximum[names[n]]
        printf "\n"
    }
' "$app_log"); then
    event "FAIL diagnostics were missing or a parameter escaped 0...1"
    exit 1
fi

process_summary=$(awk -F, '
    NR == 2 { first_rss = $3 }
    NR > 1 {
        samples++
        last_rss = $3
        if ($3 > max_rss) max_rss = $3
        cpu_sum += $5
        if ($5 > max_cpu) max_cpu = $5
    }
    END {
        if (samples == 0) exit 1
        printf "process_samples=%d rss_initial_kb=%d rss_final_kb=%d rss_max_kb=%d cpu_average_percent=%.2f cpu_max_percent=%.2f\n", samples, first_rss, last_rss, max_rss, cpu_sum / samples, max_cpu
    }
' "$samples")

elapsed_total=$(( $(date +%s) - started ))
{
    printf 'duration_seconds=%s generations_ok=%s generations_failed=%s recovery_events=%s\n' "$elapsed_total" "$success_count" "$failure_count" "$generation_recovered"
    printf '%s\n' "$process_summary"
    printf '%s\n' "$parameter_summary"
} | tee "$summary"
event "PASS application survived elapsed=$elapsed_total generations_ok=$success_count generations_failed=$failure_count"
exit 0
