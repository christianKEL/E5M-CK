#!/bin/sh
# ============================================================
# E5M-CK Entware Installer
# Install Entware (opkg) + base packages on the Nebula Pad
# Creality Ender 5 Max — Nebula Pad
# https://github.com/christianKEL/E5M-CK
# ============================================================

GITHUB_RAW="https://raw.githubusercontent.com/christianKEL/E5M-CK/main"
ENTWARE_ARCH="armv7sf-k3.2"
ENTWARE_URL="http://bin.entware.net/${ENTWARE_ARCH}/installer/generic.sh"

# Paquets de base (option B confirmée)
BASE_PACKAGES="\
ca-certificates ca-bundle \
wget-ssl curl \
python3 python3-pip python3-virtualenv python3-dev \
git git-http \
nginx \
jq \
libffi libsodium libsodium-dev libssl \
gcc make \
nano htop"

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
    p "${WHITE}             Entware Installer${NC}"
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
    p "  ${WHITE}This installer deploys ${BOLD}Entware${NC}${WHITE} (opkg package manager) on your${NC}"
    p "  ${WHITE}Nebula Pad, plus a set of base packages required by the rest of${NC}"
    p "  ${WHITE}the E5M-CK toolchain (Klipper, Moonraker, Nginx, Fluidd...).${NC}"
    p ""
    p "  ${WHITE}Installation directory : ${DIM}/opt${NC}"
    p "  ${WHITE}PATH update            : ${DIM}/etc/profile${NC}"
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

    # Architecture
    ARCH=$(uname -m)
    log_info "Detected architecture: $ARCH"
    if [ "$ARCH" != "armv7l" ]; then
        log_warn "Expected armv7l, got '$ARCH'"
        log_warn "The hardcoded Entware URL may not match your SoC."
        log_warn "Edit ENTWARE_ARCH in this script if installation fails."
    else
        log_ok "Architecture matches Entware URL ($ENTWARE_ARCH)"
    fi

    # Date
    YEAR=$(date +%Y)
    log_info "System date: $(date '+%Y-%m-%d %H:%M:%S')"
    if [ "$YEAR" -lt 2024 ]; then
        log_error "System date is in the past (year $YEAR)"
        log_error "This will break HTTPS and git operations."
        log_error "Run: ntpd -d -q -n -p pool.ntp.org"
        log_error "Or:  date -s 'YYYY-MM-DD HH:MM:SS'"
        die "Aborting until system date is correct"
    fi
    log_ok "System date looks sane"

    # Internet
    log_info "Checking internet connectivity..."
    if ! ping -c 1 -W 3 bin.entware.net >/dev/null 2>&1; then
        log_warn "Cannot ping bin.entware.net (firewall? offline?)"
        log_warn "Will try anyway, wget may still work."
    else
        log_ok "bin.entware.net is reachable"
    fi
}

# ─── CONFIRMATION ───
confirm_install() {
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${WHITE}${BOLD}READY TO INSTALL${NC}                                                ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}Entware URL  :${NC} ${DIM}$ENTWARE_URL${NC}"
    p "  ${WHITE}Install dir  :${NC} ${DIM}/opt${NC}"
    p "  ${WHITE}Architecture :${NC} ${DIM}$ENTWARE_ARCH${NC}"
    p ""
    p "  ${WHITE}Base packages to install:${NC}"
    p "  ${DIM}    $BASE_PACKAGES${NC}"
    p ""
    if [ -d /opt ] && [ -x /opt/bin/opkg ]; then
        p "  ${YELLOW}!  Entware is already installed.${NC}"
        p "  ${YELLOW}!  /opt/ will be COMPLETELY WIPED and reinstalled.${NC}"
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

# ─── STEP 1 — WIPE EXISTING ───
step_wipe() {
    log_step "1" "Wipe existing Entware (if any)"

    if [ -d /opt ] && [ -x /opt/bin/opkg ]; then
        log_info "Existing Entware detected — wiping..."
        log_action "rm -rf /opt"
        rm -rf /opt
        sync
        log_ok "Previous Entware removed"
    else
        log_info "No existing Entware — clean slate"
    fi

    # Always create /opt for the installer
    mkdir -p /opt
}

# ─── STEP 2 — INSTALL ENTWARE ───
step_entware() {
    log_step "2" "Install Entware"

    log_info "Downloading and running official Entware installer..."
    log_action "$ENTWARE_URL"

    wget --no-check-certificate -O - "$ENTWARE_URL" | sh \
        || die "Entware installer failed"

    if [ ! -x /opt/bin/opkg ]; then
        die "Entware installation completed but /opt/bin/opkg is missing"
    fi

    log_ok "Entware installed successfully"
}

# ─── STEP 3 — UPDATE PATH ───
step_path() {
    log_step "3" "Configure PATH"

    PATH_LINE='export PATH=/opt/bin:/opt/sbin:$PATH'

    log_info "Adding Entware to current session PATH..."
    export PATH=/opt/bin:/opt/sbin:$PATH
    log_ok "Current shell PATH updated"

    log_info "Persisting PATH update in /etc/profile..."
    if grep -qF "/opt/bin:/opt/sbin" /etc/profile 2>/dev/null; then
        log_info "/etc/profile already contains the PATH line — skipping"
    else
        echo "" >> /etc/profile
        echo "# E5M-CK: Entware PATH" >> /etc/profile
        echo "$PATH_LINE" >> /etc/profile
        log_ok "Added to /etc/profile"
    fi
}

# ─── STEP 4 — UPDATE PACKAGE LIST ───
step_update() {
    log_step "4" "Update package lists (opkg update)"

    /opt/bin/opkg update 2>&1 | while read line; do
        log_action "$line"
    done

    log_ok "Package lists updated"
}

# ─── STEP 5 — INSTALL BASE PACKAGES ───
step_packages() {
    log_step "5" "Install base packages"

    log_info "Installing required packages for E5M-CK toolchain..."
    p ""

    # On lance opkg install en pipe pour logger chaque ligne, mais on capture
    # le code de sortie via un fichier temporaire (pipefail not always available).
    EC_FILE=/tmp/.opkg_ec
    ( /opt/bin/opkg install $BASE_PACKAGES 2>&1; echo $? > $EC_FILE ) | \
        while read line; do
            case "$line" in
                Installing*|Configuring*|Downloading*) log_action "$line" ;;
                *already*install*) log_action "$line" ;;
                *Collected*errors*) log_warn "$line" ;;
                *)                 log_action "$line" ;;
            esac
        done

    EC=$(cat $EC_FILE 2>/dev/null || echo "1")
    rm -f $EC_FILE

    if [ "$EC" != "0" ]; then
        log_warn "opkg returned non-zero exit code ($EC)"
        log_warn "Some packages may have failed — check messages above"
    else
        log_ok "All base packages installed"
    fi
}

# ─── STEP 6 — VERIFY ───
step_verify() {
    log_step "6" "Verify installation"

    p ""
    p "  ${WHITE}Tool         Status${NC}"
    p "  ${GRAY}─────────────────────────────────────────────${NC}"

    for tool in opkg python3 pip3 git nginx wget curl jq nano htop; do
        TOOL_PATH=$(command -v $tool 2>/dev/null)
        if [ -n "$TOOL_PATH" ]; then
            VERSION=""
            case "$tool" in
                python3) VERSION=$($tool --version 2>&1 | head -1) ;;
                git)     VERSION=$($tool --version 2>&1 | head -1) ;;
                nginx)   VERSION=$($tool -v 2>&1 | head -1) ;;
                pip3)    VERSION=$($tool --version 2>&1 | head -1 | awk '{print $1, $2}') ;;
            esac
            p "  ${BR_GREEN}✓${NC} ${WHITE}$tool${NC}    ${DIM}$TOOL_PATH${NC}    ${GRAY}$VERSION${NC}"
        else
            p "  ${BR_RED}✗${NC} ${WHITE}$tool${NC}    ${BR_RED}NOT FOUND${NC}"
        fi
    done

    p ""
}

# ─── COMPLETION ───
show_completion() {
    p ""
    p "${BR_RED}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${BG_RED}${WHITE}${BOLD}  ✓  ENTWARE INSTALLER COMPLETE  ${NC}                           ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Entware is now installed at /opt/${NC}                            ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}All base packages required for the next installers${NC}           ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}(Klipper, Moonraker, Nginx, Fluidd...) are ready.${NC}            ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}${BOLD}Common opkg commands:${NC}                                        ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}opkg update           # refresh package index${NC}                ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}opkg upgrade          # upgrade all installed pkgs${NC}            ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}opkg install <pkg>    # install a package${NC}                     ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}opkg list-installed   # list what's installed${NC}                 ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ╚══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
}

# ─── REBOOT PROMPT ───
ask_reboot() {
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${WHITE}${BOLD}REBOOT RECOMMENDED${NC}                                              ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}A reboot is recommended to ensure Entware services start cleanly${NC}"
    p "  ${WHITE}and the new PATH is loaded for all sessions.${NC}"
    p ""
    p "  ${YELLOW}!${NC}  ${WHITE}If you plan to install Klipper/Moonraker/etc. right after,${NC}"
    p "     ${WHITE}you can skip the reboot for now and reboot at the end.${NC}"
    p ""
    printf "  ${WHITE}Reboot now? [y/N]: ${NC}"
    read REBOOT_ANS
    case "$REBOOT_ANS" in
        y|Y|yes|YES)
            p ""
            log_info "Rebooting in 3 seconds..."
            sleep 3
            reboot
            ;;
        *)
            p ""
            log_info "Skipping reboot (do it manually later if needed)"
            ;;
    esac
}

# ─── MAIN ───
main() {
    show_banner
    show_disclaimer
    show_banner
    step_precheck
    confirm_install
    step_wipe
    step_entware
    step_path
    step_update
    step_packages
    step_verify
    show_completion
    ask_reboot
}

main "$@"
