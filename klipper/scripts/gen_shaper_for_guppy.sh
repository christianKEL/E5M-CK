#!/bin/sh
# gen_shaper_for_guppy.sh — unified shaper-PNG generator for BOTH UIs.
#
# Installed at: /usr/data/e5m-ck/bin/gen_shaper_for_guppy.sh
# Invoked by:   [gcode_shell_command guppy_input_shaper] (macros/input_shaper.cfg)
# Companions:   /usr/data/e5m-ck/bin/_shaper_with_figsize.py
#               /usr/data/e5m-ck/bin/shaper_json_emitter.py
#
# Two entry points hit this script with identical PARAMS format:
#
#   1. GuppyScreen "Input Shaper" UI button — its binary emits
#      `RUN_SHELL_COMMAND CMD=guppy_input_shaper PARAMS=...` directly.
#   2. Fluidd MEASURE_AXIS macro — emits the SAME RUN_SHELL_COMMAND
#      with the SAME PARAMS so the two flows are byte-for-byte identical.
#
# Expected PARAMS:
#   /tmp/resonances_<axis>_<axis>.csv -o <small_png_path> -w 4.8 -l 2.72
#
# Output paths (always the same regardless of caller):
#   /tmp/resonances_<axis>.png                                        (volatile,
#                                                                     small PNG
#                                                                     consumed by
#                                                                     GuppyScreen on
#                                                                     the Nebula Pad)
#   /usr/data/printer_data/config/printer_calibration_graphs/
#       resonance_<axis>_full.png                                     (persistent,
#                                                                     full size for
#                                                                     Fluidd's File
#                                                                     Manager)
#
# GuppyScreen passes its requested small-PNG path via -o (typically
# /usr/data/printer_data/config/resonances_<axis>.png). We ignore that
# path and route the small PNG to /tmp/ instead — GuppyScreen knows
# where the PNG landed because we emit a JSON line on stdout with the
# correct "png" field, which the binary parses to locate the file.
#
# Both PNGs use Klipper master's scripts/calibrate_shaper.py via the
# matplotlib-figsize-forced _shaper_with_figsize.py wrapper. No
# --shapers restriction here — the PNG shows the full candidate set
# (zv, mzv, ei, 2hump_ei, 3hump_ei) for visual comparison, just like
# Klipper's stock workflow. The "Recommended shaper" line printed by
# the script is informational only.
#
# After both PNGs are written, shaper_json_emitter.py prints the JSON
# line GuppyScreen expects, with "best": "mzv" hardcoded (project policy)
# and "png" pointing to the /tmp/ small PNG.
#
# After the Y axis call, we enqueue APPLY_SHAPER_MAX_ACCEL via a
# detached curl to Moonraker. That command refits with shapers=['mzv']
# (forced) on both axes' latest CSVs, writes shaper_type=mzv to the
# [input_shaper] autosave entry (in memory), and rewrites [printer]
# max_accel in printer.cfg in place — so the next SAVE_INPUT_SHAPER
# (or user-triggered SAVE_CONFIG) persists MZV.

set -eu

if [ $# -lt 1 ]; then
    echo "Usage: $0 <csv> [-o <ignored>] [-w <inch>] [-l <inch>]" >&2
    exit 1
fi

CSV="$1"; shift
SMALL_W="4.8"
SMALL_L="2.72"
while [ $# -gt 0 ]; do
    case "$1" in
        -o) shift; shift ;;             # GuppyScreen-requested path — ignored
        -w) shift; SMALL_W="$1"; shift ;;
        -l) shift; SMALL_L="$1"; shift ;;
        *)  shift ;;
    esac
done

# Axis from CSV: /tmp/resonances_<axis>_<NAME>.csv
AXIS=$(echo "$CSV" | sed -n 's|.*resonances_\([xy]\)_.*|\1|p')
[ -z "$AXIS" ] && AXIS="unknown"

BIN_DIR="/usr/data/e5m-ck/bin"
KLIPPER_DIR="/usr/data/e5m-ck/klipper"
WRAPPER="$BIN_DIR/_shaper_with_figsize.py"
JSON_EMITTER="$BIN_DIR/shaper_json_emitter.py"
PY="/usr/share/klippy-env/bin/python3"

GRAPHS_DIR="/usr/data/printer_data/config/printer_calibration_graphs"
mkdir -p "$GRAPHS_DIR"

SMALL_PNG="/tmp/resonances_${AXIS}.png"
LARGE_PNG="$GRAPHS_DIR/resonance_${AXIS}_full.png"

export PYTHONPATH="$KLIPPER_DIR/klippy:${PYTHONPATH:-}"

echo "guppy_input_shaper: axis=$AXIS csv=$CSV"

# 1. Small PNG → /tmp/, sized for the Nebula Pad screen.
"$PY" "$WRAPPER" "$SMALL_W" "$SMALL_L" "$CSV" -o "$SMALL_PNG"
echo "GuppyScreen PNG: $SMALL_PNG (${SMALL_W} x ${SMALL_L} in)"

# 2. Full-size PNG → printer_calibration_graphs/, for Fluidd preview.
"$PY" "$WRAPPER" 8 4.8 "$CSV" -o "$LARGE_PNG"
echo "Full PNG:        $LARGE_PNG (8 x 4.8 in)"

# 3. Emit the JSON line GuppyScreen parses. "png" = small PNG path so
#    GuppyScreen loads it for on-screen display. "best" = "mzv" (policy).
"$PY" "$JSON_EMITTER" "$CSV" --png "$SMALL_PNG"

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
