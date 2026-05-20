#!/bin/sh
# gen_belts_png.sh — generate CoreXY belt-comparison PNG from the latest CSVs.
#
# Installed at: /usr/data/e5m-ck/bin/gen_belts_png.sh
# Invoked by:   [gcode_shell_command e5m_gen_belts_png]
#
# Auto-picks the most recent /tmp/raw_data_axis_1.000_1.000_0.000_*.csv
# and /tmp/raw_data_axis_1.000_-1.000_0.000_*.csv (written by MEASURE_BELTS'
# TEST_RESONANCES with AXIS=1,1 and AXIS=1,-1).
#
# Output:
#   /usr/data/printer_data/config/printer_calibration_graphs/
#     belts_<YYYYMMDD>_<HHMMSS>.png
#
# graph_belts.py is vendored from GuppyScreen (Klippain ancestry) into
# /usr/data/e5m-ck/klipper/scripts/graph_belts.py by install_input_shaper.sh.
# Klippain's shaketune package was refactored away from a standalone
# script post-2024, so we keep the v1-era standalone version.

set -eu

# Pick newest matching file per glob.
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

CSV_A=$(pick_newest "/tmp/raw_data_axis_1.000_1.000_0.000_*.csv")
CSV_B=$(pick_newest "/tmp/raw_data_axis_1.000_-1.000_0.000_*.csv")

[ -n "$CSV_A" ] || { echo "No A-belt CSV (raw_data_axis_1.000_1.000_0.000_*.csv) in /tmp/. Run MEASURE_BELTS first." >&2; exit 1; }
[ -n "$CSV_B" ] || { echo "No B-belt CSV (raw_data_axis_1.000_-1.000_0.000_*.csv) in /tmp/. Run MEASURE_BELTS first." >&2; exit 1; }
echo "A-belt CSV: $CSV_A"
echo "B-belt CSV: $CSV_B"

OUT_DIR="/usr/data/printer_data/config/printer_calibration_graphs"
mkdir -p "$OUT_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT_PNG="$OUT_DIR/belts_${TIMESTAMP}.png"

GRAPH_BELTS="/usr/data/e5m-ck/klipper/scripts/graph_belts.py"
[ -f "$GRAPH_BELTS" ] \
    || { echo "graph_belts.py missing at $GRAPH_BELTS — re-run install_input_shaper.sh" >&2; exit 1; }

# graph_belts.py supports -w (width) and -l (length); keep v1's 8x4.8 sizing.
/usr/share/klippy-env/bin/python3 "$GRAPH_BELTS" \
    -o "$OUT_PNG" \
    -k /usr/data/e5m-ck/klipper \
    -w 8 -l 4.8 \
    "$CSV_A" "$CSV_B"

echo "Belts PNG: $OUT_PNG"
