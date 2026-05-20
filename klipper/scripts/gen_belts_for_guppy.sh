#!/bin/sh
# gen_belts_for_guppy.sh — unified belts-comparison PNG generator.
#
# Installed at: /usr/data/e5m-ck/bin/gen_belts_for_guppy.sh
# Invoked by:   [gcode_shell_command guppy_belts_calibration] (input_shaper.cfg)
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
#   <small_png_path>  (exactly what GuppyScreen requested via -o,
#                      typically /usr/data/printer_data/config/belts_calibration.png)
#                      4.8x2.72 in. Real file — GuppyScreen's LVGL image
#                      loader doesn't follow symlinks reliably.
#   /usr/data/printer_data/config/printer_calibration_graphs/
#       belts_full.png   (8x4.8 in, desktop preview for Fluidd)

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
GRAPH_BELTS="$KLIPPER_DIR/scripts/graph_belts.py"
[ -f "$GRAPH_BELTS" ] \
    || { echo "graph_belts.py missing at $GRAPH_BELTS" >&2; exit 1; }

# graph_belts.py does `import shaper_calibrate` at module top, before
# parsing -k; need both klippy/extras (for the module itself) and klippy/
# (for the 'extras' package) on PYTHONPATH.
export PYTHONPATH="$KLIPPER_DIR/klippy/extras:$KLIPPER_DIR/klippy:${PYTHONPATH:-}"

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
LARGE_CANON="$GRAPHS_DIR/belts_full.png"
mkdir -p "$GRAPHS_DIR"

# 1. Small PNG written directly to GuppyScreen's requested path (-o).
#    -n disables the difference spectrogram (needs scipy, not in
#    klippy-env). PSD overlay + similarity score is what's useful.
if [ -n "$OUT_SMALL" ]; then
    [ -L "$OUT_SMALL" ] && rm -f "$OUT_SMALL"
    /usr/share/klippy-env/bin/python3 "$GRAPH_BELTS" \
        -o "$OUT_SMALL" \
        -k "$KLIPPER_DIR" \
        -w "$WIDTH" -l "$LENGTH" -n \
        "$CSV_A" "$CSV_B"
    echo "GuppyScreen PNG: $OUT_SMALL (${WIDTH} x ${LENGTH} in)"
fi

# 2. Large PNG (Fluidd / desktop preview).
/usr/share/klippy-env/bin/python3 "$GRAPH_BELTS" \
    -o "$LARGE_CANON" \
    -k "$KLIPPER_DIR" \
    -w 8 -l 4.8 -n \
    "$CSV_A" "$CSV_B"
echo "Full PNG:        $LARGE_CANON (8 x 4.8 in)"
