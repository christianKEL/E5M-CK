#!/bin/sh
# ═══════════════════════════════════════════════════════════════════
# gen_shaper_png.sh — wrapper to generate a PC-sized shaper PNG
#
# Called by [gcode_shell_command guppy_input_shaper_pc] from
# /usr/data/printer_data/config/GuppyScreen/guppy_cmd.cfg.
#
# Args:
#   $1 = input CSV path  (e.g. /tmp/resonances_x_x.csv)
#   $2 = axis label      (e.g. x or y)
#
# Output:
#   /usr/data/printer_data/config/printer_calibration_graphs/
#     resonances_<axis>_PC_SIZE_<YYYYMMDD>_<HHMMSS>.png
# ═══════════════════════════════════════════════════════════════════

set -e

CSV="$1"
AXIS="$2"

if [ -z "$CSV" ] || [ -z "$AXIS" ]; then
    echo "Usage: $0 <csv_path> <axis_label>"
    exit 1
fi

# Output directory (auto-created if missing — protects against
# manual deletion by the user)
OUT_DIR="/usr/data/printer_data/config/printer_calibration_graphs"
mkdir -p "$OUT_DIR"

# Timestamped filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT_PNG="$OUT_DIR/resonances_${AXIS}_PC_SIZE_${TIMESTAMP}.png"

# Generate PC-sized PNG (8 x 4.8 inches = 800 x 480 px at 100 dpi)
/usr/data/printer_data/config/GuppyScreen/scripts/calibrate_shaper.py \
    "$CSV" \
    -o "$OUT_PNG" \
    -w 8 -l 4.8

echo "PC-sized shaper PNG: $OUT_PNG"
