#!/bin/sh
# ============================================================
# install_klipper_mainline_E5M-CK.sh
# Klipper Mainline installation only — E5M-CK project
# Creality Ender 5 Max — Nebula Pad
# https://github.com/christianKEL/E5M-CK
#
# Isolated from install.sh (step5_install_klipper, minimal subset).
# Installs Klipper mainline into /usr/klipper_mainline_e5m-ck.
# No tracked file is modified -> repo stays non-dirty.
# ============================================================

GITHUB_RAW="https://raw.githubusercontent.com/christianKEL/E5M-CK/main"
E5M_DIR="/usr/data/E5M_CK"
KLIPPER_DIR="/usr/klipper_mainline_e5m-ck"
KLIPPER_SERVICE="/etc/init.d/S55klipper_service"

# ─── ANSI COLORS ───
RED='\033[0;31m'
BR_RED='\033[1;31m'
BG_RED='\033[41m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'
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

log_step() {
    STEP_NUM=$1
    STEP_TITLE=$2
    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} STEP $STEP_NUM ${NC}  ${WHITE}${BOLD}$STEP_TITLE${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
}

die() { log_error "$1"; exit 1; }


# ─── PREREQUISITES CHECK ───
check_prerequisites() {
    log_step "0" "Prerequisites check"

    # Root check
    if [ "$(id -u)" -ne 0 ]; then
        die "This script must be run as root"
    fi
    log_ok "Running as root"

    # Internet check
    log_info "Checking internet connection (github.com)..."
    if ! wget -q --spider --timeout=10 https://github.com 2>/dev/null; then
        die "No internet connection — cannot reach github.com"
    fi
    log_ok "Internet connection OK"
}


# ─── INSTALL KLIPPER MAINLINE ───
install_klipper_mainline() {
    log_step "1" "Installing Klipper mainline into $KLIPPER_DIR"

    mkdir -p $E5M_DIR
    log_info "Backing up Creality Klipper service..."
    cp $KLIPPER_SERVICE $E5M_DIR/S55klipper_service.creality.bak
    log_action "Backup: $E5M_DIR/S55klipper_service.creality.bak"

    log_info "Downloading ${BOLD}c_helper.so${NC} (MIPS XBurst2 with nan2008)..."
    wget --no-check-certificate -q \
        "$GITHUB_RAW/c_helper.so" \
        -O $E5M_DIR/c_helper.so
    [ ! -s $E5M_DIR/c_helper.so ] && die "Failed to download c_helper.so"
    log_ok "c_helper.so downloaded ($(du -h $E5M_DIR/c_helper.so | cut -f1))"

    log_info "Cloning Klipper mainline from github.com/Klipper3d/klipper..."
    log_warn "This will take 2-5 minutes depending on your connection"
    git clone https://github.com/Klipper3d/klipper.git $KLIPPER_DIR 2>&1 | \
        grep -E "Receiving|Resolving|Updating" | while read line; do log_action "$line"; done
    [ ! -d $KLIPPER_DIR/klippy ] && die "Failed to clone Klipper"

    KLIPPER_VER=$(cd $KLIPPER_DIR && git log -1 --format="%h" 2>/dev/null)
    log_ok "Klipper mainline cloned (commit: ${BOLD}$KLIPPER_VER${NC})"

    log_info "Installing c_helper.so into Klipper..."
    cp $E5M_DIR/c_helper.so $KLIPPER_DIR/klippy/chelper/c_helper.so
    log_action "c_helper.so -> $KLIPPER_DIR/klippy/chelper/"

    log_info "Updating Klipper service to use mainline..."
    sed -i "s|PY_SCRIPT=/usr/share/klipper/klippy/klippy.py|PY_SCRIPT=$KLIPPER_DIR/klippy/klippy.py|" \
        $KLIPPER_SERVICE
    log_action "Service updated: $KLIPPER_SERVICE"
    log_ok "Klipper mainline installation complete"
}


# ─── MAIN ───
main() {
    p ""
    p "${BR_RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}║${NC}  ${BG_RED}${WHITE}${BOLD}  KLIPPER MAINLINE — E5M-CK INSTALLER  ${NC}                       ${BR_RED}║${NC}"
    p "${BR_RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
    p "  ${WHITE}Target directory: ${BOLD}$KLIPPER_DIR${NC}"
    p ""

    check_prerequisites
    install_klipper_mainline

    p ""
    log_ok "${BOLD}Klipper mainline installed in $KLIPPER_DIR${NC}"
    p ""
}

main "$@"
