#!/bin/sh
# gen_belts_for_guppy.sh — unified belts-comparison PNG generator.
#
# Installed at: /usr/data/e5m-ck/bin/gen_belts_for_guppy.sh
# Invoked by:   [gcode_shell_command guppy_belts_calibration]
# Backend:      /usr/data/e5m-ck/bin/belts_full.py
#
# Two entry points hit this script with identical PARAMS format:
#
#   1. GuppyScreen "Belts/Shake" UI button → via the
#      GUPPY_BELTS_SHAPER_CALIBRATION macro (which it sends and our
#      macro definition handles).
#   2. Fluidd MEASURE_BELTS macro → calls GUPPY_BELTS_SHAPER_CALIBRATION
#      so the two flows are identical.
#
# Expected PARAMS:
#   -o <small_png_path> -w 4.8 -l 2.72
# (CSV pair auto-picked from /tmp/raw_data_axis*_e5m_belt_{a,b}.csv)
#
# Output paths:
#   <small_png_path>  (always exactly what GuppyScreen requested via -o,
#                      typically /usr/data/printer_data/config/belts_calibration.png).
#                      Real file. GuppyScreen rebuilds this path itself
#                      and reads it via LVGL's `A:` (stdio) mount — no
#                      JSON parsing on the belts panel, the trigger
#                      string is just "// Command {guppy_belts_calibration} finished"
#                      and the PNG path is fixed in the binary.
#   /usr/data/printer_data/config/printer_calibration_graphs/
#       belts_full.png   (8x4.8 in, desktop preview for Fluidd)
#
# Both PNGs come out of a SINGLE python process (belts_full.py) — one
# matplotlib + numpy import for both renders. Belt CSVs are ~21 MB
# raw accelerometer data; loading them twice was the worst-case OOM
# trigger on the 256 MB Nebula Pad.

set -eu

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

KLIPPER_DIR="/usr/data/e5m-ck/klipper"

# Pick the newest CSV per belt by NAME suffix — robust across Klipper
# master's filename punctuation ('=', ',') vs older underscores.
pick_newest() {
    pattern="$1"
    newest=""
    for f in $pattern; do
        [ -f "$f" ] || continue
        if [ -z "$newest" ] || [ "$f" -nt "$newest" ]; then
            newest="$f"
        fi
    done
    echo "$newest"
}

CSV_A=$(pick_newest "/tmp/raw_data_axis*_e5m_belt_a.csv")
CSV_B=$(pick_newest "/tmp/raw_data_axis*_e5m_belt_b.csv")
[ -n "$CSV_A" ] || { echo "No A-belt CSV in /tmp/ — run MEASURE_BELTS first." >&2; exit 1; }
[ -n "$CSV_B" ] || { echo "No B-belt CSV in /tmp/ — run MEASURE_BELTS first." >&2; exit 1; }
echo "A-belt CSV: $CSV_A"
echo "B-belt CSV: $CSV_B"

GRAPHS_DIR="/usr/data/printer_data/config/printer_calibration_graphs"
FULL_PNG="$GRAPHS_DIR/belts_full.png"
mkdir -p "$GRAPHS_DIR"

SMALL_PNG="${OUT_SMALL:-/usr/data/printer_data/config/belts_calibration.png}"
# Strip any leftover symlink from older installs so the new write is a real file.
[ -L "$SMALL_PNG" ] && rm -f "$SMALL_PNG"

# Single Python process: load CSVs once, render both PNG sizes.
/usr/share/klippy-env/bin/python3 \
    /usr/data/e5m-ck/bin/belts_full.py \
    "$CSV_A" "$CSV_B" \
    --small "$SMALL_PNG" -w "$WIDTH" -l "$LENGTH" \
    --full "$FULL_PNG" \
    --klipperdir "$KLIPPER_DIR"

echo "GuppyScreen PNG: $SMALL_PNG (${WIDTH} x ${LENGTH} in)"
echo "Full PNG:        $FULL_PNG (8 x 4.8 in)"

# Auto-delete the transient GuppyScreen PNG 30 s after we exit.
# Sequencing:
#   1. We exit. Klipper emits "// Command {guppy_belts_calibration} finished".
#   2. GuppyScreen's belts_calibration_panel.cpp handler fires on that
#      string and calls lv_img_set_src(graph, "A:<small_png>"), which
#      LVGL resolves to fopen() of the file — at this point the PNG
#      content is read into the decode cache.
#   3. 30 s later this detached subshell unlinks the on-disk file.
#      LVGL still holds the decoded bitmap in its 5-entry image cache
#      so the on-screen display is unaffected.
# The full PNG in printer_calibration_graphs/ persists for Fluidd.
( sleep 30; rm -f "$SMALL_PNG" ) </dev/null >/dev/null 2>&1 &
