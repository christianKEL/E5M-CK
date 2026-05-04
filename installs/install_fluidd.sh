#!/bin/sh
# ============================================================
# E5M-CK Fluidd Installer
# Download and extract Fluidd UI to /usr/data/fluidd
# (static HTML/JS/CSS — no compilation needed)
# Creality Ender 5 Max — Nebula Pad
# https://github.com/christianKEL/E5M-CK
# ============================================================

# ─── Configuration ─────────────────────────────────────────
# Latest Fluidd release URL (GitHub redirects to the latest tag automatically).
# To pin a specific version, replace 'latest/download' with 'download/v1.34.3' etc.
FLUIDD_URL="https://github.com/fluidd-core/fluidd/releases/latest/download/fluidd.zip"

# ─── Paths ─────────────────────────────────────────────────
FLUIDD_DIR="/usr/data/fluidd"
TMP_DIR="/usr/data/.tmp_install"
TMP_ZIP="$TMP_DIR/fluidd.zip"
NGINX_SERVICE="/etc/init.d/S50nginx"

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
    p "${WHITE}             Fluidd Installer${NC}"
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
    p "  ${WHITE}This installer downloads the latest ${BOLD}Fluidd${NC}${WHITE} release from GitHub${NC}"
    p "  ${WHITE}and extracts it to ${DIM}/usr/data/fluidd${NC}${WHITE} where Nginx (port 4408)${NC}"
    p "  ${WHITE}will serve it.${NC}"
    p ""
    p "  ${WHITE}Fluidd is a pure web UI (HTML/JS/CSS), no Python, no compilation,${NC}"
    p "  ${WHITE}no daemon. Just static files served by Nginx.${NC}"
    p ""
    p "  ${WHITE}It will:${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} download ${DIM}fluidd.zip${NC}${WHITE} (~4-6 MB) from fluidd-core releases${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} extract to ${DIM}/usr/data/fluidd/${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} reload Nginx if it's already running"
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

    log_info "Checking unzip availability..."
    if ! command -v unzip >/dev/null 2>&1; then
        die "unzip not found. Install via: opkg install unzip"
    fi
    log_ok "unzip found"

    log_info "Checking system date..."
    YEAR=$(date +%Y)
    if [ "$YEAR" -lt 2024 ]; then
        die "System date is wrong (year $YEAR). Run: ntpd -d -q -n -p pool.ntp.org"
    fi
    log_ok "System date is sane"

    log_info "Checking free disk space in /usr/data..."
    FREE_MB=$(df -m /usr/data | awk 'NR==2 {print $4}')
    log_info "Free space: ${FREE_MB} MB"
    if [ "$FREE_MB" -lt 30 ]; then
        die "Less than 30 MB free in /usr/data — Fluidd needs ~20 MB"
    fi
    log_ok "Enough disk space"

    log_info "Checking Nginx installation..."
    if [ ! -x "$NGINX_SERVICE" ]; then
        log_warn "Nginx service not found — install_nginx.sh recommended"
    else
        log_ok "Nginx service found"
    fi

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
    p "  ${WHITE}Source       :${NC} ${DIM}$FLUIDD_URL${NC}"
    p "  ${WHITE}Install dir  :${NC} ${DIM}$FLUIDD_DIR${NC}"
    p "  ${WHITE}Served by    :${NC} ${DIM}Nginx on http://<ip>:4408/${NC}"
    p ""
    if [ -d "$FLUIDD_DIR" ]; then
        EXISTING_SIZE=$(du -sh "$FLUIDD_DIR" 2>/dev/null | awk '{print $1}')
        p "  ${YELLOW}!  Existing $FLUIDD_DIR will be WIPED ($EXISTING_SIZE).${NC}"
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

# ─── STEP 1 — DOWNLOAD ───
step_download() {
    log_step "1" "Download Fluidd"

    log_info "Preparing temp dir on disk (not RAM)..."
    mkdir -p "$TMP_DIR" || die "Cannot create $TMP_DIR"
    log_action "$TMP_DIR"

    log_info "Removing previous temp file (if any)..."
    rm -f "$TMP_ZIP"

    log_info "Fetching Fluidd from GitHub Releases..."
    log_action "$FLUIDD_URL"

    # GitHub Releases redirects to a CDN, --no-check-certificate handles
    # any cert oddities on Buildroot. -L follows redirects.
    wget --no-check-certificate -O "$TMP_ZIP" "$FLUIDD_URL" 2>&1 | \
        grep -E "%|saved|Resolving|connecting" | tail -5 | \
        while read line; do log_action "$line"; done

    if [ ! -s "$TMP_ZIP" ]; then
        die "Downloaded file is empty"
    fi

    SIZE=$(wc -c < "$TMP_ZIP")
    log_info "Downloaded size: $SIZE bytes"

    # Sanity: real Fluidd zip is at least 1 MB
    if [ "$SIZE" -lt 1000000 ]; then
        log_error "Archive too small (got $SIZE bytes) — likely a 404 page"
        rm -f "$TMP_ZIP"
        die "Aborting"
    fi

    log_ok "Fluidd archive downloaded ($SIZE bytes)"
}

# ─── STEP 2 — VALIDATE ZIP ───
step_validate() {
    log_step "2" "Validate archive"

    # BusyBox unzip doesn't support -t (test mode), so we use -l (list)
    # which fails with non-zero exit if the zip is corrupt or unreadable.
    log_info "Testing zip integrity..."
    if ! unzip -l "$TMP_ZIP" >/dev/null 2>&1; then
        log_error "Archive is corrupt or not a valid zip"
        rm -f "$TMP_ZIP"
        die "Aborting"
    fi
    log_ok "Archive is a valid zip"

    log_info "Checking expected entries..."
    # Fluidd archive must contain at least index.html at the root
    if ! unzip -l "$TMP_ZIP" 2>/dev/null | grep -qE "[[:space:]]index\.html$"; then
        log_error "index.html not found at archive root"
        rm -f "$TMP_ZIP"
        die "Archive structure unexpected — Fluidd release format may have changed"
    fi
    log_action "index.html found in archive"
    log_ok "Archive structure validated"
}

# ─── STEP 3 — EXTRACT ───
step_extract() {
    log_step "3" "Extract Fluidd to $FLUIDD_DIR"

    if [ -d "$FLUIDD_DIR" ]; then
        log_info "Wiping existing $FLUIDD_DIR..."
        rm -rf "$FLUIDD_DIR"
    fi

    log_info "Creating $FLUIDD_DIR..."
    mkdir -p "$FLUIDD_DIR" || die "Cannot create $FLUIDD_DIR"

    log_info "Extracting (~5-10 sec)..."
    # BusyBox unzip is slightly chatty, we filter to keep output readable
    unzip -o "$TMP_ZIP" -d "$FLUIDD_DIR" 2>&1 | \
        grep -cE "^[[:space:]]*(inflating|extracting|creating)" | \
        while read count; do log_action "$count files extracted"; done

    log_info "Removing temp archive..."
    rm -f "$TMP_ZIP"
    rmdir "$TMP_DIR" 2>/dev/null || true

    if [ ! -f "$FLUIDD_DIR/index.html" ]; then
        die "index.html not found at $FLUIDD_DIR after extraction"
    fi

    INDEX_SIZE=$(wc -c < "$FLUIDD_DIR/index.html")
    TOTAL_SIZE=$(du -sh "$FLUIDD_DIR" | awk '{print $1}')
    log_ok "Extracted ($TOTAL_SIZE, index.html: $INDEX_SIZE bytes)"
}

# ─── STEP 4 — RELOAD NGINX (if running) ───
step_nginx_reload() {
    log_step "4" "Reload Nginx (if running)"

    if [ ! -x "$NGINX_SERVICE" ]; then
        log_info "Nginx service not present — skipping reload"
        return 0
    fi

    log_info "Checking Nginx status..."
    if "$NGINX_SERVICE" status 2>/dev/null | grep -q "running"; then
        log_info "Nginx is running — sending reload signal..."
        "$NGINX_SERVICE" reload 2>&1 | while read line; do log_action "$line"; done
        log_ok "Nginx reloaded — Fluidd is live now on :4408"
    else
        log_info "Nginx is not running — start it with:"
        log_action "$NGINX_SERVICE start"
    fi
}

# ─── STEP 5 — VERIFY ───
step_verify() {
    log_step "5" "Verify installation"

    p ""
    p "  ${WHITE}Check                          Status${NC}"
    p "  ${GRAY}──────────────────────────────────────────────────────────${NC}"

    # index.html
    if [ -f "$FLUIDD_DIR/index.html" ]; then
        SIZE=$(wc -c < "$FLUIDD_DIR/index.html")
        p "  ${BR_GREEN}✓${NC} ${WHITE}index.html${NC}                    ${DIM}$SIZE bytes${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}index.html${NC}                    ${BR_RED}MISSING${NC}"
    fi

    # Total size
    if [ -d "$FLUIDD_DIR" ]; then
        TOTAL=$(du -sh "$FLUIDD_DIR" 2>/dev/null | awk '{print $1}')
        FILE_COUNT=$(find "$FLUIDD_DIR" -type f 2>/dev/null | wc -l)
        p "  ${BR_GREEN}✓${NC} ${WHITE}Total content${NC}                 ${DIM}$TOTAL ($FILE_COUNT files)${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}Total content${NC}                 ${BR_RED}MISSING${NC}"
    fi

    # Critical assets directory
    if [ -d "$FLUIDD_DIR/assets" ] || [ -d "$FLUIDD_DIR/css" ] || [ -d "$FLUIDD_DIR/js" ]; then
        p "  ${BR_GREEN}✓${NC} ${WHITE}Assets${NC}                        ${DIM}static resources present${NC}"
    else
        p "  ${YELLOW}!${NC} ${WHITE}Assets${NC}                        ${YELLOW}no assets/css/js dir found${NC}"
    fi

    # Nginx ready to serve?
    if [ -x "$NGINX_SERVICE" ]; then
        if "$NGINX_SERVICE" status 2>/dev/null | grep -q "running"; then
            p "  ${BR_GREEN}✓${NC} ${WHITE}Nginx${NC}                         ${DIM}running, Fluidd live on :4408${NC}"
        else
            p "  ${YELLOW}!${NC} ${WHITE}Nginx${NC}                         ${YELLOW}not running, start it to serve Fluidd${NC}"
        fi
    else
        p "  ${YELLOW}!${NC} ${WHITE}Nginx${NC}                         ${YELLOW}not installed${NC}"
    fi

    p ""
}

# ─── COMPLETION ───
show_completion() {
    p ""
    p "${BR_RED}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${BG_RED}${WHITE}${BOLD}  ✓  FLUIDD INSTALLER COMPLETE  ${NC}                            ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Fluidd is installed at ${DIM}/usr/data/fluidd${NC}                       ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}${BOLD}Once Klipper + Moonraker + Nginx are running:${NC}               ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}http://<your-printer-ip>:4408/${NC}                                ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}${BOLD}Next steps:${NC}                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}1. install_guppyscreen.sh (touch UI on the printer)${NC}            ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}2. push your .cfg files to printer_data/config/${NC}               ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}3. start the stack:${NC}                                            ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}   /etc/init.d/S55klipper_service start${NC}                       ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}   /etc/init.d/S56moonraker_service start${NC}                     ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}   /etc/init.d/S50nginx start${NC}                                 ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Fluidd auto-updates via Moonraker Update Manager${NC}                ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}(already configured in your moonraker.conf)${NC}                    ${BR_RED}║${NC}"
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
    step_download
    step_validate
    step_extract
    step_nginx_reload
    step_verify
    show_completion
}

main "$@"
