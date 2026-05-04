#!/bin/sh
# ============================================================
# E5M-CK Klipper Configs Installer
# Auto-discover and deploy all .cfg files from configs/cfg/
# on the E5M-CK repo to /usr/data/printer_data/config/
# Creality Ender 5 Max — Nebula Pad
# https://github.com/christianKEL/E5M-CK
# ============================================================

# ─── Configuration ─────────────────────────────────────────
REPO_OWNER="christianKEL"
REPO_NAME="E5M-CK"
REPO_BRANCH="main"
CFG_DIR_REPO="configs/cfg"

API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/${CFG_DIR_REPO}?ref=${REPO_BRANCH}"
RAW_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/${CFG_DIR_REPO}"

# ─── Paths ─────────────────────────────────────────────────
PRINTER_DATA="/usr/data/printer_data"
CONFIG_DIR="$PRINTER_DATA/config"
KLIPPER_SERVICE="/etc/init.d/S55klipper_service"
MOONRAKER_SERVICE="/etc/init.d/S56moonraker_service"

# Files we never touch in CONFIG_DIR (deployed by other installers)
PROTECTED_FILES="moonraker.conf"

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

die() { log_error "$1"; exit 1; }

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
    p "${WHITE}             Klipper Configs Installer${NC}"
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
    p "  ${WHITE}This installer auto-discovers and deploys ALL .cfg files from${NC}"
    p "  ${WHITE}the ${DIM}configs/cfg/${NC}${WHITE} directory of your E5M-CK GitHub repo to${NC}"
    p "  ${WHITE}${DIM}/usr/data/printer_data/config/${NC}"
    p ""
    p "  ${WHITE}Add a new .cfg to ${DIM}configs/cfg/${NC}${WHITE} on the repo, push it,${NC}"
    p "  ${WHITE}re-run this script — it will be deployed automatically.${NC}"
    p ""
    p "  ${WHITE}It will:${NC}"
    p "  ${WHITE}  ${BR_RED}>${NC} stop Klipper and Moonraker"
    p "  ${WHITE}  ${BR_RED}>${NC} list all .cfg files on the repo (via GitHub API)"
    p "  ${WHITE}  ${BR_RED}>${NC} ${BOLD}wipe${NC}${WHITE} the existing .cfg files in ${DIM}$CONFIG_DIR${NC}"
    p "  ${WHITE}    (except moonraker.conf which is protected)"
    p "  ${WHITE}  ${BR_RED}>${NC} download and deploy each .cfg from the repo"
    p "  ${WHITE}  ${BR_RED}>${NC} restart Klipper and Moonraker"
    p ""
    p "  ${YELLOW}!${NC}  ${WHITE}No backups: existing .cfg files are deleted directly.${NC}"
    p "     ${WHITE}Your source of truth is the GitHub repo.${NC}"
    p ""
    p "  ${WHITE}I am not responsible for ANYTHING that happens to your printer,${NC}"
    p "  ${WHITE}your Nebula Pad, your house, your cat, or your sanity.${NC}"
    p ""
    p "  ${WHITE}Everyone using this installer is assumed to have a brain and${NC}"
    p "  ${WHITE}the ability to figure things out on their own.${NC}"
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

    log_info "Checking Klipper installation..."
    if [ ! -d "/usr/data/klipper" ]; then
        die "Klipper not found at /usr/data/klipper. Run install_klipper.sh first."
    fi
    log_ok "Klipper found"

    log_info "Checking $CONFIG_DIR..."
    if [ ! -d "$CONFIG_DIR" ]; then
        log_warn "$CONFIG_DIR does not exist — creating it"
        mkdir -p "$CONFIG_DIR"
    fi
    log_ok "$CONFIG_DIR ready"

    log_info "Checking system date..."
    YEAR=$(date +%Y)
    if [ "$YEAR" -lt 2024 ]; then
        die "System date wrong (year $YEAR). Run: ntpd -d -q -n -p pool.ntp.org"
    fi
    log_ok "System date sane"

    log_info "Checking GitHub API access..."
    if ! ping -c 1 -W 3 api.github.com >/dev/null 2>&1; then
        log_warn "Cannot ping api.github.com — install may fail"
    else
        log_ok "api.github.com reachable"
    fi
}

# ─── DISCOVER ───
step_discover() {
    log_step "1" "Discover .cfg files on the repo"

    log_info "Querying GitHub API..."
    log_action "$API_URL"

    # GitHub API returns JSON with each file's name+size on its own line in our grep filter
    API_RESPONSE=$(wget --no-check-certificate -q -O- "$API_URL" 2>&1)
    if [ -z "$API_RESPONSE" ]; then
        die "GitHub API returned empty response"
    fi

    # Parse the JSON. GitHub may return either pretty-printed (multi-line)
    # or compact (single-line) JSON. We use `tr ',' '\n'` to break the
    # compact form into one entry per line, then grep for the .cfg names.
    DISCOVERED_FILES=$(echo "$API_RESPONSE" | tr ',' '\n' | grep -E '"name"' | grep -E '\.cfg"' | sed 's/.*"name": *"\([^"]*\)".*/\1/' | sort -u)

    if [ -z "$DISCOVERED_FILES" ]; then
        die "No .cfg files found on $CFG_DIR_REPO branch=$REPO_BRANCH"
    fi

    COUNT=$(echo "$DISCOVERED_FILES" | wc -l)
    log_ok "Found $COUNT .cfg file(s) on the repo:"
    echo "$DISCOVERED_FILES" | while read f; do
        log_action "$f"
    done
}

# ─── CONFIRMATION ───
confirm_install() {
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${WHITE}${BOLD}READY TO INSTALL${NC}                                                ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}Source       :${NC} ${DIM}$RAW_URL/${NC}"
    p "  ${WHITE}Target dir   :${NC} ${DIM}$CONFIG_DIR${NC}"
    p "  ${WHITE}Files count  :${NC} ${DIM}$COUNT${NC}"
    p "  ${WHITE}Protected    :${NC} ${DIM}$PROTECTED_FILES${NC}"
    p ""

    # List existing .cfg in target that will be wiped
    EXISTING=$(ls -1 "$CONFIG_DIR"/*.cfg 2>/dev/null | xargs -I{} basename {} 2>/dev/null)
    if [ -n "$EXISTING" ]; then
        EXISTING_COUNT=$(echo "$EXISTING" | wc -l)
        p "  ${YELLOW}!  ${EXISTING_COUNT} existing .cfg file(s) will be DELETED:${NC}"
        echo "$EXISTING" | while read f; do
            p "      ${DIM}$f${NC}"
        done
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

# ─── STOP SERVICES ───
step_stop_services() {
    log_step "2" "Stop Klipper and Moonraker"

    if [ -x "$KLIPPER_SERVICE" ]; then
        if pgrep -f "klippy.py" >/dev/null 2>&1; then
            log_info "Stopping Klipper..."
            "$KLIPPER_SERVICE" stop 2>&1 | while read line; do log_action "$line"; done
            sleep 1
        else
            log_action "Klipper not running"
        fi
    else
        log_warn "Klipper service not found"
    fi

    if [ -x "$MOONRAKER_SERVICE" ]; then
        if pgrep -f "moonraker.py" >/dev/null 2>&1; then
            log_info "Stopping Moonraker..."
            "$MOONRAKER_SERVICE" stop 2>&1 | while read line; do log_action "$line"; done
            sleep 1
        else
            log_action "Moonraker not running"
        fi
    else
        log_warn "Moonraker service not found"
    fi

    log_ok "Services stopped"
}

# ─── WIPE ───
step_wipe() {
    log_step "3" "Wipe existing .cfg files"

    cd "$CONFIG_DIR" || die "Cannot cd to $CONFIG_DIR"

    # Also wipe any old .bak files left over from previous runs of this script
    OLD_BAKS=$(ls -1 *.cfg.bak 2>/dev/null | wc -l)
    if [ "$OLD_BAKS" -gt 0 ]; then
        rm -f *.cfg.bak
        log_action "Removed $OLD_BAKS old .bak file(s)"
    fi

    log_info "Wiping current .cfg files (except protected)..."
    WIPED=0
    for f in *.cfg; do
        [ -f "$f" ] || continue

        SKIP=0
        for prot in $PROTECTED_FILES; do
            if [ "$f" = "$prot" ]; then
                SKIP=1
                break
            fi
        done

        if [ "$SKIP" -eq 1 ]; then
            log_action "Skip (protected): $f"
            continue
        fi

        rm -f "$f"
        WIPED=$((WIPED + 1))
    done
    log_ok "$WIPED file(s) wiped"
}

# ─── DOWNLOAD ───
step_download() {
    log_step "4" "Download .cfg files from repo"

    cd "$CONFIG_DIR" || die "Cannot cd to $CONFIG_DIR"

    SUCCESS=0
    FAILED=0

    echo "$DISCOVERED_FILES" | while read cfg; do
        [ -z "$cfg" ] && continue

        log_info "Fetching $cfg..."
        if wget --no-check-certificate -q -O "$cfg" "$RAW_URL/$cfg"; then
            if [ -s "$cfg" ]; then
                SIZE=$(wc -c < "$cfg")
                log_action "$cfg ($SIZE bytes)"
                chmod 644 "$cfg"
            else
                log_error "$cfg download produced empty file"
                rm -f "$cfg"
            fi
        else
            log_error "$cfg download FAILED"
            rm -f "$cfg"
        fi
    done

    log_ok "Download phase complete"
}

# ─── START SERVICES ───
step_start_services() {
    log_step "5" "Start Klipper and Moonraker"

    if [ -x "$KLIPPER_SERVICE" ]; then
        log_info "Starting Klipper..."
        "$KLIPPER_SERVICE" start 2>&1 | while read line; do log_action "$line"; done
        sleep 2
    fi

    if [ -x "$MOONRAKER_SERVICE" ]; then
        log_info "Starting Moonraker..."
        "$MOONRAKER_SERVICE" start 2>&1 | while read line; do log_action "$line"; done
        sleep 2
    fi

    log_ok "Services start commands issued"
}

# ─── VERIFY ───
step_verify() {
    log_step "6" "Verify deployment"

    p ""
    p "  ${WHITE}File state in $CONFIG_DIR:${NC}"
    p "  ${GRAY}──────────────────────────────────────────────────────────${NC}"

    cd "$CONFIG_DIR" || return 1

    for cfg in *.cfg; do
        [ -f "$cfg" ] || continue
        SIZE=$(wc -c < "$cfg")
        p "  ${BR_GREEN}✓${NC} ${WHITE}$cfg${NC}     ${DIM}($SIZE bytes)${NC}"
    done

    p ""
    p "  ${WHITE}Klipper status:${NC}"
    p "  ${GRAY}──────────────────────────────────────────────────────────${NC}"
    sleep 1
    if pgrep -f "klippy.py" >/dev/null 2>&1; then
        KLIPPY_STATE=$(curl -s http://localhost:7125/printer/info 2>/dev/null | sed -n 's/.*"state": "\([^"]*\)".*/\1/p' | head -1)
        if [ -z "$KLIPPY_STATE" ]; then
            p "  ${YELLOW}!${NC} ${WHITE}Klipper running but Moonraker API not responding yet${NC}"
        elif [ "$KLIPPY_STATE" = "ready" ]; then
            p "  ${BR_GREEN}✓${NC} ${WHITE}Klipper state: ${BOLD}ready${NC}"
        elif [ "$KLIPPY_STATE" = "shutdown" ] || [ "$KLIPPY_STATE" = "startup" ]; then
            p "  ${BR_GREEN}✓${NC} ${WHITE}Klipper state: ${BOLD}$KLIPPY_STATE${NC} ${DIM}(normal, MCU communication required)${NC}"
        else
            p "  ${BR_RED}✗${NC} ${WHITE}Klipper state: ${BR_RED}$KLIPPY_STATE${NC}"
            p "      ${WHITE}Check log: ${DIM}tail -30 /usr/data/printer_data/logs/klippy.log${NC}"
        fi
    else
        p "  ${BR_RED}✗${NC} ${WHITE}Klipper process not running${NC}"
    fi

    p ""
}

# ─── COMPLETION ───
show_completion() {
    p ""
    p "${BR_RED}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${BG_RED}${WHITE}${BOLD}  ✓  CONFIGS INSTALLER COMPLETE  ${NC}                           ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}All .cfg files have been deployed.${NC}                            ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}${BOLD}Useful commands:${NC}                                             ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}tail -50 /usr/data/printer_data/logs/klippy.log${NC}               ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}curl -s http://localhost:7125/printer/info${NC}                    ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}/etc/init.d/S55klipper_service restart${NC}                        ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}/etc/init.d/S56moonraker_service restart${NC}                      ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Open Fluidd in browser:${NC}                                      ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}http://<your-printer-ip>:4408/${NC}                                ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Re-run this script anytime to redeploy from the repo.${NC}          ${BR_RED}║${NC}"
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
    step_discover
    confirm_install
    step_stop_services
    step_wipe
    step_download
    step_start_services
    step_verify
    show_completion
}

main "$@"
