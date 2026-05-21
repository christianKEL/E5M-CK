#!/bin/sh
# gen_shaper_for_guppy.sh — unified shaper-PNG generator for BOTH UIs.
#
# Installed at: /usr/data/e5m-ck/bin/gen_shaper_for_guppy.sh
# Invoked by:   [gcode_shell_command guppy_input_shaper] (macros/input_shaper.cfg)
# Backend:      /usr/data/e5m-ck/bin/shaper_full.py
#
# Two entry points hit this script with identical PARAMS format:
#
#   1. GuppyScreen "Input Shaper" UI button — its binary emits
#      `RUN_SHELL_COMMAND CMD=guppy_input_shaper PARAMS=...` directly,
#      with -w/-l computed from screen resolution (Nebula Pad 480x272
#      → -w 4.8 -l 2.72).
#   2. Fluidd MEASURE_AXIS macro — emits the SAME RUN_SHELL_COMMAND
#      with the SAME PARAMS so the two flows are byte-for-byte identical.
#
# Expected PARAMS:
#   /tmp/resonances_<axis>_<axis>.csv -o <small_png_path> -w 4.8 -l 2.72
#
# Output paths:
#   <small_png_path>  (always exactly what GuppyScreen requested via -o,
#                      typically /usr/data/printer_data/config/resonances_<axis>.png)
#                      Real file. GuppyScreen rebuilds this path itself
#                      from <config_root>/resonances_<axis>.png and reads
#                      the PNG via LVGL's `A:` (stdio) mount, so the file
#                      MUST exist at exactly that path.
#   /usr/data/printer_data/config/printer_calibration_graphs/
#       resonance_<axis>_full.png   (8x4.8 in, desktop preview for Fluidd)
#
# Both PNGs come out of a SINGLE python process (shaper_full.py) — one
# matplotlib import for both renders + the JSON output. This was the
# fix for OOM kills we saw with the previous 3-script chain on the
# 200 MB MIPS host (matplotlib eats ~50 MB per import).
#
# After the Y axis run, we enqueue APPLY_SHAPER_MAX_ACCEL via a
# detached curl to Moonraker. That command refits with shapers=['mzv']
# (forced) on both axes' latest CSVs, writes shaper_type=mzv to the
# [input_shaper] autosave entry (in memory), and rewrites [printer]
# max_accel in printer.cfg in place.

set -eu

if [ $# -lt 1 ]; then
    echo "Usage: $0 <csv> [-o <png>] [-w <inch>] [-l <inch>]" >&2
    exit 1
fi

CSV="$1"; shift
OUT_SMALL=""
SMALL_W="4.8"
SMALL_L="2.72"
while [ $# -gt 0 ]; do
    case "$1" in
        -o) shift; OUT_SMALL="$1"; shift ;;
        -w) shift; SMALL_W="$1"; shift ;;
        -l) shift; SMALL_L="$1"; shift ;;
        *)  shift ;;
    esac
done

# Axis from CSV: /tmp/resonances_<axis>_<NAME>.csv
AXIS=$(echo "$CSV" | sed -n 's|.*resonances_\([xy]\)_.*|\1|p')
[ -z "$AXIS" ] && AXIS="unknown"

# Small PNG goes at the path GuppyScreen requested via -o; default
# matches the canonical path GuppyScreen reconstructs internally if
# -o wasn't passed (e.g. Fluidd MEASURE_AXIS calling with the same args).
SMALL_PNG="${OUT_SMALL:-/usr/data/printer_data/config/resonances_${AXIS}.png}"

GRAPHS_DIR="/usr/data/printer_data/config/printer_calibration_graphs"
FULL_PNG="$GRAPHS_DIR/resonance_${AXIS}_full.png"
mkdir -p "$GRAPHS_DIR"

# Clean up any leftover symlink at the small path from earlier installs.
[ -L "$SMALL_PNG" ] && rm -f "$SMALL_PNG"

echo "guppy_input_shaper: axis=$AXIS csv=$CSV"

# Single Python process: fit + small PNG + full PNG + JSON.
/usr/share/klippy-env/bin/python3 \
    /usr/data/e5m-ck/bin/shaper_full.py \
    "$CSV" \
    -o "$SMALL_PNG" -w "$SMALL_W" -l "$SMALL_L" \
    --full "$FULL_PNG"

echo "GuppyScreen PNG: $SMALL_PNG (${SMALL_W} x ${SMALL_L} in)"
echo "Full PNG:        $FULL_PNG (8 x 4.8 in)"

# After Y: enqueue APPLY_SHAPER_MAX_ACCEL via Moonraker.
#
# Detached curl avoids deadlock: Klippy is still inside this
# RUN_SHELL_COMMAND and cannot process queued gcode until we return.
# A synchronous curl would have Moonraker hold the HTTP request
# waiting for Klippy to complete the queued APPLY — and Klippy can't
# complete it until our shell exits. Detached subshell fires off the
# request and returns immediately; Klippy picks up APPLY after.
if [ "$AXIS" = "y" ]; then
    echo "Y axis done — enqueueing APPLY_SHAPER_MAX_ACCEL..."
    ( curl -s -X POST http://127.0.0.1:7125/printer/gcode/script \
          -H 'Content-Type: application/json' \
          -d '{"script":"APPLY_SHAPER_MAX_ACCEL"}' \
          >/dev/null 2>&1 & ) </dev/null
fi
