#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
service_port=8877
service_log=/tmp/evolving-impressionist-visual-service.log

cd "$repo_dir"
python3 -m unittest discover -s visual_service/tests -v
swift build

EVOLVING_VISUAL_PORT=$service_port EVOLVING_QUIET=1 python3 visual_service/server.py >"$service_log" 2>&1 &
service_pid=$!
trap 'kill "$service_pid" 2>/dev/null || true' EXIT INT TERM

attempt=0
until curl -fsS "http://127.0.0.1:$service_port/health" >/dev/null; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 50 ]; then
        printf 'Visual service failed to start; log: %s\n' "$service_log" >&2
        exit 1
    fi
    sleep 0.1
done

VISUAL_SERVICE_URL="http://127.0.0.1:$service_port" swift run EvolvingImpressionistVerify
