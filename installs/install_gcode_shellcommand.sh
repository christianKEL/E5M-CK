#!/bin/sh
# ============================================================
# E5M-CK Klipper Gcode Shell Command Installer
# Install gcode_shell_command.py extension into Klipper mainline
# Creality Ender 5 Max — Nebula Pad
# https://github.com/christianKEL/E5M-CK
# ============================================================

GITHUB_RAW="https://raw.githubusercontent.com/christianKEL/E5M-CK/main"
SHELL_CMD_URL="$GITHUB_RAW/files/gcode_shell_command.py"
EXPECTED_MD5="eb67142f91af7e750cec3db294943926"
EXPECTED_SIZE="3266"

KLIPPER_DIR="/usr/data/klipper"
TARGET_FILE="$KLIPPER_DIR/klippy/extras/gcode_shell_command.py"
TMP_FILE="/tmp/gcode_shell_command.py.new"

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
    p "${WHITE}             Klipper Gcode Shell Command Installer${NC}"
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
    p "  ${WHITE}This installer adds the ${BOLD}gcode_shell_command${NC}${WHITE} extension to your${NC}"
    p "  ${WHITE}Klipper mainline. It allows running linux shell commands from G-code${NC}"
    p "  ${WHITE}macros, e.g.:${NC}"
    p ""
    p "  ${DIM}    [gcode_shell_command my_cmd]${NC}"
    p "  ${DIM}    command: /usr/bin/my_script.sh${NC}"
    p "  ${DIM}    timeout: 5${NC}"
    p "  ${DIM}    verbose: True${NC}"
    p ""
    p "  ${WHITE}This module is not part of mainline Klipper but is widely used by${NC}"
    p "  ${WHITE}KIAUH, GuppyScreen, Helper-Script, etc. Source: Eric Callahan, 2019.${NC}"
    p ""
    p "  ${YELLOW}!${NC}  ${WHITE}This extension may have a high potential for abuse if not used${NC}"
    p "     ${WHITE}carefully. Use at your own risk.${NC}"
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
    if [ ! -d "$KLIPPER_DIR" ]; then
        die "Klipper not found at $KLIPPER_DIR. Run install_klipper.sh first."
    fi
    if [ ! -d "$KLIPPER_DIR/klippy/extras" ]; then
        die "Klipper extras dir missing: $KLIPPER_DIR/klippy/extras"
    fi
    log_ok "Klipper installation found"

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
    p "  ${WHITE}Source     :${NC} ${DIM}$SHELL_CMD_URL${NC}"
    p "  ${WHITE}Target     :${NC} ${DIM}$TARGET_FILE${NC}"
    p "  ${WHITE}MD5        :${NC} ${DIM}$EXPECTED_MD5${NC}"
    p "  ${WHITE}Size       :${NC} ${DIM}$EXPECTED_SIZE bytes${NC}"
    p ""
    if [ -f "$TARGET_FILE" ]; then
        p "  ${YELLOW}!  An existing $TARGET_FILE will be replaced.${NC}"
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
    log_step "1" "Download gcode_shell_command.py"

    log_info "Removing previous temp file (if any)..."
    rm -f "$TMP_FILE"

    log_info "Fetching from GitHub..."
    log_action "$SHELL_CMD_URL"

    wget --no-check-certificate -q -O "$TMP_FILE" "$SHELL_CMD_URL" \
        || die "Download failed (no internet? GitHub down?)"

    if [ ! -s "$TMP_FILE" ]; then
        die "Downloaded file is empty"
    fi

    log_ok "Downloaded to $TMP_FILE"
}

# ─── STEP 2 — VERIFY INTEGRITY ───
step_verify() {
    log_step "2" "Verify integrity"

    ACTUAL_MD5=$(md5sum "$TMP_FILE" | awk '{print $1}')
    ACTUAL_SIZE=$(wc -c < "$TMP_FILE")

    log_info "MD5  : $ACTUAL_MD5"
    log_info "Size : $ACTUAL_SIZE bytes"

    if [ "$ACTUAL_MD5" != "$EXPECTED_MD5" ]; then
        log_error "MD5 mismatch (expected $EXPECTED_MD5)"
        log_error "Likely cause: git converted LF -> CRLF on push."
        log_error "Fix: add .gitattributes with 'files/gcode_shell_command.py text eol=lf'"
        rm -f "$TMP_FILE"
        die "Aborting before touching Klipper"
    fi

    if [ "$ACTUAL_SIZE" != "$EXPECTED_SIZE" ]; then
        log_error "Size mismatch (expected $EXPECTED_SIZE bytes)"
        rm -f "$TMP_FILE"
        die "Aborting before touching Klipper"
    fi

    log_ok "Integrity verified"
}

# ─── STEP 3 — INSTALL ───
step_install() {
    log_step "3" "Install gcode_shell_command.py into Klipper"

    if [ -f "$TARGET_FILE" ]; then
        log_info "Removing existing $TARGET_FILE..."
        rm -f "$TARGET_FILE"
    fi

    log_info "Moving new file into place..."
    mv "$TMP_FILE" "$TARGET_FILE" || die "Failed to move file to $TARGET_FILE"

    log_info "Setting permissions (chmod 644)..."
    chmod 644 "$TARGET_FILE" || die "chmod failed"

    log_ok "Deployed: $TARGET_FILE"
}

# ─── STEP 4 — UPDATE GIT EXCLUDE ───
step_git_exclude() {
    log_step "4" "Add to .git/info/exclude (clean Update Manager)"

    EXCLUDE="$KLIPPER_DIR/.git/info/exclude"

    if [ ! -f "$EXCLUDE" ]; then
        log_warn "$EXCLUDE not found — Klipper repo may not be a git clone"
        log_warn "Skipping exclude step (no harm done)"
        return 0
    fi

    log_info "Checking $EXCLUDE..."
    if grep -qF "klippy/extras/gcode_shell_command.py" "$EXCLUDE" 2>/dev/null; then
        log_action "Already excluded"
    else
        echo "klippy/extras/gcode_shell_command.py" >> "$EXCLUDE"
        log_action "Added: klippy/extras/gcode_shell_command.py"
    fi
    log_ok "Klipper repo clean for Update Manager"
}

# ─── STEP 5 — VERIFY ───
step_final_verify() {
    log_step "5" "Verify installation"

    p ""
    p "  ${WHITE}Check                          Status${NC}"
    p "  ${GRAY}──────────────────────────────────────────────────────────${NC}"

    # File exists
    if [ -f "$TARGET_FILE" ]; then
        FSIZE=$(wc -c < "$TARGET_FILE")
        FMD5=$(md5sum "$TARGET_FILE" | awk '{print $1}')
        p "  ${BR_GREEN}✓${NC} ${WHITE}gcode_shell_command.py${NC}        ${DIM}$FSIZE bytes${NC}"
        p "  ${BR_GREEN}✓${NC} ${WHITE}MD5 matches expected${NC}          ${DIM}$FMD5${NC}"
    else
        p "  ${BR_RED}✗${NC} ${WHITE}gcode_shell_command.py${NC}        ${BR_RED}MISSING${NC}"
    fi

    # Git exclude
    EXCLUDE="$KLIPPER_DIR/.git/info/exclude"
    if [ -f "$EXCLUDE" ] && grep -qF "klippy/extras/gcode_shell_command.py" "$EXCLUDE"; then
        p "  ${BR_GREEN}✓${NC} ${WHITE}.git/info/exclude${NC}             ${DIM}entry present${NC}"
    else
        p "  ${YELLOW}!${NC} ${WHITE}.git/info/exclude${NC}             ${YELLOW}entry NOT present${NC}"
    fi

    # Klipper dirty status (just informative)
    cd "$KLIPPER_DIR"
    DIRTY=$(/opt/bin/git status --porcelain 2>/dev/null | wc -l)
    cd - >/dev/null
    if [ "$DIRTY" -eq 0 ]; then
        p "  ${BR_GREEN}✓${NC} ${WHITE}Klipper repo status${NC}            ${DIM}clean${NC}"
    else
        p "  ${YELLOW}!${NC} ${WHITE}Klipper repo status${NC}            ${YELLOW}$DIRTY untracked/modified file(s)${NC}"
    fi

    p ""
}

# ─── COMPLETION ───
show_completion() {
    p ""
    p "${BR_RED}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${BG_RED}${WHITE}${BOLD}  ✓  GCODE SHELL COMMAND INSTALLED  ${NC}                        ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}You can now use ${BOLD}[gcode_shell_command]${NC}${WHITE} in your configs.${NC}        ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}${BOLD}Example:${NC}                                                     ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}[gcode_shell_command backup_config]${NC}                            ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}command: /usr/data/scripts/backup.sh${NC}                           ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}timeout: 30${NC}                                                    ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}verbose: True${NC}                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}[gcode_macro DO_BACKUP]${NC}                                        ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}gcode:${NC}                                                         ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}    RUN_SHELL_COMMAND CMD=backup_config${NC}                        ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${YELLOW}!${NC} ${WHITE}Klipper must be restarted for the extension to load.${NC}      ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}(not done by this script — Klipper is not running yet)${NC}        ${BR_RED}║${NC}"
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
    step_verify
    step_install
    step_git_exclude
    step_final_verify
    show_completion
}

main "$@"
