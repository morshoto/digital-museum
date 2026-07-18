#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

awk '
    /^d[12] \$/ { print ":{"; in_pattern = 1 }
    in_pattern && /^$/ { print ":}"; in_pattern = 0 }
    { print }
    END {
        if (in_pattern) print ":}"
        print "putStrLn \"INSTALLATION_TIDAL_READY\""
    }
' "$repo_dir/tidal/EvolvingImpressionist.hs"
