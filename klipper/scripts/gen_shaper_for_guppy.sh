#!/bin/sh
# gen_shaper_for_guppy.sh — wrapper invoked by GuppyScreen's "Input Shaper" button.
#
# Installed at: /usr/data/e5m-ck/bin/gen_shaper_for_guppy.sh
# Invoked by:   [gcode_shell_command guppy_input_shaper] (input_shaper.cfg)
#
# GuppyScreen sends (per its binary, confirmed 2026-05):
#   RUN_SHELL_COMMAND CMD=guppy_input_shaper \
#     PARAMS="/tmp/resonances_<axis>_<axis>.csv \
#             -o /usr/data/printer_data/config/resonances_<axis>.png \
#             -w 4.8 -l 2.72"
#
# We forward the args verbatim to calibrate_shaper.py. The 4.8x2.72 inch
# size matches the Nebula Pad's 480x272 px screen (per the v1 memo §5.2).
#
# Why a separate wrapper rather than pointing CMD directly at python:
#   1. PYTHONPATH plumbing — calibrate_shaper.py does
#      `importlib.import_module('.shaper_calibrate', 'extras')`, which
#      needs klippy/ on the path so 'extras' is importable as a package.
#   2. Easier to hook in a dual-PNG strategy later (small for the screen,
#      large for desktop viewing in Fluidd) without touching Klipper config.

set -eu

KLIPPER_DIR="/usr/data/e5m-ck/klipper"
CALIBRATE="$KLIPPER_DIR/scripts/calibrate_shaper.py"
[ -f "$CALIBRATE" ] || { echo "calibrate_shaper.py missing at $CALIBRATE" >&2; exit 1; }

export PYTHONPATH="$KLIPPER_DIR/klippy:${PYTHONPATH:-}"

echo "guppy_input_shaper invoked with: $*"

# Klipper master's scripts/calibrate_shaper.py dropped the -w (width) and
# -l (length) flags that GuppyScreen's vendored copy had. Strip them out
# so the call doesn't error with "no such option". GuppyScreen always
# passes them as a pair with float values; consume both.
ARGS=""
while [ $# -gt 0 ]; do
    case "$1" in
        -w|-l)
            shift  # discard flag
            [ $# -gt 0 ] && shift  # discard its float value
            ;;
        *)
            ARGS="$ARGS \"$1\""
            shift
            ;;
    esac
done

eval set -- $ARGS
echo "(stripped -w/-l) forwarding to calibrate_shaper.py: $*"
exec /usr/share/klippy-env/bin/python3 "$CALIBRATE" "$@"
