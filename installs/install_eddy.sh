#!/bin/sh
# ============================================================
# E5M-CK BTT Eddy USB Flasher
# Flash btteddy.uf2 firmware to a BTT Eddy (RP2040) in BOOTSEL mode
# Then update eddy.cfg with the correct serial ID if needed.
# Creality Ender 5 Max — Nebula Pad
# https://github.com/christianKEL/E5M-CK
# ============================================================

# ─── Configuration ─────────────────────────────────────────
REPO_OWNER="christianKEL"
REPO_NAME="E5M-CK"
REPO_BRANCH="main"

UF2_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/files/btteddy.uf2"
EDDY_CFG_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/configs/cfg/eddy.cfg"

EXPECTED_UF2_SIZE_MIN="50000"
EXPECTED_UF2_SIZE_MAX="200000"

# ─── Paths ─────────────────────────────────────────────────
TMP_DIR="/usr/data/.tmp_install"
UF2_TMP="$TMP_DIR/btteddy.uf2"
EDDY_CFG="/usr/data/printer_data/config/eddy.cfg"
KLIPPER_SERVICE="/etc/init.d/S55klipper_service"

WAIT_BOOTSEL_TIMEOUT="120"
WAIT_SERIAL_TIMEOUT="30"

# ─── ANSI COLORS (Red / White / Black theme) ───
RED='\033[0;31m'
BR_RED='\033[1;31m'
BG_RED='\033[41m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
DIM='\033[2m'
BLACK='\033[0;30m'
BG_BLACK='\033[40m'
BG_WHITE='\033[47m'
BOLD='\033[1m'
BLINK='\033[5m'
UNDER='\033[4m'
INV='\033[7m'
NC='\033[0m'

GREEN='\033[0;32m'
BR_GREEN='\033[1;32m'
YELLOW='\033[1;33m'

# ─── printf wrapper ───
p() { printf "%b\n" "$1"; }

# ─── LOG FUNCTIONS ───
log_info()    { p "  ${WHITE}i${NC}  ${GRAY}$(date +%H:%M:%S)${NC} ${WHITE}$1${NC}"; }
log_ok()      { p "  ${BR_GREEN}✓${NC}  ${GRAY}$(date +%H:%M:%S)${NC} ${WHITE}$1${NC}"; }
log_warn()    { p "  ${YELLOW}!${NC}  ${GRAY}$(date +%H:%M:%S)${NC} ${YELLOW}$1${NC}"; }
log_error()   { p "  ${BR_RED}✗${NC}  ${GRAY}$(date +%H:%M:%S)${NC} ${BR_RED}$1${NC}"; }
log_action()  { p "  ${RED}>${NC}  ${GRAY}$(date +%H:%M:%S)${NC} ${DIM}$1${NC}"; }

# ─── STEP HEADER ───
log_step() {
    STEP_NUM=$1
    STEP_TITLE=$2
    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} STEP $STEP_NUM ${NC}  ${WHITE}${BOLD}$STEP_TITLE${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
}

pause_user() {
    p ""
    printf "  ${YELLOW}>${NC} ${WHITE}$1${NC}"
    read DUMMY
}

die() {
    log_error "$1"
    rm -f "$UF2_TMP"
    exit 1
}

# ─── BANNER ───
show_banner() {
    clear
    p ""
    p "${BR_RED}    ███████╗███████╗███╗   ███╗       ██████╗██╗  ██╗${NC}"
    p "${BR_RED}    ██╔════╝██╔════╝████╗ ████║      ██╔════╝██║ ██╔╝${NC}"
    p "${BR_RED}    █████╗  ███████╗██╔████╔██║█████╗██║     █████╔╝${NC}"
    p "${BR_RED}    ██╔══╝  ╚════██║██║╚██╔╝██║╚════╝██║     ██╔═██╗${NC}"
    p "${BR_RED}    ███████╗███████║██║ ╚═╝ ██║      ╚██████╗██║  ██╗${NC}"
    p "${BR_RED}    ╚══════╝╚══════╝╚═╝     ╚═╝       ╚═════╝╚═╝  ╚═╝${NC}"
    p ""
    p "${WHITE}             BTT Eddy USB Flasher${NC}"
    p "${GRAY}              for Creality Ender 5 Max (Nebula Pad)${NC}"
    p ""
    p "                    ${BG_RED}${WHITE}${BOLD}  CR*ALITY S*CKS  ${NC}"
    p ""
    p "${DIM}                 github.com/christianKEL/E5M-CK${NC}"
    p ""
}

# ─── DISCLAIMER ───
show_disclaimer() {
    p "${BR_RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}║${NC}  ${BG_RED}${WHITE}${BOLD}  DISCLAIMER  ${NC}                                                   ${BR_RED}║${NC}"
    p "${BR_RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
    p "  ${WHITE}This installer flashes the ${BOLD}BTT Eddy USB${NC}${WHITE} (RP2040) firmware${NC}"
    p "  ${WHITE}so it can be used as a Z-probe with Klipper mainline.${NC}"
    p ""
    p "  ${WHITE}It will:${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} guide you through putting the Eddy in BOOTSEL mode"
    p "  ${WHITE}  ${BR_RED}>${NC} detect the RP2040 USB mass storage device"
    p "  ${WHITE}  ${BR_RED}>${NC} download ${DIM}btteddy.uf2${NC}${WHITE} from your repo${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} flash the firmware (copy .uf2 onto the device)"
    p "  ${WHITE}  ${BR_RED}>${NC} wait for the Eddy to come back as a Klipper serial port"
    p "  ${WHITE}  ${BR_RED}>${NC} update ${DIM}eddy.cfg${NC}${WHITE} with the correct serial ID${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} restart Klipper to pick up the change"
    p ""
    p "  ${YELLOW}!${NC}  ${WHITE}Have your Eddy and a USB cable ready before continuing.${NC}"
    p ""
    p "  ${WHITE}I am not responsible for ANYTHING that happens to your printer,${NC}"
    p "  ${WHITE}your Eddy, your house, your cat, or your sanity.${NC}"
    p ""
    p "  ${WHITE}${BOLD}CR*ALITY S*CKS${NC} ${WHITE}is a humorous expression, NOT defamation.${NC}"
    p ""
    p "  ${DIM}Signed: Christian KELHETTER${NC}"
    p "  ${DIM}github.com/christianKEL${NC}"
    p "  ${DIM}https://e5mdocumentation.kinsta.cloud/${NC}"
    p ""
    p "${BR_RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}║${NC}  ${BG_RED}${WHITE}${BOLD}  ♥  SUPPORT THIS WORK  ♥  ${NC}                                    ${BR_RED}║${NC}"
    p "${BR_RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
    p "  ${WHITE}If this installer saved you hours of work, please consider${NC}"
    p "  ${WHITE}buying me a ${BOLD}spool of filament${NC}${WHITE} as a thank you:${NC}"
    p ""
    p "  ${BR_RED}>${NC} ${UNDER}${WHITE}https://www.paypal.com/donate?token=6lw51uQOrrDBLN32dn5JPMpL0HSA8vMrRfjZSHFmQKXYKCddr1LHHpuKWCNTPMiqj2kIly1n5nmP0U6R${NC}"
    p ""
    pause_user "Press ENTER to continue..."
}

# ─── PRECHECK ───
step_precheck() {
    log_step "0" "Pre-flight checks"

    log_info "Checking required tools..."
    for tool in mount umount wget; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            die "Required tool not found: $tool"
        fi
    done
    log_ok "All tools present"

    log_info "Checking system date..."
    YEAR=$(date +%Y)
    if [ "$YEAR" -lt 2024 ]; then
        die "System date wrong (year $YEAR). Run: ntpd -d -q -n -p pool.ntp.org"
    fi
    log_ok "System date sane"

    log_info "Checking eddy.cfg presence..."
    if [ ! -f "$EDDY_CFG" ]; then
        log_warn "$EDDY_CFG not found — install_configs.sh first?"
        log_warn "Continuing anyway, but serial ID auto-update will be skipped."
    else
        log_ok "eddy.cfg found at $EDDY_CFG"
    fi

    log_info "Checking internet..."
    if ! ping -c 1 -W 3 raw.githubusercontent.com >/dev/null 2>&1; then
        die "Cannot reach raw.githubusercontent.com"
    fi
    log_ok "Internet OK"
}

# ─── SNAPSHOT BEFORE ───
step_snapshot() {
    log_step "1" "Check current automount state"

    log_info "Checking that no USB device is currently mounted on /tmp/udisk/..."
    if mount | grep -q "/tmp/udisk/"; then
        log_warn "An USB device is already mounted at /tmp/udisk/"
        log_warn "Existing entries:"
        mount | grep "/tmp/udisk/" | while read line; do log_action "$line"; done
        printf "  ${WHITE}Continue anyway? [y/N]: ${NC}"
        read CONTINUE
        case "$CONTINUE" in
            y|Y|yes|YES) log_warn "Continuing — make sure to identify the right device" ;;
            *) die "Aborted by user" ;;
        esac
    else
        log_ok "No USB device currently mounted at /tmp/udisk/"
    fi
}

# ─── BOOTSEL PROMPT ───
step_bootsel_prompt() {
    log_step "2" "Put Eddy in BOOTSEL mode"

    p ""
    p "${BR_RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}║${NC}  ${BG_RED}${WHITE}${BOLD}  YOUR ACTION REQUIRED  ${NC}                                         ${BR_RED}║${NC}"
    p "${BR_RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
    p "  ${WHITE}${BOLD}Follow these steps in order:${NC}"
    p ""
    p "  ${BR_RED}1.${NC} ${WHITE}Make sure the Eddy USB cable is ${BOLD}NOT${NC}${WHITE} connected to the Pad.${NC}"
    p ""
    p "  ${BR_RED}2.${NC} ${WHITE}On the Eddy board, locate the ${BOLD}BOOT${NC}${WHITE} button (small tactile switch).${NC}"
    p ""
    p "  ${BR_RED}3.${NC} ${WHITE}Press and ${BOLD}HOLD${NC}${WHITE} the BOOT button.${NC}"
    p ""
    p "  ${BR_RED}4.${NC} ${WHITE}While still holding BOOT, ${BOLD}plug the USB cable${NC}${WHITE} into the Nebula Pad.${NC}"
    p ""
    p "  ${BR_RED}5.${NC} ${WHITE}${BOLD}Release${NC}${WHITE} the BOOT button.${NC}"
    p ""
    p "  ${WHITE}When done correctly, the Eddy appears as a USB mass storage${NC}"
    p "  ${WHITE}device (similar to a USB key).${NC}"
    p ""
    pause_user "Press ENTER once the cable is plugged in with BOOT held..."
}

# ─── WAIT FOR BOOTSEL (Creality automount) ───
step_wait_bootsel() {
    log_step "3" "Wait for RP2040 in BOOTSEL mode (Creality automount)"

    log_info "Polling for /tmp/udisk/sd* mount (timeout ${WAIT_BOOTSEL_TIMEOUT}s)..."
    log_action "The Creality system auto-mounts USB mass storage there."

    BOOTSEL_MOUNT=""
    ELAPSED=0
    while [ "$ELAPSED" -lt "$WAIT_BOOTSEL_TIMEOUT" ]; do
        # Look for any /tmp/udisk/sdX1 or /tmp/udisk/sdX entry in mount output
        BOOTSEL_MOUNT=$(mount | grep -oE '/tmp/udisk/sd[a-z][0-9]*' | head -1)
        if [ -n "$BOOTSEL_MOUNT" ]; then
            break
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
        if [ $((ELAPSED % 10)) -eq 0 ]; then
            log_action "Still waiting... (${ELAPSED}s / ${WAIT_BOOTSEL_TIMEOUT}s)"
        fi
    done

    if [ -z "$BOOTSEL_MOUNT" ]; then
        die "Timeout: no USB device auto-mounted at /tmp/udisk/. Check that BOOT was held during plug-in."
    fi

    log_ok "USB device auto-mounted at: $BOOTSEL_MOUNT"
    RP2040_MOUNT="$BOOTSEL_MOUNT"
}

# ─── VERIFY RP2040 ───
step_verify_rp2040() {
    log_step "4" "Verify the auto-mounted device is a RP2040"

    log_info "Listing contents of $RP2040_MOUNT..."
    if [ ! -d "$RP2040_MOUNT" ]; then
        die "Mount point $RP2040_MOUNT does not exist"
    fi

    # The RP2040 in BOOTSEL exposes 2 standard files :
    #   - INFO_UF2.TXT  (info about UF2 mode)
    #   - INDEX.HTM     (link to https://raspberrypi.com/...)
    if [ -f "$RP2040_MOUNT/INFO_UF2.TXT" ]; then
        log_action "INFO_UF2.TXT found"
        # Display first line for confirmation
        FIRST_LINE=$(head -1 "$RP2040_MOUNT/INFO_UF2.TXT" 2>/dev/null)
        if [ -n "$FIRST_LINE" ]; then
            log_action "Content: $FIRST_LINE"
        fi
        log_ok "Confirmed: this is a RP2040 in BOOTSEL mode"
    elif [ -f "$RP2040_MOUNT/INDEX.HTM" ]; then
        log_action "INDEX.HTM found (no INFO_UF2.TXT — older RP2040 variant)"
        log_ok "Probably a RP2040 in BOOTSEL mode"
    else
        log_warn "Neither INFO_UF2.TXT nor INDEX.HTM found at $RP2040_MOUNT"
        log_warn "This might NOT be a RP2040. Listing contents:"
        ls -la "$RP2040_MOUNT" 2>&1 | while read line; do log_action "$line"; done
        printf "  ${WHITE}Continue anyway? [y/N]: ${NC}"
        read CONTINUE_ANYWAY
        case "$CONTINUE_ANYWAY" in
            y|Y|yes|YES) log_warn "Continuing at user's risk" ;;
            *) die "Aborted by user" ;;
        esac
    fi
}

# ─── DOWNLOAD UF2 ───
step_download() {
    log_step "5" "Download btteddy.uf2 firmware"

    log_info "Preparing temp dir..."
    mkdir -p "$TMP_DIR" || die "Cannot create $TMP_DIR"

    log_info "Removing previous firmware (if any)..."
    rm -f "$UF2_TMP"

    log_info "Fetching $UF2_URL..."
    wget --no-check-certificate -q -O "$UF2_TMP" "$UF2_URL" \
        || die "Firmware download failed"

    if [ ! -s "$UF2_TMP" ]; then
        die "Downloaded firmware is empty"
    fi

    SIZE=$(wc -c < "$UF2_TMP")
    log_info "Firmware size: $SIZE bytes"

    if [ "$SIZE" -lt "$EXPECTED_UF2_SIZE_MIN" ] || [ "$SIZE" -gt "$EXPECTED_UF2_SIZE_MAX" ]; then
        rm -f "$UF2_TMP"
        die "Firmware size outside expected range ($EXPECTED_UF2_SIZE_MIN - $EXPECTED_UF2_SIZE_MAX bytes)"
    fi

    # UF2 magic check: starts with "UF2\nWQ]\x9e..." -> first 4 bytes are 'UF2\n'
    HEAD4=$(head -c 4 "$UF2_TMP" | od -An -c | tr -d ' \n')
    case "$HEAD4" in
        UF2*) log_ok "Valid UF2 magic header" ;;
        *)    rm -f "$UF2_TMP"; die "Downloaded file is not a valid UF2 firmware" ;;
    esac

    log_ok "Firmware downloaded ($SIZE bytes)"
}

# ─── FLASH (via Creality automount) ───
step_flash() {
    log_step "6" "Copy firmware to RP2040 (Creality auto-mounted)"

    log_info "Copying $UF2_TMP to $RP2040_MOUNT/btteddy.uf2..."
    log_warn "The RP2040 will reboot AS SOON AS the copy completes."

    # The cp will likely fail with "I/O error" or "Bad file descriptor" when the
    # RP2040 reboots mid-copy. This is normal and expected.
    cp "$UF2_TMP" "$RP2040_MOUNT/btteddy.uf2" 2>&1 || true
    sync 2>&1 || true

    log_action "Copy command issued (expected USB disconnect imminent)"
    log_info "Waiting 3 seconds for the RP2040 to reboot..."
    sleep 3

    log_ok "Flash sequence completed"
}

# ─── WAIT FOR SERIAL ───
step_wait_serial() {
    log_step "7" "Wait for Eddy to come back as serial port"

    log_info "Polling for /dev/serial/by-id/usb-Klipper_rp2040_* (timeout ${WAIT_SERIAL_TIMEOUT}s)..."

    SERIAL_DEV=""
    ELAPSED=0
    while [ "$ELAPSED" -lt "$WAIT_SERIAL_TIMEOUT" ]; do
        for f in /dev/serial/by-id/usb-Klipper_rp2040_*-if00; do
            [ -e "$f" ] || continue
            SERIAL_DEV="$f"
            break
        done
        if [ -n "$SERIAL_DEV" ]; then
            break
        fi
        sleep 1
        ELAPSED=$((ELAPSED + 1))
        if [ $((ELAPSED % 3)) -eq 0 ]; then
            log_action "Still waiting... (${ELAPSED}s / ${WAIT_SERIAL_TIMEOUT}s)"
        fi
    done

    if [ -z "$SERIAL_DEV" ]; then
        die "Timeout: no Klipper RP2040 serial port appeared. Flash may have failed."
    fi

    log_ok "Eddy is now visible as: $SERIAL_DEV"
    EDDY_SERIAL="$SERIAL_DEV"

    # Extract the unique ID
    EDDY_ID=$(basename "$EDDY_SERIAL" | sed 's/usb-Klipper_rp2040_\(.*\)-if00/\1/')
    log_info "Eddy unique ID: $EDDY_ID"
}

# ─── UPDATE EDDY.CFG ───
step_update_cfg() {
    log_step "8" "Check and update eddy.cfg serial ID"

    if [ ! -f "$EDDY_CFG" ]; then
        log_warn "$EDDY_CFG not present — skipping serial ID update"
        return 0
    fi

    log_info "Reading current serial ID from eddy.cfg..."
    CURRENT_SERIAL=$(grep -E '^serial:' "$EDDY_CFG" | head -1 | sed 's/.*= *//; s/.*: *//' | tr -d ' ')

    if [ -z "$CURRENT_SERIAL" ]; then
        log_warn "Could not parse 'serial:' line from $EDDY_CFG"
        log_warn "Skipping auto-update. Edit manually if needed."
        return 0
    fi

    log_info "Current serial : $CURRENT_SERIAL"
    log_info "Detected serial: $EDDY_SERIAL"

    if [ "$CURRENT_SERIAL" = "$EDDY_SERIAL" ]; then
        log_ok "Serial IDs match — no update needed"
        return 0
    fi

    log_warn "Serial IDs DIFFER. Updating eddy.cfg with detected serial..."

    # Backup before sed
    cp "$EDDY_CFG" "${EDDY_CFG}.preflash" \
        || die "Cannot backup eddy.cfg before update"

    # Replace the line. Use | as separator since the value contains /
    sed -i "s|^serial:.*|serial: $EDDY_SERIAL|" "$EDDY_CFG" \
        || die "sed failed on $EDDY_CFG"

    # Verify the change took
    NEW_SERIAL=$(grep -E '^serial:' "$EDDY_CFG" | head -1 | sed 's/.*= *//; s/.*: *//' | tr -d ' ')
    if [ "$NEW_SERIAL" != "$EDDY_SERIAL" ]; then
        die "eddy.cfg update failed (serial line not changed correctly)"
    fi

    log_ok "eddy.cfg updated"
    log_action "Backup of previous eddy.cfg: ${EDDY_CFG}.preflash"
    p ""
    p "  ${YELLOW}!${NC}  ${WHITE}You should ${BOLD}push${NC}${WHITE} the updated eddy.cfg to your repo so future${NC}"
    p "     ${WHITE}redeployments use the right serial ID:${NC}"
    p ""
    p "     ${DIM}# On your PC:${NC}"
    p "     ${DIM}scp root@<printer-ip>:$EDDY_CFG <repo>/configs/cfg/eddy.cfg${NC}"
    p "     ${DIM}cd <repo> && git commit -am 'eddy: update serial ID' && git push${NC}"
    p ""
}

# ─── RESTART KLIPPER ───
step_restart_klipper() {
    log_step "9" "Restart Klipper"

    if [ ! -x "$KLIPPER_SERVICE" ]; then
        log_warn "Klipper service not found — skipping restart"
        return 0
    fi

    log_info "Restarting Klipper to pick up new MCU..."
    "$KLIPPER_SERVICE" restart 2>&1 | while read line; do log_action "$line"; done

    log_info "Waiting for Klipper to settle..."
    sleep 5

    log_info "Querying Klipper state via Moonraker..."
    KLIPPY_INFO=$(curl -s http://localhost:7125/printer/info 2>/dev/null)
    if [ -z "$KLIPPY_INFO" ]; then
        log_warn "Moonraker not responding — check it manually"
        return 0
    fi

    KLIPPY_STATE=$(echo "$KLIPPY_INFO" | sed -n 's/.*"state": "\([^"]*\)".*/\1/p' | head -1)
    case "$KLIPPY_STATE" in
        ready)
            log_ok "Klipper state: ${BOLD}ready${NC} — Eddy is connected and operational"
            ;;
        startup)
            log_warn "Klipper state: startup — still initializing, wait a few more seconds"
            log_action "Re-check with: curl -s http://localhost:7125/printer/info"
            ;;
        shutdown)
            log_warn "Klipper state: shutdown — there may be another error"
            log_action "Check log: tail -30 /usr/data/printer_data/logs/klippy.log"
            ;;
        error)
            log_error "Klipper state: error"
            log_action "Check log: tail -50 /usr/data/printer_data/logs/klippy.log"
            ;;
        *)
            log_warn "Klipper state: $KLIPPY_STATE (unexpected)"
            ;;
    esac
}

# ─── VERIFY ───
step_verify() {
    log_step "10" "Final verification"

    p ""
    p "  ${WHITE}Check                          Status${NC}"
    p "  ${GRAY}──────────────────────────────────────────────────────────${NC}"

    if [ -e "$EDDY_SERIAL" ]; then
        p "  ${BR_GREEN}✓${NC} ${WHITE}Eddy serial port${NC}              ${DIM}$EDDY_SERIAL${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}Eddy serial port${NC}              ${BR_RED}not found${NC}"
    fi

    if [ -f "$EDDY_CFG" ]; then
        CFG_SERIAL=$(grep -E '^serial:' "$EDDY_CFG" | head -1 | sed 's/.*: *//' | tr -d ' ')
        if [ "$CFG_SERIAL" = "$EDDY_SERIAL" ]; then
            p "  ${BR_GREEN}✓${NC} ${WHITE}eddy.cfg serial ID${NC}            ${DIM}matches${NC}"
        else
            p "  ${BR_RED}✗${NC} ${WHITE}eddy.cfg serial ID${NC}            ${BR_RED}MISMATCH ($CFG_SERIAL)${NC}"
        fi
    else
        p "  ${YELLOW}!${NC} ${WHITE}eddy.cfg${NC}                      ${YELLOW}not present${NC}"
    fi

    if pgrep -f "klippy.py" >/dev/null 2>&1; then
        p "  ${BR_GREEN}✓${NC} ${WHITE}Klipper process${NC}               ${DIM}running${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}Klipper process${NC}               ${BR_RED}not running${NC}"
    fi

    # Check that mcu 'eddy' is connected (no errors in last 20 lines of log)
    if grep -q "mcu 'eddy': Unable to open serial port" /usr/data/printer_data/logs/klippy.log 2>/dev/null | tail -5; then
        # Look at very recent log only (last 30 lines)
        RECENT_ERR=$(tail -30 /usr/data/printer_data/logs/klippy.log 2>/dev/null | grep -c "mcu 'eddy': Unable to open serial port")
        if [ "$RECENT_ERR" -eq 0 ]; then
            p "  ${BR_GREEN}✓${NC} ${WHITE}MCU 'eddy' connection${NC}         ${DIM}no recent errors${NC}"
        else
            p "  ${BR_RED}✗${NC} ${WHITE}MCU 'eddy' connection${NC}         ${BR_RED}$RECENT_ERR recent errors${NC}"
        fi
    fi

    p ""
}

# ─── COMPLETION ───
show_completion() {
    p ""
    p "${BR_RED}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${BG_RED}${WHITE}${BOLD}  ✓  EDDY FLASHER COMPLETE  ${NC}                                ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Your BTT Eddy is flashed with Klipper firmware and ready${NC}        ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}for use as a Z-probe.${NC}                                          ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}${BOLD}Next steps:${NC}                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}1. tail -30 /usr/data/printer_data/logs/klippy.log${NC}             ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}   → check that Klipper state is 'ready'${NC}                       ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}2. Calibrate Eddy:${NC}                                              ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}   - CAL_EDDY_DRIVE_CURRENT${NC}                                    ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}   - CAL_EDDY_MAPPING${NC}                                          ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}3. Test homing: G28${NC}                                            ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}If eddy.cfg was updated, push it to your repo so future${NC}         ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}install_configs.sh runs use the right serial ID.${NC}                ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ╚══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
}

# ─── MAIN ───
main() {
    show_banner
    show_disclaimer
    show_banner
    step_precheck
    step_snapshot
    step_bootsel_prompt
    step_wait_bootsel
    step_verify_rp2040
    step_download
    step_flash
    step_wait_serial
    step_update_cfg
    step_restart_klipper
    step_verify
    show_completion

    # Final cleanup
    rm -f "$UF2_TMP"
    rmdir "$TMP_DIR" 2>/dev/null || true
}

main "$@"
