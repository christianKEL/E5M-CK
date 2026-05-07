#!/bin/sh
# ═══════════════════════════════════════════════════════════════════
#   install.sh — ADXL345 Creality firmware bridge for Klipper mainline
#
#   Deploys two Python modules into Klipper extras and patches
#   printer.cfg so [resonance_tester] / SHAPER_CALIBRATE can talk to
#   the Creality 2023 firmware on the nozzle_mcu (which uses the
#   legacy "query_adxl345 oid clock rest_ticks" wire format).
#
#   Usage from SSH on the printer:
#     curl -sSL https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh | sh
#     curl -sSL https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh | sh -s -- status
#     curl -sSL https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh | sh -s -- update
#     curl -sSL https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh | sh -s -- uninstall
#
#   Or download once and run locally:
#     wget https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh
#     sh install_adxl_patch_v2.sh install
# ═══════════════════════════════════════════════════════════════════

set -e

# ─── Configuration (edit before publishing) ────────────────────────
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/christianKEL/E5M-CK/main/files}"

# ─── Paths (Creality K-stack defaults) ─────────────────────────────
KLIPPER_EXTRAS="/usr/data/klipper/klippy/extras"
KLIPPY_ENV_PYTHON="/usr/share/klippy-env/bin/python"
PRINTER_CFG="/usr/data/printer_data/config/printer.cfg"
KLIPPY_LOG="/usr/data/printer_data/logs/klippy.log"
SERVICE_SCRIPT="/etc/init.d/S55klipper_service"

# ─── Internal markers ──────────────────────────────────────────────
MODULES="adxl345_creality.py accel_chip_proxy.py"
CFG_MARKER_BEGIN="# >>> adxl345-creality-bridge >>>"
CFG_MARKER_END="# <<< adxl345-creality-bridge <<<"
CFG_BACKUP_SUFFIX=".bak.adxl345-creality"

# ─── Console helpers ───────────────────────────────────────────────
RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; RESET=""
if [ -t 1 ]; then
    RED="$(printf '\033[31m')"
    GREEN="$(printf '\033[32m')"
    YELLOW="$(printf '\033[33m')"
    BLUE="$(printf '\033[34m')"
    BOLD="$(printf '\033[1m')"
    RESET="$(printf '\033[0m')"
fi

log()  { printf '%s[*]%s %s\n' "$BLUE"  "$RESET" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[!]%s %s\n' "$YELLOW" "$RESET" "$*"; }
err()  { printf '%s[-]%s %s\n' "$RED"   "$RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }


# ═══════════════════════════════════════════════════════════════════
#   Sanity checks
# ═══════════════════════════════════════════════════════════════════
preflight() {
    [ "$(id -u)" -eq 0 ] || die "Run as root."

    [ -d "$KLIPPER_EXTRAS" ] || die "Not found: $KLIPPER_EXTRAS — is Klipper installed?"
    [ -x "$KLIPPY_ENV_PYTHON" ] || die "Not found: $KLIPPY_ENV_PYTHON — wrong venv path?"
    [ -f "$PRINTER_CFG" ] || die "Not found: $PRINTER_CFG"
    [ -x "$SERVICE_SCRIPT" ] || die "Not found: $SERVICE_SCRIPT"

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        die "Neither curl nor wget is available."
    fi

    case "$REPO_RAW" in
        *CHANGE_ME*)
            die "REPO_RAW is not configured. Edit install_adxl_patch_v2.sh and set the GitHub raw URL, or run with REPO_RAW=https://... sh install_adxl_patch_v2.sh"
            ;;
    esac
}

fetch() {
    # fetch <url> <dest>
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2" || return 1
    else
        wget -qO "$2" "$1" || return 1
    fi
    [ -s "$2" ] || return 1
}

py_check() {
    # py_check <file>
    "$KLIPPY_ENV_PYTHON" -m py_compile "$1" 2>&1
}

klipper_running() {
    pgrep -f "klippy.py" >/dev/null 2>&1
}

klipper_stop() {
    if klipper_running; then
        log "Stopping Klipper..."
        "$SERVICE_SCRIPT" stop >/dev/null 2>&1 || true
        sleep 2
    fi
}

klipper_start() {
    log "Starting Klipper..."
    "$SERVICE_SCRIPT" start >/dev/null 2>&1 || true
    sleep 3
}

klipper_restart() {
    log "Restarting Klipper..."
    "$SERVICE_SCRIPT" restart >/dev/null 2>&1 || true
    sleep 5
}


# ═══════════════════════════════════════════════════════════════════
#   Module download & install
# ═══════════════════════════════════════════════════════════════════
download_modules() {
    TMPDIR="$(mktemp -d)"
    trap 'rm -rf "$TMPDIR"' EXIT

    for f in $MODULES; do
        log "Downloading $f..."
        if ! fetch "$REPO_RAW/$f" "$TMPDIR/$f"; then
            die "Download failed: $REPO_RAW/$f"
        fi
        # Sanity: must be Python (not a 404 HTML page)
        if ! head -1 "$TMPDIR/$f" | grep -qE '^(#|import|from|""")'; then
            die "Downloaded $f does not look like Python — bad URL?"
        fi
    done
    ok "All modules downloaded."
}

install_modules() {
    for f in $MODULES; do
        if [ -f "$KLIPPER_EXTRAS/$f" ]; then
            cp -a "$KLIPPER_EXTRAS/$f" "$KLIPPER_EXTRAS/$f$CFG_BACKUP_SUFFIX"
        fi
        cp "$TMPDIR/$f" "$KLIPPER_EXTRAS/$f"

        log "Verifying $f syntax..."
        if ! py_check "$KLIPPER_EXTRAS/$f"; then
            err "Syntax check failed on $f"
            die "Aborting — restore via 'uninstall' or check $f manually."
        fi
        ok "Installed: $KLIPPER_EXTRAS/$f"
    done
}

remove_modules() {
    for f in $MODULES; do
        if [ -f "$KLIPPER_EXTRAS/$f" ]; then
            rm -f "$KLIPPER_EXTRAS/$f"
            ok "Removed: $KLIPPER_EXTRAS/$f"
        fi
        # Also clean .pyc Klipper might have generated
        rm -f "$KLIPPER_EXTRAS/${f}c"
        rm -f "$KLIPPER_EXTRAS/$f$CFG_BACKUP_SUFFIX"
    done
}


# ═══════════════════════════════════════════════════════════════════
#   printer.cfg patching
# ═══════════════════════════════════════════════════════════════════
cfg_already_patched() {
    grep -qF "$CFG_MARKER_BEGIN" "$PRINTER_CFG"
}

cfg_patch() {
    if cfg_already_patched; then
        warn "printer.cfg already contains the bridge config — skipping patch."
        return 0
    fi

    BACKUP="$PRINTER_CFG$CFG_BACKUP_SUFFIX"
    log "Backing up printer.cfg → $BACKUP"
    cp -a "$PRINTER_CFG" "$BACKUP"

    # Klipper's SAVE_CONFIG appends a block at the end of printer.cfg
    # (lines starting with #*#). Anything ADDED AFTER that block will
    # be silently moved or corrupted on the next SAVE_CONFIG. So we
    # must insert our block BEFORE the SAVE_CONFIG block.
    SAVE_BLOCK_LINE="$(grep -n '^#\*#' "$PRINTER_CFG" | head -1 | cut -d: -f1)"

    BLOCK_FILE="$(mktemp)"
    cat > "$BLOCK_FILE" <<EOF

$CFG_MARKER_BEGIN
# Auto-added by adxl345-creality-bridge install_adxl_patch_v2.sh
# To remove this block, run install.sh uninstall (or delete manually
# everything between the BEGIN/END markers).

[accel_chip_proxy]
accel_use_chip: adxl345
adxl345_cs_pin: nozzle_mcu:PA4
adxl345_spi_speed: 5000000
adxl345_axes_map: x,-z,y
adxl345_spi_software_sclk_pin: nozzle_mcu:PA5
adxl345_spi_software_mosi_pin: nozzle_mcu:PA7
adxl345_spi_software_miso_pin: nozzle_mcu:PA6
lis2dw_cs_pin: nozzle_mcu:PA4
lis2dw_spi_speed: 5000000
lis2dw_axes_map: x,-z,y
lis2dw_spi_software_sclk_pin: nozzle_mcu:PA5
lis2dw_spi_software_mosi_pin: nozzle_mcu:PA7
lis2dw_spi_software_miso_pin: nozzle_mcu:PA6

[resonance_tester]
accel_chip: accel_chip_proxy
probe_points: 200, 200, 10
accel_per_hz: 50
$CFG_MARKER_END
EOF

    if [ -n "$SAVE_BLOCK_LINE" ]; then
        log "Found SAVE_CONFIG block at line $SAVE_BLOCK_LINE — inserting block before it"
        # Split: lines 1..(SAVE_BLOCK_LINE-1), our block, lines SAVE_BLOCK_LINE..end
        BEFORE_LINE=$((SAVE_BLOCK_LINE - 1))
        TMPCFG="$(mktemp)"
        head -n "$BEFORE_LINE" "$PRINTER_CFG" > "$TMPCFG"
        cat "$BLOCK_FILE" >> "$TMPCFG"
        tail -n +"$SAVE_BLOCK_LINE" "$PRINTER_CFG" >> "$TMPCFG"
        mv "$TMPCFG" "$PRINTER_CFG"
        ok "printer.cfg patched (inserted before SAVE_CONFIG block)."
    else
        log "No SAVE_CONFIG block found — appending at end of file"
        cat "$BLOCK_FILE" >> "$PRINTER_CFG"
        ok "printer.cfg patched (appended at end)."
    fi

    rm -f "$BLOCK_FILE"
}

cfg_unpatch() {
    if ! cfg_already_patched; then
        warn "No bridge block found in printer.cfg — nothing to unpatch."
        return 0
    fi

    BACKUP="$PRINTER_CFG$CFG_BACKUP_SUFFIX"
    if [ -f "$BACKUP" ]; then
        log "Restoring printer.cfg from backup $BACKUP"
        # Save current as .pre-restore in case user wants it back
        cp -a "$PRINTER_CFG" "${PRINTER_CFG}.pre-uninstall"
        cp -a "$BACKUP" "$PRINTER_CFG"
        ok "printer.cfg restored. (Pre-restore version saved to ${PRINTER_CFG}.pre-uninstall)"
    else
        warn "Backup $BACKUP not found — stripping markers in place."
        # Use sed to delete from BEGIN to END marker inclusive.
        # Use a temp file to avoid sed -i portability issues.
        TMPCFG="$(mktemp)"
        awk -v b="$CFG_MARKER_BEGIN" -v e="$CFG_MARKER_END" '
            $0 ~ b { skip=1 }
            !skip
            $0 ~ e { skip=0 }
        ' "$PRINTER_CFG" > "$TMPCFG"
        mv "$TMPCFG" "$PRINTER_CFG"
        ok "Bridge block removed from printer.cfg."
    fi
}


# ═══════════════════════════════════════════════════════════════════
#   Subcommands
# ═══════════════════════════════════════════════════════════════════
cmd_install() {
    log "${BOLD}Installing adxl345-creality-bridge${RESET}"
    preflight
    download_modules
    klipper_stop
    install_modules
    cfg_patch
    klipper_start

    echo
    ok "Installation complete."
    log "Watch the log for errors:"
    echo "    tail -f $KLIPPY_LOG"
    log "Then in Fluidd / GuppyScreen, run:"
    echo "    ACCELEROMETER_QUERY"
    echo "    SHAPER_CALIBRATE"
}

cmd_update() {
    log "${BOLD}Updating modules only (no printer.cfg changes)${RESET}"
    preflight
    download_modules
    klipper_stop
    install_modules
    klipper_start
    ok "Update complete."
}

cmd_uninstall() {
    log "${BOLD}Uninstalling adxl345-creality-bridge${RESET}"
    preflight
    klipper_stop
    cfg_unpatch
    remove_modules
    klipper_start
    ok "Uninstall complete."
}

cmd_status() {
    preflight
    echo
    printf "${BOLD}Klipper service:${RESET}        "
    if klipper_running; then
        printf "${GREEN}running${RESET} (pid %s)\n" "$(pgrep -f klippy.py | head -1)"
    else
        printf "${RED}not running${RESET}\n"
    fi

    printf "${BOLD}Klipper venv python:${RESET}   "
    [ -x "$KLIPPY_ENV_PYTHON" ] && printf "${GREEN}OK${RESET} (%s)\n" "$KLIPPY_ENV_PYTHON" \
                              || printf "${RED}MISSING${RESET}\n"

    echo
    printf "${BOLD}Modules in extras:${RESET}\n"
    for f in $MODULES; do
        if [ -f "$KLIPPER_EXTRAS/$f" ]; then
            SIZE=$(wc -c < "$KLIPPER_EXTRAS/$f")
            printf "  ${GREEN}[installed]${RESET} %-30s (%s bytes)\n" "$f" "$SIZE"
        else
            printf "  ${RED}[missing]${RESET}   %s\n" "$f"
        fi
    done

    echo
    printf "${BOLD}printer.cfg patch:${RESET}     "
    if cfg_already_patched; then
        printf "${GREEN}present${RESET}\n"
    else
        printf "${YELLOW}absent${RESET}\n"
    fi

    if [ -f "$PRINTER_CFG$CFG_BACKUP_SUFFIX" ]; then
        printf "${BOLD}printer.cfg backup:${RESET}    ${GREEN}present${RESET} (%s)\n" \
            "$PRINTER_CFG$CFG_BACKUP_SUFFIX"
    fi

    echo
    printf "${BOLD}Last 5 lines of klippy.log:${RESET}\n"
    if [ -f "$KLIPPY_LOG" ]; then
        tail -5 "$KLIPPY_LOG" | sed 's/^/    /'
    else
        echo "    (no log file)"
    fi
}

cmd_help() {
    cat <<EOF
${BOLD}install_adxl_patch_v2.sh — adxl345-creality-bridge installer${RESET}

Subcommands:
  install     Download modules, patch printer.cfg, restart Klipper
  update      Download modules only (no printer.cfg changes)
  uninstall   Restore printer.cfg, remove modules, restart Klipper
  status      Show what's installed / running
  help        This message

Environment:
  REPO_RAW    GitHub raw URL base. Currently: $REPO_RAW

Examples:
  curl -sSL https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh | sh
  curl -sSL https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh | sh -s -- status
  curl -sSL https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh | sh -s -- uninstall
EOF
}


# ═══════════════════════════════════════════════════════════════════
#   Dispatch
# ═══════════════════════════════════════════════════════════════════
CMD="${1:-install}"
case "$CMD" in
    install)    cmd_install ;;
    update)     cmd_update ;;
    uninstall)  cmd_uninstall ;;
    status)     cmd_status ;;
    help|-h|--help) cmd_help ;;
    *)
        err "Unknown subcommand: $CMD"
        cmd_help
        exit 1
        ;;
esac
