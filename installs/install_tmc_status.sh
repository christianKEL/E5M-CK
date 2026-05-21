#!/bin/sh
# install_tmc_status.sh — wire GuppyScreen's "TMC Metrics" panel.
#
# Runs ON THE PRINTER (busybox sh).
# Idempotent: re-running upgrades the extras in place.
#
# Scope: Phase A (status-only). TMC Autotune is intentionally NOT
# installed — see klipper/config/tmc.cfg for the rationale.
#
# Prerequisites:
#   - install_klipper.sh   already ran (klippy/extras/ exists, .git present)
#   - install_guppyscreen.sh already ran (init.d/S99guppyscreen present)
#   - Three artifacts staged at /tmp/:
#       /tmp/tmcstatus.py            (vendored master-safe rewrite)
#       /tmp/guppy_module_loader.py  (vendored with tmcstatus auto-restart)
#       /tmp/restart_guppyscreen.sh  (detached-restart helper)
#
# What this script does:
#   1. Validates the three staged artifacts.
#   2. Copies the two .py extras into klippy/extras/.
#   3. Copies restart_guppyscreen.sh into /usr/data/e5m-ck/bin/ (chmod 0755).
#   4. Ensures [include tmc.cfg] is present in /usr/data/printer_data/config/printer.cfg
#      (in-place edit so Klipper's autosave block at the bottom is preserved
#      — we never scp printer.cfg).
#
# Why both .py extras are vendored:
#
# - tmcstatus.py: upstream (k1_mods/) was written for the Creality K1
#   Klipper fork and reads DRV_STATUS/SG_RESULT directly from
#   get_status(), which on Klipper master crashes the MCU ("Command
#   request") within seconds of _GUPPY_LOAD_MODULE. Our rewrite uses
#   a 1 Hz reactor timer that caches registers, so get_status() does
#   pure dict lookups.
#
# - guppy_module_loader.py: upstream just pops the object on
#   _GUPPY_UNLOAD_MODULE, which on tmcstatus specifically leaves the
#   LVGL panel frozen on the last live frame (Guppy doesn't redraw
#   on empty-payload updates). Our patched loader fires
#   `RUN_SHELL_COMMAND CMD=restart_guppyscreen` after popping
#   tmcstatus, so the user toggling OFF in Settings automatically
#   gets a clean "back to before ON" screen.
#
# Usage (over SSH from local):
#   scp -O klipper/extras/tmcstatus.py            root@printer:/tmp/
#   scp -O klipper/extras/guppy_module_loader.py  root@printer:/tmp/
#   scp -O klipper/scripts/restart_guppyscreen.sh root@printer:/tmp/
#   cat installs/install_tmc_status.sh | ssh root@printer 'sh -s'

set -eu

KLIPPER_DIR="/usr/data/e5m-ck/klipper"
EXTRAS_DIR="$KLIPPER_DIR/klippy/extras"
BIN_DIR="/usr/data/e5m-ck/bin"
PRINTER_CFG="/usr/data/printer_data/config/printer.cfg"

ts()   { date +'%H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(ts)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; exit 1; }

# -- Preflight ------------------------------------------------------------
info "=== Preflight ==="
[ -d "$KLIPPER_DIR/.git" ] || die "Klipper not installed at $KLIPPER_DIR. Run install_klipper.sh first."
[ -d "$EXTRAS_DIR" ]       || die "$EXTRAS_DIR missing — broken Klipper install?"
[ -x /etc/init.d/S99guppyscreen ] \
    || die "/etc/init.d/S99guppyscreen not present — run install_guppyscreen.sh first."
for f in tmcstatus.py guppy_module_loader.py restart_guppyscreen.sh; do
    [ -f "/tmp/$f" ] || die "/tmp/$f missing. Stage it: scp -O <repo-path> root@printer:/tmp/"
done
info "All three artifacts staged at /tmp/"
[ -f "$PRINTER_CFG" ] || die "$PRINTER_CFG not found — Klipper config dir missing?"

# -- 1. Copy .py extras into Klipper ------------------------------------
info ""
info "=== Copy extras → klippy/extras/ ==="
for f in guppy_module_loader.py tmcstatus.py; do
    src="/tmp/$f"
    dst="$EXTRAS_DIR/$f"
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        info "  $f already up to date — skipping."
    else
        cp "$src" "$dst"
        chmod 0644 "$dst"
        info "  installed $dst ($(wc -c < "$dst") bytes, vendored)"
    fi
done

# -- 2. Copy restart helper into bin/ -----------------------------------
info ""
info "=== Copy restart helper → bin/ ==="
mkdir -p "$BIN_DIR"
src="/tmp/restart_guppyscreen.sh"
dst="$BIN_DIR/restart_guppyscreen.sh"
if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    info "  restart_guppyscreen.sh already up to date — skipping."
else
    cp "$src" "$dst"
    chmod 0755 "$dst"
    info "  installed $dst ($(wc -c < "$dst") bytes)"
fi

# -- 3. Ensure [include tmc.cfg] in printer.cfg --------------------------
# We do NOT scp printer.cfg from the repo — that would clobber the
# autosave block (PIDs, eddy z-offset, probe cal) at the bottom of
# the file. Instead, add the include in place if it's missing.
info ""
info "=== Wire [include tmc.cfg] into printer.cfg ==="
if grep -q '^\[include tmc\.cfg\]' "$PRINTER_CFG"; then
    info "  already present — skipping."
else
    tmp=$(mktemp)
    awk '
        /^\[include / { last_include = NR; lines[NR] = $0; next }
        { lines[NR] = $0 }
        END {
            for (i = 1; i <= NR; i++) {
                print lines[i]
                if (i == last_include) print "[include tmc.cfg]"
            }
        }
    ' "$PRINTER_CFG" > "$tmp"
    orig_lines=$(wc -l < "$PRINTER_CFG")
    new_lines=$(wc -l < "$tmp")
    if [ "$new_lines" -ne "$((orig_lines + 1))" ]; then
        rm -f "$tmp"
        die "awk inject produced unexpected line count ($orig_lines → $new_lines). Aborting; printer.cfg untouched."
    fi
    cp "$PRINTER_CFG" "$PRINTER_CFG.bak-tmc-$(date +%Y%m%d-%H%M%S)"
    mv "$tmp" "$PRINTER_CFG"
    info "  added [include tmc.cfg] (backup of pre-edit cfg kept next to it)"
fi

# -- 4. tmc.cfg presence ------------------------------------------------
info ""
info "=== Check tmc.cfg deployed ==="
if [ -f "/usr/data/printer_data/config/tmc.cfg" ]; then
    info "  /usr/data/printer_data/config/tmc.cfg present."
else
    warn "  /usr/data/printer_data/config/tmc.cfg NOT present."
    warn "  Run \`bash scripts/sync.sh --apply\` from your local repo, THEN restart Klipper."
fi

info ""
info "Done. Restart Klipper from local:"
info "  ssh root@printer '/etc/init.d/S55klipper_service restart'"
info ""
info "Behavior:"
info "  - TMC Metrics ON  in Guppy Settings → panel shows live driver data"
info "  - TMC Metrics OFF in Guppy Settings → Guppy auto-restarts (~3 s blank),"
info "    panel disappears (clean 'back to before ON' state)"
