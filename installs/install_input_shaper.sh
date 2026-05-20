#!/bin/sh
# install_input_shaper.sh — deploy input-shaper helpers + graph_belts.py.
#
# Runs ON THE PRINTER (busybox sh).
# Idempotent: re-running upgrades artifacts in place.
#
# Prerequisites (must already be done):
#   - install_klipper.sh has staged klipper/extras/accel_chip_proxy.py,
#     adxl345_creality.py, and gcode_shell_command.py into
#     /usr/data/e5m-ck/klipper/klippy/extras/
#   - klipper/config/input_shaper.cfg and klipper/config/macros/input_shaper.cfg
#     are included from /usr/data/printer_data/config/printer.cfg
#     (sync.sh handles this)
#
# What this script does:
#   1. Validates the three required extras .py files are present in
#      klippy/extras/ (deployed by install_klipper.sh's extras pipeline).
#   2. Copies gen_shaper_png.sh + gen_belts_png.sh to /usr/data/e5m-ck/bin/
#      with executable permissions.
#   3. Copies the vendored graph_belts.py to klipper/scripts/.
#   4. Creates /usr/data/printer_data/config/printer_calibration_graphs/.
#
# Required artifacts pre-staged to /tmp/ before running:
#   - /tmp/gen_shaper_png.sh
#   - /tmp/gen_belts_png.sh
#   - /tmp/graph_belts.py
#
# Usage (over SSH from local):
#   scp -O klipper/scripts/gen_shaper_png.sh root@printer:/tmp/
#   scp -O klipper/scripts/gen_belts_png.sh  root@printer:/tmp/
#   scp -O klipper/scripts/graph_belts.py    root@printer:/tmp/
#   cat installs/install_input_shaper.sh | ssh root@printer 'sh -s'

set -eu

BIN_DIR="/usr/data/e5m-ck/bin"
KLIPPER_DIR="/usr/data/e5m-ck/klipper"
EXTRAS_DIR="$KLIPPER_DIR/klippy/extras"
SCRIPTS_DIR="$KLIPPER_DIR/scripts"
GRAPHS_DIR="/usr/data/printer_data/config/printer_calibration_graphs"

ts()   { date +'%H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(ts)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; exit 1; }

# -- Preflight ------------------------------------------------------------
info "=== Preflight ==="
[ -d "$KLIPPER_DIR/.git" ] || die "Klipper not installed at $KLIPPER_DIR. Run install_klipper.sh first."
[ -d "$EXTRAS_DIR" ]       || die "$EXTRAS_DIR missing — broken Klipper install?"

for required in accel_chip_proxy.py adxl345_creality.py gcode_shell_command.py; do
    [ -f "$EXTRAS_DIR/$required" ] \
        || die "$required not in $EXTRAS_DIR/ — re-run install_klipper.sh with klipper/extras/*.py staged via /tmp/klipper_extras_*"
done
info "All three .py extras present in $EXTRAS_DIR/"

for required in gen_shaper_png.sh gen_belts_png.sh graph_belts.py; do
    [ -f "/tmp/$required" ] || die "/tmp/$required missing. Staging step skipped?"
done
info "All three /tmp/ artifacts present"

# -- 1. Shell helpers -----------------------------------------------------
info ""
info "=== Shell helpers ==="
mkdir -p "$BIN_DIR"
cp /tmp/gen_shaper_png.sh "$BIN_DIR/gen_shaper_png.sh"
cp /tmp/gen_belts_png.sh  "$BIN_DIR/gen_belts_png.sh"
chmod 0755 "$BIN_DIR/gen_shaper_png.sh" "$BIN_DIR/gen_belts_png.sh"
info "  installed gen_shaper_png.sh + gen_belts_png.sh in $BIN_DIR/"

# -- 2. graph_belts.py ----------------------------------------------------
info ""
info "=== graph_belts.py ==="
cp /tmp/graph_belts.py "$SCRIPTS_DIR/graph_belts.py"
chmod 0755 "$SCRIPTS_DIR/graph_belts.py"
info "  installed at $SCRIPTS_DIR/graph_belts.py ($(wc -c < "$SCRIPTS_DIR/graph_belts.py") bytes)"

# -- 3. Output dir --------------------------------------------------------
info ""
info "=== Output dir ==="
mkdir -p "$GRAPHS_DIR"
info "  ensured $GRAPHS_DIR/"

info ""
info "Done. Restart Klipper from local:"
info "  ssh root@printer '/etc/init.d/S55klipper_service restart'"
info "Then in Fluidd console:"
info "  MEASURE_AXIS AXIS=X"
info "  MEASURE_AXIS AXIS=Y"
info "  SAVE_CONFIG     (persists shaper_type / shaper_freq)"
info "  MEASURE_BELTS   (optional, CoreXY belt health check)"
