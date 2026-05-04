#!/bin/sh
# ============================================================
# E5M-CK Moonraker Installer
# Install Moonraker via Helper-Script pre-built archive
# (contains a Python 3.8 venv with all MIPS wheels pre-compiled)
# Creality Ender 5 Max — Nebula Pad
# https://github.com/christianKEL/E5M-CK
# ============================================================

# ─── Helper-Script source URLs ─────────────────────────────
HS_RAW="https://raw.githubusercontent.com/Guilouz/Creality-Helper-Script/main/files"
MOONRAKER_TAR_URL="$HS_RAW/moonraker/moonraker.tar.gz"
MOONRAKER_CONF_URL="$HS_RAW/moonraker/moonraker.conf"
MOONRAKER_ASVC_URL="$HS_RAW/moonraker/moonraker.asvc"
S56_SERVICE_URL="$HS_RAW/services/S56moonraker_service"

# ─── Paths ─────────────────────────────────────────────────
USER_DATA="/usr/data"
MOONRAKER_DIR="$USER_DATA/moonraker"
MOONRAKER_PY="$MOONRAKER_DIR/moonraker-env/bin/python"
MOONRAKER_SCRIPT="$MOONRAKER_DIR/moonraker/moonraker/moonraker.py"
PRINTER_DATA="$USER_DATA/printer_data"
PRINTER_CONFIG="$PRINTER_DATA/config"
PRINTER_LOGS="$PRINTER_DATA/logs"
PRINTER_GCODES="$PRINTER_DATA/gcodes"
PRINTER_COMMS="$PRINTER_DATA/comms"
S56_SERVICE="/etc/init.d/S56moonraker_service"
TAR_TMP="/tmp/moonraker.tar.gz"

# Expected sizes (Helper-Script values, may evolve over time)
EXPECTED_TAR_SIZE_MIN="20000000"   # >20 MB sanity check
EXPECTED_SERVICE_SIZE="1122"
EXPECTED_ASVC_SIZE="183"

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

# ─── printf wrapper (safe %b format) ───
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

# ─── PAUSE UTILITY ───
pause_user() {
    p ""
    printf "  ${YELLOW}>${NC} ${WHITE}$1${NC}"
    read DUMMY
}

die() { log_error "$1"; exit 1; }

# ─── BIG ASCII BANNER ───
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
    p "${WHITE}             Moonraker Installer${NC}"
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
    p "  ${WHITE}This installer deploys ${BOLD}Moonraker${NC}${WHITE} (web API for Klipper) on your${NC}"
    p "  ${WHITE}Nebula Pad. It uses the pre-built archive from Helper-Script (Guilouz)${NC}"
    p "  ${WHITE}because Moonraker has C dependencies that require GCC to compile,${NC}"
    p "  ${WHITE}and we can't fit GCC in the limited /opt space.${NC}"
    p ""
    p "  ${WHITE}It will:${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} download Moonraker pre-built tar.gz (~23 MB) from Helper-Script"
    p "  ${WHITE}  ${BR_RED}>${NC} extract it to ${DIM}/usr/data/moonraker${NC}${WHITE} (with venv + MIPS wheels)${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} install ${DIM}/etc/init.d/S56moonraker_service${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} create ${DIM}/usr/data/printer_data/{config,logs,gcodes,comms}${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} drop ${DIM}moonraker.conf${NC}${WHITE} and ${DIM}moonraker.asvc${NC}${WHITE} (Helper-Script defaults)${NC}"
    p ""
    p "  ${YELLOW}!${NC}  ${WHITE}Moonraker is NOT started by this script (Klipper isn't either).${NC}"
    p "     ${WHITE}You'll start everything once all components are in place.${NC}"
    p ""
    p "  ${WHITE}I am not responsible for ANYTHING that happens to your printer,${NC}"
    p "  ${WHITE}your Nebula Pad, your house, your cat, or your sanity.${NC}"
    p ""
    p "  ${WHITE}Everyone using this installer is assumed to have a brain and${NC}"
    p "  ${WHITE}the ability to figure things out on their own.${NC}"
    p ""
    p "  ${WHITE}${BOLD}CR*ALITY S*CKS${NC} ${WHITE}is a humorous expression, NOT defamation.${NC}"
    p "  ${WHITE}Their team should have provided a working printer so we didn't${NC}"
    p "  ${WHITE}need to build this tool in the first place.${NC}"
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

    log_info "Checking Klipper installation..."
    if [ ! -d "/usr/data/klipper" ]; then
        die "Klipper not found at /usr/data/klipper. Run install_klipper.sh first."
    fi
    log_ok "Klipper found"

    log_info "Checking system date..."
    YEAR=$(date +%Y)
    if [ "$YEAR" -lt 2024 ]; then
        die "System date is wrong (year $YEAR). Run: ntpd -d -q -n -p pool.ntp.org"
    fi
    log_ok "System date is sane"

    log_info "Checking free disk space in /usr/data..."
    FREE_MB=$(df -m /usr/data | awk 'NR==2 {print $4}')
    log_info "Free space: ${FREE_MB} MB"
    if [ "$FREE_MB" -lt 100 ]; then
        die "Less than 100 MB free in /usr/data — Moonraker needs ~80 MB"
    fi
    log_ok "Enough disk space"

    log_info "Checking internet..."
    if ! ping -c 1 -W 3 raw.githubusercontent.com >/dev/null 2>&1; then
        log_warn "Cannot ping raw.githubusercontent.com — install may fail"
    else
        log_ok "raw.githubusercontent.com reachable"
    fi
}

# ─── CONFIRMATION ───
confirm_install() {
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${WHITE}${BOLD}READY TO INSTALL${NC}                                                ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}Source       :${NC} ${DIM}Helper-Script (Guilouz) pre-built archive${NC}"
    p "  ${WHITE}Install dir  :${NC} ${DIM}$MOONRAKER_DIR${NC}"
    p "  ${WHITE}Service      :${NC} ${DIM}$S56_SERVICE${NC}"
    p "  ${WHITE}Printer data :${NC} ${DIM}$PRINTER_DATA${NC}"
    p ""
    if [ -d "$MOONRAKER_DIR" ]; then
        p "  ${YELLOW}!  Existing $MOONRAKER_DIR will be WIPED and reinstalled.${NC}"
        p ""
    fi
    if [ -f "$S56_SERVICE" ]; then
        p "  ${YELLOW}!  Existing $S56_SERVICE will be replaced.${NC}"
        p ""
    fi
    printf "  ${WHITE}Continue? [Y/n]: ${NC}"
    read CONFIRM
    case "$CONFIRM" in
        n|N|no|NO)
            p ""
            log_warn "Cancelled by user"
            p ""
            exit 0
            ;;
    esac
}

# ─── STEP 1 — DOWNLOAD MOONRAKER TAR ───
step_download_tar() {
    log_step "1" "Download Moonraker pre-built archive"

    log_info "Removing previous temp file (if any)..."
    rm -f "$TAR_TMP"

    log_info "Fetching from Helper-Script (~23 MB, may take 1-2 min)..."
    log_action "$MOONRAKER_TAR_URL"

    wget --no-check-certificate -O "$TAR_TMP" "$MOONRAKER_TAR_URL" 2>&1 | \
        grep -E "%|saved|connecting" | tail -5 | \
        while read line; do log_action "$line"; done

    if [ ! -s "$TAR_TMP" ]; then
        die "Downloaded archive is empty"
    fi

    SIZE=$(wc -c < "$TAR_TMP")
    log_info "Downloaded size: $SIZE bytes"

    if [ "$SIZE" -lt "$EXPECTED_TAR_SIZE_MIN" ]; then
        log_error "Archive too small (got $SIZE, expected at least $EXPECTED_TAR_SIZE_MIN)"
        rm -f "$TAR_TMP"
        die "Aborting"
    fi

    log_ok "Archive downloaded ($SIZE bytes)"
}

# ─── STEP 2 — VALIDATE TAR ───
step_validate_tar() {
    log_step "2" "Validate archive structure"

    log_info "Testing archive integrity (tar tzf)..."
    if ! tar tzf "$TAR_TMP" >/dev/null 2>&1; then
        log_error "Archive is corrupt or not a valid tar.gz"
        rm -f "$TAR_TMP"
        die "Aborting"
    fi
    log_ok "Archive is a valid gzip tar"

    log_info "Checking expected entries..."
    NEEDED="moonraker/moonraker-env/bin/python moonraker/moonraker/moonraker/moonraker.py"
    for entry in $NEEDED; do
        if tar tzf "$TAR_TMP" | grep -qF "$entry"; then
            log_action "Found: $entry"
        else
            log_error "Missing expected entry: $entry"
            rm -f "$TAR_TMP"
            die "Archive structure unexpected — Helper-Script may have changed it"
        fi
    done
    log_ok "Archive structure validated"
}

# ─── STEP 3 — EXTRACT ───
step_extract() {
    log_step "3" "Extract Moonraker to /usr/data/"

    if [ -d "$MOONRAKER_DIR" ]; then
        log_info "Wiping existing $MOONRAKER_DIR..."
        rm -rf "$MOONRAKER_DIR"
    fi

    log_info "Extracting archive (this takes 30-60 sec)..."
    cd "$USER_DATA"
    tar xzf "$TAR_TMP" || die "Extraction failed"
    cd - >/dev/null

    log_info "Removing temp archive..."
    rm -f "$TAR_TMP"

    log_info "Verifying extracted Python..."
    if [ ! -x "$MOONRAKER_PY" ]; then
        die "Python not found at $MOONRAKER_PY after extraction"
    fi
    PY_VER=$($MOONRAKER_PY --version 2>&1)
    log_ok "Moonraker venv ready ($PY_VER)"

    log_info "Verifying extracted moonraker.py..."
    if [ ! -f "$MOONRAKER_SCRIPT" ]; then
        die "Moonraker script not found at $MOONRAKER_SCRIPT"
    fi
    log_ok "Moonraker code at $MOONRAKER_SCRIPT"
}

# ─── STEP 4 — INSTALL SERVICE ───
step_install_service() {
    log_step "4" "Install S56moonraker_service"

    TMP="/tmp/S56moonraker_service.new"
    log_info "Removing previous temp file (if any)..."
    rm -f "$TMP"

    log_info "Fetching service from Helper-Script..."
    log_action "$S56_SERVICE_URL"
    wget --no-check-certificate -q -O "$TMP" "$S56_SERVICE_URL" \
        || die "Service download failed"

    if [ ! -s "$TMP" ]; then
        die "Service file is empty"
    fi

    SIZE=$(wc -c < "$TMP")
    log_info "Service size: $SIZE bytes"
    if [ "$SIZE" != "$EXPECTED_SERVICE_SIZE" ]; then
        log_warn "Size mismatch (got $SIZE, expected $EXPECTED_SERVICE_SIZE)"
        log_warn "Helper-Script may have updated the file. Continuing anyway."
    fi

    if [ -f "$S56_SERVICE" ]; then
        log_info "Replacing existing $S56_SERVICE..."
        rm -f "$S56_SERVICE"
    fi

    mv "$TMP" "$S56_SERVICE" || die "Failed to move service to $S56_SERVICE"
    chmod 755 "$S56_SERVICE" || die "chmod failed"

    log_ok "Service deployed: $S56_SERVICE"
}

# ─── STEP 5 — CREATE PRINTER_DATA DIRS ───
step_printer_data() {
    log_step "5" "Create printer_data directory structure"

    for dir in "$PRINTER_DATA" "$PRINTER_CONFIG" "$PRINTER_LOGS" "$PRINTER_GCODES" "$PRINTER_COMMS"; do
        if [ -d "$dir" ]; then
            log_action "Already exists: $dir"
        else
            mkdir -p "$dir" || die "Failed to create $dir"
            log_action "Created: $dir"
        fi
    done

    log_ok "printer_data structure ready"
}

# ─── STEP 6 — DEPLOY MOONRAKER.CONF ───
step_moonraker_conf() {
    log_step "6" "Deploy moonraker.conf"

    TMP="/tmp/moonraker.conf.new"
    rm -f "$TMP"

    log_info "Fetching moonraker.conf from Helper-Script..."
    log_action "$MOONRAKER_CONF_URL"
    wget --no-check-certificate -q -O "$TMP" "$MOONRAKER_CONF_URL" \
        || die "moonraker.conf download failed"

    if [ ! -s "$TMP" ]; then
        die "Downloaded moonraker.conf is empty"
    fi

    SIZE_BEFORE=$(wc -c < "$TMP")
    log_info "Conf size: $SIZE_BEFORE bytes (before cleanup)"

    # Remove the [update_manager Creality-Helper-Script] section.
    # Helper-Script's default conf includes a section that points to
    # /usr/data/helper-script/ which we don't install. Without this cleanup,
    # Moonraker logs "Repo path does not exist" warnings continuously.
    #
    # awk script: prints all lines EXCEPT those starting at the
    # [update_manager Creality-Helper-Script] header up to (but not
    # including) the next blank line or next [section] header.
    log_info "Removing [update_manager Creality-Helper-Script] section..."
    awk '
        /^\[update_manager Creality-Helper-Script\]/ { skip=1; next }
        skip && /^\[/ { skip=0 }
        skip && /^[[:space:]]*$/ { skip=0; next }
        !skip { print }
    ' "$TMP" > "${TMP}.cleaned"

    # Also remove the comment line that introduces the section, if present.
    # Pattern in Helper-Script default: "# Remove '#' after this line to keep Creality Helper Script up to date"
    sed -i "/^# Remove '#' after this line to keep Creality Helper Script/d" "${TMP}.cleaned"

    # Collapse multiple blank lines into one (cosmetic cleanup after removal)
    awk 'BEGIN { blank=0 } /^[[:space:]]*$/ { blank++; if (blank<=1) print; next } { blank=0; print }' \
        "${TMP}.cleaned" > "${TMP}.final"

    mv "${TMP}.final" "$TMP"
    rm -f "${TMP}.cleaned"

    SIZE_AFTER=$(wc -c < "$TMP")
    REMOVED=$((SIZE_BEFORE - SIZE_AFTER))
    log_action "Removed Helper-Script update_manager section ($REMOVED bytes)"

    # Sanity check: section is really gone
    if grep -qF "[update_manager Creality-Helper-Script]" "$TMP"; then
        log_error "Cleanup failed: section still present in conf"
        rm -f "$TMP"
        die "Aborting before deploying broken conf"
    fi
    log_ok "Section successfully removed"

    log_info "Final conf size: $SIZE_AFTER bytes"

    TARGET="$PRINTER_CONFIG/moonraker.conf"
    if [ -f "$TARGET" ]; then
        log_info "Backing up existing $TARGET to ${TARGET}.bak..."
        mv "$TARGET" "${TARGET}.bak"
    fi

    mv "$TMP" "$TARGET" || die "Failed to move moonraker.conf to $TARGET"
    chmod 644 "$TARGET"

    log_ok "Deployed: $TARGET"
}

# ─── STEP 7 — DEPLOY MOONRAKER.ASVC ───
step_moonraker_asvc() {
    log_step "7" "Deploy moonraker.asvc"

    TMP="/tmp/moonraker.asvc.new"
    rm -f "$TMP"

    log_info "Fetching moonraker.asvc from Helper-Script..."
    log_action "$MOONRAKER_ASVC_URL"
    wget --no-check-certificate -q -O "$TMP" "$MOONRAKER_ASVC_URL" \
        || die "moonraker.asvc download failed"

    if [ ! -s "$TMP" ]; then
        die "Downloaded moonraker.asvc is empty"
    fi

    SIZE=$(wc -c < "$TMP")
    log_info "ASVC size: $SIZE bytes"

    TARGET="$PRINTER_DATA/moonraker.asvc"
    if [ -f "$TARGET" ]; then
        log_info "Replacing existing $TARGET..."
        rm -f "$TARGET"
    fi

    mv "$TMP" "$TARGET" || die "Failed to move moonraker.asvc to $TARGET"
    chmod 644 "$TARGET"

    log_ok "Deployed: $TARGET"
}

# ─── STEP 8 — VERIFY ───
step_verify() {
    log_step "8" "Verify installation"

    p ""
    p "  ${WHITE}Check                          Status${NC}"
    p "  ${GRAY}──────────────────────────────────────────────────────────${NC}"

    # Moonraker code
    if [ -f "$MOONRAKER_SCRIPT" ]; then
        p "  ${BR_GREEN}✓${NC} ${WHITE}Moonraker code${NC}                ${DIM}$MOONRAKER_SCRIPT${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}Moonraker code${NC}                ${BR_RED}MISSING${NC}"
    fi

    # Python venv
    if [ -x "$MOONRAKER_PY" ]; then
        PY_VER=$($MOONRAKER_PY --version 2>&1)
        p "  ${BR_GREEN}✓${NC} ${WHITE}Moonraker venv${NC}                ${DIM}$PY_VER${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}Moonraker venv${NC}                ${BR_RED}MISSING${NC}"
    fi

    # Service
    if [ -x "$S56_SERVICE" ]; then
        p "  ${BR_GREEN}✓${NC} ${WHITE}S56moonraker_service${NC}          ${DIM}executable${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}S56moonraker_service${NC}          ${BR_RED}NOT executable${NC}"
    fi

    # printer_data dirs
    ALL_DIRS_OK=1
    for dir in "$PRINTER_CONFIG" "$PRINTER_LOGS" "$PRINTER_GCODES" "$PRINTER_COMMS"; do
        [ -d "$dir" ] || ALL_DIRS_OK=0
    done
    if [ "$ALL_DIRS_OK" -eq 1 ]; then
        p "  ${BR_GREEN}✓${NC} ${WHITE}printer_data structure${NC}        ${DIM}all 4 dirs present${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}printer_data structure${NC}        ${BR_RED}some dirs missing${NC}"
    fi

    # moonraker.conf
    if [ -f "$PRINTER_CONFIG/moonraker.conf" ]; then
        SIZE=$(wc -c < "$PRINTER_CONFIG/moonraker.conf")
        p "  ${BR_GREEN}✓${NC} ${WHITE}moonraker.conf${NC}                ${DIM}$SIZE bytes${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}moonraker.conf${NC}                ${BR_RED}MISSING${NC}"
    fi

    # moonraker.asvc
    if [ -f "$PRINTER_DATA/moonraker.asvc" ]; then
        SIZE=$(wc -c < "$PRINTER_DATA/moonraker.asvc")
        p "  ${BR_GREEN}✓${NC} ${WHITE}moonraker.asvc${NC}                ${DIM}$SIZE bytes${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}moonraker.asvc${NC}                ${BR_RED}MISSING${NC}"
    fi

    # Quick import test (sanity check that the venv works)
    log_info ""
    log_info "Testing Moonraker venv (import key modules)..."
    if $MOONRAKER_PY -c "import tornado, jinja2, streaming_form_data" 2>/dev/null; then
        p "  ${BR_GREEN}✓${NC} ${WHITE}Venv key imports${NC}              ${DIM}tornado, jinja2, streaming_form_data${NC}"
    else
        p "  ${YELLOW}!${NC} ${WHITE}Venv key imports${NC}              ${YELLOW}some modules missing — check at start${NC}"
    fi

    p ""
}

# ─── COMPLETION ───
show_completion() {
    p ""
    p "${BR_RED}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${BG_RED}${WHITE}${BOLD}  ✓  MOONRAKER INSTALLER COMPLETE  ${NC}                         ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Moonraker is installed but ${BOLD}NOT started${NC}${WHITE}.${NC}                       ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Next steps (in order):${NC}                                       ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}1. install_nginx.sh${NC}                                           ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}2. install_fluidd.sh${NC}                                          ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}3. install_guppyscreen.sh${NC}                                     ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}4. push your .cfg files to printer_data/config/${NC}               ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}5. start klipper + moonraker:${NC}                                 ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}   /etc/init.d/S55klipper_service start${NC}                       ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}   /etc/init.d/S56moonraker_service start${NC}                     ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Manage Moonraker service:${NC}                                    ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}/etc/init.d/S56moonraker_service {start|stop|restart}${NC}          ${BR_RED}║${NC}"
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
    confirm_install
    step_download_tar
    step_validate_tar
    step_extract
    step_install_service
    step_printer_data
    step_moonraker_conf
    step_moonraker_asvc
    step_verify
    show_completion
}

main "$@"
