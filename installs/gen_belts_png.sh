#!/bin/sh
# ═══════════════════════════════════════════════════════════════════
# gen_belts_png.sh — wrapper to generate a PC-sized belts PNG
#
# Called by [gcode_shell_command guppy_belts_calibration_pc] from
# /usr/data/printer_data/config/GuppyScreen/guppy_cmd.cfg.
#
# Args:
#   $1 = CSV A path  (e.g. /tmp/raw_data_axis=1.000,-1.000,0.000_a.csv)
#   $2 = CSV B path  (e.g. /tmp/raw_data_axis=1.000,1.000,0.000_b.csv)
#
# Output:
#   /usr/data/printer_data/config/printer_calibration_graphs/
#     belts_calibration_PC_SIZE_<YYYYMMDD>_<HHMMSS>.png
# ═══════════════════════════════════════════════════════════════════

set -e

CSV_A="$1"
CSV_B="$2"

if [ -z "$CSV_A" ] || [ -z "$CSV_B" ]; then
    echo "Usage: $0 <csv_a> <csv_b>"
    exit 1
fi

# Output directory (auto-created if missing)
OUT_DIR="/usr/data/printer_data/config/printer_calibration_graphs"
mkdir -p "$OUT_DIR"

# Timestamped filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT_PNG="$OUT_DIR/belts_calibration_PC_SIZE_${TIMESTAMP}.png"

# Generate PC-sized PNG (8 x 4.8 inches)
/usr/data/printer_data/config/GuppyScreen/scripts/graph_belts.py \
    -w 8 -l 4.8 -n \
    -o "$OUT_PNG" \
    -k /usr/data/klipper \
    "$CSV_A" "$CSV_B"

echo "PC-sized belts PNG: $OUT_PNG"
