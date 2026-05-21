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
#   -o <ignored> -w 4.8 -l 2.72
# (CSV pair auto-picked from /tmp/raw_data_axis*_e5m_belt_{a,b}.csv)
#
# Output paths (always the same regardless of caller):
#   /tmp/belts_calibration.png        (volatile, small for GuppyScreen)
#   /usr/data/printer_data/config/printer_calibration_graphs/
#       belts_full.png                (persistent, full size for Fluidd)
#
# GuppyScreen's binary hardcodes /usr/data/printer_data/config/
# belts_calibration.png as its display path (no JSON parsing here —
# graph_belts.py doesn't emit one). So for belts we cannot route the
# small PNG into /tmp/ without GuppyScreen losing track of it; we keep
# the small PNG at GuppyScreen's expected path. The full PNG goes to
# printer_calibration_graphs/ as for shapers.
#
# (If GuppyScreen ever grows JSON parsing for belts, we'll mirror the
# shaper approach and route the small PNG to /tmp/ too.)

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

# 1. Small PNG written to the path GuppyScreen requested via -o
#    (or a sensible default). Real file, replacing any leftover symlink.
#    -n disables the difference spectrogram (needs scipy, not in klippy-env).
SMALL_OUT="${OUT_SMALL:-/usr/data/printer_data/config/belts_calibration.png}"
[ -L "$SMALL_OUT" ] && rm -f "$SMALL_OUT"
/usr/share/klippy-env/bin/python3 "$GRAPH_BELTS" \
    -o "$SMALL_OUT" \
    -k "$KLIPPER_DIR" \
    -w "$WIDTH" -l "$LENGTH" -n \
    "$CSV_A" "$CSV_B"
echo "GuppyScreen PNG: $SMALL_OUT (${WIDTH} x ${LENGTH} in)"

# 2. Large PNG → printer_calibration_graphs/, for Fluidd preview.
/usr/share/klippy-env/bin/python3 "$GRAPH_BELTS" \
    -o "$LARGE_CANON" \
    -k "$KLIPPER_DIR" \
    -w 8 -l 4.8 -n \
    "$CSV_A" "$CSV_B"
echo "Full PNG:        $LARGE_CANON (8 x 4.8 in)"
