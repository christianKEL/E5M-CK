#!/bin/sh
# gen_shaper_png.sh — generate a shaper PNG from the most recent CSV.
#
# Installed at: /usr/data/e5m-ck/bin/gen_shaper_png.sh
# Invoked by:   [gcode_shell_command e5m_gen_shaper_png]
#               (defined in klipper/config/macros/input_shaper.cfg)
#
# Args:
#   $1 = axis label (x or y)
#
# Output:
#   /usr/data/printer_data/config/printer_calibration_graphs/
#     resonances_<axis>_<YYYYMMDD>_<HHMMSS>.png
#
# Picks the most recent /tmp/calibration_data_<axis>_*.csv automatically
# (SHAPER_CALIBRATE writes timestamped files).
#
# NB: Klipper master's scripts/calibrate_shaper.py dropped the -w / -l
# flags that GuppyScreen's vendored version had. We rely on matplotlib
# defaults for figure size — renders cleanly in Fluidd's file viewer.

set -eu

AXIS="${1:-}"
[ -n "$AXIS" ]                  || { echo "Usage: $0 <axis_label>"   >&2; exit 1; }
[ "$AXIS" = "x" ] || [ "$AXIS" = "y" ] || { echo "Axis must be x or y, got $AXIS" >&2; exit 1; }

# Find the most recent CSV for this axis from /tmp/. SHAPER_CALIBRATE
# writes calibration_data_<axis>_<timestamp>.csv; TEST_RESONANCES with
# OUTPUT=raw_data writes raw_data_axis_<axis>_<NAME>.csv. We try both.
CSV=""
for pattern in "/tmp/calibration_data_${AXIS}_"* "/tmp/raw_data_axis_${AXIS}_"*; do
    for f in $pattern; do
        [ -f "$f" ] || continue
        # Pick newest by ls -t.
        if [ -z "$CSV" ] || [ "$f" -nt "$CSV" ]; then
            CSV="$f"
        fi
    done
done
[ -n "$CSV" ] || { echo "No CSV found for axis $AXIS under /tmp/" >&2; exit 1; }
echo "Using CSV: $CSV"

OUT_DIR="/usr/data/printer_data/config/printer_calibration_graphs"
mkdir -p "$OUT_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT_PNG="$OUT_DIR/resonances_${AXIS}_${TIMESTAMP}.png"

KLIPPER_SCRIPT="/usr/data/e5m-ck/klipper/scripts/calibrate_shaper.py"
[ -f "$KLIPPER_SCRIPT" ] \
    || { echo "calibrate_shaper.py missing at $KLIPPER_SCRIPT — is Klipper installed?" >&2; exit 1; }

/usr/share/klippy-env/bin/python3 "$KLIPPER_SCRIPT" "$CSV" -o "$OUT_PNG"

echo "Shaper PNG: $OUT_PNG"
