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
#   - install_klipper.sh   already ran  (klippy/extras/ exists, .git present)
#   - install_guppyscreen.sh already ran (k1_mods/ extras present)
#   - /tmp/tmcstatus.py staged (our vendored, master-safe rewrite from
#     klipper/extras/tmcstatus.py — NOT the k1_mods/ upstream copy).
#   - klipper/config/tmc.cfg is included from printer.cfg (sync.sh does
#     not touch printer.cfg — the include line is added in place; see
#     "printer.cfg include" step below).
#
# What this script does:
#   1. Validates guppy_module_loader.py is present in /usr/data/guppyscreen/k1_mods/
#      and our vendored tmcstatus.py is staged at /tmp/.
#   2. Copies guppy_module_loader.py (untouched upstream) and our vendored
#      tmcstatus.py into klippy/extras/. Plain `cp`, not symlink: if Guppy
#      is ever wiped or upgraded, Klipper at boot would crash on a dangling
#      symlink. With a copy, Klipper stays up; re-run this installer to
#      refresh.
#   3. Ensures [include tmc.cfg] is present in /usr/data/printer_data/config/printer.cfg
#      (in-place edit so Klipper's autosave block at the bottom is preserved
#      — we never scp printer.cfg).
#
# About the vendored tmcstatus.py:
# The upstream tmcstatus.py shipped in /usr/data/guppyscreen/k1_mods/ was
# written for the Creality K1 Klipper fork. It reads DRV_STATUS/SG_RESULT
# directly from get_status(), which on Klipper master triggers an MCU
# shutdown ("Command request") and a reactor crash within seconds of
# _GUPPY_LOAD_MODULE SECTION=tmcstatus. Our rewrite at klipper/extras/
# tmcstatus.py uses a 1 Hz reactor timer to cache registers, so
# get_status() does pure dict lookups — same API, same field names,
# zero UART traffic in the hot callback.
#
# Usage (over SSH from local):
#   scp -O klipper/extras/tmcstatus.py root@printer:/tmp/
#   cat installs/install_tmc_status.sh | ssh root@printer 'sh -s'

set -eu

KLIPPER_DIR="/usr/data/e5m-ck/klipper"
EXTRAS_DIR="$KLIPPER_DIR/klippy/extras"
GUPPY_MODS="/usr/data/guppyscreen/k1_mods"
PRINTER_CFG="/usr/data/printer_data/config/printer.cfg"

ts()   { date +'%H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(ts)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; exit 1; }

# -- Preflight ------------------------------------------------------------
info "=== Preflight ==="
[ -d "$KLIPPER_DIR/.git" ] || die "Klipper not installed at $KLIPPER_DIR. Run install_klipper.sh first."
[ -d "$EXTRAS_DIR" ]       || die "$EXTRAS_DIR missing — broken Klipper install?"
[ -d "$GUPPY_MODS" ]       || die "$GUPPY_MODS missing — run install_guppyscreen.sh first."

[ -f "$GUPPY_MODS/guppy_module_loader.py" ] \
    || die "guppy_module_loader.py missing from $GUPPY_MODS — GuppyScreen tarball layout changed?"
[ -f /tmp/tmcstatus.py ] \
    || die "/tmp/tmcstatus.py missing. Stage it first: scp -O klipper/extras/tmcstatus.py root@printer:/tmp/"
info "Source extras present (guppy_module_loader.py from k1_mods/, tmcstatus.py from /tmp/)"
[ -f "$PRINTER_CFG" ] || die "$PRINTER_CFG not found — Klipper config dir missing?"

# -- 1. Copy extras into Klipper -----------------------------------------
info ""
info "=== Copy TMC status extras → klippy/extras/ ==="
# guppy_module_loader.py comes from upstream Guppy untouched (28 lines,
# just registers _GUPPY_LOAD_MODULE / _GUPPY_UNLOAD_MODULE — no MCU
# traffic, harmless on master).
src="$GUPPY_MODS/guppy_module_loader.py"
dst="$EXTRAS_DIR/guppy_module_loader.py"
if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    info "  guppy_module_loader.py already up to date — skipping."
else
    cp "$src" "$dst"
    chmod 0644 "$dst"
    info "  installed $dst ($(wc -c < "$dst") bytes, from k1_mods/)"
fi
# tmcstatus.py is our vendored rewrite — DO NOT use the k1_mods/ copy,
# it crashes Klipper master (see header of klipper/extras/tmcstatus.py).
src="/tmp/tmcstatus.py"
dst="$EXTRAS_DIR/tmcstatus.py"
if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    info "  tmcstatus.py already up to date — skipping."
else
    cp "$src" "$dst"
    chmod 0644 "$dst"
    info "  installed $dst ($(wc -c < "$dst") bytes, from repo /tmp/)"
fi

# -- 2. Ensure [include tmc.cfg] in printer.cfg --------------------------
# We do NOT scp printer.cfg from the repo — that would clobber the
# autosave block (PIDs, eddy z-offset, probe cal) at the bottom of
# the file. Instead, add the include in place if it's missing.
info ""
info "=== Wire [include tmc.cfg] into printer.cfg ==="
if grep -q '^\[include tmc\.cfg\]' "$PRINTER_CFG"; then
    info "  already present — skipping."
else
    # Insert the new include line directly after the last existing
    # [include ...] line. awk in busybox is fine for this.
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
    # Sanity check: the new file must be longer by exactly one line.
    orig_lines=$(wc -l < "$PRINTER_CFG")
    new_lines=$(wc -l < "$tmp")
    if [ "$new_lines" -ne "$((orig_lines + 1))" ]; then
        rm -f "$tmp"
        die "awk inject produced unexpected line count ($orig_lines → $new_lines). Aborting; printer.cfg untouched."
    fi
    # Back up the live cfg before overwriting (in-place; no scp).
    cp "$PRINTER_CFG" "$PRINTER_CFG.bak-tmc-$(date +%Y%m%d-%H%M%S)"
    mv "$tmp" "$PRINTER_CFG"
    info "  added [include tmc.cfg] (backup of pre-edit cfg kept next to it)"
fi

# -- 3. tmc.cfg presence -------------------------------------------------
# tmc.cfg lives in the repo and is pushed by sync.sh. Don't fail hard if
# it's missing here — the user may run this installer before the next
# sync. Just nudge them.
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
info "Then open GuppyScreen → Settings → TMC Metrics. Live driver state"
info "appears per stepper. The tmcstatus object is only loaded while the"
info "panel is visible (lazy via _GUPPY_LOAD_MODULE)."
