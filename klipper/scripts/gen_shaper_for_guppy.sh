#!/bin/sh
# gen_shaper_for_guppy.sh — unified shaper-PNG generator for BOTH UIs.
#
# Installed at: /usr/data/e5m-ck/bin/gen_shaper_for_guppy.sh
# Invoked by:   [gcode_shell_command guppy_input_shaper] (macros/input_shaper.cfg)
# Companion:    /usr/data/e5m-ck/bin/_shaper_with_figsize.py
#
# Two entry points hit this script with identical PARAMS format:
#
#   1. GuppyScreen "Input Shaper" UI button — the binary emits
#      `RUN_SHELL_COMMAND CMD=guppy_input_shaper PARAMS=...` directly.
#   2. Fluidd MEASURE_AXIS macro — emits the SAME RUN_SHELL_COMMAND
#      with the SAME PARAMS so the two flows are byte-for-byte identical.
#
# Expected PARAMS:
#   /tmp/resonances_<axis>_<axis>.csv -o <small_png_path> -w 4.8 -l 2.72
#
# Canonical output paths (both UIs always produce both files):
#   /usr/data/printer_data/config/printer_calibration_graphs/
#       resonance_<axis>_guppy_screen.png   (4.8x2.72 in, 480x272 px)
#       resonance_<axis>_full.png           (8x4.8 in, desktop preview)
#
# GuppyScreen's binary hardcodes the path it polls for its on-screen
# display (/usr/data/printer_data/config/resonances_<axis>.png — comes
# in via -o). We honor that by SYMLINKING from there to the canonical
# guppy_screen PNG. The symlink is transparent to GuppyScreen and keeps
# all real PNG content in printer_calibration_graphs/.
#
# Both PNGs use Klipper master's scripts/calibrate_shaper.py via the
# matplotlib-figsize-forced _shaper_with_figsize.py wrapper, with
# `--shapers=mzv` so the recommended shaper is always MZV.
#
# After the Y axis call, we enqueue APPLY_SHAPER_MAX_ACCEL via a
# detached curl to Moonraker — that command refits MZV on both axes'
# latest CSVs, writes the [input_shaper] autosave entry, and updates
# [printer] max_accel in printer.cfg.

set -eu

if [ $# -lt 1 ]; then
    echo "Usage: $0 <csv> [-o <png>] [-w <inch>] [-l <inch>]" >&2
    exit 1
fi

CSV="$1"; shift
OUT_REQUESTED=""
SMALL_W="4.8"
SMALL_L="2.72"
while [ $# -gt 0 ]; do
    case "$1" in
        -o) shift; OUT_REQUESTED="$1"; shift ;;
        -w) shift; SMALL_W="$1"; shift ;;
        -l) shift; SMALL_L="$1"; shift ;;
        *)  shift ;;
    esac
done

# Axis from CSV: /tmp/resonances_<axis>_<NAME>.csv
AXIS=$(echo "$CSV" | sed -n 's|.*resonances_\([xy]\)_.*|\1|p')
[ -z "$AXIS" ] && AXIS="unknown"

WRAPPER="/usr/data/e5m-ck/bin/_shaper_with_figsize.py"
KLIPPER_DIR="/usr/data/e5m-ck/klipper"
GRAPHS_DIR="/usr/data/printer_data/config/printer_calibration_graphs"
SMALL_CANON="$GRAPHS_DIR/resonance_${AXIS}_guppy_screen.png"
LARGE_CANON="$GRAPHS_DIR/resonance_${AXIS}_full.png"

export PYTHONPATH="$KLIPPER_DIR/klippy:${PYTHONPATH:-}"
mkdir -p "$GRAPHS_DIR"

echo "guppy_input_shaper: axis=$AXIS csv=$CSV"

# 1. Small PNG (GuppyScreen size). Always written to the canonical
#    printer_calibration_graphs/ path.
/usr/share/klippy-env/bin/python3 "$WRAPPER" \
    "$SMALL_W" "$SMALL_L" "$CSV" -o "$SMALL_CANON" --shapers=mzv
echo "GuppyScreen-sized PNG: $SMALL_CANON (${SMALL_W} x ${SMALL_L} in)"

# 2. If GuppyScreen asked us to write to a specific path (via -o), make
#    that path a symlink to the canonical. GuppyScreen polls the path
#    it requested; the symlink is transparent. Replaces any old regular
#    file or stale symlink there.
if [ -n "$OUT_REQUESTED" ] && [ "$OUT_REQUESTED" != "$SMALL_CANON" ]; then
    rm -f "$OUT_REQUESTED"
    ln -s "$SMALL_CANON" "$OUT_REQUESTED"
    echo "Symlinked $OUT_REQUESTED -> $SMALL_CANON"
fi

# 3. Large PNG (desktop / Fluidd preview). Default 8x4.8 in.
/usr/share/klippy-env/bin/python3 "$WRAPPER" \
    8 4.8 "$CSV" -o "$LARGE_CANON" --shapers=mzv
echo "Full-sized PNG: $LARGE_CANON (8 x 4.8 in)"

# 4. After Y: enqueue APPLY_SHAPER_MAX_ACCEL via Moonraker.
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
