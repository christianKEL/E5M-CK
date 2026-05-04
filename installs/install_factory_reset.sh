#!/bin/sh
# ============================================================
# E5M-CK Factory Reset Installer
# Deploy /etc/init.d/S58factoryreset on the Nebula Pad
# Creality Ender 5 Max — Nebula Pad
# https://github.com/christianKEL/E5M-CK
# ============================================================

GITHUB_RAW="https://raw.githubusercontent.com/christianKEL/E5M-CK/main"
S58_URL="$GITHUB_RAW/files/S58factoryreset"
S58_TARGET="/etc/init.d/S58factoryreset"
S58_TMP="/tmp/S58factoryreset.new"
EXPECTED_MD5="4902ede5c58470748adb7e107cab8702"
EXPECTED_SIZE="2084"

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
    p "${WHITE}             Factory Reset Installer${NC}"
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
    p "  ${WHITE}This installer deploys the Helper-Script (Guilouz) S58factoryreset${NC}"
    p "  ${WHITE}to /etc/init.d/ on your Nebula Pad. Once installed, you can wipe${NC}"
    p "  ${WHITE}the printer back to factory state at any time using:${NC}"
    p ""
    p "  ${WHITE}  ${BR_RED}>${NC} ${WHITE}SSH       :${NC} /etc/init.d/S58factoryreset reset"
    p "  ${WHITE}  ${BR_RED}>${NC} ${WHITE}USB stick :${NC} empty file 'factory_reset' at root of FAT32"
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

# ─── CONFIRMATION ───
confirm_install() {
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${WHITE}${BOLD}READY TO INSTALL${NC}                                                ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}Source     :${NC} ${DIM}$S58_URL${NC}"
    p "  ${WHITE}Target     :${NC} ${DIM}$S58_TARGET${NC}"
    p "  ${WHITE}MD5        :${NC} ${DIM}$EXPECTED_MD5${NC}"
    p "  ${WHITE}Size       :${NC} ${DIM}$EXPECTED_SIZE bytes${NC}"
    p ""
    if [ -f "$S58_TARGET" ]; then
        p "  ${YELLOW}!  An existing $S58_TARGET will be replaced.${NC}"
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
    log_step "1" "Download S58factoryreset"

    log_info "Removing previous temp file (if any)..."
    rm -f "$S58_TMP"

    log_info "Fetching from GitHub..."
    log_action "$S58_URL"

    wget --no-check-certificate -q -O "$S58_TMP" "$S58_URL" \
        || die "Download failed (no internet? GitHub down?)"

    if [ ! -s "$S58_TMP" ]; then
        die "Downloaded file is empty"
    fi

    log_ok "Downloaded to $S58_TMP"
}

# ─── STEP 2 — VERIFY INTEGRITY ───
step_verify() {
    log_step "2" "Verify integrity"

    ACTUAL_MD5=$(md5sum "$S58_TMP" | awk '{print $1}')
    ACTUAL_SIZE=$(wc -c < "$S58_TMP")

    log_info "MD5  : $ACTUAL_MD5"
    log_info "Size : $ACTUAL_SIZE bytes"

    if [ "$ACTUAL_MD5" != "$EXPECTED_MD5" ]; then
        log_error "MD5 mismatch (expected $EXPECTED_MD5)"
        log_error "Likely cause: git converted LF -> CRLF on push."
        log_error "Fix: add a .gitattributes with 'files/S58factoryreset text eol=lf'"
        rm -f "$S58_TMP"
        die "Aborting before touching system files"
    fi

    if [ "$ACTUAL_SIZE" != "$EXPECTED_SIZE" ]; then
        log_error "Size mismatch (expected $EXPECTED_SIZE bytes)"
        rm -f "$S58_TMP"
        die "Aborting before touching system files"
    fi

    log_ok "Integrity verified"
}

# ─── STEP 3 — INSTALL ───
step_install() {
    log_step "3" "Install /etc/init.d/S58factoryreset"

    if [ -f "$S58_TARGET" ]; then
        log_info "Removing existing $S58_TARGET..."
        rm -f "$S58_TARGET"
    fi

    log_info "Moving new file into place..."
    mv "$S58_TMP" "$S58_TARGET" || die "Failed to move file to $S58_TARGET"

    log_info "Setting permissions (chmod 755)..."
    chmod 755 "$S58_TARGET" || die "chmod failed"

    log_ok "Deployed: $S58_TARGET"
}

# ─── STEP 4 — TEST ───
step_test() {
    log_step "4" "Sanity check (no reset triggered)"

    log_info "Calling script without arguments to verify Usage output..."
    OUTPUT=$("$S58_TARGET" 2>&1 || true)
    log_action "$OUTPUT"

    case "$OUTPUT" in
        *Usage*) log_ok "Script responds correctly" ;;
        *)       log_warn "Unexpected output — manual verification recommended" ;;
    esac
}

# ─── COMPLETION ───
show_completion() {
    p ""
    p "${BR_RED}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${BG_RED}${WHITE}${BOLD}  ✓  FACTORY RESET INSTALLER COMPLETE  ${NC}                     ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}You can now wipe the printer at any time using:${NC}               ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}${BOLD}From SSH:${NC}                                                    ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}/etc/init.d/S58factoryreset reset${NC}                             ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}${BOLD}From USB stick (FAT32):${NC}                                      ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}empty file named 'factory_reset' at root,${NC}                     ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}plug into printer, power cycle, wait 2-3 minutes${NC}              ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${YELLOW}!  Either method TRIGGERS A FULL WIPE — be sure!${NC}              ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ╚══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
}

# ─── MAIN ───
main() {
    show_banner
    show_disclaimer
    show_banner
    confirm_install
    step_download
    step_verify
    step_install
    step_test
    show_completion
}

main "$@"
