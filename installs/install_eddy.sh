#!/bin/sh
# install_eddy.sh — flash and register the BTT Eddy probe.
#
# Runs ON THE PRINTER (busybox sh).
#
# What this script does:
#   1. Verifies the Eddy is in BOOTSEL mode (RPI-RP2 USB mass storage)
#      OR already running Klipper firmware (/dev/serial/by-id/usb-Klipper_rp2040_*).
#   2. If in BOOTSEL: mounts the RPI-RP2 drive, copies our UF2,
#      unmounts, waits for the device to re-enumerate as Klipper.
#   3. Once running, captures the actual /dev/serial/by-id/... path and
#      patches /usr/data/printer_data/config/eddy.cfg to use it.
#   4. Reports the detected serial-id so it can be synced back into the
#      repo via klipper/config/eddy.cfg.
#
# Required artifacts:
#   - /tmp/btteddy.uf2 (scp'd from klipper/binaries/rp2040/ before running)
#
# Usage (from local):
#   scp -O klipper/binaries/rp2040/btteddy.uf2 root@printer:/tmp/
#   cat installs/install_eddy.sh | ssh root@printer 'sh -s'

set -eu

UF2="/tmp/btteddy.uf2"
EDDY_CFG="/usr/data/printer_data/config/eddy.cfg"

ts()   { date +'%H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(ts)" "$*" >&2; }
err()  { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; }
die()  { err "$*"; exit 1; }

# -- Preflight ------------------------------------------------------------
info "=== Preflight ==="
[ -f "$UF2" ] || die "$UF2 missing. From local: scp -O klipper/binaries/rp2040/btteddy.uf2 root@printer:/tmp/"
info "UF2 present: $(wc -c < "$UF2") bytes"

# -- Detect Eddy state ----------------------------------------------------
info ""
info "=== Detect Eddy state ==="
EDDY_SERIAL_PATH=""
RP2_MOUNT=""

# Already running Klipper?
if ls /dev/serial/by-id/usb-Klipper_rp2040_*-if00 >/dev/null 2>&1; then
    EDDY_SERIAL_PATH=$(ls /dev/serial/by-id/usb-Klipper_rp2040_*-if00 | head -1)
    info "Eddy already running Klipper firmware."
    info "  serial: $EDDY_SERIAL_PATH"
    info "Skipping flash. Use --force to reflash."
elif RP2_DEV=$(blkid 2>/dev/null | grep -iE 'label=.*"?rpi-rp2"?' | head -1 | cut -d: -f1); then
    info "Eddy in BOOTSEL mode (RPI-RP2 mass storage at $RP2_DEV)"
    RP2_MOUNT="/tmp/rpi-rp2.mnt.$$"
    mkdir -p "$RP2_MOUNT"
    mount -t vfat "$RP2_DEV" "$RP2_MOUNT" || die "Failed to mount $RP2_DEV"
    info "Mounted at $RP2_MOUNT"

    info "Copying UF2..."
    cp "$UF2" "$RP2_MOUNT/btteddy.uf2"
    sync
    umount "$RP2_MOUNT" || warn "umount returned non-zero (Eddy may have already rebooted — that's normal)"
    rmdir "$RP2_MOUNT" 2>/dev/null || true

    info "Waiting up to 30s for Eddy to re-enumerate as Klipper..."
    for i in $(seq 1 30); do
        sleep 1
        if ls /dev/serial/by-id/usb-Klipper_rp2040_*-if00 >/dev/null 2>&1; then
            EDDY_SERIAL_PATH=$(ls /dev/serial/by-id/usb-Klipper_rp2040_*-if00 | head -1)
            info "  Found: $EDDY_SERIAL_PATH (after ${i}s)"
            break
        fi
    done
    [ -n "$EDDY_SERIAL_PATH" ] || die "Eddy never re-enumerated as Klipper. Check USB / firmware."
else
    err "No Eddy detected — neither as Klipper serial nor as BOOTSEL RPI-RP2 drive."
    err "Steps to put it in BOOTSEL:"
    err "  1. Unplug USB cable from the Eddy."
    err "  2. Hold the BOOT button on the Eddy board."
    err "  3. Plug USB back in (button still held)."
    err "  4. Release the button after 1 second."
    err "  5. Re-run this installer."
    exit 1
fi

# -- Patch eddy.cfg -------------------------------------------------------
info ""
info "=== Patch eddy.cfg with detected serial ==="
if [ ! -f "$EDDY_CFG" ]; then
    warn "$EDDY_CFG does not exist yet. Run scripts/sync.sh --apply first to deploy it,"
    warn "then re-run this installer to patch the serial path in place."
    info "For now, the detected serial is:"
    info "  $EDDY_SERIAL_PATH"
    info "Paste this into klipper/config/eddy.cfg in the [mcu eddy] section."
    exit 0
fi

# Replace any existing 'serial:' line in [mcu eddy] with the detected path.
# We use a simple awk pass: track when we're inside [mcu eddy], replace
# the serial: line, leave everything else untouched.
TMP_CFG="/tmp/eddy.cfg.patched.$$"
awk -v new="$EDDY_SERIAL_PATH" '
  /^\[mcu eddy\]/         { in_mcu=1; print; next }
  /^\[/ && in_mcu         { in_mcu=0 }
  in_mcu && /^serial:/    { print "serial: " new; next }
  { print }
' "$EDDY_CFG" > "$TMP_CFG"

# Verify the change actually happened
if grep -q "^serial: $EDDY_SERIAL_PATH" "$TMP_CFG"; then
    mv "$TMP_CFG" "$EDDY_CFG"
    info "Patched $EDDY_CFG"
    info "  serial: $EDDY_SERIAL_PATH"
else
    rm -f "$TMP_CFG"
    warn "Couldn't patch — [mcu eddy] section or 'serial:' line not found in $EDDY_CFG."
    info "Manual fix: edit the [mcu eddy] section to use:"
    info "  serial: $EDDY_SERIAL_PATH"
fi

info ""
info "Done. Next from local:"
info "  1. Pull the live eddy.cfg back into your repo and commit, so future"
info "     deploys carry the right serial-id:"
info "     ssh root@printer 'cat $EDDY_CFG' > klipper/config/eddy.cfg"
info "  2. Restart Klipper: ssh root@printer '/etc/init.d/S55klipper_service restart'"
info "  3. Verify [mcu eddy] is loaded: curl http://printer/printer/info"
