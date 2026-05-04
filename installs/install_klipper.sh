#!/bin/sh
# ============================================================
# E5M-CK Klipper Mainline Installer
# Install Klipper mainline + c_helper.so on the Nebula Pad
# Reuses Creality's /usr/share/klippy-env (no new venv)
# Patches Creality's S55klipper_service to point to /usr/data/klipper
# Creality Ender 5 Max — Nebula Pad
# https://github.com/christianKEL/E5M-CK
# ============================================================

GITHUB_RAW="https://raw.githubusercontent.com/christianKEL/E5M-CK/main"
C_HELPER_URL="$GITHUB_RAW/files/c_helper.so"

# ─── Pin Klipper version (optional) ──────────────────────────
# Leave empty to use latest master.
# Set to a commit hash to pin a specific Klipper version (recommended if your
# MCU firmwares were compiled with a specific Klipper commit).
# Example : KLIPPER_COMMIT="373f200ca69adb624675f42e685f61d85d49ba40"
KLIPPER_COMMIT=""

# ─── Paths ───────────────────────────────────────────────────
KLIPPER_REPO="https://github.com/Klipper3d/klipper.git"
KLIPPER_DIR="/usr/data/klipper"
KLIPPER_VENV="/usr/share/klippy-env"          # Creality stock, reused as-is
KLIPPER_PY="/usr/share/klippy-env/bin/python"
KLIPPER_SERVICE="/etc/init.d/S55klipper_service"
E5M_DIR="/usr/data/E5M_CK"
PRINTER_DATA="/usr/data/printer_data"

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
    p "${WHITE}             Klipper Mainline Installer${NC}"
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
    p "  ${WHITE}This installer deploys ${BOLD}Klipper mainline${NC}${WHITE} from upstream${NC}"
    p "  ${WHITE}(github.com/Klipper3d/klipper) on your Nebula Pad.${NC}"
    p ""
    p "  ${WHITE}It will:${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} clone Klipper into ${DIM}/usr/data/klipper${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} download MIPS XBurst2 ${BOLD}c_helper.so${NC}${WHITE} (faster kinematics)${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} reuse Creality stock venv ${DIM}/usr/share/klippy-env${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} patch ${DIM}/etc/init.d/S55klipper_service${NC}${WHITE} (sed)${NC}"
    p ""
    p "  ${YELLOW}!${NC}  ${WHITE}Your MCU firmwares (mainboard / nozzle / Eddy) MUST be${NC}"
    p "     ${WHITE}compatible with the Klipper version you install. If you see${NC}"
    p "     ${WHITE}'MCU firmware out of date' after install, edit ${BOLD}KLIPPER_COMMIT${NC}"
    p "     ${WHITE}at the top of this script to pin a specific commit.${NC}"
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

    log_info "Checking Entware (opkg, git)..."
    if [ ! -x /opt/bin/opkg ]; then
        die "Entware not found. Run install_entware.sh first."
    fi
    if [ ! -x /opt/bin/git ]; then
        die "git not found in /opt/bin. Run install_entware.sh first."
    fi
    log_ok "Entware + git found"

    log_info "Checking Creality stock Klipper venv..."
    if [ ! -x "$KLIPPER_PY" ]; then
        die "Creality venv missing: $KLIPPER_PY does not exist"
    fi
    PY_VER=$($KLIPPER_PY --version 2>&1)
    log_ok "Creality venv OK ($PY_VER)"

    log_info "Checking Creality stock Klipper service..."
    if [ ! -f "$KLIPPER_SERVICE" ]; then
        die "Creality service missing: $KLIPPER_SERVICE does not exist"
    fi
    log_ok "Creality S55klipper_service found"

    log_info "Checking system date..."
    YEAR=$(date +%Y)
    if [ "$YEAR" -lt 2024 ]; then
        die "System date is wrong (year $YEAR). Run: ntpd -d -q -n -p pool.ntp.org"
    fi
    log_ok "System date is sane"

    log_info "Checking internet..."
    if ! ping -c 1 -W 3 github.com >/dev/null 2>&1; then
        log_warn "Cannot ping github.com — install may fail"
    else
        log_ok "github.com reachable"
    fi
}

# ─── CONFIRMATION ───
confirm_install() {
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${WHITE}${BOLD}READY TO INSTALL${NC}                                                ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}Klipper repo  :${NC} ${DIM}$KLIPPER_REPO${NC}"
    p "  ${WHITE}Install path  :${NC} ${DIM}$KLIPPER_DIR${NC}"
    if [ -n "$KLIPPER_COMMIT" ]; then
        p "  ${WHITE}Pinned commit :${NC} ${DIM}$KLIPPER_COMMIT${NC}"
    else
        p "  ${WHITE}Version       :${NC} ${DIM}latest master${NC}"
    fi
    p "  ${WHITE}Venv reused   :${NC} ${DIM}$KLIPPER_VENV${NC}"
    p "  ${WHITE}E5M-CK dir    :${NC} ${DIM}$E5M_DIR${NC}"
    p "  ${WHITE}c_helper.so   :${NC} ${DIM}$C_HELPER_URL${NC}"
    p ""
    if [ -d "$KLIPPER_DIR" ]; then
        p "  ${YELLOW}!  Existing $KLIPPER_DIR will be WIPED and reinstalled.${NC}"
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

# ─── STEP 1 — BACKUP CREALITY SERVICE ───
step_backup_service() {
    log_step "1" "Backup Creality stock S55klipper_service"

    mkdir -p "$E5M_DIR"

    BACKUP="$E5M_DIR/S55klipper_service.creality.bak"

    # If a backup already exists, keep the FIRST one (the original Creality stock).
    # Don't overwrite with an already-patched version from a previous run.
    if [ -f "$BACKUP" ]; then
        log_info "Backup already exists — keeping the original"
        log_action "$BACKUP"
    else
        log_info "Saving original to $BACKUP..."
        cp "$KLIPPER_SERVICE" "$BACKUP" || die "Backup failed"
        log_ok "Backup saved"
    fi
}

# ─── STEP 2 — DOWNLOAD c_helper.so ───
step_chelper() {
    log_step "2" "Download c_helper.so (MIPS XBurst2 with nan2008)"

    mkdir -p "$E5M_DIR"
    TMP="$E5M_DIR/c_helper.so.tmp"

    log_info "Removing previous temp file (if any)..."
    rm -f "$TMP"

    log_info "Fetching from GitHub..."
    log_action "$C_HELPER_URL"

    wget --no-check-certificate -q -O "$TMP" "$C_HELPER_URL" \
        || die "Download of c_helper.so failed"

    if [ ! -s "$TMP" ]; then
        die "Downloaded c_helper.so is empty"
    fi

    SIZE=$(wc -c < "$TMP")
    log_ok "Downloaded c_helper.so ($SIZE bytes)"

    mv "$TMP" "$E5M_DIR/c_helper.so"
}

# ─── STEP 3 — CLONE KLIPPER ───
step_clone() {
    log_step "3" "Clone Klipper mainline"

    if [ -d "$KLIPPER_DIR" ]; then
        log_info "Wiping existing $KLIPPER_DIR..."
        rm -rf "$KLIPPER_DIR"
    fi

    log_info "Cloning from $KLIPPER_REPO..."
    log_warn "This takes 2-5 minutes depending on connection"
    p ""

    /opt/bin/git clone "$KLIPPER_REPO" "$KLIPPER_DIR" 2>&1 | \
        grep -E "Receiving|Resolving|Updating|Counting|Compressing" | \
        while read line; do log_action "$line"; done

    if [ ! -f "$KLIPPER_DIR/klippy/klippy.py" ]; then
        die "Clone failed — $KLIPPER_DIR/klippy/klippy.py not found"
    fi

    if [ -n "$KLIPPER_COMMIT" ]; then
        log_info "Checking out pinned commit $KLIPPER_COMMIT..."
        cd "$KLIPPER_DIR" && /opt/bin/git checkout "$KLIPPER_COMMIT" 2>&1 | \
            while read line; do log_action "$line"; done
        cd - >/dev/null
    fi

    HEAD_HASH=$(cd "$KLIPPER_DIR" && /opt/bin/git log -1 --format='%h' 2>/dev/null)
    HEAD_DATE=$(cd "$KLIPPER_DIR" && /opt/bin/git log -1 --format='%ai' 2>/dev/null)
    HEAD_MSG=$(cd "$KLIPPER_DIR" && /opt/bin/git log -1 --format='%s' 2>/dev/null)

    log_ok "Klipper cloned at commit $HEAD_HASH ($HEAD_DATE)"
    log_action "$HEAD_MSG"
}

# ─── STEP 4 — INSTALL c_helper.so INTO KLIPPER ───
step_install_chelper() {
    log_step "4" "Install c_helper.so into Klipper"

    log_info "Copying to $KLIPPER_DIR/klippy/chelper/..."
    cp "$E5M_DIR/c_helper.so" "$KLIPPER_DIR/klippy/chelper/c_helper.so" \
        || die "Failed to copy c_helper.so"
    log_ok "c_helper.so installed"

    # Tell git to ignore this file so Moonraker Update Manager doesn't show
    # the repo as dirty.
    log_info "Adding c_helper.so to .git/info/exclude..."
    EXCLUDE="$KLIPPER_DIR/.git/info/exclude"
    if ! grep -qF "klippy/chelper/c_helper.so" "$EXCLUDE" 2>/dev/null; then
        echo "klippy/chelper/c_helper.so" >> "$EXCLUDE"
        log_action "Added to $EXCLUDE"
    else
        log_action "Already excluded"
    fi
    log_ok "Repo clean for Update Manager"
}

# ─── STEP 5 — PATCH SERVICE ───
step_patch_service() {
    log_step "5" "Patch S55klipper_service to use mainline"

    log_info "Current PY_SCRIPT line:"
    log_action "$(grep '^PY_SCRIPT=' $KLIPPER_SERVICE)"

    log_info "Patching to point at $KLIPPER_DIR/klippy/klippy.py..."
    sed -i "s|PY_SCRIPT=/usr/share/klipper/klippy/klippy.py|PY_SCRIPT=$KLIPPER_DIR/klippy/klippy.py|" \
        "$KLIPPER_SERVICE" || die "sed patch failed"

    log_info "New PY_SCRIPT line:"
    log_action "$(grep '^PY_SCRIPT=' $KLIPPER_SERVICE)"

    # Verify the patch took effect
    if grep -q "PY_SCRIPT=$KLIPPER_DIR/klippy/klippy.py" "$KLIPPER_SERVICE"; then
        log_ok "Service patched successfully"
    else
        die "Patch verification failed (line not found in service)"
    fi
}

# ─── STEP 6 — VERIFY ───
step_verify() {
    log_step "6" "Verify installation"

    p ""
    p "  ${WHITE}Check                     Status${NC}"
    p "  ${GRAY}──────────────────────────────────────────────────────────${NC}"

    # klippy.py
    if [ -f "$KLIPPER_DIR/klippy/klippy.py" ]; then
        p "  ${BR_GREEN}✓${NC} ${WHITE}klippy.py${NC}                ${DIM}$KLIPPER_DIR/klippy/klippy.py${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}klippy.py${NC}                ${BR_RED}MISSING${NC}"
    fi

    # c_helper.so
    if [ -f "$KLIPPER_DIR/klippy/chelper/c_helper.so" ]; then
        SIZE=$(wc -c < "$KLIPPER_DIR/klippy/chelper/c_helper.so")
        p "  ${BR_GREEN}✓${NC} ${WHITE}c_helper.so${NC}              ${DIM}$SIZE bytes${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}c_helper.so${NC}              ${BR_RED}MISSING${NC}"
    fi

    # Service patched
    if grep -q "PY_SCRIPT=$KLIPPER_DIR/klippy/klippy.py" "$KLIPPER_SERVICE"; then
        p "  ${BR_GREEN}✓${NC} ${WHITE}S55klipper_service${NC}       ${DIM}patched (mainline)${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}S55klipper_service${NC}       ${BR_RED}NOT patched${NC}"
    fi

    # Backup
    if [ -f "$E5M_DIR/S55klipper_service.creality.bak" ]; then
        p "  ${BR_GREEN}✓${NC} ${WHITE}Service backup${NC}           ${DIM}$E5M_DIR/S55klipper_service.creality.bak${NC}"
    else
        p "  ${YELLOW}!${NC} ${WHITE}Service backup${NC}           ${YELLOW}MISSING${NC}"
    fi

    # Venv
    if [ -x "$KLIPPER_PY" ]; then
        p "  ${BR_GREEN}✓${NC} ${WHITE}Python venv${NC}              ${DIM}$KLIPPER_VENV ($($KLIPPER_PY --version 2>&1))${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}Python venv${NC}              ${BR_RED}MISSING${NC}"
    fi

    # Klipper commit
    HEAD_HASH=$(cd "$KLIPPER_DIR" && /opt/bin/git log -1 --format='%h' 2>/dev/null || echo "?")
    p "  ${BR_GREEN}✓${NC} ${WHITE}Klipper commit${NC}           ${DIM}$HEAD_HASH${NC}"

    p ""
}

# ─── COMPLETION ───
show_completion() {
    p ""
    p "${BR_RED}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${BG_RED}${WHITE}${BOLD}  ✓  KLIPPER MAINLINE INSTALLER COMPLETE  ${NC}                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}${BOLD}Klipper is installed but NOT started yet.${NC}                    ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Next steps (in order):${NC}                                       ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}1. install_gcode_shellcommand.sh${NC}                              ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}2. install_moonraker.sh${NC}                                       ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}3. install_nginx.sh${NC}                                           ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}4. install_fluidd.sh${NC}                                          ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}5. install_guppyscreen.sh${NC}                                     ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}6. push your .cfg files to printer_data/config/${NC}               ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}7. start klipper:${NC}                                             ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}   /etc/init.d/S55klipper_service start${NC}                       ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Manage Klipper service:${NC}                                      ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}/etc/init.d/S55klipper_service {start|stop|restart}${NC}            ${BR_RED}║${NC}"
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
    step_backup_service
    step_chelper
    step_clone
    step_install_chelper
    step_patch_service
    step_verify
    show_completion
}

main "$@"
