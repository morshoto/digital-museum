#!/bin/sh
set -eu

tidal_data_dir=$(ghc-pkg field tidal data-dir | sed -n 's/^data-dir: //p')
boot_tidal="$tidal_data_dir/BootTidal.hs"

if [ ! -f "$boot_tidal" ]; then
    printf 'BootTidal.hs not found at %s\n' "$boot_tidal" >&2
    exit 1
fi

exec ghci -ghci-script "$boot_tidal"
