#!/bin/sh
# gen_belts_png.sh — generate CoreXY belt-comparison PNG from the latest CSVs.
#
# Installed at: /usr/data/e5m-ck/bin/gen_belts_png.sh
# Invoked by:   [gcode_shell_command e5m_gen_belts_png]
#
# Auto-picks the most recent CSVs written by MEASURE_BELTS' TEST_RESONANCES.
# Klipper master names them with literal '=' and ',' characters
# (e.g. /tmp/raw_data_axis=1.000,1.000,0.000_<NAME>.csv) — older Klipper
# variants used '_' separators. We try both forms.
#
# The NAME suffix comes from the macro: 'e5m_belt_a' for AXIS=1,1 (A belt
# = stepper_y rotation alone) and 'e5m_belt_b' for AXIS=1,-1 (B belt =
# stepper_x rotation alone). See klipper/config/macros/input_shaper.cfg.
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

# MEASURE_BELTS passes NAME=e5m_belt_a (AXIS=1,1) and NAME=e5m_belt_b (AXIS=1,-1).
# Match by the NAME suffix since Klipper master's filename punctuation
# ('=', ',') depends on the version and is awkward to glob safely.
CSV_A=$(pick_newest "/tmp/raw_data_axis*_e5m_belt_a.csv")
CSV_B=$(pick_newest "/tmp/raw_data_axis*_e5m_belt_b.csv")

[ -n "$CSV_A" ] || { echo "No A-belt CSV (*_e5m_belt_a.csv) in /tmp/. Run MEASURE_BELTS first." >&2; exit 1; }
[ -n "$CSV_B" ] || { echo "No B-belt CSV (*_e5m_belt_b.csv) in /tmp/. Run MEASURE_BELTS first." >&2; exit 1; }
echo "A-belt CSV: $CSV_A"
echo "B-belt CSV: $CSV_B"

OUT_DIR="/usr/data/printer_data/config/printer_calibration_graphs"
mkdir -p "$OUT_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT_PNG="$OUT_DIR/belts_${TIMESTAMP}.png"

GRAPH_BELTS="/usr/data/e5m-ck/klipper/scripts/graph_belts.py"
[ -f "$GRAPH_BELTS" ] \
    || { echo "graph_belts.py missing at $GRAPH_BELTS — re-run install_input_shaper.sh" >&2; exit 1; }

# graph_belts.py does `import shaper_calibrate` at module top — before
# it parses the -k flag — so we must put Klipper's klippy/extras on
# PYTHONPATH ourselves. -w/-l keep v1's 8x4.8 sizing.
# shaper_calibrate internally does `import_module('.shaper_defs', 'extras')`,
# so we need klippy/ (not klippy/extras/) on the path — 'extras' must
# be importable as a package.
export PYTHONPATH="/usr/data/e5m-ck/klipper/klippy/extras:/usr/data/e5m-ck/klipper/klippy:${PYTHONPATH:-}"
# -n disables the difference spectrogram (requires scipy, not in
# /usr/share/klippy-env). The PSD-overlay + similarity score on the
# main panel is what's actually useful for belt-tension diagnosis.
/usr/share/klippy-env/bin/python3 "$GRAPH_BELTS" \
    -o "$OUT_PNG" \
    -k /usr/data/e5m-ck/klipper \
    -w 8 -l 4.8 -n \
    "$CSV_A" "$CSV_B"

echo "Belts PNG: $OUT_PNG"
