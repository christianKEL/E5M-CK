#!/bin/sh
# ============================================================
# E5M-CK Installation Script
# Klipper Mainline + BTT Eddy USB + GuppyScreen
# Creality Ender 5 Max — Nebula Pad
# https://github.com/christianKEL/E5M-CK
# ============================================================

GITHUB_RAW="https://raw.githubusercontent.com/christianKEL/E5M-CK/main"
E5M_DIR="/usr/data/E5M_CK"
SAVE_DIR="$E5M_DIR/ORIGINAL_SAVE"
CONFIG_DIR="/usr/data/printer_data/config"
CONFIG_E5M_CK="/usr/data/printer_data/config_E5M_CK"
CONFIG_CREALITY_BAK="/usr/data/printer_data/config_creality_BAK"
KLIPPER_SERVICE="/etc/init.d/S55klipper_service"
MOONRAKER_SERVICE="/etc/init.d/S56moonraker_service"
MOONRAKER_API="http://localhost:7125"
HELPER_SCRIPT_FOLDER="/usr/data/helper-script"

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

# Kept minimal color helpers — internally we still need a few signals
GREEN='\033[0;32m'    # for OK markers only
BR_GREEN='\033[1;32m'
YELLOW='\033[1;33m'

# ─── printf wrapper (safe %b format, no % interpretation issues) ───
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
    p "${WHITE}        Klipper Mainline + BTT Eddy USB + GuppyScreen${NC}"
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
    p "  ${WHITE}I am not responsible for ANYTHING that happens to your printer,${NC}"
    p "  ${WHITE}your Nebula Pad, your house, your cat, or your sanity.${NC}"
    p ""
    p "  ${WHITE}Everyone using this installer is assumed to have a brain and${NC}"
    p "  ${WHITE}the ability to figure things out on their own.${NC}"
    p ""
    p "  ${WHITE}I do not know what happens if services installed here are${NC}"
    p "  ${WHITE}updated by the Update Manager. Use at your own risk.${NC}"
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

# ─── PREREQUISITES MESSAGE ───
show_prerequisites() {
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${WHITE}${BOLD}PREREQUISITES${NC}                                                   ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}1.${NC} ${BOLD}Factory reset${NC} of the Nebula Pad must be done"
    p "     ${GRAY}Create empty file 'factory_reset' (no extension) on FAT32 USB${NC}"
    p "     ${GRAY}Insert USB, power off/on the Nebula, wait 2-3 minutes${NC}"
    p ""
    p "  ${WHITE}2.${NC} ${BOLD}BTT Eddy USB${NC} probe required"
    p "     ${DIM}https://biqu.equipment/products/bigtreetech-eddy${NC}"
    p ""
    p "  ${WHITE}3.${NC} ${BOLD}Internet connection${NC} on the Nebula (WiFi or Ethernet)"
    p ""
    p "  ${WHITE}4.${NC} ${BOLD}Root SSH access${NC} to the Nebula"
    p ""
}

# ─── MENU MAIN ───
show_main_menu() {
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${WHITE}${BOLD}INSTALLATION MODE${NC}                                               ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${BG_RED}${WHITE}${BOLD} 1 ${NC}  ${WHITE}${BOLD}Full automatic installation${NC} ${GRAY}(recommended)${NC}"
    p "       ${DIM}Runs all steps 0 through 9 sequentially${NC}"
    p ""
    p "  ${BG_RED}${WHITE}${BOLD} 2 ${NC}  ${WHITE}${BOLD}Manual step-by-step installation${NC}"
    p "       ${DIM}Choose individual steps to run${NC}"
    p ""
    p "  ${BG_BLACK}${WHITE} q ${NC}  ${GRAY}Quit${NC}"
    p ""
    printf "  ${WHITE}Your choice [1/2/q]: ${NC}"
    read MAIN_CHOICE
}

# ─── MENU STEPS ───
show_steps_menu() {
    clear
    show_banner
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${WHITE}${BOLD}MANUAL INSTALLATION — Choose a step${NC}                             ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${BG_RED}${WHITE} 0 ${NC}  Clone Creality Helper Script"
    p "  ${BG_RED}${WHITE} 1 ${NC}  Install Moonraker, Nginx, Fluidd, Gcode Shell Command"
    p "  ${BG_RED}${WHITE} 2 ${NC}  Install GuppyScreen"
    p "  ${BG_RED}${WHITE} 3 ${NC}  Save original Creality config"
    p "  ${BG_RED}${WHITE} 4 ${NC}  Patch Creality servers (app-server, master-server)"
    p "  ${BG_RED}${WHITE} 5 ${NC}  Install Klipper mainline"
    p "  ${BG_RED}${WHITE} 6 ${NC}  Create E5M-CK config files"
    p "  ${BG_RED}${WHITE} 7 ${NC}  Configure GuppyScreen UI (theme, macros, Z axis)"
    p "  ${BG_RED}${WHITE} 8 ${NC}  Flash BTT Eddy USB firmware"
    p "  ${BG_RED}${WHITE} 9 ${NC}  Start Klipper mainline + GuppyScreen"
    p ""
    p "  ${BG_BLACK}${WHITE} a ${NC}  Run all steps (full auto)"
    p "  ${BG_BLACK}${WHITE} q ${NC}  Quit"
    p ""
    printf "  ${WHITE}Your choice [0-9/a/q]: ${NC}"
    read STEP_CHOICE
}

# ─── PAUSE UTILITY ───
pause_user() {
    p ""
    printf "  ${YELLOW}>${NC} ${WHITE}$1${NC}"
    read DUMMY
}

die() { log_error "$1"; exit 1; }

# ─── STEP 0 — CLONE HELPER SCRIPT ───
step0_clone_helper() {
    log_step "0" "Cloning Creality Helper Script (Guilouz)"

    if [ -d "$HELPER_SCRIPT_FOLDER/.git" ]; then
        log_info "Helper Script already present - updating..."
        cd $HELPER_SCRIPT_FOLDER
        git pull 2>&1 | while read line; do log_action "$line"; done
    else
        log_info "Cloning from github.com/Guilouz/Creality-Helper-Script..."
        rm -rf $HELPER_SCRIPT_FOLDER
        git clone --depth 1 https://github.com/Guilouz/Creality-Helper-Script.git \
            $HELPER_SCRIPT_FOLDER 2>&1 | \
            grep -E "Receiving|Resolving|Updating" | while read line; do log_action "$line"; done
        [ ! -d "$HELPER_SCRIPT_FOLDER/scripts" ] && die "Failed to clone Helper Script"
    fi
    log_ok "Helper Script ready at $HELPER_SCRIPT_FOLDER"
}

# ─── HELPER SCRIPT SOURCING ───
source_helper_script() {
    export HELPER_SCRIPT_FOLDER
    cd $HELPER_SCRIPT_FOLDER
    for f in scripts/*.sh scripts/menu/*.sh scripts/menu/E5M/*.sh; do
        . "$f" 2>/dev/null || true
    done
    set_paths 2>/dev/null || true
}

# ─── STEP 1 — INSTALL MOONRAKER + NGINX + FLUIDD + GCODE SHELL ───
step1_helper_base() {
    log_step "1" "Installing Moonraker, Nginx, Fluidd, Gcode Shell Command"

    log_info "Sourcing Helper Script functions..."
    source_helper_script

    log_info "Installing ${BOLD}Moonraker + Nginx${NC}..."
    log_action "Extracting moonraker.tar.gz + nginx.tar.gz"
    log_action "Setting up S56moonraker_service + S50nginx services"
    (echo "y" | install_moonraker_nginx 2>&1 | grep -E "Info:|Extract|Copy|error" | \
        while read line; do log_action "$line"; done) || true
    log_ok "Moonraker + Nginx installed"

    log_info "Installing ${BOLD}Fluidd${NC} (web UI on port 4408)..."
    (echo "y" | install_fluidd 2>&1 | grep -E "Info:|Downloading|error" | \
        while read line; do log_action "$line"; done) || true
    log_ok "Fluidd installed"

    log_info "Installing ${BOLD}Klipper Gcode Shell Command${NC}..."
    (echo "y" | install_gcode_shell_command 2>&1 | grep -E "Info:|Copy|error" | \
        while read line; do log_action "$line"; done) || true
    log_ok "Klipper Gcode Shell Command installed"

    log_ok "Base Helper Script components installed"
}

# ─── STEP 2 — INSTALL GUPPYSCREEN ───
step2_helper_guppy() {
    log_step "2" "Installing GuppyScreen (touch UI)"

    log_info "Sourcing Helper Script functions..."
    source_helper_script

    log_info "Preparing answer file for non-interactive install..."
    cat > /tmp/guppy_answers.txt << 'ANSEOF'
y
release
n
ANSEOF
    log_action "Answers: install=y, build=release, disable_creality=n"

    log_info "Downloading and installing ${BOLD}GuppyScreen${NC}..."
    (install_guppy_screen < /tmp/guppy_answers.txt 2>&1 | \
        grep -E "Info:|Downloading|Installing|Backing|error" | \
        while read line; do log_action "$line"; done) || true

    log_info "Finalizing GuppyScreen installation..."

    if [ ! -f /etc/init.d/S99guppyscreen ]; then
        log_action "Copying S99guppyscreen service..."
        cp /usr/data/guppyscreen/k1_mods/S99guppyscreen /etc/init.d/S99guppyscreen
        chmod +x /etc/init.d/S99guppyscreen
    fi

    if [ ! -f /usr/data/guppyscreen/guppyconfig.json ]; then
        log_action "Creating guppyconfig.json from default..."
        cp /usr/data/guppyscreen/debian/guppyconfig.json \
           /usr/data/guppyscreen/guppyconfig.json
    fi

    if [ ! -L /lib/libeinfo.so.1 ]; then
        log_action "Creating libeinfo.so.1 symlink..."
        ln -sf /usr/data/guppyscreen/k1_mods/respawn/libeinfo.so.1 /lib/libeinfo.so.1
    fi
    if [ ! -L /lib/librc.so.1 ]; then
        log_action "Creating librc.so.1 symlink..."
        ln -sf /usr/data/guppyscreen/k1_mods/respawn/librc.so.1 /lib/librc.so.1
    fi

    log_ok "GuppyScreen installed and ready to start"
}

# ─── STEP 3 — SAVE ORIGINAL CREALITY CONFIG ───
step3_save_original() {
    log_step "3" "Saving original Creality config"
    log_info "Creating backup directory: ${BOLD}${SAVE_DIR}${NC}"
    mkdir -p $SAVE_DIR

    log_info "Copying original config files..."
    for f in printer.cfg gcode_macro.cfg printer_params.cfg sensorless.cfg; do
        if [ -f "$CONFIG_DIR/$f" ]; then
            cp "$CONFIG_DIR/$f" "$SAVE_DIR/${f%.cfg}_creality_ORIGINAL.cfg"
            log_action "Saved: ${f%.cfg}_creality_ORIGINAL.cfg"
        fi
    done
    log_ok "Original Creality config saved (safe rollback point)"
}

# ─── STEP 4 — PATCH CREALITY SERVERS ───
step4_patch_servers() {
    log_step "4" "Patching Creality servers"
    p ""
    p "                    ${BG_RED}${WHITE}${BOLD}  CR*ALITY S*CKS  ${NC}"
    p ""
    log_info "These patches prevent Creality from interfering with Klipper mainline"

    log_action "Stopping running server processes..."
    killall app-server 2>/dev/null
    killall master-server 2>/dev/null
    sleep 2

    log_info "Creating server backups (first run only)..."
    if [ ! -f /usr/bin/app-server.orig ]; then
        cp /usr/bin/app-server /usr/bin/app-server.orig
        log_action "Backup: /usr/bin/app-server.orig"
    fi
    if [ ! -f /usr/bin/master-server.orig ]; then
        cp /usr/bin/master-server /usr/bin/master-server.orig
        log_action "Backup: /usr/bin/master-server.orig"
    fi

    log_info "Patching ${BOLD}app-server${NC} (disable klippy socket connection)..."
    python3 << 'PY' | while read line; do log_action "$line"; done
path = "/usr/bin/app-server"
old = b"/tmp/klippy_uds"
new = b"/tmp/klippy_udx"
with open(path, "rb") as f:
    data = f.read()
if old in data:
    data = data.replace(old, new)
    open(path, "wb").write(data)
    print("Replaced /tmp/klippy_uds with /tmp/klippy_udx")
else:
    print("Already patched or pattern not found")
PY

    log_info "Patching ${BOLD}master-server${NC} (disable bed heater interference)..."
    python3 << 'PY' | while read line; do log_action "$line"; done
path = "/usr/bin/master-server"
old = b"SET_HEATER_TEMPERATURE HEATER=heater_bed"
new = b"NOP_HEATER_TEMPERATURE HEATER=heater_bed"
with open(path, "rb") as f:
    data = f.read()
count = data.count(old)
if count > 0:
    data = data.replace(old, new)
    open(path, "wb").write(data)
    print(f"Replaced {count} SET_HEATER_TEMPERATURE calls")
else:
    print("Already patched or pattern not found")
PY

    chmod +x /usr/bin/app-server /usr/bin/master-server
    log_ok "Creality servers neutralized successfully"
}

# ─── STEP 5 — INSTALL KLIPPER MAINLINE ───
step5_install_klipper() {
    log_step "5" "Installing Klipper mainline"

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
    [ -d /usr/data/klipper ] && rm -rf /usr/data/klipper
    git clone https://github.com/Klipper3d/klipper.git /usr/data/klipper 2>&1 | \
        grep -E "Receiving|Resolving|Updating" | while read line; do log_action "$line"; done
    [ ! -d /usr/data/klipper/klippy ] && die "Failed to clone Klipper"

    KLIPPER_VER=$(cd /usr/data/klipper && git log -1 --format="%h" 2>/dev/null)
    log_ok "Klipper mainline cloned (commit: ${BOLD}$KLIPPER_VER${NC})"

    log_info "Installing c_helper.so into Klipper..."
    cp $E5M_DIR/c_helper.so /usr/data/klipper/klippy/chelper/c_helper.so
    log_action "c_helper.so -> /usr/data/klipper/klippy/chelper/"

    log_info "Copying Creality extras to Klipper mainline..."
    cp /usr/share/klipper/klippy/extras/gcode_shell_command.py /usr/data/klipper/klippy/extras/
    log_action "gcode_shell_command.py"
    cp /usr/share/klipper/klippy/extras/custom_macro.py /usr/data/klipper/klippy/extras/
    log_action "custom_macro.py"

    log_info "Installing GuppyScreen Klipper modules..."
    cp /usr/data/guppyscreen/k1_mods/guppy_module_loader.py /usr/data/klipper/klippy/extras/
    log_action "guppy_module_loader.py"
    cp /usr/data/guppyscreen/k1_mods/calibrate_shaper_config.py /usr/data/klipper/klippy/extras/
    log_action "calibrate_shaper_config.py"
    cp /usr/data/guppyscreen/k1_mods/tmcstatus.py /usr/data/klipper/klippy/extras/
    log_action "tmcstatus.py"
    log_ok "All Klipper extras installed"

    log_info "Patching stepper.py to suppress MCU deprecated warning..."
    sed -i '105s/^/# /' /usr/data/klipper/klippy/stepper.py
    rm -f /usr/data/klipper/klippy/stepper.pyc
    log_action "Commented line 105 of stepper.py"
    log_ok "MCU deprecated warning suppressed"

    log_info "Telling Git to ignore our customizations (clean Update Manager)..."
    cd /usr/data/klipper
    git update-index --assume-unchanged klippy/stepper.py 2>/dev/null
    log_action "stepper.py marked as assume-unchanged"

    cat > /usr/data/klipper/.git/info/exclude << "GITEXCL"
klippy/extras/calibrate_shaper_config.py
klippy/extras/custom_macro.py
klippy/extras/gcode_shell_command.py
klippy/extras/guppy_module_loader.py
klippy/extras/tmcstatus.py
klippy/chelper/c_helper.so
GITEXCL
    log_action "Untracked files added to .git/info/exclude"
    log_ok "Git repo cleaned for Update Manager"

    log_info "Cleaning Helper Script dirty state..."
    cd /usr/data/helper-script
    git update-index --assume-unchanged files/guppy-screen/guppy-update.sh 2>/dev/null || true
    log_action "guppy-update.sh marked as assume-unchanged"

    log_info "Updating Klipper service to use mainline..."
    sed -i 's|PY_SCRIPT=/usr/share/klipper/klippy/klippy.py|PY_SCRIPT=/usr/data/klipper/klippy/klippy.py|' \
        $KLIPPER_SERVICE
    log_action "Service updated: $KLIPPER_SERVICE"
    log_ok "Klipper mainline installation complete"
}

# ─── STEP 6 — CREATE E5M_CK CONFIG ───
step6_create_config() {
    log_step "6" "Creating E5M-CK config"

    log_info "Creating ${BOLD}$CONFIG_E5M_CK${NC} directory..."
    mkdir -p $CONFIG_E5M_CK
    mkdir -p $CONFIG_E5M_CK/GuppyScreen

    log_info "Copying base Creality config files..."
    cp $CONFIG_DIR/printer.cfg $CONFIG_E5M_CK/printer.cfg
    log_action "printer.cfg"
    cp $CONFIG_DIR/gcode_macro.cfg $CONFIG_E5M_CK/gcode_macro.cfg
    log_action "gcode_macro.cfg"
    [ -f $CONFIG_DIR/printer_params.cfg ] && cp $CONFIG_DIR/printer_params.cfg $CONFIG_E5M_CK/
    [ -f $CONFIG_DIR/sensorless.cfg ] && cp $CONFIG_DIR/sensorless.cfg $CONFIG_E5M_CK/
    [ -f $CONFIG_DIR/moonraker.conf ] && cp $CONFIG_DIR/moonraker.conf $CONFIG_E5M_CK/

    log_info "Patching printer.cfg for Klipper mainline compatibility..."
    log_action "Commenting incompatible sections (leveling_mcu, prtouch, hx711s...)"
    log_action "Fixing deprecated parameters (CXSAVE_CONFIG, max_accel_to_decel)"
    log_action "Setting max_accel: 100000 -> 10000"
    log_action "Configuring stepper_z endstop for Eddy probe"
    log_action "Uncommenting control and pid values for heaters"

    python3 << 'PYEOF'
import re
with open('/usr/data/printer_data/config_E5M_CK/printer.cfg', 'r') as f:
    content = f.read()

sections_to_comment = [
    'mcu leveling_mcu', 'mcu rpi', 'bl24c16f', 'prtouch_v2',
    'hx711s', 'accel_chip_proxy', 'resonance_tester',
    'filter', 'dirzctl', 'temperature_sensor mcu_temp',
]
lines = content.split('\n')
result = []
in_section = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith('[') and stripped.endswith(']'):
        section = stripped[1:-1].strip()
        in_section = any(section == s for s in sections_to_comment)
    if in_section and stripped and not stripped.startswith('#'):
        result.append('#' + line)
    else:
        result.append(line)
content = '\n'.join(result)

content = content.replace('CXSAVE_CONFIG', 'SAVE_CONFIG')
content = re.sub(r'max_accel_to_decel\s*:\s*\d+', 'minimum_cruise_ratio: 0.5', content)
content = re.sub(r'max_accel\s*:\s*100000', 'max_accel: 10000', content)
content = content.replace('[include sensorless.cfg]', '#[include sensorless.cfg]')

content = re.sub(
    r'(endstop_pin: tmc2209_stepper_z:virtual_endstop)',
    r'#\1\nendstop_pin: probe:z_virtual_endstop\nhoming_retract_dist: 0',
    content
)
content = re.sub(r'^(position_endstop: 0.*)$', r'#\1', content, flags=re.MULTILINE)

content = re.sub(r'#(control\s*=\s*(?:pid|watermark))', r'\1', content)
content = re.sub(r'#(pid_kp\s*=\s*[\d.]+)', r'\1', content)
content = re.sub(r'#(pid_ki\s*=\s*[\d.]+)', r'\1', content)
content = re.sub(r'#(pid_kd\s*=\s*[\d.]+)', r'\1', content)

with open('/usr/data/printer_data/config_E5M_CK/printer.cfg', 'w') as f:
    f.write(content)
PYEOF
    log_ok "printer.cfg patched"

    log_info "Computing bed_mesh boundaries from Eddy offsets..."
    python3 << 'PYEOF'
import re
X_OFFSET = 38
Y_OFFSET = 6
SCAN_OVERSHOOT = 8
POS_MAX_X = 406
POS_MAX_Y = 401
mesh_min_x = X_OFFSET + SCAN_OVERSHOOT
mesh_min_y = Y_OFFSET
mesh_max_x = POS_MAX_X - X_OFFSET - SCAN_OVERSHOOT
mesh_max_y = POS_MAX_Y - Y_OFFSET

with open('/usr/data/printer_data/config_E5M_CK/printer.cfg', 'r') as f:
    content = f.read()

new_mesh = f"""[bed_mesh]
horizontal_move_z: 2
scan_overshoot: 8
speed: 200
mesh_min: {mesh_min_x}, {mesh_min_y}
mesh_max: {mesh_max_x}, {mesh_max_y}
probe_count: 40, 40
fade_start: 1.0
fade_end: 20
fade_target: 0
mesh_pps: 4, 4
algorithm: bicubic
bicubic_tension: 0.2
"""
content = re.sub(r'\[bed_mesh\].*?(?=\n\[)', new_mesh, content, flags=re.DOTALL)
content = re.sub(r'\[heater_bed\]', '[heater_bed]\npwm_cycle_time: 0.3', content)
with open('/usr/data/printer_data/config_E5M_CK/printer.cfg', 'w') as f:
    f.write(content)
PYEOF
    log_action "bed_mesh: mesh_min=46,6 mesh_max=360,395 (40x40 points)"
    log_action "heater_bed: pwm_cycle_time: 0.3 added"
    log_ok "Bed mesh configured"

    log_info "Adding config includes at top of printer.cfg..."
    python3 << 'PYEOF'
with open('/usr/data/printer_data/config_E5M_CK/printer.cfg', 'r') as f:
    content = f.read()
includes = """[include macros_calibration.cfg]
[include GuppyScreen/*.cfg]
[include eddy.cfg]
[include homing.cfg]
"""
if '[include eddy.cfg]' not in content:
    content = includes + content
with open('/usr/data/printer_data/config_E5M_CK/printer.cfg', 'w') as f:
    f.write(content)
PYEOF
    log_action "Added: macros_calibration.cfg, GuppyScreen/*.cfg, eddy.cfg, homing.cfg"

    log_info "Creating ${BOLD}eddy.cfg${NC} (BTT Eddy USB probe config)..."
    cat > $CONFIG_E5M_CK/eddy.cfg << 'EDDYEOF'
[mcu eddy]
serial: /dev/serial/by-id/TO_BE_FILLED_AFTER_FLASH

[temperature_sensor btt_eddy_mcu]
sensor_type: temperature_mcu
sensor_mcu: eddy
min_temp: 10
max_temp: 100

[probe_eddy_current btt_eddy]
sensor_type: ldc1612
descend_z: 3.0
i2c_mcu: eddy
i2c_bus: i2c0f
x_offset: 38
y_offset: 6

[temperature_probe btt_eddy]
sensor_type: Generic 3950
sensor_pin: eddy:gpio26
horizontal_move_z: 2
EDDYEOF
    log_action "Serial will be filled after Eddy flash"
    log_action "Offsets: x=38, y=6 (measured physically)"
    log_ok "eddy.cfg created"

    log_info "Creating ${BOLD}homing.cfg${NC} (CoreXY homing sequence)..."
    cat > $CONFIG_E5M_CK/homing.cfg << 'HOMEOF'
[homing_override]
axes: xyz
set_position_z: 0
gcode:
  G90
  {% set home_all = 'X' not in params and 'Y' not in params and 'Z' not in params %}
  G1 Z30 F600
  {% if home_all or 'X' in params or 'Y' in params %}
    G28 Y
    G1 Y400 F2400
  {% endif %}
  {% if home_all or 'X' in params %}
    G28 X
    G1 X380 F2400
  {% endif %}
  {% if home_all or 'Z' in params %}
    G0 X200 Y200 F6000
    G28 Z
    G1 Z10 F600
  {% endif %}
HOMEOF
    log_action "Sequence: Y first -> X -> Z at center (200,200)"
    log_ok "homing.cfg created"

    log_info "Creating ${BOLD}macros_calibration.cfg${NC} (calibration macros)..."
    cat > $CONFIG_E5M_CK/macros_calibration.cfg << 'MACROEOF'
# ═══════════════════════════════════════════════════════
# CALIBRATION MACROS — Ender 5 Max
# ═══════════════════════════════════════════════════════

[gcode_macro CAL_BED_Z_TILT]
description: Mechanical bed Z tilt leveling via FORCE_MOVE
gcode:
  RESPOND TYPE=command MSG="Starting mechanical bed leveling..."
  G28
  RESPOND TYPE=command MSG="Homing complete"
  G1 Z400 F300
  {% for i in range(8) %}
    {% set step = i + 1 %}
    RESPOND TYPE=command MSG="Synchronizing Z motors - step {step}/8..."
    FORCE_MOVE STEPPER=stepper_z DISTANCE=5 VELOCITY=5
  {% endfor %}
  FORCE_MOVE STEPPER=stepper_z DISTANCE=-200 VELOCITY=5
  G28
  RESPOND TYPE=command MSG="Mechanical leveling complete"

[gcode_macro CAL_BED_PID]
description: Bed PID calibration (CAL_BED_PID TEMP=80)
gcode:
  {% set temp = params.TEMP|default(65)|int %}
  RESPOND TYPE=command MSG="Starting bed PID at {temp}C..."
  PID_CALIBRATE HEATER=heater_bed TARGET={temp}
  RESPOND TYPE=command MSG="Bed PID complete - Run SAVE_CONFIG"

[gcode_macro CAL_NOZZLE_PID]
description: Nozzle PID calibration (CAL_NOZZLE_PID TEMP=250)
gcode:
  {% set temp = params.TEMP|default(220)|int %}
  RESPOND TYPE=command MSG="Starting nozzle PID at {temp}C..."
  PID_CALIBRATE HEATER=extruder TARGET={temp}
  RESPOND TYPE=command MSG="Nozzle PID complete - Run SAVE_CONFIG"

[gcode_macro CAL_EDDY_DRIVE_CURRENT]
description: Calibrate BTT Eddy drive current
gcode:
  G28 X Y
  CENTER_TOOLHEAD
  RESPOND TYPE=command MSG="SET_KINEMATIC_Z_200 then lower bed to 20mm"
  RESPOND TYPE=command MSG="Then: LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy"

[gcode_macro CAL_EDDY_MAPPING]
description: Calibrate BTT Eddy height mapping
gcode:
  G28 X Y
  CENTER_TOOLHEAD
  RESPOND TYPE=command MSG="Lower bed until nozzle touches, then:"
  RESPOND TYPE=command MSG="SET_KINEMATIC_POSITION Z=0 / G1 Z1 F300"
  RESPOND TYPE=command MSG="PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy"

[gcode_macro CAL_BED_MESH]
description: Full rapid bed mesh scan
gcode:
  G28
  BED_MESH_CLEAR
  RESPOND TYPE=command MSG="Scanning bed (40x40 points)..."
  BED_MESH_CALIBRATE METHOD=rapid_scan
  RESPOND TYPE=command MSG="Bed mesh complete - Run SAVE_CONFIG"
MACROEOF
    log_action "CAL_BED_Z_TILT, CAL_BED_PID, CAL_NOZZLE_PID"
    log_action "CAL_EDDY_DRIVE_CURRENT, CAL_EDDY_MAPPING, CAL_BED_MESH"
    log_ok "macros_calibration.cfg created"

    log_info "Creating ${BOLD}GuppyScreen/macros_guppy.cfg${NC} (UI macros)..."
    cat > $CONFIG_E5M_CK/GuppyScreen/macros_guppy.cfg << 'GUPPYEOF'
[gcode_macro SET_KINEMATIC_Z_200]
description: SET_KINEMATIC Z 200
gcode:
  SET_KINEMATIC_POSITION Z=200

[gcode_macro CENTER_TOOLHEAD]
description: Center toolhead at X=200 Y=200
gcode:
  G90
  G0 X200 Y200 F6000
GUPPYEOF
    log_ok "GuppyScreen UI macros created"

    log_info "Copying guppy_cmd.cfg from GuppyScreen installation..."
    cp /usr/data/guppyscreen/scripts/guppy_cmd.cfg \
       $CONFIG_E5M_CK/GuppyScreen/guppy_cmd.cfg 2>/dev/null || \
        log_warn "guppy_cmd.cfg not found - skipping"

    log_info "Switching config symlink: ${BOLD}config -> config_E5M_CK${NC}"
    if [ ! -L $CONFIG_DIR ]; then
        mv $CONFIG_DIR $CONFIG_CREALITY_BAK
        log_action "mv config -> config_creality_BAK"
    fi
    ln -sf $CONFIG_E5M_CK $CONFIG_DIR
    log_action "ln -sf config_E5M_CK -> config"
    log_ok "Config structure ready"

    sed -i '/config_path:.*config_E5M_CK/d' $CONFIG_E5M_CK/moonraker.conf 2>/dev/null || true
    log_ok "E5M-CK config complete"
}

# ─── STEP 7 — CONFIGURE GUPPYSCREEN ───
step7_configure_guppy() {
    log_step "7" "Configuring GuppyScreen UI"

    log_info "Setting GuppyScreen theme to ${BOLD}red${NC}..."
    python3 << 'PYEOF'
import json
with open('/usr/data/guppyscreen/guppyconfig.json', 'r') as f:
    c = json.load(f)
c['theme'] = 'red'
with open('/usr/data/guppyscreen/guppyconfig.json', 'w') as f:
    json.dump(c, f, indent=4)
PYEOF
    log_action "guppyconfig.json: theme = red"

    log_info "Configuring visible macros via Moonraker API..."
    log_action "Hidden: 36 legacy Creality macros (PRTouch, LED, M-codes...)"
    log_action "Visible: E5M-CK calibration macros"
    python3 << 'PYEOF'
import urllib.request, json
macros_hidden = [
    "ACCURATE_G28", "AUTOTUNE_SHAPERS", "BEDPID", "CANCEL_PRINT",
    "FINISH_INIT", "FIRST_FLOOR_PAUSE", "FIRST_FLOOR_PAUSE_POSITION",
    "FIRST_FLOOR_RESUME", "G29", "GREEN_LED_OFF", "GREEN_LED_ON",
    "INPUTSHAPER", "LIGHT_LED_OFF", "LIGHT_LED_ON", "LOAD_MATERIAL",
    "M106", "M107", "M204", "M205", "M600", "M900", "PAUSE",
    "PRINTER_PARAM", "PRINT_CALIBRATION_EXT", "PRINT_FINI_ZDN",
    "QUIT_MATERIAL", "RED_LED_OFF", "RED_LED_ON", "RESUME",
    "STRUCTURE_PARAM", "TUNOFFINPUTSHAPER", "YELLOW_LED_OFF",
    "YELLOW_LED_ON", "ZZ_OFFSET_TEST", "Z_OFFSET_TEST",
    "GUPPY_SHAPERS", "GUPPY_EXCITATE_AXIS_AT_FREQ",
    "GUPPY_BELTS_SHAPER_CALIBRATION"
]
macros_visible = [
    "SET_KINEMATIC_Z_200", "CENTER_TOOLHEAD",
    "CAL_BED_Z_TILT", "CAL_BED_PID", "CAL_NOZZLE_PID",
    "CAL_EDDY_DRIVE_CURRENT", "CAL_EDDY_MAPPING",
    "CAL_BED_MESH"
]
settings = {}
for m in macros_visible: settings[m] = {"hidden": False}
for m in macros_hidden:  settings[m] = {"hidden": True}
data = json.dumps({
    "namespace": "guppyscreen", "key": "macros.settings", "value": settings
}).encode()
req = urllib.request.Request("http://localhost:7125/server/database/item",
    data=data, headers={"Content-Type": "application/json"}, method="POST")
try:
    urllib.request.urlopen(req, timeout=5)
except:
    pass
PYEOF
    log_ok "Macros visibility configured"

    log_info "Inverting Z axis direction in Fluidd (Z+ moves bed down)..."
    python3 << 'PYEOF'
import urllib.request, json

# Fluidd stores UI settings per-user in browser localStorage, but also syncs
# some settings via Moonraker database namespace "fluidd"
# The correct key for invert Z controls is uiSettings.general.invertZControl
settings_combos = [
    ("fluidd", "uiSettings.general.invertZControl", True),
    ("fluidd", "uiSettings.toolhead.invertZControls", True),
    ("fluidd", "uiSettings.general.axis", {"z": {"inverted": True}}),
]
for ns, key, value in settings_combos:
    try:
        data = json.dumps({"namespace": ns, "key": key, "value": value}).encode()
        req = urllib.request.Request("http://localhost:7125/server/database/item",
            data=data, headers={"Content-Type": "application/json"}, method="POST")
        urllib.request.urlopen(req, timeout=5)
    except Exception as e:
        pass
PYEOF
    log_action "Multiple Fluidd namespaces updated for Z inversion"
    log_ok "GuppyScreen + Fluidd UI configured"
}

# ─── STEP 8 — FLASH BTT EDDY USB ───
step8_flash_eddy() {
    log_step "8" "Flashing BTT Eddy USB"

    mkdir -p $E5M_DIR
    log_info "Downloading ${BOLD}btteddy.uf2${NC} firmware..."
    wget --no-check-certificate -q \
        "$GITHUB_RAW/btteddy.uf2" \
        -O $E5M_DIR/btteddy.uf2
    [ ! -s $E5M_DIR/btteddy.uf2 ] && die "Failed to download btteddy.uf2"
    log_ok "btteddy.uf2 downloaded ($(du -h $E5M_DIR/btteddy.uf2 | cut -f1))"

    # Big action box
    p ""
    p "${BG_RED}${WHITE}${BOLD}                                                                   ${NC}"
    p "${BG_RED}${WHITE}${BOLD}   ⚠  ACTION REQUIRED — Flash BTT Eddy USB                        ${NC}"
    p "${BG_RED}${WHITE}${BOLD}                                                                   ${NC}"
    p ""
    p "  ${WHITE}Follow these steps carefully:${NC}"
    p ""
    p "  ${WHITE}${BOLD}1.${NC}  ${WHITE}Locate the ${BOLD}BOOT${NC}${WHITE} button on the BTT Eddy USB${NC}"
    p "  ${WHITE}${BOLD}2.${NC}  ${WHITE}${BOLD}Hold${NC}${WHITE} the BOOT button${NC}"
    p "  ${WHITE}${BOLD}3.${NC}  ${WHITE}${BOLD}While still holding${NC}${WHITE}, plug the USB into the Nebula${NC}"
    p "  ${WHITE}${BOLD}4.${NC}  ${WHITE}Wait ${BOLD}3 seconds${NC}${WHITE}, then release the button${NC}"
    p "  ${WHITE}${BOLD}5.${NC}  ${WHITE}The Eddy should appear as a USB mass storage${NC}"
    p ""
    pause_user "Press ENTER when the BTT Eddy is connected in BOOT mode..."

    log_info "Waiting for Eddy in BOOT mode (up to 60 seconds)..."
    TIMEOUT=60
    while [ $TIMEOUT -gt 0 ]; do
        if mount | grep -q "/tmp/udisk/sda1"; then
            log_ok "Eddy detected in BOOT mode !"
            break
        fi
        sleep 2
        TIMEOUT=$((TIMEOUT - 2))
    done

    if [ $TIMEOUT -le 0 ]; then
        log_error "Eddy not detected in BOOT mode."
        log_error "You can retry this step later with: sh /tmp/install.sh 8"
        return 1
    fi

    log_info "Flashing firmware..."
    cp $E5M_DIR/btteddy.uf2 /tmp/udisk/sda1/
    sync
    log_action "cp btteddy.uf2 -> /tmp/udisk/sda1/"
    log_ok "Firmware copied - Eddy will reboot automatically"

    log_info "Waiting for Eddy to reboot in Klipper mode..."
    sleep 15

    log_info "Looking for Eddy serial device..."
    EDDY_SERIAL=""
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        EDDY_SERIAL=$(ls /dev/serial/by-id/ 2>/dev/null | grep rp2040 | head -1)
        if [ -n "$EDDY_SERIAL" ]; then
            log_ok "Eddy serial: ${BOLD}$EDDY_SERIAL${NC}"
            break
        fi
        sleep 2
    done

    [ -z "$EDDY_SERIAL" ] && die "Eddy not detected after flash!"

    log_info "Updating eddy.cfg with detected serial..."
    sed -i "s|serial: /dev/serial/by-id/.*|serial: /dev/serial/by-id/${EDDY_SERIAL}|" \
        $CONFIG_E5M_CK/eddy.cfg
    log_action "eddy.cfg: serial = $EDDY_SERIAL"
    log_ok "BTT Eddy USB flashed and configured"
}

# ─── STEP 9 — START KLIPPER MAINLINE ───
step9_start_klipper() {
    log_step "9" "Starting services (Klipper + Moonraker + GuppyScreen)"

    # Cleanup any zombie moonraker processes and locks
    log_info "Cleaning up any zombie processes and stale locks..."
    killall -9 moonraker 2>/dev/null || true
    sleep 2
    rm -f /usr/data/moonraker/tmp/.moonraker_instance_ids.lock 2>/dev/null
    log_action "Removed moonraker lock file"

    log_info "Restarting Moonraker service..."
    $MOONRAKER_SERVICE restart 2>&1 | while read line; do log_action "$line"; done || true
    sleep 5

    log_info "Starting GuppyScreen service..."
    /etc/init.d/S99guppyscreen restart 2>&1 | while read line; do log_action "$line"; done || true
    sleep 2
    if pgrep -f guppyscreen >/dev/null; then
        log_ok "GuppyScreen is running"
    else
        log_warn "GuppyScreen not detected - will start on next boot"
    fi

    log_info "Restarting Klipper service..."
    $KLIPPER_SERVICE restart 2>&1 | while read line; do log_action "$line"; done
    log_info "Waiting for Klipper to initialize (30 seconds)..."

    for i in 1 2 3 4 5 6; do
        sleep 5
        log_action "Checking state... ($i/6)"
    done

    STATE=$(python3 -c "
import urllib.request, json
try:
    d = json.loads(urllib.request.urlopen('http://localhost:7125/printer/info').read())
    print(d['result']['state'])
except:
    print('unknown')
" 2>/dev/null)

    if [ "$STATE" = "ready" ]; then
        log_ok "Klipper mainline is ${BR_GREEN}${BOLD}READY${NC}"
    else
        log_warn "Klipper state: ${BOLD}$STATE${NC}"
        log_warn "Check logs: /usr/data/printer_data/logs/klippy.log"
    fi
}

# ─── COMPLETION MESSAGE ───
show_completion() {
    IP=$(ifconfig 2>/dev/null | grep -A1 'wlan0\|eth0' | grep 'inet ' | awk '{print $2}' | sed 's/addr://' | head -1)
    [ -z "$IP" ] && IP="<nebula-ip>"

    p ""
    p "${BR_RED}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${BG_RED}${WHITE}${BOLD}  ✓  INSTALLATION COMPLETE  ${NC}                                ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Fluidd:${NC}         ${BOLD}http://${IP}:4408${NC}                        ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Moonraker API:${NC}  ${BOLD}http://${IP}:7125${NC}                        ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${YELLOW}NEXT:${NC}  Run calibration macros from GuppyScreen or Fluidd      ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}      ${DIM}1. CAL_BED_Z_TILT${NC}                                            ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}      ${DIM}2. CAL_EDDY_DRIVE_CURRENT${NC}                                    ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}      ${DIM}3. CAL_EDDY_MAPPING + SAVE_CONFIG${NC}                            ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}      ${DIM}4. CAL_BED_MESH + SAVE_CONFIG${NC}                                ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}      ${DIM}5. CAL_BED_PID + SAVE_CONFIG${NC}                                 ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}      ${DIM}6. CAL_NOZZLE_PID + SAVE_CONFIG${NC}                              ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ╚══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
}

# ─── RUN ALL STEPS ───
run_all() {
    step0_clone_helper
    step1_helper_base
    step2_helper_guppy
    step3_save_original
    step4_patch_servers
    step5_install_klipper
    step6_create_config
    step7_configure_guppy
    step8_flash_eddy
    step9_start_klipper
    show_completion
}

# ─── RUN SINGLE STEP BY NUMBER ───
run_step() {
    case $1 in
        "0")  step0_clone_helper   ;;
        "1")  step1_helper_base    ;;
        "2")  step2_helper_guppy   ;;
        "3")  step3_save_original  ;;
        "4")  step4_patch_servers  ;;
        "5")  step5_install_klipper;;
        "6")  step6_create_config  ;;
        "7")  step7_configure_guppy;;
        "8")  step8_flash_eddy     ;;
        "9")  step9_start_klipper  ;;
        *)
            log_error "Unknown step: $1"
            return 1
            ;;
    esac
}

# ─── INTERACTIVE MENU LOOP ───
menu_loop() {
    while true; do
        show_steps_menu
        case $STEP_CHOICE in
            [0-9])
                run_step $STEP_CHOICE
                pause_user "Press ENTER to return to menu..."
                ;;
            a|A)
                run_all
                pause_user "Press ENTER to return to menu..."
                ;;
            q|Q|"")
                p ""
                p "  ${WHITE}Goodbye!${NC}"
                p ""
                exit 0
                ;;
            *)
                log_warn "Invalid choice: $STEP_CHOICE"
                sleep 2
                ;;
        esac
    done
}

# ─── MAIN ───
main() {
    # If called with a numeric argument, run that step directly (for resume)
    if [ -n "$1" ]; then
        case $1 in
            [0-9])
                show_banner
                run_step $1
                show_completion
                exit 0
                ;;
            all|ALL)
                show_banner
                run_all
                exit 0
                ;;
        esac
    fi

    # Otherwise, show interactive menu
    show_banner
    show_disclaimer
    show_prerequisites
    show_main_menu

    case $MAIN_CHOICE in
        1)
            clear
            show_banner
            run_all
            ;;
        2)
            menu_loop
            ;;
        q|Q|"")
            p ""
            p "  ${WHITE}Goodbye!${NC}"
            p ""
            exit 0
            ;;
        *)
            log_warn "Invalid choice: $MAIN_CHOICE"
            exit 1
            ;;
    esac
}

main "$@"
