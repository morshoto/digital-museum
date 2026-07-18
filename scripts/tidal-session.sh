#!/bin/sh
set -eu

tidal_data_dir=$(ghc-pkg field tidal data-dir | sed -n 's/^data-dir: //p')
boot_tidal="$tidal_data_dir/BootTidal.hs"
generated_boot=

cleanup() {
    [ -n "$generated_boot" ] && rm -f "$generated_boot"
}
trap cleanup EXIT INT TERM

if [ ! -f "$boot_tidal" ]; then
    printf 'BootTidal.hs not found at %s\n' "$boot_tidal" >&2
    exit 1
fi

control_port=${EVOLVING_TIDAL_CONTROL_PORT:-6010}
dirt_port=${EVOLVING_DIRT_PORT:-57120}
case "$control_port:$dirt_port" in *[!0-9:]*) printf '%s\n' 'Tidal and Dirt ports must be integers' >&2; exit 1 ;; esac

if [ "$control_port" != 6010 ] || [ "$dirt_port" != 57120 ]; then
    generated_boot=$(mktemp /tmp/evolving-impressionist-boot-tidal.XXXXXX)
    awk -v control_port="$control_port" -v dirt_port="$dirt_port" '
        /^tidalInst <- mkTidal$/ {
            print "tidalInst <- mkTidalWith [(superdirtTarget { oPort = " dirt_port " }, [superdirtShape])] (defaultConfig { cCtrlPort = " control_port " })"
            next
        }
        { print }
    ' "$boot_tidal" >"$generated_boot"
    replacement_count=$(grep -c '^tidalInst <- mkTidalWith' "$generated_boot" || true)
    if [ "$replacement_count" -ne 1 ] || \
        ! grep -F "oPort = $dirt_port" "$generated_boot" >/dev/null || \
        ! grep -F "cCtrlPort = $control_port" "$generated_boot" >/dev/null; then
        printf '%s\n' 'Failed to apply configured ports to the pinned BootTidal.hs; refusing silent defaults' >&2
        exit 1
    fi
    boot_tidal=$generated_boot
fi

if [ -n "$generated_boot" ]; then
    ghci -ghci-script "$boot_tidal"
else
    exec ghci -ghci-script "$boot_tidal"
fi
