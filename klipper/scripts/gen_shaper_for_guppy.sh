#!/bin/sh
# gen_shaper_for_guppy.sh — wrapper for GuppyScreen's "Input Shaper" UI button.
#
# Installed at: /usr/data/e5m-ck/bin/gen_shaper_for_guppy.sh
# Invoked by:   [gcode_shell_command guppy_input_shaper] (input_shaper.cfg)
#
# GuppyScreen sends (per `strings` on the binary, confirmed 2026-05):
#   RUN_SHELL_COMMAND CMD=guppy_input_shaper \
#     PARAMS="/tmp/resonances_<axis>_<axis>.csv \
#             -o /usr/data/printer_data/config/resonances_<axis>.png \
#             -w 4.8 -l 2.72"
# (once per axis, after its own TEST_RESONANCES sweep).
#
# We produce TWO PNGs from each invocation plus auto-apply the
# recommended max_accel after Y — matching the Fluidd MEASURE_AXIS flow.
#
#   1. GuppyScreen-sized PNG at the -o path, 4.8x2.72 in for the
#      Nebula Pad's 480x272 screen (GuppyScreen displays at native res
#      with no scaling — confirmed in its binary).
#   2. Fluidd-readable PNG at /usr/data/printer_data/config/
#      printer_calibration_graphs/resonances_<axis>_<timestamp>.png,
#      8x4.8 in.
#   3. After axis=y, enqueue APPLY_SHAPER_MAX_ACCEL via Moonraker
#      (backgrounded to avoid Klippy gcode-queue deadlock).
#
# Why /usr/data/guppyscreen/scripts/calibrate_shaper.py instead of
# Klipper master's /usr/data/e5m-ck/klipper/scripts/calibrate_shaper.py:
# the vendored version still supports the -w/-l flags that mainline
# dropped. Same numerics either way (same shaper_calibrate library).
# The vendored script's shebang points to Entware python which lacks
# matplotlib — we invoke it via klippy-env's python explicitly.

set -eu

if [ $# -lt 1 ]; then
    echo "Usage: $0 <csv> [-o <png>] [-w <inch>] [-l <inch>]" >&2
    exit 1
fi

CSV="$1"; shift
OUT_SMALL=""
WIDTH="4.8"
LENGTH="2.72"
while [ $# -gt 0 ]; do
    case "$1" in
        -o) shift; OUT_SMALL="$1"; shift ;;
        -w) shift; WIDTH="$1"; shift ;;
        -l) shift; LENGTH="$1"; shift ;;
        *)  shift ;;
    esac
done

AXIS=$(echo "$CSV" | sed -n 's|.*resonances_\([xy]\)_.*|\1|p')
[ -z "$AXIS" ] && AXIS="unknown"

CALIBRATE="/usr/data/guppyscreen/scripts/calibrate_shaper.py"
[ -f "$CALIBRATE" ] || {
    echo "Vendored calibrate_shaper.py missing at $CALIBRATE — is GuppyScreen installed?" >&2
    exit 1
}
PY="/usr/share/klippy-env/bin/python3"

echo "guppy_input_shaper: axis=$AXIS csv=$CSV"

# 1. Small PNG (GuppyScreen on-screen).
if [ -n "$OUT_SMALL" ]; then
    "$PY" "$CALIBRATE" "$CSV" -o "$OUT_SMALL" -w "$WIDTH" -l "$LENGTH"
    echo "GuppyScreen PNG: $OUT_SMALL (${WIDTH} x ${LENGTH} in)"
fi

# 2. Large PNG (Fluidd File Manager).
GRAPHS_DIR="/usr/data/printer_data/config/printer_calibration_graphs"
mkdir -p "$GRAPHS_DIR"
TS=$(date +%Y%m%d_%H%M%S)
OUT_LARGE="$GRAPHS_DIR/resonances_${AXIS}_${TS}.png"
"$PY" "$CALIBRATE" "$CSV" -o "$OUT_LARGE" -w 8 -l 4.8
echo "Fluidd PNG:      $OUT_LARGE (8 x 4.8 in)"

# 3. After Y: queue APPLY_SHAPER_MAX_ACCEL via Moonraker.
#
# We curl 127.0.0.1:7125/printer/gcode/script which goes through
# Moonraker → Klippy via UDS. The detached background subshell is
# important: Klippy is currently inside this RUN_SHELL_COMMAND, so it
# can't pick up new gcode until we return. If we curl synchronously,
# Moonraker holds the HTTP request until Klippy completes the queued
# APPLY — and Klippy can't complete it until our shell exits. Deadlock.
# Detached curl returns immediately; Klippy picks the APPLY up after.
if [ "$AXIS" = "y" ]; then
    echo "Y axis done — enqueueing APPLY_SHAPER_MAX_ACCEL..."
    ( curl -s -X POST http://127.0.0.1:7125/printer/gcode/script \
          -H 'Content-Type: application/json' \
          -d '{"script":"APPLY_SHAPER_MAX_ACCEL"}' \
          >/dev/null 2>&1 & ) </dev/null
fi
