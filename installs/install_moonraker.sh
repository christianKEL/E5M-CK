#!/bin/sh
# ============================================================
#   E5M-CK — install_moonraker.sh
#   Installs Moonraker (mainline) + MIPS venv on Creality Nebula Pad
#
#   Strategy:
#     - venv (MIPS, Python 3.8) is downloaded as a precompiled tarball
#       from the E5M-CK repo (see assets/memos/MEMO_moonraker_venv_FR.md
#       for how it was built).
#     - Moonraker code is git-cloned from Arksine/moonraker.git, so
#       Moonraker's Update Manager works out of the box.
#
#   Modes:
#     - FULL INSTALL  (no existing install detected) — downloads venv,
#                     clones code, deploys conf + service.
#     - UPDATE        (already installed) — just `git pull` + restart.
#
#   Repo:  https://github.com/christianKEL/E5M-CK
#   Docs:  https://e5mdocumentation.kinsta.cloud/
# ============================================================

set -e

# ─── PATHS ─────────────────────────────────────────────────
GITHUB_RAW="https://raw.githubusercontent.com/christianKEL/E5M-CK/main"
MOONRAKER_REPO="https://github.com/Arksine/moonraker.git"
MOONRAKER_DIR="/usr/data/moonraker"
MOONRAKER_CODE_DIR="$MOONRAKER_DIR/moonraker"
MOONRAKER_VENV_DIR="$MOONRAKER_DIR/moonraker-env"
MOONRAKER_INSTALLED_FLAG="$MOONRAKER_DIR/.e5m_ck_installed"
PRINTER_DATA="/usr/data/printer_data"
CONFIG_DIR="$PRINTER_DATA/config"
LOGS_DIR="$PRINTER_DATA/logs"
COMMS_DIR="$PRINTER_DATA/comms"
MOONRAKER_CONF="$CONFIG_DIR/moonraker.conf"
SERVICE_FILE="/etc/init.d/S56moonraker_service"
TMP_DIR="/usr/data/.tmp_install"

# Expected venv tarball (hosted in our own repo for autonomy).
VENV_TARBALL_URL="$GITHUB_RAW/files/moonraker-env.tar.gz"
VENV_TARBALL_LOCAL="$TMP_DIR/moonraker-env.tar.gz"
VENV_TARBALL_MD5="913e85247d94e788797308e067314600"
VENV_TARBALL_SIZE_MIN=15000000

MOONRAKER_CONF_URL="$GITHUB_RAW/configs/moonraker.conf"

# ─── ANSI COLORS ───────────────────────────────────────────
RED='\033[0;31m'
BR_RED='\033[1;31m'
BG_RED='\033[41m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
DIM='\033[2m'
BOLD='\033[1m'
UNDER='\033[4m'
NC='\033[0m'
BR_GREEN='\033[1;32m'
YELLOW='\033[1;33m'

p() { printf "%b\n" "$1"; }

log_info()    { p "  ${WHITE}i${NC}  ${GRAY}$(date +%H:%M:%S)${NC} ${WHITE}$1${NC}"; }
log_ok()      { p "  ${BR_GREEN}✓${NC}  ${GRAY}$(date +%H:%M:%S)${NC} ${WHITE}$1${NC}"; }
log_warn()    { p "  ${YELLOW}!${NC}  ${GRAY}$(date +%H:%M:%S)${NC} ${YELLOW}$1${NC}"; }
log_error()   { p "  ${BR_RED}✗${NC}  ${GRAY}$(date +%H:%M:%S)${NC} ${BR_RED}$1${NC}"; }
log_action()  { p "  ${RED}>${NC}  ${GRAY}$(date +%H:%M:%S)${NC} ${DIM}$1${NC}"; }

log_step() {
    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} STEP $1 ${NC}  ${WHITE}${BOLD}$2${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
}

show_banner() {
    clear
    p ""
    p "${BR_RED}    ███████╗███████╗███╗   ███╗       ██████╗██╗  ██╗${NC}"
    p "${BR_RED}    ██╔════╝██╔════╝████╗ ████║      ██╔════╝██║ ██╔╝${NC}"
    p "${BR_RED}    █████╗  ███████╗██╔████╔██║█████╗██║     █████╔╝ ${NC}"
    p "${BR_RED}    ██╔══╝  ╚════██║██║╚██╔╝██║╚════╝██║     ██╔═██╗ ${NC}"
    p "${BR_RED}    ███████╗███████║██║ ╚═╝ ██║      ╚██████╗██║  ██╗${NC}"
    p "${BR_RED}    ╚══════╝╚══════╝╚═╝     ╚═╝       ╚═════╝╚═╝  ╚═╝${NC}"
    p ""
    p "${WHITE}              install_moonraker.sh${NC}"
    p "${GRAY}        Moonraker (mainline) + MIPS venv${NC}"
    p ""
    p "                    ${BG_RED}${WHITE}${BOLD}  CR*ALITY S*CKS  ${NC}"
    p ""
    p "${DIM}                 github.com/christianKEL/E5M-CK${NC}"
    p ""
}

show_disclaimer() {
    p "${BR_RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}║${NC}  ${BG_RED}${WHITE}${BOLD}  DISCLAIMER  ${NC}                                                   ${BR_RED}║${NC}"
    p "${BR_RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
    p "  ${WHITE}This installer will REMOVE any existing Moonraker installation${NC}"
    p "  ${WHITE}at $MOONRAKER_DIR (full mode) or update it via 'git pull'${NC}"
    p "  ${WHITE}(update mode).${NC}"
    p ""
    p "  ${WHITE}I am not responsible for ANYTHING that happens to your printer,${NC}"
    p "  ${WHITE}your Nebula Pad, your house, your cat, or your sanity.${NC}"
    p ""
    p "  ${DIM}Signed: Christian KELHETTER${NC}"
    p "  ${DIM}https://e5mdocumentation.kinsta.cloud/${NC}"
    p ""
}

die() {
    log_error "$1"
    exit 1
}

confirm() {
    p ""
    printf "  ${WHITE}${BOLD}>${NC} ${WHITE}$1${NC} ${GRAY}[y/N]${NC} "
    read CONFIRM
    case "$CONFIRM" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}


# ════════════════════════════════════════════════════════════
# STEP 1 — PRECHECK
# ════════════════════════════════════════════════════════════
step_precheck() {
    log_step "1" "Pre-checks (network, disk, klipper running)"

    log_info "Checking internet connectivity..."
    if ! ping -c 1 -W 3 raw.githubusercontent.com >/dev/null 2>&1; then
        die "Cannot reach raw.githubusercontent.com — check your network"
    fi
    log_ok "Internet OK"

    log_info "Checking required tools..."
    for tool in wget tar git python3 md5sum; do
        if ! command -v $tool >/dev/null 2>&1; then
            die "Required tool '$tool' not found in PATH (install Entware first?)"
        fi
    done
    log_ok "All required tools available"

    log_info "Checking disk space (need at least 100 MB free in /usr/data)..."
    AVAIL_KB=$(df -k /usr/data | awk 'NR==2 {print $4}')
    if [ "$AVAIL_KB" -lt 102400 ]; then
        die "Insufficient disk space (only $((AVAIL_KB/1024)) MB free)"
    fi
    log_ok "Disk space OK ($((AVAIL_KB/1024)) MB free)"

    log_info "Preparing temp dir at $TMP_DIR..."
    mkdir -p "$TMP_DIR"
    log_ok "Temp dir ready"
}


# ════════════════════════════════════════════════════════════
# STEP 2 — DETECT MODE
# ════════════════════════════════════════════════════════════
step_detect_mode() {
    log_step "2" "Detect install mode (FULL or UPDATE)"

    INSTALL_MODE="FULL"

    if [ -f "$MOONRAKER_INSTALLED_FLAG" ] \
        && [ -d "$MOONRAKER_CODE_DIR/.git" ] \
        && [ -d "$MOONRAKER_VENV_DIR/bin" ]; then
        INSTALL_MODE="UPDATE"
        log_ok "Existing E5M-CK install detected — UPDATE mode (git pull only)"
    else
        log_info "No previous E5M-CK install found — FULL INSTALL mode"
        if [ -d "$MOONRAKER_DIR" ]; then
            log_warn "But $MOONRAKER_DIR exists from a previous (non-E5M-CK) install"
            log_warn "It will be REMOVED and replaced"
        fi
    fi

    log_action "Mode: $INSTALL_MODE"
}


# ════════════════════════════════════════════════════════════
# STEP 3 — STOP RUNNING SERVICES
# ════════════════════════════════════════════════════════════
step_stop_services() {
    log_step "3" "Stop Moonraker (if running)"

    if [ -f "$SERVICE_FILE" ]; then
        log_info "Stopping S56moonraker_service..."
        "$SERVICE_FILE" stop 2>&1 | while read line; do log_action "$line"; done || true
        sleep 2
    else
        log_action "No init script yet (first install)"
    fi

    if pgrep -f "moonraker.py" >/dev/null 2>&1; then
        log_warn "Moonraker process still running — killing"
        killall -9 moonraker 2>/dev/null || true
        pkill -9 -f "moonraker.py" 2>/dev/null || true
        sleep 2
    fi

    if pgrep -f "moonraker.py" >/dev/null 2>&1; then
        die "Cannot stop Moonraker process — please reboot and retry"
    fi
    log_ok "Moonraker stopped"

    rm -f "$MOONRAKER_DIR/tmp/.moonraker_instance_ids.lock" 2>/dev/null || true
}


# ════════════════════════════════════════════════════════════
# STEP 4a — UPDATE PATH
# ════════════════════════════════════════════════════════════
step_update_only() {
    log_step "4" "UPDATE — git pull on Moonraker repo"

    cd "$MOONRAKER_CODE_DIR" || die "Cannot cd to $MOONRAKER_CODE_DIR"

    log_info "Fetching upstream changes..."
    git fetch --all 2>&1 | while read line; do log_action "$line"; done || true

    BEFORE=$(git rev-parse HEAD)
    log_info "Current commit: ${BOLD}${BEFORE}${NC}" | head -c 200

    log_info "Pulling latest master..."
    git pull origin master 2>&1 | while read line; do log_action "$line"; done || \
        log_warn "git pull had issues — repo may be in a divergent state"

    AFTER=$(git rev-parse HEAD)
    if [ "$BEFORE" = "$AFTER" ]; then
        log_ok "Already up-to-date"
    else
        log_ok "Updated to a new commit"
        log_action "Before: $BEFORE"
        log_action "After:  $AFTER"
    fi
}


# ════════════════════════════════════════════════════════════
# STEP 4b — FULL INSTALL: cleanup, download, extract, clone
# ════════════════════════════════════════════════════════════
step_full_cleanup() {
    log_step "4" "FULL INSTALL — cleanup previous Moonraker"

    if [ -d "$MOONRAKER_DIR" ]; then
        log_info "Removing $MOONRAKER_DIR (this may take a minute)..."
        rm -rf "$MOONRAKER_DIR"
        log_ok "Old directory removed"
    fi

    mkdir -p "$MOONRAKER_DIR"
    log_ok "Fresh $MOONRAKER_DIR created"
}

step_download_venv() {
    log_step "5" "Download MIPS venv tarball from E5M-CK repo"

    log_info "URL: $VENV_TARBALL_URL"
    log_info "Expected size: ~16 MB, MD5: $VENV_TARBALL_MD5"

    rm -f "$VENV_TARBALL_LOCAL"

    log_info "Downloading..."
    if ! wget --no-check-certificate -q "$VENV_TARBALL_URL" \
            -O "$VENV_TARBALL_LOCAL"; then
        die "Download failed"
    fi

    SIZE=$(wc -c < "$VENV_TARBALL_LOCAL")
    log_action "Downloaded size: $SIZE bytes"

    if [ "$SIZE" -lt "$VENV_TARBALL_SIZE_MIN" ]; then
        die "Tarball too small ($SIZE bytes) — likely a 404 or LFS pointer"
    fi

    log_info "Verifying MD5..."
    DL_MD5=$(md5sum "$VENV_TARBALL_LOCAL" | awk '{print $1}')
    if [ "$DL_MD5" = "$VENV_TARBALL_MD5" ]; then
        log_ok "MD5 matches: $DL_MD5"
    else
        log_warn "MD5 mismatch: got $DL_MD5, expected $VENV_TARBALL_MD5"
        log_warn "The repo tarball may have been updated. Continuing anyway."
    fi
}

step_extract_venv() {
    log_step "6" "Extract MIPS venv into $MOONRAKER_DIR"

    cd "$MOONRAKER_DIR" || die "Cannot cd to $MOONRAKER_DIR"

    log_info "Extracting moonraker-env/ ..."
    if ! tar -xzf "$VENV_TARBALL_LOCAL"; then
        die "tar extraction failed"
    fi

    if [ ! -x "$MOONRAKER_VENV_DIR/bin/python" ] \
        && [ ! -x "$MOONRAKER_VENV_DIR/bin/python3" ]; then
        die "Venv extraction OK but no python binary found in $MOONRAKER_VENV_DIR/bin"
    fi

    log_info "Verifying venv Python..."
    PYVER=$("$MOONRAKER_VENV_DIR/bin/python" --version 2>&1 || echo "?")
    log_action "Venv Python: $PYVER"

    log_info "Verifying critical packages are importable..."
    "$MOONRAKER_VENV_DIR/bin/python" -c "
import tornado, jinja2, paho.mqtt.client, inotify_simple, dbus_fast, lmdb
print('All critical imports OK')
" 2>&1 | while read line; do log_action "$line"; done

    log_ok "Venv extracted and validated"
}

step_clone_code() {
    log_step "7" "Clone Moonraker code from Arksine/moonraker.git"

    log_info "git clone $MOONRAKER_REPO into $MOONRAKER_CODE_DIR..."
    log_warn "This takes 30-90 seconds depending on your connection"

    git clone "$MOONRAKER_REPO" "$MOONRAKER_CODE_DIR" 2>&1 | \
        grep -E "Receiving|Resolving|Updating|Cloning" | \
        while read line; do log_action "$line"; done

    if [ ! -d "$MOONRAKER_CODE_DIR/.git" ]; then
        die "git clone failed — no .git directory"
    fi

    if [ ! -f "$MOONRAKER_CODE_DIR/moonraker/moonraker.py" ]; then
        die "Clone OK but moonraker.py is missing — repo structure changed?"
    fi

    cd "$MOONRAKER_CODE_DIR"
    COMMIT=$(git rev-parse --short HEAD)
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    log_ok "Cloned at branch=${BOLD}$BRANCH${NC} commit=${BOLD}$COMMIT${NC}"
}


# ════════════════════════════════════════════════════════════
# STEP 8 — DEPLOY moonraker.conf
# ════════════════════════════════════════════════════════════
step_deploy_conf() {
    log_step "8" "Deploy moonraker.conf"

    mkdir -p "$CONFIG_DIR" "$LOGS_DIR" "$COMMS_DIR"

    if [ -f "$MOONRAKER_CONF" ]; then
        log_info "Backing up existing moonraker.conf..."
        cp "$MOONRAKER_CONF" "${MOONRAKER_CONF}.before_E5M_CK"
        log_action "Backup: ${MOONRAKER_CONF}.before_E5M_CK"
    fi

    log_info "Downloading moonraker.conf from E5M-CK repo..."
    if ! wget --no-check-certificate -q "$MOONRAKER_CONF_URL" \
            -O "$MOONRAKER_CONF"; then
        die "Cannot download moonraker.conf from $MOONRAKER_CONF_URL"
    fi

    if ! grep -q "^provider: none" "$MOONRAKER_CONF"; then
        log_warn "Downloaded conf does not contain 'provider: none' — check the file"
    fi

    log_ok "moonraker.conf deployed at $MOONRAKER_CONF"
}


# ════════════════════════════════════════════════════════════
# STEP 9 — INSTALL S56moonraker_service
# ════════════════════════════════════════════════════════════
step_install_service() {
    log_step "9" "Install S56moonraker_service init script"

    if [ -f "$SERVICE_FILE" ]; then
        log_info "Backing up existing service file..."
        cp "$SERVICE_FILE" "${SERVICE_FILE}.before_E5M_CK"
    fi

    log_info "Writing $SERVICE_FILE..."
    cat > "$SERVICE_FILE" << 'SVCEOF'
#!/bin/sh
# S56moonraker_service — E5M-CK Moonraker service
# Compatible with Buildroot Creality (no systemd, no supervisord)

NAME="moonraker"
PROG="/usr/data/moonraker/moonraker-env/bin/python"
PY_SCRIPT="/usr/data/moonraker/moonraker/moonraker/moonraker.py"
DATA_PATH="/usr/data/printer_data"
LOG="$DATA_PATH/logs/moonraker.log"
PID_FILE="/var/run/$NAME.pid"

# Redirect Python tempfile.gettempdir() to flash storage instead of /tmp.
# Creality firmware mounts /tmp as a ~104 MB tmpfs (half of total RAM).
# Moonraker stages uploaded gcodes there before moving them to gcodes/,
# so any upload > ~100 MB saturates /tmp and Moonraker returns HTTP 502
# (nginx Bad Gateway in slicers like Orca/Prusa). Pointing TMPDIR to
# /usr/data/tmp (flash, several GB free) avoids the issue and makes the
# final move a same-filesystem rename instead of a tmpfs→flash copy.
TMPDIR="/usr/data/tmp"
export TMPDIR

start() {
    echo "Starting $NAME..."
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "$NAME is already running (pid $(cat $PID_FILE))"
        return 1
    fi
    rm -f "$PID_FILE"
    mkdir -p "$DATA_PATH/logs" "$DATA_PATH/comms" "$TMPDIR"
    start-stop-daemon -S -q -b -m -p "$PID_FILE" \
        --exec "$PROG" -- "$PY_SCRIPT" -d "$DATA_PATH"
    sleep 1
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "$NAME started (pid $(cat $PID_FILE))"
    else
        echo "$NAME failed to start — check $LOG"
        return 1
    fi
}

stop() {
    echo "Stopping $NAME..."
    if [ -f "$PID_FILE" ]; then
        start-stop-daemon -K -q -p "$PID_FILE" 2>/dev/null
        rm -f "$PID_FILE"
    fi
    pkill -f "$PY_SCRIPT" 2>/dev/null
    sleep 1
    if pgrep -f "$PY_SCRIPT" >/dev/null 2>&1; then
        pkill -9 -f "$PY_SCRIPT" 2>/dev/null
    fi
    echo "$NAME stopped"
}

restart() {
    stop
    sleep 1
    start
}

status() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "$NAME is running (pid $(cat $PID_FILE))"
        return 0
    else
        echo "$NAME is not running"
        return 1
    fi
}

case "$1" in
    start)   start ;;
    stop)    stop ;;
    restart) restart ;;
    status)  status ;;
    *)       echo "Usage: $0 {start|stop|restart|status}"; exit 1 ;;
esac
SVCEOF

    chmod +x "$SERVICE_FILE"
    log_ok "Service installed at $SERVICE_FILE"
}


# ════════════════════════════════════════════════════════════
# STEP 10 — START + VERIFY
# ════════════════════════════════════════════════════════════
step_start_verify() {
    log_step "10" "Start Moonraker and verify"

    log_info "Starting service..."
    "$SERVICE_FILE" start 2>&1 | while read line; do log_action "$line"; done

    log_info "Waiting for Moonraker to listen on port 7125..."
    READY=0
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        sleep 2
        if netstat -ln 2>/dev/null | grep -q ":7125 "; then
            READY=1
            break
        fi
        log_action "Still waiting... ($((i*2))/24s)"
    done

    if [ "$READY" -eq 0 ]; then
        log_error "Moonraker did not start listening on port 7125 within 24s"
        log_error "Check $LOGS_DIR/moonraker.log"
        return 1
    fi
    log_ok "Port 7125 listening"

    log_info "Querying /server/info..."
    sleep 2
    INFO=$(wget --no-check-certificate -q -O - "http://localhost:7125/server/info" 2>/dev/null || echo "")
    if [ -z "$INFO" ]; then
        log_warn "API did not respond yet — Moonraker may still be initializing"
    else
        VERSION=$(echo "$INFO" | grep -oE '"moonraker_version":"[^"]+"' | head -1 | cut -d\" -f4)
        if [ -n "$VERSION" ]; then
            log_ok "Moonraker version: ${BOLD}$VERSION${NC}"
        fi
        if echo "$INFO" | grep -q '"klippy_connected":true'; then
            log_ok "Klippy connection OK"
        elif echo "$INFO" | grep -q '"klippy_connected":false'; then
            log_warn "Moonraker is up but klippy is not connected — check Klipper"
        fi
    fi

    log_info "Marking install as complete..."
    touch "$MOONRAKER_INSTALLED_FLAG"
    log_ok "Flag created at $MOONRAKER_INSTALLED_FLAG"
}


# ════════════════════════════════════════════════════════════
# STEP 11 — FINAL CLEANUP
# ════════════════════════════════════════════════════════════
step_cleanup() {
    log_step "11" "Cleanup temp files"

    if [ -f "$VENV_TARBALL_LOCAL" ]; then
        log_info "Removing downloaded tarball..."
        rm -f "$VENV_TARBALL_LOCAL"
        log_action "Removed $VENV_TARBALL_LOCAL"
    fi

    log_ok "Cleanup done"
}


# ════════════════════════════════════════════════════════════
# COMPLETION
# ════════════════════════════════════════════════════════════
show_completion() {
    IP=$(ifconfig 2>/dev/null | grep -A1 'wlan0\|eth0' | grep 'inet ' | \
         awk '{print $2}' | sed 's/addr://' | head -1)
    [ -z "$IP" ] && IP="<nebula-ip>"

    p ""
    p "${BR_RED}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${BG_RED}${WHITE}${BOLD}  ✓  MOONRAKER INSTALL/UPDATE COMPLETE  ${NC}                    ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Mode:${NC}            ${BOLD}$INSTALL_MODE${NC}                                       ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Code:${NC}            /usr/data/moonraker/moonraker/.git              ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Venv:${NC}            /usr/data/moonraker/moonraker-env/             ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}API:${NC}             ${BOLD}http://${IP}:7125${NC}                          ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${YELLOW}NEXT:${NC}                                                          ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}      ${DIM}- Future updates: just run this script again${NC}                 ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}      ${DIM}- It will detect the existing install and git pull${NC}            ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ╚══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
}


# ════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════
main() {
    show_banner
    show_disclaimer

    if ! confirm "Continue with Moonraker installation?"; then
        log_warn "Cancelled by user"
        exit 0
    fi

    step_precheck
    step_detect_mode
    step_stop_services

    if [ "$INSTALL_MODE" = "UPDATE" ]; then
        step_update_only
    else
        step_full_cleanup
        step_download_venv
        step_extract_venv
        step_clone_code
        step_deploy_conf
        step_install_service
    fi

    step_start_verify
    step_cleanup
    show_completion
}

main "$@"
