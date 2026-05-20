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
# Output paths:
#   <small_png_path>  (always exactly what GuppyScreen requested via -o,
#                      typically /usr/data/printer_data/config/resonances_<axis>.png)
#                      4.8x2.72 in, ~480x272 px. Real file — GuppyScreen's
#                      LVGL image loader doesn't follow symlinks reliably,
#                      so the small PNG must live at the requested path
#                      directly. No copy elsewhere.
#   /usr/data/printer_data/config/printer_calibration_graphs/
#       resonance_<axis>_full.png   (8x4.8 in, desktop preview for Fluidd)
#
# Both PNGs use Klipper master's scripts/calibrate_shaper.py via the
# matplotlib-figsize-forced _shaper_with_figsize.py wrapper. We do NOT
# pass --shapers=mzv here — the PNG shows the full candidate set
# (zv, mzv, ei, 2hump_ei, 3hump_ei) for visual comparison, just like
# Klipper's stock workflow. The "Recommended shaper" line printed by
# the script is informational only.
#
# After the Y axis call, we enqueue APPLY_SHAPER_MAX_ACCEL via a
# detached curl to Moonraker. That command refits with shapers=['mzv']
# (forced) on both axes' latest CSVs, writes shaper_type=mzv to the
# [input_shaper] autosave entry, and updates [printer] max_accel —
# so SAVE_CONFIG always persists MZV regardless of what the PNG's
# auto-pick suggested.

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

WRAPPER="/usr/data/e5m-ck/bin/_shaper_with_figsize.py"
KLIPPER_DIR="/usr/data/e5m-ck/klipper"
GRAPHS_DIR="/usr/data/printer_data/config/printer_calibration_graphs"
LARGE_CANON="$GRAPHS_DIR/resonance_${AXIS}_full.png"

export PYTHONPATH="$KLIPPER_DIR/klippy:${PYTHONPATH:-}"
mkdir -p "$GRAPHS_DIR"

echo "guppy_input_shaper: axis=$AXIS csv=$CSV"

# 1. Small PNG written directly to the requested path (where GuppyScreen
#    polls for its on-screen display). Replaces any stale file or symlink.
if [ -n "$OUT_SMALL" ]; then
    # Remove any previous symlink at this path (left over from earlier
    # versions of this script) so the new write is a real file.
    [ -L "$OUT_SMALL" ] && rm -f "$OUT_SMALL"
    /usr/share/klippy-env/bin/python3 "$WRAPPER" \
        "$SMALL_W" "$SMALL_L" "$CSV" -o "$OUT_SMALL"
    echo "GuppyScreen PNG: $OUT_SMALL (${SMALL_W} x ${SMALL_L} in)"
fi

# 2. Large PNG in printer_calibration_graphs/ — for Fluidd preview /
#    desktop viewing. 8x4.8 in. All shapers shown (no --shapers flag).
/usr/share/klippy-env/bin/python3 "$WRAPPER" \
    8 4.8 "$CSV" -o "$LARGE_CANON"
echo "Full PNG:        $LARGE_CANON (8 x 4.8 in)"

# 3. After Y: enqueue APPLY_SHAPER_MAX_ACCEL via Moonraker.
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
