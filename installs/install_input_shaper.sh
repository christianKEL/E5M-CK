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
#   - install_guppyscreen.sh has run — its k1_mods/ directory provides the
#     ABI-fixed ft2font.so that step 3 below swaps in (matplotlib 2.2.3 vs
#     freetype 2.13 ABI mismatch; see docs/operations/input_shaper.md §3).
#
# What this script does:
#   1. Validates the three required extras .py files are present in
#      klippy/extras/ (deployed by install_klipper.sh's extras pipeline).
#   2. Copies gen_shaper_png.sh + gen_belts_png.sh to /usr/data/e5m-ck/bin/
#      with executable permissions.
#   3. Copies the vendored graph_belts.py to klipper/scripts/.
#   4. Swaps matplotlib's stock ft2font.so for the K1-mod version dropped
#      by GuppyScreen at /usr/data/guppyscreen/k1_mods/. Without this,
#      every matplotlib savefig() call aborts the process.
#   5. Creates /usr/data/printer_data/config/printer_calibration_graphs/.
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

# Path to the matplotlib ft2font.so that ships with this Python venv.
FT2FONT="/usr/lib/python3.8/site-packages/matplotlib/ft2font.cpython-38-mipsel-linux-gnu.so"
# The K1-mod ft2font.so dropped by the GuppyScreen installer. ABI-compatible
# with the printer's freetype 2.13 (Entware), unlike the stock matplotlib-2.2.3
# one which was statically built against freetype 2.6-2.8. See §3 of
# docs/operations/input_shaper.md for the full diagnosis.
FT2FONT_K1MOD="/usr/data/guppyscreen/k1_mods/ft2font.cpython-38-mipsel-linux-gnu.so"
FT2FONT_K1MOD_MD5="7706852f09ad75472d15ff790ecc0d55"

ts()   { date +'%H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(ts)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; exit 1; }

# -- Preflight ------------------------------------------------------------
info "=== Preflight ==="
[ -d "$KLIPPER_DIR/.git" ] || die "Klipper not installed at $KLIPPER_DIR. Run install_klipper.sh first."
[ -d "$EXTRAS_DIR" ]       || die "$EXTRAS_DIR missing — broken Klipper install?"

for required in accel_chip_proxy.py adxl345_creality.py gcode_shell_command.py shaper_max_accel_apply.py; do
    [ -f "$EXTRAS_DIR/$required" ] \
        || die "$required not in $EXTRAS_DIR/ — re-run install_klipper.sh with klipper/extras/*.py staged via /tmp/klipper_extras_*"
done
info "All four .py extras present in $EXTRAS_DIR/"

for required in gen_belts_for_guppy.sh gen_shaper_for_guppy.sh _shaper_with_figsize.py graph_belts.py; do
    [ -f "/tmp/$required" ] || die "/tmp/$required missing. Staging step skipped?"
done
info "All four /tmp/ artifacts present"

# -- 1. Shell + Python helpers ------------------------------------------
info ""
info "=== Shell + Python helpers ==="
mkdir -p "$BIN_DIR"
cp /tmp/gen_belts_for_guppy.sh     "$BIN_DIR/gen_belts_for_guppy.sh"
cp /tmp/gen_shaper_for_guppy.sh    "$BIN_DIR/gen_shaper_for_guppy.sh"
cp /tmp/_shaper_with_figsize.py    "$BIN_DIR/_shaper_with_figsize.py"
chmod 0755 "$BIN_DIR/gen_belts_for_guppy.sh" \
           "$BIN_DIR/gen_shaper_for_guppy.sh" \
           "$BIN_DIR/_shaper_with_figsize.py"
info "  installed in $BIN_DIR/:"
info "    gen_belts_for_guppy.sh  (unified belts PNG — Fluidd + GuppyScreen)"
info "    gen_shaper_for_guppy.sh (unified shaper PNG — Fluidd + GuppyScreen)"
info "    _shaper_with_figsize.py (matplotlib figsize-forced wrapper)"

# Clean up stale helpers from earlier installs.
for stale in gen_shaper_png.sh gen_belts_png.sh; do
    if [ -f "$BIN_DIR/$stale" ]; then
        rm -f "$BIN_DIR/$stale"
        info "  removed stale $BIN_DIR/$stale"
    fi
done

# -- 2. graph_belts.py ----------------------------------------------------
info ""
info "=== graph_belts.py ==="
cp /tmp/graph_belts.py "$SCRIPTS_DIR/graph_belts.py"
chmod 0755 "$SCRIPTS_DIR/graph_belts.py"
info "  installed at $SCRIPTS_DIR/graph_belts.py ($(wc -c < "$SCRIPTS_DIR/graph_belts.py") bytes)"

# -- 3. matplotlib ft2font ABI fix ---------------------------------------
# matplotlib 2.2.3 (pre-installed in /usr/share/klippy-env) ships an
# ft2font.so that was statically linked against freetype 2.6-2.8 headers.
# On this printer libfreetype.so.6 is freetype 2.13 (from Entware), so the
# stock .so throws std::runtime_error("Couldn't close file") during
# font_manager init — making any matplotlib savefig() abort the process.
#
# GuppyScreen's installer ships an ABI-fixed ft2font.so at k1_mods/. It
# was built by the upstream ballaswag/guppyscreen project against a recent
# freetype, and is the same binary regardless of which K1-derived board
# it's installed on. We just swap it in. Idempotent via md5 check.
info ""
info "=== matplotlib ft2font ABI fix ==="
if [ ! -f "$FT2FONT" ]; then
    warn "  $FT2FONT not present — matplotlib not installed? Skipping swap."
elif [ ! -f "$FT2FONT_K1MOD" ]; then
    warn "  $FT2FONT_K1MOD not present — GuppyScreen not installed yet?"
    warn "  Run installs/install_guppyscreen.sh first, then re-run this script."
else
    current_md5=$(md5sum "$FT2FONT" | awk '{print $1}')
    if [ "$current_md5" = "$FT2FONT_K1MOD_MD5" ]; then
        info "  ft2font.so already the K1-mod version (md5 $FT2FONT_K1MOD_MD5). Skipping."
    else
        if [ ! -f "$FT2FONT.original" ]; then
            cp "$FT2FONT" "$FT2FONT.original"
            info "  backed up stock ft2font.so → ${FT2FONT}.original"
        else
            info "  backup ${FT2FONT}.original already exists"
        fi
        cp "$FT2FONT_K1MOD" "$FT2FONT"
        new_md5=$(md5sum "$FT2FONT" | awk '{print $1}')
        [ "$new_md5" = "$FT2FONT_K1MOD_MD5" ] \
            || die "  swap copied but md5 mismatch ($new_md5 != $FT2FONT_K1MOD_MD5)"
        rm -rf /root/.cache/matplotlib /root/.matplotlib
        info "  swapped ft2font.so → K1-mod version + wiped /root/.cache/matplotlib"
    fi
fi

# -- 4. Output dir --------------------------------------------------------
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
