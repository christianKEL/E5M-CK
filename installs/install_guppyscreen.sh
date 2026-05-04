#!/bin/sh
# ============================================================
#   E5M-CK — install_guppyscreen.sh  (v2)
#   Installs GuppyScreen (touch UI, ballaswag) on Creality Nebula Pad
#
#   Strategy:
#     - Pre-built tarball downloaded from ballaswag/guppyscreen GitHub
#       releases (auto-detects screen size: smallscreen <800px or normal).
#     - We do NOT use ballaswag's installer.sh — we replicate its logic
#       with E5M-CK conventions (clearer flow, safer error handling,
#       UPDATE mode, no [update_manager guppyscreen] section).
#
#   Modes:
#     - FULL INSTALL  (no existing install detected)
#     - UPDATE        (install detected, just download newer release)
#
#   v2 changes (vs v1):
#     - Fixed pgrep detection: use ps+grep on full path instead of
#       pgrep -x (which doesn't match supervise-daemon-spawned processes)
#     - Fixed killall calls: removed "| while read line" pipe that was
#       breaking signal delivery in busybox sh
#     - Extended kill list: 9 Creality processes (master-server,
#       app-server, display-server, Monitor, audio-server, upgrade-server,
#       log_main, cx_ai_middleware, webrtc) — keeps network daemons alive
#     - Added retry pass with pkill -9 -f for stubborn processes
#     - Increased GuppyScreen startup wait window from 5s to 20s
#
#   Repo:  https://github.com/christianKEL/E5M-CK
#   Docs:  https://e5mdocumentation.kinsta.cloud/
# ============================================================

set -e

# ─── PATHS ─────────────────────────────────────────────────
GITHUB_RAW="https://raw.githubusercontent.com/christianKEL/E5M-CK/main"
GUPPY_REPO_API="https://api.github.com/repos/ballaswag/guppyscreen/releases/latest"
GUPPY_DOWNLOAD_BASE="https://github.com/ballaswag/guppyscreen/releases/download"

GUPPY_DIR="/usr/data/guppyscreen"
GUPPY_BIN="$GUPPY_DIR/guppyscreen"
GUPPY_INSTALLED_FLAG="$GUPPY_DIR/.e5m_ck_installed"
GUPPY_VERSION_FILE="$GUPPY_DIR/.e5m_ck_version"

KLIPPER_DIR="/usr/data/klipper"
KLIPPY_EXTRAS="$KLIPPER_DIR/klippy/extras"
PRINTER_DATA="/usr/data/printer_data"
CONFIG_DIR="$PRINTER_DATA/config"
GUPPY_CONFIG_DIR="$CONFIG_DIR/GuppyScreen"
GCODES_DIR="$PRINTER_DATA/gcodes"

KLIPPER_SERVICE="/etc/init.d/S55klipper_service"
GUPPY_SERVICE="/etc/init.d/S99guppyscreen"
DROPBEAR_SERVICE="/etc/init.d/S50dropbear"

BACKUP_DIR="/usr/data/guppyify-backup"
TMP_DIR="/usr/data/.tmp_install"
TARBALL_LOCAL="$TMP_DIR/guppyscreen.tar.gz"

# ─── ANSI COLORS ───────────────────────────────────────────
RED='\033[0;31m'
BR_RED='\033[1;31m'
BG_RED='\033[41m'
BG_BLACK='\033[40m'
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
    p "${WHITE}              install_guppyscreen.sh${NC}"
    p "${GRAY}        Touch UI for Klipper (ballaswag/guppyscreen)${NC}"
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
    p "  ${WHITE}This installer will REPLACE the Creality touch UI (display-server)${NC}"
    p "  ${WHITE}with GuppyScreen (LVGL-based, native Klipper UI by ballaswag).${NC}"
    p ""
    p "  ${WHITE}It will also OPTIONALLY disable Creality services (Cloud, Slicer,${NC}"
    p "  ${WHITE}Monitor) to free up resources. This is REVERSIBLE — original files${NC}"
    p "  ${WHITE}are backed up to $BACKUP_DIR${NC}"
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
    log_step "1" "Pre-checks (network, Klipper, Moonraker, screen, disk)"

    log_info "Checking internet connectivity..."
    if ! ping -c 1 -W 3 raw.githubusercontent.com >/dev/null 2>&1; then
        die "Cannot reach raw.githubusercontent.com — check your network"
    fi
    log_ok "Internet OK"

    log_info "Checking required tools..."
    for tool in wget tar; do
        if ! command -v $tool >/dev/null 2>&1; then
            die "Required tool '$tool' not found"
        fi
    done
    log_ok "Required tools available"

    log_info "Checking ld.so version (firmware Creality 1.3.x)..."
    if [ ! -f /lib/ld-2.29.so ]; then
        die "ld-2.29.so not found — your firmware is not Creality 1.3.x.y, GuppyScreen won't run"
    fi
    log_ok "ld-2.29.so present"

    log_info "Checking Moonraker availability..."
    MRK_OK=$(wget --no-check-certificate -q -O - "http://localhost:7125/server/info" 2>/dev/null | \
             grep -o '"klippy_connected":true' | head -1)
    if [ -z "$MRK_OK" ]; then
        die "Moonraker is not responding at port 7125 with klippy_connected=true. Install/start it first."
    fi
    log_ok "Moonraker responds, Klippy connected"

    log_info "Detecting screen resolution..."
    if [ ! -f /sys/class/graphics/fb0/virtual_size ]; then
        die "No framebuffer fb0 — is the display panel connected?"
    fi
    SCREEN_SIZE=$(cat /sys/class/graphics/fb0/virtual_size)
    SCREEN_X=${SCREEN_SIZE%,*}
    SCREEN_Y=${SCREEN_SIZE#*,}
    log_action "Screen: ${SCREEN_X} x ${SCREEN_Y}"

    if [ "$SCREEN_Y" -lt 800 ] && [ "$SCREEN_X" -lt 800 ]; then
        ASSET_NAME="guppyscreen-smallscreen"
        log_ok "Detected SMALL screen (<800px) — will use ${BOLD}${ASSET_NAME}.tar.gz${NC}"
    else
        ASSET_NAME="guppyscreen"
        log_ok "Detected LARGE screen — will use ${BOLD}${ASSET_NAME}.tar.gz${NC}"
    fi

    log_info "Checking disk space (need at least 30 MB free in /usr/data)..."
    AVAIL_KB=$(df -k /usr/data | awk 'NR==2 {print $4}')
    if [ "$AVAIL_KB" -lt 30720 ]; then
        die "Insufficient disk space (only $((AVAIL_KB/1024)) MB free)"
    fi
    log_ok "Disk space OK ($((AVAIL_KB/1024)) MB free)"

    log_info "Preparing temp dir at $TMP_DIR..."
    mkdir -p "$TMP_DIR"
    log_ok "Temp dir ready"
}


# ════════════════════════════════════════════════════════════
# STEP 2 — DETECT MODE + GET LATEST VERSION
# ════════════════════════════════════════════════════════════
step_detect_mode() {
    log_step "2" "Detect install mode + check latest version"

    log_info "Querying GitHub API for latest release..."
    LATEST_VERSION=$(wget --no-check-certificate -q -O - "$GUPPY_REPO_API" 2>/dev/null | \
                     grep '"tag_name"' | head -1 | cut -d'"' -f4)
    if [ -z "$LATEST_VERSION" ]; then
        die "Cannot fetch latest version from GitHub API (rate limit? network?)"
    fi
    log_ok "Latest available version: ${BOLD}$LATEST_VERSION${NC}"

    INSTALL_MODE="FULL"

    if [ -f "$GUPPY_INSTALLED_FLAG" ] && [ -x "$GUPPY_BIN" ]; then
        # Read installed version (if file exists)
        INSTALLED_VERSION=""
        if [ -f "$GUPPY_VERSION_FILE" ]; then
            INSTALLED_VERSION=$(cat "$GUPPY_VERSION_FILE" 2>/dev/null)
        fi
        log_info "Existing E5M-CK install detected — version: ${BOLD}${INSTALLED_VERSION:-unknown}${NC}"

        if [ "$INSTALLED_VERSION" = "$LATEST_VERSION" ]; then
            log_ok "Already at latest version ($LATEST_VERSION)"
            log_info "Nothing to do — script will exit"
            log_info "(use FORCE_REINSTALL=1 environment var to force a full reinstall)"
            if [ "$FORCE_REINSTALL" = "1" ]; then
                log_warn "FORCE_REINSTALL=1 — proceeding anyway in UPDATE mode"
                INSTALL_MODE="UPDATE"
            else
                exit 0
            fi
        else
            INSTALL_MODE="UPDATE"
            log_action "UPDATE available: $INSTALLED_VERSION → $LATEST_VERSION"
        fi
    else
        log_info "No previous E5M-CK install — FULL INSTALL mode"
        if [ -d "$GUPPY_DIR" ]; then
            log_warn "But $GUPPY_DIR exists from a previous (non-E5M-CK) install"
            log_warn "It will be REMOVED and replaced"
        fi
    fi

    log_action "Mode: $INSTALL_MODE"
    log_action "Asset: ${ASSET_NAME}.tar.gz @ $LATEST_VERSION"

    # Build download URL
    DOWNLOAD_URL="$GUPPY_DOWNLOAD_BASE/$LATEST_VERSION/${ASSET_NAME}.tar.gz"
    log_action "URL: $DOWNLOAD_URL"
}


# ════════════════════════════════════════════════════════════
# STEP 3 — STOP RUNNING SERVICES
# ════════════════════════════════════════════════════════════
step_stop_guppy() {
    log_step "3" "Stop GuppyScreen (if running)"

    if [ -f "$GUPPY_SERVICE" ]; then
        log_info "Stopping S99guppyscreen service..."
        "$GUPPY_SERVICE" stop 2>&1 | while read line; do log_action "$line"; done || true
        sleep 2
    else
        log_action "No init script yet (first install)"
    fi

    if pgrep -x "guppyscreen" >/dev/null 2>&1; then
        log_warn "GuppyScreen process still running — killing"
        killall -9 guppyscreen 2>/dev/null || true
        sleep 2
    fi

    log_ok "GuppyScreen stopped (Creality display-server still running)"
}


# ════════════════════════════════════════════════════════════
# STEP 4 — DOWNLOAD TARBALL
# ════════════════════════════════════════════════════════════
step_download() {
    log_step "4" "Download GuppyScreen tarball"

    rm -f "$TARBALL_LOCAL"

    log_info "Downloading from $DOWNLOAD_URL..."
    if ! wget --no-check-certificate -q -L "$DOWNLOAD_URL" \
            -O "$TARBALL_LOCAL"; then
        die "Download failed"
    fi

    SIZE=$(wc -c < "$TARBALL_LOCAL")
    log_action "Downloaded size: $SIZE bytes"

    if [ "$SIZE" -lt 100000 ]; then
        die "Tarball too small ($SIZE bytes) — likely a 404 or redirect to an HTML page"
    fi

    log_info "Validating tarball integrity..."
    if ! tar -tzf "$TARBALL_LOCAL" >/dev/null 2>&1; then
        die "Tarball is corrupt or not a valid tar.gz"
    fi

    if ! tar -tzf "$TARBALL_LOCAL" | grep -q "guppyscreen/guppyscreen$"; then
        die "Tarball does not contain expected guppyscreen binary"
    fi

    log_ok "Tarball validated"
}


# ════════════════════════════════════════════════════════════
# STEP 5 — EXTRACT
# ════════════════════════════════════════════════════════════
step_extract() {
    log_step "5" "Extract tarball to /usr/data/"

    # In UPDATE mode: backup user's guppyconfig.json before extraction
    USER_CONFIG_BACKUP=""
    if [ "$INSTALL_MODE" = "UPDATE" ] && [ -f "$GUPPY_DIR/guppyconfig.json" ]; then
        USER_CONFIG_BACKUP="$TMP_DIR/guppyconfig.json.user"
        cp "$GUPPY_DIR/guppyconfig.json" "$USER_CONFIG_BACKUP"
        log_info "Backed up user's guppyconfig.json (will be restored)"
    fi

    # In FULL mode: full wipe of /usr/data/guppyscreen/
    if [ "$INSTALL_MODE" = "FULL" ] && [ -d "$GUPPY_DIR" ]; then
        log_info "Removing $GUPPY_DIR (FULL mode)..."
        rm -rf "$GUPPY_DIR"
    fi

    log_info "Extracting tarball into /usr/data/..."
    cd /usr/data/
    if ! tar -xzf "$TARBALL_LOCAL"; then
        die "Tar extraction failed"
    fi

    if [ ! -x "$GUPPY_BIN" ]; then
        die "Extraction OK but $GUPPY_BIN is missing/not executable"
    fi

    log_action "Binary size: $(wc -c < "$GUPPY_BIN") bytes"

    # Restore user's guppyconfig.json (UPDATE mode)
    if [ -n "$USER_CONFIG_BACKUP" ] && [ -f "$USER_CONFIG_BACKUP" ]; then
        cp "$USER_CONFIG_BACKUP" "$GUPPY_DIR/guppyconfig.json"
        rm -f "$USER_CONFIG_BACKUP"
        log_action "Restored user's guppyconfig.json"
    fi

    log_ok "Extraction complete"
}


# ════════════════════════════════════════════════════════════
# STEP 6 — INSTALL SYSTEM SYMLINKS (libeinfo, librc)
# ════════════════════════════════════════════════════════════
step_system_symlinks() {
    log_step "6" "Install system symlinks (respawn daemon libs)"

    if [ ! -f "$GUPPY_DIR/k1_mods/respawn/libeinfo.so.1" ]; then
        die "respawn/libeinfo.so.1 not found in extracted tarball"
    fi
    if [ ! -f "$GUPPY_DIR/k1_mods/respawn/librc.so.1" ]; then
        die "respawn/librc.so.1 not found in extracted tarball"
    fi

    log_info "Creating symlinks in /lib/..."
    ln -sf "$GUPPY_DIR/k1_mods/respawn/libeinfo.so.1" /lib/libeinfo.so.1
    ln -sf "$GUPPY_DIR/k1_mods/respawn/librc.so.1" /lib/librc.so.1
    log_action "/lib/libeinfo.so.1 -> $GUPPY_DIR/k1_mods/respawn/libeinfo.so.1"
    log_action "/lib/librc.so.1 -> $GUPPY_DIR/k1_mods/respawn/librc.so.1"

    log_ok "System symlinks installed"
}


# ════════════════════════════════════════════════════════════
# STEP 7 — KLIPPER INTEGRATION
# ════════════════════════════════════════════════════════════
step_klipper_integration() {
    log_step "7" "Install Klipper extras (modules + scripts)"

    if [ ! -d "$KLIPPY_EXTRAS" ]; then
        die "$KLIPPY_EXTRAS not found — Klipper not installed?"
    fi

    log_info "Installing GuppyScreen Klipper modules..."

    # calibrate_shaper_config.py is a hard copy (different from upstream)
    cp "$GUPPY_DIR/k1_mods/calibrate_shaper_config.py" "$KLIPPY_EXTRAS/"
    log_action "Copied: calibrate_shaper_config.py"

    # The other modules are linked (so update.sh can refresh them)
    ln -sf "$GUPPY_DIR/k1_mods/guppy_module_loader.py" "$KLIPPY_EXTRAS/guppy_module_loader.py"
    log_action "Linked: guppy_module_loader.py"

    ln -sf "$GUPPY_DIR/k1_mods/guppy_config_helper.py" "$KLIPPY_EXTRAS/guppy_config_helper.py"
    log_action "Linked: guppy_config_helper.py"

    ln -sf "$GUPPY_DIR/k1_mods/tmcstatus.py" "$KLIPPY_EXTRAS/tmcstatus.py"
    log_action "Linked: tmcstatus.py"

    log_ok "Klipper extras installed"
}


# ════════════════════════════════════════════════════════════
# STEP 8 — CONFIG FILES (GuppyScreen *.cfg + scripts)
# ════════════════════════════════════════════════════════════
step_config_files() {
    log_step "8" "Install GuppyScreen config files"

    mkdir -p "$GUPPY_CONFIG_DIR/scripts"

    if [ -d "$GUPPY_DIR/scripts" ]; then
        # Copy *.cfg files (top-level)
        if ls "$GUPPY_DIR/scripts/"*.cfg >/dev/null 2>&1; then
            cp "$GUPPY_DIR/scripts/"*.cfg "$GUPPY_CONFIG_DIR/" 2>/dev/null || true
            log_action "Copied *.cfg files to $GUPPY_CONFIG_DIR/"
        fi

        # Copy *.py files into scripts/ subdirectory
        if ls "$GUPPY_DIR/scripts/"*.py >/dev/null 2>&1; then
            cp "$GUPPY_DIR/scripts/"*.py "$GUPPY_CONFIG_DIR/scripts/" 2>/dev/null || true
            log_action "Copied *.py files to $GUPPY_CONFIG_DIR/scripts/"
        fi
    fi

    # Verify printer.cfg includes GuppyScreen — should already be there from
    # E5M-CK config but let's check.
    if [ -f "$CONFIG_DIR/printer.cfg" ]; then
        if grep -q "include GuppyScreen" "$CONFIG_DIR/printer.cfg" 2>/dev/null; then
            log_action "printer.cfg already includes GuppyScreen — good"
        else
            log_warn "printer.cfg does NOT include GuppyScreen cfgs"
            log_warn "Adding [include GuppyScreen/*.cfg] now..."
            # Insert after [include gcode_macro.cfg] if it exists, else at top
            if grep -q "include gcode_macro.cfg" "$CONFIG_DIR/printer.cfg"; then
                sed -i '/\[include gcode_macro\.cfg\]/a [include GuppyScreen/*.cfg]' \
                    "$CONFIG_DIR/printer.cfg"
            else
                # Prepend at top of file (safer than appending)
                sed -i '1i [include GuppyScreen/*.cfg]' "$CONFIG_DIR/printer.cfg"
            fi
            log_action "Added [include GuppyScreen/*.cfg] to printer.cfg"
        fi
    fi

    # USB symlink for Fluidd to see USB drives in gcode list
    if [ -d "$GCODES_DIR" ] && [ ! -L "$GCODES_DIR/usb" ]; then
        ln -sf /tmp/udisk "$GCODES_DIR/usb"
        log_action "Linked $GCODES_DIR/usb -> /tmp/udisk"
    fi

    log_ok "Config files installed"
}


# ════════════════════════════════════════════════════════════
# STEP 9 — INSTALL S99guppyscreen + S50dropbear (with backup)
# ════════════════════════════════════════════════════════════
step_install_services() {
    log_step "9" "Install init.d services (S99guppyscreen + S50dropbear)"

    mkdir -p "$BACKUP_DIR"

    # ─── BACKUP ORIGINAL FILES (FULL mode only, idempotent) ───
    if [ "$INSTALL_MODE" = "FULL" ]; then
        if [ ! -f "$BACKUP_DIR/S50dropbear" ] && [ -f "$DROPBEAR_SERVICE" ]; then
            cp "$DROPBEAR_SERVICE" "$BACKUP_DIR/S50dropbear"
            log_action "Backed up: $DROPBEAR_SERVICE -> $BACKUP_DIR/S50dropbear"
        fi
        if [ ! -f "$BACKUP_DIR/S99start_app" ] && [ -f /etc/init.d/S99start_app ]; then
            cp /etc/init.d/S99start_app "$BACKUP_DIR/S99start_app"
            log_action "Backed up: S99start_app -> $BACKUP_DIR/S99start_app"
        fi
        if [ ! -f "$BACKUP_DIR/S12boot_display" ] && [ -f /etc/init.d/S12boot_display ]; then
            mv /etc/init.d/S12boot_display "$BACKUP_DIR/S12boot_display"
            log_action "Moved (boot splash): S12boot_display -> $BACKUP_DIR/"
        fi
    fi

    # ─── INSTALL S50dropbear (modified to start SSH before display) ───
    log_info "Replacing S50dropbear with GuppyScreen-modified version..."
    log_warn "This is critical — SSH must keep working after reboot"
    if [ ! -f "$GUPPY_DIR/k1_mods/S50dropbear" ]; then
        die "S50dropbear not found in tarball"
    fi
    cp "$GUPPY_DIR/k1_mods/S50dropbear" "$DROPBEAR_SERVICE"
    chmod +x "$DROPBEAR_SERVICE"
    log_action "Installed: $DROPBEAR_SERVICE"

    # ─── INSTALL S99guppyscreen ───
    log_info "Installing S99guppyscreen..."
    if [ ! -f "$GUPPY_DIR/k1_mods/S99guppyscreen" ]; then
        die "S99guppyscreen not found in tarball"
    fi
    cp "$GUPPY_DIR/k1_mods/S99guppyscreen" "$GUPPY_SERVICE"
    chmod +x "$GUPPY_SERVICE"
    log_action "Installed: $GUPPY_SERVICE"

    log_ok "Services installed"
}


# ════════════════════════════════════════════════════════════
# STEP 10 — RESTART KLIPPER (load new extras)
# ════════════════════════════════════════════════════════════
step_restart_klipper() {
    log_step "10" "Restart Klipper to load GuppyScreen extras"

    log_info "Restarting Klipper service..."
    "$KLIPPER_SERVICE" restart 2>&1 | while read line; do log_action "$line"; done || true

    log_info "Waiting for Klipper to be ready (up to 30s)..."
    READY=0
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        sleep 2
        STATE=$(wget --no-check-certificate -q -O - "http://localhost:7125/printer/info" 2>/dev/null | \
                grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
        if [ "$STATE" = "ready" ]; then
            READY=1
            break
        fi
        log_action "State: ${STATE:-?} (waiting... $((i*2))s/30s)"
    done

    if [ "$READY" -eq 1 ]; then
        log_ok "Klipper is ready"
    else
        log_warn "Klipper did not reach 'ready' state in 30s"
        log_warn "Check $PRINTER_DATA/logs/klippy.log — GuppyScreen modules may have errors"
        log_warn "Continuing anyway"
    fi
}


# ════════════════════════════════════════════════════════════
# STEP 11 — START GUPPYSCREEN
# ════════════════════════════════════════════════════════════

# Helper: detect if guppyscreen binary is running (not the supervise-daemon)
# Returns the PID of the actual binary, or empty string if not running.
guppy_pid() {
    # Match the binary path exactly. supervise-daemon has the same string in
    # its argv but is at a different position; we filter it out by excluding
    # "supervise-daemon" from the matching command line.
    ps 2>/dev/null | grep "/usr/data/guppyscreen/guppyscreen" | \
        grep -v supervise-daemon | grep -v grep | \
        awk '{print $1}' | head -1
}

step_start_guppy() {
    log_step "11" "Start GuppyScreen"

    log_info "Starting S99guppyscreen..."
    "$GUPPY_SERVICE" start 2>&1 | while read line; do log_action "$line"; done || true

    log_info "Waiting for GuppyScreen to be running (up to 20s)..."
    GUPPY_OK=0
    for i in 1 2 3 4 5 6 7 8 9 10; do
        sleep 2
        PID=$(guppy_pid)
        if [ -n "$PID" ]; then
            GUPPY_OK=1
            break
        fi
        log_action "Waiting... ($((i*2))s/20s)"
    done

    if [ "$GUPPY_OK" -eq 1 ]; then
        log_ok "GuppyScreen is running (pid: $PID)"
    else
        log_error "GuppyScreen did not appear within 20s"
        log_warn "Check logs and configuration:"
        log_warn "  tail -30 $PRINTER_DATA/logs/guppyscreen.log"
        log_warn "  cd $GUPPY_DIR && ./guppyscreen   # manual launch"
        log_warn "Continuing the install — you can debug after."
    fi
}


# ════════════════════════════════════════════════════════════
# STEP 12 — DISABLE CREALITY SERVICES (optional)
# ════════════════════════════════════════════════════════════

# Processes to kill in FULL disable mode. These are all spawned by
# /etc/init.d/S99start_app and are unnecessary once GuppyScreen + Moonraker
# + Klipper take over. Network-related daemons (wpa_supplicant, ifplugd,
# dropbear, mdns) are NOT in this list — they are needed for connectivity.
CREALITY_PROCS="master-server app-server display-server Monitor audio-server upgrade-server log_main cx_ai_middleware webrtc"

# Kill a list of processes, with a retry pass if any survive.
kill_processes() {
    KILLED=0
    for proc in $1; do
        if pgrep -x "$proc" >/dev/null 2>&1; then
            killall -9 "$proc" 2>/dev/null
            KILLED=$((KILLED + 1))
            log_action "Sent SIGKILL to $proc"
        fi
    done

    if [ "$KILLED" -gt 0 ]; then
        sleep 2
        # Retry pass for stubborn ones
        for proc in $1; do
            if pgrep -x "$proc" >/dev/null 2>&1; then
                log_warn "$proc still alive after first kill — retrying with pkill -9 -f"
                pkill -9 -f "$proc" 2>/dev/null
            fi
        done
        sleep 1
    fi

    # Final report
    SURVIVORS=""
    for proc in $1; do
        if pgrep -x "$proc" >/dev/null 2>&1; then
            SURVIVORS="$SURVIVORS $proc"
        fi
    done
    if [ -n "$SURVIVORS" ]; then
        log_warn "These processes survived all kill attempts:$SURVIVORS"
        log_warn "(They may be respawned by a watchdog. Reboot will fix it.)"
    fi
}

step_disable_creality() {
    log_step "12" "Disable Creality services (optional)"

    if [ "$INSTALL_MODE" = "UPDATE" ]; then
        log_info "Skipping in UPDATE mode (already configured during initial install)"
        return 0
    fi

    p ""
    p "  ${WHITE}You can now disable Creality services to free up resources.${NC}"
    p ""
    p "  ${BR_GREEN}${BOLD}Pros (disable):${NC}"
    p "    ${WHITE}• Frees ~50-80 MB RAM and CPU cycles${NC}"
    p "    ${WHITE}• GuppyScreen runs more smoothly${NC}"
    p "    ${WHITE}• Removes 'shakehands' spam in klippy.log (master-server gone)${NC}"
    p "    ${WHITE}• Removes Creality cloud telemetry${NC}"
    p ""
    p "  ${YELLOW}${BOLD}Cons (disable):${NC}"
    p "    ${WHITE}• Creality Cloud / Creality Slicer no longer work${NC}"
    p "    ${WHITE}• Loses Creality firmware updates ability${NC}"
    p ""
    p "  ${DIM}Note: this is REVERSIBLE — files are backed up to $BACKUP_DIR${NC}"
    p "  ${DIM}Network (wifi/ssh) is NOT touched.${NC}"
    p ""

    if confirm "Disable all Creality services?"; then
        log_info "Disabling Creality services..."

        # Kill running processes (with retry)
        kill_processes "$CREALITY_PROCS"

        # Remove S99start_app (already backed up in step 9)
        if [ -f /etc/init.d/S99start_app ]; then
            rm -f /etc/init.d/S99start_app
            log_action "Removed: /etc/init.d/S99start_app"
        fi

        log_ok "Creality services FULLY disabled"
        log_action "Backup at $BACKUP_DIR — restore via: cp $BACKUP_DIR/S99start_app /etc/init.d/"
    else
        log_info "Keeping Creality services (minimal mode)"
        log_info "Disabling only Monitor + display-server (framebuffer conflict)"

        # Disable just the binaries that conflict with GuppyScreen
        # (display-server holds the framebuffer)
        if [ -x /usr/bin/Monitor ] && [ ! -e /usr/bin/Monitor.disable ]; then
            mv /usr/bin/Monitor /usr/bin/Monitor.disable
            log_action "Disabled: /usr/bin/Monitor -> .disable"
        fi
        if [ -x /usr/bin/display-server ] && [ ! -e /usr/bin/display-server.disable ]; then
            mv /usr/bin/display-server /usr/bin/display-server.disable
            log_action "Disabled: /usr/bin/display-server -> .disable"
        fi

        # Kill the running ones (already-spawned won't relaunch since
        # the binary is renamed, but they will linger until killed)
        kill_processes "Monitor display-server"

        log_ok "Minimal Creality disable done"
        log_action "Restore via: mv /usr/bin/Monitor.disable /usr/bin/Monitor (etc.)"
    fi
}


# ════════════════════════════════════════════════════════════
# STEP 13 — MARK INSTALLED
# ════════════════════════════════════════════════════════════
step_mark_installed() {
    log_step "13" "Mark install as complete"

    touch "$GUPPY_INSTALLED_FLAG"
    echo "$LATEST_VERSION" > "$GUPPY_VERSION_FILE"
    log_action "Flag: $GUPPY_INSTALLED_FLAG"
    log_action "Version: $LATEST_VERSION (saved to $GUPPY_VERSION_FILE)"

    log_ok "Install marked complete"
}


# ════════════════════════════════════════════════════════════
# STEP 14 — CLEANUP
# ════════════════════════════════════════════════════════════
step_cleanup() {
    log_step "14" "Cleanup temp files"

    if [ -f "$TARBALL_LOCAL" ]; then
        rm -f "$TARBALL_LOCAL"
        log_action "Removed $TARBALL_LOCAL"
    fi

    # Cleanup any leftover guppy_inspection from manual debugging
    rm -rf "$TMP_DIR/guppy_inspection" 2>/dev/null || true

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
    p "${BR_RED}  ║${NC}    ${BG_RED}${WHITE}${BOLD}  ✓  GUPPYSCREEN INSTALL/UPDATE COMPLETE  ${NC}                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Mode:${NC}            ${BOLD}$INSTALL_MODE${NC}                                       ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Version:${NC}         ${BOLD}$LATEST_VERSION${NC}                                ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Asset:${NC}           $ASSET_NAME.tar.gz                          ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Screen:${NC}          ${SCREEN_X} x ${SCREEN_Y} px                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Binary:${NC}          /usr/data/guppyscreen/guppyscreen                ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Service:${NC}         /etc/init.d/S99guppyscreen                       ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${YELLOW}NEXT:${NC}                                                          ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}      ${DIM}- Look at the touchscreen — GuppyScreen UI should be there${NC}    ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}      ${DIM}- Adjust theme: edit /usr/data/guppyscreen/guppyconfig.json${NC}   ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}      ${DIM}- Future updates: just run this script again${NC}                 ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ╚══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
    p "  ${WHITE}Fluidd:${NC}  ${UNDER}${WHITE}http://${IP}:4408${NC}"
    p ""
}


# ════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════
main() {
    show_banner
    show_disclaimer

    if ! confirm "Continue with GuppyScreen installation?"; then
        log_warn "Cancelled by user"
        exit 0
    fi

    step_precheck
    step_detect_mode
    step_stop_guppy
    step_download
    step_extract
    step_system_symlinks
    step_klipper_integration
    step_config_files
    step_install_services
    step_restart_klipper
    step_start_guppy
    step_disable_creality
    step_mark_installed
    step_cleanup
    show_completion
}

main "$@"
