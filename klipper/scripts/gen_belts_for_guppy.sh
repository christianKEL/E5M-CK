#!/bin/sh
# gen_belts_for_guppy.sh — unified belts-comparison PNG generator.
#
# Installed at: /usr/data/e5m-ck/bin/gen_belts_for_guppy.sh
# Invoked by:   [gcode_shell_command guppy_belts_calibration] (input_shaper.cfg)
# Companion:    /usr/data/e5m-ck/bin/_shaper_with_figsize.py  (not used here;
#               graph_belts.py supports -w/-l natively)
#
# Two entry points hit this script with identical PARAMS format:
#
#   1. GuppyScreen "Belts/Shake" UI button → its binary emits
#      `GUPPY_BELTS_SHAPER_CALIBRATION PNG_OUT_PATH=... PNG_WIDTH=... PNG_HEIGHT=...`
#      which our macro forwards as RUN_SHELL_COMMAND PARAMS=...
#   2. Fluidd MEASURE_BELTS macro → forwards the same RUN_SHELL_COMMAND
#      with the SAME PARAMS so the two flows are byte-for-byte identical.
#
# Expected PARAMS:
#   -o <small_png_path> -w 4.8 -l 2.72
# (the CSV pair is auto-picked from /tmp/raw_data_axis*_e5m_belt_a.csv
#  and *_e5m_belt_b.csv — written by the macro's TEST_RESONANCES calls)
#
# Canonical output paths (both UIs always produce both files):
#   /usr/data/printer_data/config/printer_calibration_graphs/
#       belts_guppy_screen.png   (4.8 x 2.72 in, 480x272 px)
#       belts_full.png            (8 x 4.8 in, desktop preview)
#
# GuppyScreen's binary hardcodes the path it polls for its on-screen
# display (typically /usr/data/printer_data/config/belts_calibration.png —
# comes in via -o). We SYMLINK from there to the canonical
# belts_guppy_screen.png. Transparent to GuppyScreen, all real PNG
# content centralized in printer_calibration_graphs/.

set -eu

OUT_REQUESTED=""
WIDTH="4.8"
LENGTH="2.72"

while [ $# -gt 0 ]; do
    case "$1" in
        -o) shift; OUT_REQUESTED="$1"; shift ;;
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

# Pick the newest CSV per belt. NAME suffix (e5m_belt_a / _b) is robust
# across Klipper master's filename punctuation ('=', ','), which the
# old '_'-separator pattern wasn't.
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
SMALL_CANON="$GRAPHS_DIR/belts_guppy_screen.png"
LARGE_CANON="$GRAPHS_DIR/belts_full.png"
mkdir -p "$GRAPHS_DIR"

# 1. Small PNG (GuppyScreen on-screen).
#    -n disables the difference spectrogram (needs scipy, not in
#    klippy-env). PSD overlay + similarity score on the main panel is
#    what's actually useful for belt-tension diagnosis.
/usr/share/klippy-env/bin/python3 "$GRAPH_BELTS" \
    -o "$SMALL_CANON" \
    -k "$KLIPPER_DIR" \
    -w "$WIDTH" -l "$LENGTH" -n \
    "$CSV_A" "$CSV_B"
echo "GuppyScreen-sized PNG: $SMALL_CANON (${WIDTH} x ${LENGTH} in)"

# 2. Symlink GuppyScreen-requested path to canonical.
if [ -n "$OUT_REQUESTED" ] && [ "$OUT_REQUESTED" != "$SMALL_CANON" ]; then
    rm -f "$OUT_REQUESTED"
    ln -s "$SMALL_CANON" "$OUT_REQUESTED"
    echo "Symlinked $OUT_REQUESTED -> $SMALL_CANON"
fi

# 3. Large PNG (Fluidd File Manager / desktop preview).
/usr/share/klippy-env/bin/python3 "$GRAPH_BELTS" \
    -o "$LARGE_CANON" \
    -k "$KLIPPER_DIR" \
    -w 8 -l 4.8 -n \
    "$CSV_A" "$CSV_B"
echo "Full-sized PNG: $LARGE_CANON (8 x 4.8 in)"
