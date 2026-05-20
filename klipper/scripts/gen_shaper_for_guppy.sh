#!/bin/sh
# gen_shaper_for_guppy.sh — unified shaper-PNG generator for BOTH UIs.
#
# Installed at: /usr/data/e5m-ck/bin/gen_shaper_for_guppy.sh
# Invoked by:   [gcode_shell_command guppy_input_shaper] (input_shaper.cfg)
# Companion:    /usr/data/e5m-ck/bin/_shaper_with_figsize.py
#
# This is called from TWO entry points, with identical PARAMS format:
#
#   1. GuppyScreen "Input Shaper" button → its binary emits
#      `RUN_SHELL_COMMAND CMD=guppy_input_shaper PARAMS=...` directly.
#   2. Fluidd's MEASURE_AXIS macro → emits the SAME RUN_SHELL_COMMAND
#      with the SAME PARAMS so the two flows are byte-for-byte identical.
#
# Expected PARAMS:
#   /tmp/resonances_<axis>_<axis>.csv -o <small_png_path> -w 4.8 -l 2.72
#
# We produce TWO PNGs from each invocation, always at fixed paths so
# users don't deal with timestamped clutter:
#
#   Small (4.8x2.72 in, 480x272 px) for GuppyScreen's screen:
#     /usr/data/printer_data/config/resonances_<axis>.png
#   Large (8x4.8 in) for Fluidd's File Manager preview:
#     /usr/data/printer_data/config/printer_calibration_graphs/resonances_<axis>.png
#
# Both use Klipper master's scripts/calibrate_shaper.py with
# `--shapers=mzv` to force MZV as the recommended shaper. find_best_shaper
# will only consider MZV in its candidate list, so the JSON output's
# "best" field is guaranteed to be "mzv" regardless of the measurement.
#
# After the Y axis call, we enqueue APPLY_SHAPER_MAX_ACCEL via Moonraker.
# That command refits MZV on both axes' latest CSVs, writes the
# [input_shaper] autosave entry, and updates [printer] max_accel.

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
export PYTHONPATH="$KLIPPER_DIR/klippy:${PYTHONPATH:-}"

echo "guppy_input_shaper: axis=$AXIS csv=$CSV"

# 1. Small PNG (GuppyScreen on-screen). Forced size via wrapper, --shapers=mzv.
if [ -n "$OUT_SMALL" ]; then
    /usr/share/klippy-env/bin/python3 "$WRAPPER" \
        "$SMALL_W" "$SMALL_L" "$CSV" -o "$OUT_SMALL" --shapers=mzv
    echo "GuppyScreen PNG: $OUT_SMALL (${SMALL_W} x ${SMALL_L} in)"
fi

# 2. Large PNG (Fluidd File Manager). Fixed 8x4.8, --shapers=mzv, no
#    timestamp — overwrite the latest. Keeps the directory tidy.
GRAPHS_DIR="/usr/data/printer_data/config/printer_calibration_graphs"
mkdir -p "$GRAPHS_DIR"
OUT_LARGE="$GRAPHS_DIR/resonances_${AXIS}.png"
/usr/share/klippy-env/bin/python3 "$WRAPPER" \
    8 4.8 "$CSV" -o "$OUT_LARGE" --shapers=mzv
echo "Fluidd PNG:      $OUT_LARGE (8 x 4.8 in)"

# 3. After Y: enqueue APPLY_SHAPER_MAX_ACCEL via Moonraker.
#
# Detached curl: Klippy is currently inside this RUN_SHELL_COMMAND and
# can't process queued gcode until we return. Synchronous curl would
# deadlock (Moonraker holds the request waiting for completion, but
# Klippy can't complete it until our shell exits). Background subshell
# fires the request and returns immediately.
if [ "$AXIS" = "y" ]; then
    echo "Y axis done — enqueueing APPLY_SHAPER_MAX_ACCEL..."
    ( curl -s -X POST http://127.0.0.1:7125/printer/gcode/script \
          -H 'Content-Type: application/json' \
          -d '{"script":"APPLY_SHAPER_MAX_ACCEL"}' \
          >/dev/null 2>&1 & ) </dev/null
fi
