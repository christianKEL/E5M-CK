#!/bin/sh
# install_eddy_drift.sh — deploy the EDDY_DRIFT_CALIBRATE one-click macro.
#
# Runs ON THE PRINTER (busybox sh).
# Idempotent: re-running upgrades the artifacts in place.
#
# Prerequisites:
#   - install_klipper.sh   already ran  (klippy/extras/gcode_shell_command.py present)
#   - install_eddy.sh      already ran  (BTT Eddy flashed + eddy.cfg deployed)
#   - Three artifacts staged at /tmp/:
#       /tmp/eddy_drift_watchdog.py
#       /tmp/start_eddy_drift_watchdog.sh
#       /tmp/eddy_drift.cfg
#
# What this script does:
#   1. Validates the three staged artifacts and Klipper has the
#      gcode_shell_command extra (otherwise the macro can't dispatch
#      the watchdog).
#   2. Copies the python watchdog + shell launcher into
#      /usr/data/e5m-ck/bin/ (chmod 0755 on both).
#   3. Copies eddy_drift.cfg into /usr/data/printer_data/config/macros/.
#   4. Ensures [include macros/eddy_drift.cfg] is present in printer.cfg
#      (in-place edit — autosave block preserved, no scp).
#
# The macro itself, once registered, can be invoked from Fluidd's console
# or any Guppy "Macros" button as EDDY_DRIFT_CALIBRATE — no parameters
# needed, ~25-35 min for a full TARGET=100 STEP=2 run, then SAVE_CONFIG
# (run by the user at their leisure since SAVE_CONFIG restarts Klipper).
#
# Usage (over SSH from local):
#   scp -O klipper/scripts/eddy_drift_watchdog.py        root@printer:/tmp/
#   scp -O klipper/scripts/start_eddy_drift_watchdog.sh  root@printer:/tmp/
#   scp -O klipper/config/macros/eddy_drift.cfg          root@printer:/tmp/
#   cat installs/install_eddy_drift.sh | ssh root@printer 'sh -s'

set -eu

KLIPPER_DIR="/usr/data/e5m-ck/klipper"
EXTRAS_DIR="$KLIPPER_DIR/klippy/extras"
BIN_DIR="/usr/data/e5m-ck/bin"
CONFIG_DIR="/usr/data/printer_data/config"
MACROS_DIR="$CONFIG_DIR/macros"
PRINTER_CFG="$CONFIG_DIR/printer.cfg"

ts()   { date +'%H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(ts)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; exit 1; }

# -- Preflight ------------------------------------------------------------
info "=== Preflight ==="
[ -d "$KLIPPER_DIR/.git" ]   || die "Klipper not installed at $KLIPPER_DIR. Run install_klipper.sh first."
[ -d "$EXTRAS_DIR" ]         || die "$EXTRAS_DIR missing — broken Klipper install?"
[ -f "$EXTRAS_DIR/gcode_shell_command.py" ] \
    || die "gcode_shell_command.py missing — run install_klipper.sh with the extras pipeline."
[ -x /usr/share/klippy-env/bin/python3 ] \
    || die "/usr/share/klippy-env/bin/python3 missing — Klipper venv broken?"
for f in eddy_drift_watchdog.py start_eddy_drift_watchdog.sh eddy_drift.cfg; do
    [ -f "/tmp/$f" ] || die "/tmp/$f missing. Stage it: scp -O <repo-path> root@printer:/tmp/"
done
info "All three artifacts staged at /tmp/"
[ -f "$PRINTER_CFG" ] || die "$PRINTER_CFG not found."

# -- 1. Copy python + shell launcher -------------------------------------
info ""
info "=== Copy watchdog + launcher → bin/ ==="
mkdir -p "$BIN_DIR"
for f in eddy_drift_watchdog.py start_eddy_drift_watchdog.sh; do
    src="/tmp/$f"
    dst="$BIN_DIR/$f"
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        info "  $f already up to date — skipping."
    else
        cp "$src" "$dst"
        chmod 0755 "$dst"
        info "  installed $dst ($(wc -c < "$dst") bytes)"
    fi
done

# -- 2. Copy the macro config --------------------------------------------
info ""
info "=== Copy eddy_drift.cfg → config/macros/ ==="
mkdir -p "$MACROS_DIR"
src="/tmp/eddy_drift.cfg"
dst="$MACROS_DIR/eddy_drift.cfg"
if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    info "  eddy_drift.cfg already up to date — skipping."
else
    cp "$src" "$dst"
    chmod 0644 "$dst"
    info "  installed $dst ($(wc -c < "$dst") bytes)"
fi

# -- 3. Ensure [include macros/eddy_drift.cfg] in printer.cfg ------------
# In-place edit (no scp) to preserve the SAVE_CONFIG autosave block.
info ""
info "=== Wire [include macros/eddy_drift.cfg] into printer.cfg ==="
if grep -q '^\[include macros/eddy_drift\.cfg\]' "$PRINTER_CFG"; then
    info "  already present — skipping."
else
    tmp=$(mktemp)
    awk '
        /^\[include macros\// { last_macros = NR; lines[NR] = $0; next }
        /^\[include / { last_include = NR; lines[NR] = $0; next }
        { lines[NR] = $0 }
        END {
            anchor = (last_macros ? last_macros : last_include)
            for (i = 1; i <= NR; i++) {
                print lines[i]
                if (i == anchor) print "[include macros/eddy_drift.cfg]"
            }
        }
    ' "$PRINTER_CFG" > "$tmp"
    orig_lines=$(wc -l < "$PRINTER_CFG")
    new_lines=$(wc -l < "$tmp")
    if [ "$new_lines" -ne "$((orig_lines + 1))" ]; then
        rm -f "$tmp"
        die "awk inject produced unexpected line count ($orig_lines → $new_lines). Aborting."
    fi
    cp "$PRINTER_CFG" "$PRINTER_CFG.bak-eddy-drift-$(date +%Y%m%d-%H%M%S)"
    mv "$tmp" "$PRINTER_CFG"
    info "  added [include macros/eddy_drift.cfg] (backup of pre-edit cfg kept)"
fi

info ""
info "Done. Restart Klipper from local:"
info "  ssh root@printer '/etc/init.d/S55klipper_service restart'"
info ""
info "Then from Fluidd's console (or any Guppy macro button):"
info "  EDDY_DRIFT_CALIBRATE"
info ""
info "Watchdog log (post-mortem if needed): /tmp/eddy_drift_watchdog.log"
