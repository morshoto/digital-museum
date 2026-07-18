#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tidal_source="$repo_dir/tidal/EvolvingImpressionist.hs"
tidal_data_dir=$(ghc-pkg field tidal data-dir | sed -n 's/^data-dir: //p')
boot_tidal="$tidal_data_dir/BootTidal.hs"
input_file=$(mktemp /tmp/evolving-impressionist-tidal-input.XXXXXX)
output_file=$(mktemp /tmp/evolving-impressionist-tidal-output.XXXXXX)

cleanup() {
    rm -f "$input_file" "$output_file"
}
trap cleanup EXIT INT TERM

awk '
    /^d[12] \$/ { print ":{"; in_pattern = 1 }
    in_pattern && /^$/ { print ":}"; in_pattern = 0 }
    { print }
    END { if (in_pattern) print ":}"; print "hush" }
' "$tidal_source" >"$input_file"

if ! ghci -v0 -ghci-script "$boot_tidal" <"$input_file" >"$output_file" 2>&1; then
    cat "$output_file"
    exit 1
fi

cat "$output_file"
if grep -Eq '(^|:)([0-9]+:)?[0-9]+: error:|Exception|Not in scope' "$output_file"; then
    exit 1
fi

printf '%s\n' 'PASS: EvolvingImpressionist.hs evaluated both patterns without errors'
