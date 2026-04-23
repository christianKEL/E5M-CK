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
    p "  ${BG_RED}${WHITE}${BOLD} 3 ${NC}  ${WHITE}${BOLD}Set BTT Eddy X/Y offsets${NC} ${GRAY}(post-install)${NC}"
    p "       ${DIM}Configure offsets and recompute bed_mesh bounds${NC}"
    p ""
    p "  ${BG_BLACK}${WHITE} q ${NC}  ${GRAY}Quit${NC}"
    p ""
    printf "  ${WHITE}Your choice [1/2/3/q]: ${NC}"
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
    p "  ${BG_RED}${WHITE}10 ${NC}  Install E5M-CK user macros (load, unload, present print)"
    p ""
    p "  ${BG_BLACK}${WHITE} a ${NC}  Run all steps (full auto)"
    p "  ${BG_BLACK}${WHITE} q ${NC}  Quit"
    p ""
    printf "  ${WHITE}Your choice [0-10/a/q]: ${NC}"
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
probe_count: 25, 25
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

    log_info "Creating ${BOLD}eddy.cfg${NC} (BTT Eddy USB + homing config, aligned with BTT template)..."
    cat > $CONFIG_E5M_CK/eddy.cfg << 'EDDYEOF'
# ═══════════════════════════════════════════════════════
# BTT Eddy USB — Klipper mainline configuration
# Aligned with official BTT template (github.com/bigtreetech/Eddy)
# Adapted for Creality Ender 5 Max (400x400 bed, center 200,200)
# ═══════════════════════════════════════════════════════

[mcu eddy]
serial: /dev/serial/by-id/TO_BE_FILLED_AFTER_FLASH
restart_method: command

[temperature_sensor btt_eddy_mcu]
sensor_type: temperature_mcu
sensor_mcu: eddy
min_temp: 10
max_temp: 100

[probe_eddy_current btt_eddy]
sensor_type: ldc1612
descend_z: 2.5
i2c_mcu: eddy
i2c_bus: i2c0f
x_offset: 38
y_offset: 6

[temperature_probe btt_eddy]
sensor_type: Generic 3950
sensor_pin: eddy:gpio26
horizontal_move_z: 2

# ─── SAFE Z HOME ─────────────────────────────────────────
# Moves toolhead to bed center before probing Z
# Essential when using Eddy as Z endstop
[safe_z_home]
home_xy_position: 200, 200
z_hop: 10
z_hop_speed: 25
speed: 200

# ─── Z-OFFSET PERSISTENT STORAGE ─────────────────────────
# Allows babystepping to survive reboots
[save_variables]
filename: /usr/data/printer_data/config/variables.cfg

# ─── RESTORE PROBE OFFSET AT STARTUP ─────────────────────
[delayed_gcode RESTORE_PROBE_OFFSET]
initial_duration: 1.
gcode:
  {% set svv = printer.save_variables.variables %}
  {% if not printer["gcode_macro SET_GCODE_OFFSET"].restored %}
    SET_GCODE_VARIABLE MACRO=SET_GCODE_OFFSET VARIABLE=runtime_offset VALUE={ svv.nvm_offset|default(0) }
    SET_GCODE_VARIABLE MACRO=SET_GCODE_OFFSET VARIABLE=restored VALUE=True
  {% endif %}

# ─── APPLY PROBE Z FROM LAST MEASUREMENT ─────────────────
[gcode_macro SET_Z_FROM_PROBE]
gcode:
    {% set cf = printer.configfile.settings %}
    SET_GCODE_OFFSET_ORIG Z={printer.probe.last_z_result - cf['probe_eddy_current btt_eddy'].descend_z + printer["gcode_macro SET_GCODE_OFFSET"].runtime_offset}
    G90
    G1 Z{cf.safe_z_home.z_hop}

# ─── Z_OFFSET_APPLY_PROBE (save babystepping) ────────────
[gcode_macro Z_OFFSET_APPLY_PROBE]
rename_existing: Z_OFFSET_APPLY_PROBE_ORIG
gcode:
  SAVE_VARIABLE VARIABLE=nvm_offset VALUE={ printer["gcode_macro SET_GCODE_OFFSET"].runtime_offset }

# ─── SET_GCODE_OFFSET with runtime tracking ──────────────
[gcode_macro SET_GCODE_OFFSET]
rename_existing: SET_GCODE_OFFSET_ORIG
variable_restored: False
variable_runtime_offset: 0
gcode:
  {% if params.Z_ADJUST %}
    SET_GCODE_VARIABLE MACRO=SET_GCODE_OFFSET VARIABLE=runtime_offset VALUE={ printer["gcode_macro SET_GCODE_OFFSET"].runtime_offset + params.Z_ADJUST|float }
  {% endif %}
  {% if params.Z %}
    {% set paramList = rawparams.split() %}
    {% for i in range(paramList|length) %}
      {% if paramList[i]=="Z=0" %}
        {% set temp=paramList.pop(i) %}
        {% set temp="Z_ADJUST=" + (-printer["gcode_macro SET_GCODE_OFFSET"].runtime_offset)|string %}
        {% if paramList.append(temp) %}{% endif %}
      {% endif %}
    {% endfor %}
    {% set rawparams=paramList|join(' ') %}
    SET_GCODE_VARIABLE MACRO=SET_GCODE_OFFSET VARIABLE=runtime_offset VALUE=0
  {% endif %}
  SET_GCODE_OFFSET_ORIG { rawparams }
EDDYEOF
    log_action "Serial will be filled after Eddy flash"
    log_action "Offsets: x=38, y=6 (measured physically)"
    log_action "[safe_z_home] at 200,200 (bed center)"
    log_action "[save_variables] for persistent Z-offset"
    log_action "SET_Z_FROM_PROBE / SET_GCODE_OFFSET custom macros"
    log_ok "eddy.cfg created (BTT template aligned)"

    log_info "Creating ${BOLD}homing.cfg${NC} (CoreXY homing with Eddy probe integration)..."
    cat > $CONFIG_E5M_CK/homing.cfg << 'HOMEOF'
# ═══════════════════════════════════════════════════════
# HOMING — CoreXY sequence (Y -> X -> Z at bed center)
# Integrates BTT template SET_Z_FROM_PROBE for accurate Z
# ═══════════════════════════════════════════════════════

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
    # After G28 Z, probe the actual height and apply precise offset
    PROBE
    SET_Z_FROM_PROBE
  {% endif %}
HOMEOF
    log_action "Sequence: Y first -> X -> Z at center (200,200)"
    log_action "After G28 Z: PROBE + SET_Z_FROM_PROBE for precision"
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
description: Calibrate BTT Eddy height mapping (automated)
gcode:
  BED_MESH_CLEAR
  G28 X Y
  G90
  G1 X200 Y200 F6000
  {% if 'z' not in printer.toolhead.homed_axes %}
    SET_KINEMATIC_POSITION Z=399
  {% endif %}
  RESPOND TYPE=command MSG="Lower bed until nozzle catches paper"
  RESPOND TYPE=command MSG="Then send: PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy"
  RESPOND TYPE=command MSG="Follow TESTZ / ACCEPT workflow, then SAVE_CONFIG"

[gcode_macro CAL_BED_MESH]
description: Quick bed mesh scan (15x15 rapid_scan, ~30s)
gcode:
  RESPOND TYPE=command MSG="Quick bed mesh scan starting..."
  {% if "xyz" not in printer.toolhead.homed_axes %}
    G28
  {% endif %}
  BED_MESH_CLEAR
  RESPOND TYPE=command MSG="Scanning bed (15x15 rapid_scan)..."
  BED_MESH_CALIBRATE METHOD=rapid_scan PROBE_COUNT=15,15
  RESPOND TYPE=command MSG="Quick mesh complete - Run SAVE_CONFIG if needed"

[gcode_macro CAL_BED_MESH_PRECISE]
description: Precise bed mesh scan (25x25 method=scan, ~2min)
gcode:
  RESPOND TYPE=command MSG="Precise bed mesh scan starting..."
  RESPOND TYPE=command MSG="This will take ~2 minutes - please wait"
  {% if "xyz" not in printer.toolhead.homed_axes %}
    G28
  {% endif %}
  BED_MESH_CLEAR
  RESPOND TYPE=command MSG="Scanning bed (25x25 points with pauses)..."
  BED_MESH_CALIBRATE METHOD=scan PROBE_COUNT=25,25
  RESPOND TYPE=command MSG="Precise mesh complete - Run SAVE_CONFIG"
MACROEOF
    log_action "CAL_BED_Z_TILT, CAL_BED_PID, CAL_NOZZLE_PID"
    log_action "CAL_EDDY_DRIVE_CURRENT, CAL_EDDY_MAPPING"
    log_action "CAL_BED_MESH (15x15 quick), CAL_BED_MESH_PRECISE (25x25 precise)"
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

    log_info "Deduplicating [include] directives in printer.cfg..."
    python3 << 'PYDEDUP'
path = '/usr/data/printer_data/config_E5M_CK/printer.cfg'
with open(path) as f:
    lines = f.readlines()
seen = set()
result = []
for line in lines:
    stripped = line.strip()
    if stripped.startswith('[include ') and stripped.endswith(']'):
        if stripped in seen:
            continue
        seen.add(stripped)
    result.append(line)
with open(path, 'w') as f:
    f.writelines(result)
print(f"Kept {len(seen)} unique [include] directives")
PYDEDUP

    log_info "Removing obsolete files (sensorless.cfg, printer_params.cfg)..."
    rm -f $CONFIG_E5M_CK/sensorless.cfg
    rm -f $CONFIG_E5M_CK/printer_params.cfg
    sed -i "/include sensorless.cfg/d" $CONFIG_E5M_CK/printer.cfg
    sed -i "/include printer_params.cfg/d" $CONFIG_E5M_CK/printer.cfg
    log_action "sensorless.cfg removed (force_move already in printer.cfg)"
    log_action "printer_params.cfg removed (obsolete Creality params)"

    log_info "Replacing ${BOLD}gcode_macro.cfg${NC} with clean E5M-CK version..."
    log_action "Old file: 632 lines (Creality bloated) -> New: ~280 lines (clean)"
    log_action "Status LED system: RED/GREEN/YELLOW with auto-exclusivity"
    log_action "Panel light system: LIGHT_LED_ON/OFF"
    log_action "High-level states: LED_STATE_READY/HEATING/PRINTING/PAUSE/CANCEL/ERROR/DONE"
    log_action "Startup: yellow LED (not homed) via [delayed_gcode]"
    log_action "Standard Fluidd macros: CANCEL_PRINT, PAUSE, RESUME, M600"
    log_action "GuppyScreen aliases: LOAD_MATERIAL, QUIT_MATERIAL"

    # Backup original before replacing
    cp $CONFIG_E5M_CK/gcode_macro.cfg $E5M_DIR/gcode_macro_creality_BAK.cfg

    cat > $CONFIG_E5M_CK/gcode_macro.cfg << 'GCODEMACROEOF'
# ═══════════════════════════════════════════════════════
# E5M-CK Base Klipper/Fluidd Configuration
# Clean macros compatible with mainline Klipper
# ═══════════════════════════════════════════════════════

[virtual_sdcard]
path: /usr/data/printer_data/gcodes

[pause_resume]

[display_status]

[gcode_arcs]
resolution: 0.1


# ═══════════════════════════════════════════════════════
# LED STATUS INDICATOR
# 3 LEDs (red/green/yellow) in a single panel light
# Only one color at a time — helpers ensure exclusivity
# ═══════════════════════════════════════════════════════

[gcode_macro RED_LED_ON]
description: Turn status LED red (auto turns off green+yellow)
gcode:
  SET_PIN PIN=green_pin VALUE=0
  SET_PIN PIN=yellow_pin VALUE=0
  SET_PIN PIN=red_pin VALUE=1

[gcode_macro RED_LED_OFF]
description: Turn red LED off
gcode:
  SET_PIN PIN=red_pin VALUE=0

[gcode_macro GREEN_LED_ON]
description: Turn status LED green (auto turns off red+yellow)
gcode:
  SET_PIN PIN=red_pin VALUE=0
  SET_PIN PIN=yellow_pin VALUE=0
  SET_PIN PIN=green_pin VALUE=1

[gcode_macro GREEN_LED_OFF]
description: Turn green LED off
gcode:
  SET_PIN PIN=green_pin VALUE=0

[gcode_macro YELLOW_LED_ON]
description: Turn status LED yellow (auto turns off red+green)
gcode:
  SET_PIN PIN=red_pin VALUE=0
  SET_PIN PIN=green_pin VALUE=0
  SET_PIN PIN=yellow_pin VALUE=1

[gcode_macro YELLOW_LED_OFF]
description: Turn yellow LED off
gcode:
  SET_PIN PIN=yellow_pin VALUE=0

[gcode_macro LIGHT_LED_ON]
description: Turn bed lighting on
gcode:
  SET_PIN PIN=light_pin VALUE=1

[gcode_macro LIGHT_LED_OFF]
description: Turn bed lighting off
gcode:
  SET_PIN PIN=light_pin VALUE=0

[gcode_macro LED_STATUS_OFF]
description: Turn all status LEDs off
gcode:
  SET_PIN PIN=red_pin VALUE=0
  SET_PIN PIN=green_pin VALUE=0
  SET_PIN PIN=yellow_pin VALUE=0


# ═══════════════════════════════════════════════════════
# HIGH-LEVEL PRINTER STATE INDICATORS
# Use these in your start/end/pause/cancel gcodes
# ═══════════════════════════════════════════════════════

[gcode_macro LED_STATE_READY]
description: Printer ready (green + bed light on)
gcode:
  GREEN_LED_ON
  LIGHT_LED_ON

[gcode_macro LED_STATE_NOT_HOMED]
description: Printer not homed (yellow + bed light on)
gcode:
  YELLOW_LED_ON
  LIGHT_LED_ON

[gcode_macro LED_STATE_HEATING]
description: Heating up (yellow + bed light on)
gcode:
  YELLOW_LED_ON
  LIGHT_LED_ON

[gcode_macro LED_STATE_PRINTING]
description: Print in progress (green + bed light on)
gcode:
  GREEN_LED_ON
  LIGHT_LED_ON

[gcode_macro LED_STATE_PAUSE]
description: Print paused (yellow + bed light on)
gcode:
  YELLOW_LED_ON
  LIGHT_LED_ON

[gcode_macro LED_STATE_CANCEL]
description: Print cancelled (red + bed light off)
gcode:
  RED_LED_ON
  LIGHT_LED_OFF

[gcode_macro LED_STATE_ERROR]
description: Error (red + bed light on)
gcode:
  RED_LED_ON
  LIGHT_LED_ON

[gcode_macro LED_STATE_DONE]
description: Print finished (green + bed light off)
gcode:
  GREEN_LED_ON
  LIGHT_LED_OFF


# ═══════════════════════════════════════════════════════
# PAUSE / RESUME / CANCEL — Fluidd standard with LEDs
# ═══════════════════════════════════════════════════════

[gcode_macro CANCEL_PRINT]
description: Cancel the running print
rename_existing: CANCEL_PRINT_BASE
variable_park: True
gcode:
  {% if printer['pause_resume'].is_paused|lower == 'false' and params.PARK|default(park)|lower == 'true' %}
    _TOOLHEAD_PARK_PAUSE_CANCEL
  {% endif %}
  TURN_OFF_HEATERS
  M106 S0
  LED_STATE_CANCEL
  CANCEL_PRINT_BASE

[gcode_macro PAUSE]
description: Pause the running print
rename_existing: PAUSE_BASE
gcode:
  PAUSE_BASE
  _TOOLHEAD_PARK_PAUSE_CANCEL
  LED_STATE_PAUSE

[gcode_macro RESUME]
description: Resume the paused print
rename_existing: RESUME_BASE
gcode:
  {% set extrude = printer['gcode_macro _TOOLHEAD_PARK_PAUSE_CANCEL'].extrude %}
  {% if 'VELOCITY' in params|upper %}
    {% set get_params = ('VELOCITY=' + params.VELOCITY) %}
  {% else %}
    {% set get_params = "" %}
  {% endif %}
  {% if printer.extruder.can_extrude|lower == 'true' %}
    M83
    G1 E{extrude} F2100
    {% if printer.gcode_move.absolute_extrude|lower == 'true' %} M82 {% endif %}
  {% else %}
    {action_respond_info("Extruder not hot enough")}
  {% endif %}
  LED_STATE_PRINTING
  RESUME_BASE {get_params}

[gcode_macro _TOOLHEAD_PARK_PAUSE_CANCEL]
description: Helper - park toolhead during pause/cancel
variable_extrude: 1.0
gcode:
  {% set E = printer["gcode_macro _TOOLHEAD_PARK_PAUSE_CANCEL"].extrude|float %}
  {% set x_park = printer.toolhead.axis_maximum.x|float - 5.0 %}
  {% set y_park = printer.toolhead.axis_maximum.y|float - 5.0 %}
  {% set max_z = printer.toolhead.axis_maximum.z|float %}
  {% set act_z = printer.toolhead.position.z|float %}
  {% if act_z < (max_z - 2.0) %}
    {% set z_safe = 2.0 %}
  {% else %}
    {% set z_safe = max_z - act_z %}
  {% endif %}
  {% if printer.extruder.can_extrude|lower == 'true' %}
    M83
    G1 E-{E} F2100
    {% if printer.gcode_move.absolute_extrude|lower == 'true' %} M82 {% endif %}
  {% else %}
    {action_respond_info("Extruder not hot enough")}
  {% endif %}
  {% if "xyz" in printer.toolhead.homed_axes %}
    G91
    G1 Z{z_safe} F900
    G90
    G1 X{x_park} Y{y_park} F6000
  {% else %}
    {action_respond_info("Printer not homed")}
  {% endif %}


# ═══════════════════════════════════════════════════════
# FILAMENT CHANGE (standard M600)
# ═══════════════════════════════════════════════════════

[gcode_macro M600]
description: Filament change (standard pause + park)
gcode:
  {% set X = params.X|default(50)|float %}
  {% set Y = params.Y|default(0)|float %}
  {% set Z = params.Z|default(10)|float %}
  SAVE_GCODE_STATE NAME=M600_state
  PAUSE
  G91
  G1 E-.8 F2700
  G1 Z{Z}
  G90
  G1 X{X} Y{Y} F3000
  G91
  G1 E-50 F1000
  RESTORE_GCODE_STATE NAME=M600_state


# ═══════════════════════════════════════════════════════
# GUPPYSCREEN FILAMENT LOAD/UNLOAD
# ═══════════════════════════════════════════════════════

[gcode_macro LOAD_MATERIAL]
description: Heat up and load filament
gcode:
  {% set temp = params.TEMP|default(220)|int %}
  LED_STATE_HEATING
  M104 S{temp}
  M109 S{temp}
  G91
  G1 E50 F300
  G1 E20 F150
  G90
  LED_STATE_READY

[gcode_macro QUIT_MATERIAL]
description: Heat up and unload filament
gcode:
  {% set temp = params.TEMP|default(220)|int %}
  LED_STATE_HEATING
  M104 S{temp}
  M109 S{temp}
  G91
  G1 E20 F300
  G1 E-80 F2700
  G90
  LED_STATE_READY

# GuppyScreen aliases (internal, referenced by guppyconfig.json)

[gcode_macro _GUPPY_LOAD_MATERIAL]
gcode:
  LOAD_MATERIAL

[gcode_macro _GUPPY_QUIT_MATERIAL]
gcode:
  QUIT_MATERIAL


# ═══════════════════════════════════════════════════════
# STARTUP — set LEDs to yellow (not homed) on Klipper start
# ═══════════════════════════════════════════════════════

[delayed_gcode _STARTUP_LEDS]
initial_duration: 1
gcode:
  LED_STATE_NOT_HOMED
GCODEMACROEOF

    log_ok "gcode_macro.cfg rewritten with LED system and clean macros"

    log_ok "E5M-CK config complete (no duplicate includes)"
}

# ─── STEP 7 — CONFIGURE GUPPYSCREEN ───
step7_configure_guppy() {
    log_step "7" "Configuring GuppyScreen UI"

    log_info "Configuring GuppyScreen (theme + display sleep)..."
    python3 << 'PYEOF'
import json
with open('/usr/data/guppyscreen/guppyconfig.json', 'r') as f:
    c = json.load(f)
c['theme'] = 'red'
c['display_sleep_sec'] = -1  # -1 = never sleep
with open('/usr/data/guppyscreen/guppyconfig.json', 'w') as f:
    json.dump(c, f, indent=4)
PYEOF
    log_action "guppyconfig.json: theme = red"
    log_action "guppyconfig.json: display_sleep_sec = -1 (never)"

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
    "CAL_BED_MESH", "CAL_BED_MESH_PRECISE"
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
    log_action "Reading current Fluidd DB to ensure namespace is initialized..."
    # Ensure Fluidd namespace exists by reading it first
    curl -s -X GET "http://localhost:7125/server/database/item?namespace=fluidd" \
        >/dev/null 2>&1 || true
    sleep 1
    python3 << 'PYEOF'
import urllib.request, json

# ─── Settings to apply to Fluidd ───
fluidd_settings = [
    # Invert Z axis (Z+ moves bed down)
    ("uiSettings.general.axis", {"z": {"inverted": True}}),
    # Theme: Klipper (red)
    ("uiSettings.theme", {
        "isDark": True,
        "logo": {"src": "logo_klipper.svg"},
        "color": "#B12F36",
        "backgroundLogo": True
    }),
]

for key, value in fluidd_settings:
    try:
        data = json.dumps({
            "namespace": "fluidd",
            "key": key,
            "value": value
        }).encode()
        req = urllib.request.Request("http://localhost:7125/server/database/item",
            data=data, headers={"Content-Type": "application/json"}, method="POST")
        urllib.request.urlopen(req, timeout=5)
        print(f"Applied: {key}")
    except Exception as e:
        print(f"Error on {key}: {e}")
PYEOF
    log_action "Z axis inverted: uiSettings.general.axis.z.inverted=true"
    log_action "Theme: Klipper (red #B12F36, dark, logo=klipper)"
    log_ok "Fluidd UI configured (theme + Z axis)"
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

# ─── STEP 10 — INSTALL E5M_CK MACROS ───
step10_install_macros() {
    log_step "10" "Installing E5M-CK user macros"

    log_info "Creating ${BOLD}macros_E5M_CK.cfg${NC} in $CONFIG_E5M_CK..."

    cat > $CONFIG_E5M_CK/macros_E5M_CK.cfg << "MACROEOF"
# ═══════════════════════════════════════════════════════
# E5M-CK USER MACROS
# ═══════════════════════════════════════════════════════

# ─── FILAMENT LOAD ───
[gcode_macro GUPPY_LOAD_FILAMENT]
description: Load filament (heat nozzle + extrude)
gcode:
  {% set temp = params.TEMP|default(220)|int %}
  RESPOND TYPE=command MSG="Heating nozzle to {temp}C for filament load..."
  M109 S{temp}
  RESPOND TYPE=command MSG="Loading filament..."
  M83
  G1 E50 F300
  G1 E30 F150
  M82
  RESPOND TYPE=command MSG="Filament loaded"

# ─── FILAMENT UNLOAD ───
[gcode_macro GUPPY_UNLOAD_FILAMENT]
description: Unload filament (heat nozzle + retract)
gcode:
  {% set temp = params.TEMP|default(220)|int %}
  RESPOND TYPE=command MSG="Heating nozzle to {temp}C for filament unload..."
  M109 S{temp}
  RESPOND TYPE=command MSG="Unloading filament..."
  M83
  G1 E10 F300
  G1 E-50 F1200
  G1 E-30 F300
  M82
  RESPOND TYPE=command MSG="Filament unloaded"

# ─── PRINT END — PRESENT PRINT ───
[gcode_macro PRINT_FINI_ZDN]
description: Lower bed to present the finished print
gcode:
  {% set cur_remain = (380.0 - printer.toolhead.position.z)|float %}
  {% if (cur_remain > 0) %}
    FORCE_MOVE STEPPER=stepper_z DISTANCE={cur_remain} VELOCITY=10
  {% endif %}
MACROEOF
    log_action "GUPPY_LOAD_FILAMENT (TEMP param, default 220C)"
    log_action "GUPPY_UNLOAD_FILAMENT (TEMP param, default 220C)"
    log_action "PRINT_FINI_ZDN (presents print by lowering bed)"
    log_ok "macros_E5M_CK.cfg created"

    log_info "Adding include to printer.cfg..."
    python3 << "PYEOF"
with open("/usr/data/printer_data/config_E5M_CK/printer.cfg", "r") as f:
    content = f.read()
if "[include macros_E5M_CK.cfg]" not in content:
    # Insert after the existing includes
    if "[include macros_calibration.cfg]" in content:
        content = content.replace(
            "[include macros_calibration.cfg]",
            "[include macros_calibration.cfg]
[include macros_E5M_CK.cfg]"
        )
    else:
        content = "[include macros_E5M_CK.cfg]
" + content
    with open("/usr/data/printer_data/config_E5M_CK/printer.cfg", "w") as f:
        f.write(content)
    print("Include added")
else:
    print("Include already present")
PYEOF
    log_action "printer.cfg: [include macros_E5M_CK.cfg] added"

    log_info "Updating GuppyScreen visible macros..."
    python3 << "PYEOF"
import urllib.request, json
# Add the new macros to the visible list
new_visible = [
    "GUPPY_LOAD_FILAMENT",
    "GUPPY_UNLOAD_FILAMENT",
    "PRINT_FINI_ZDN"
]
settings = {}
for m in new_visible:
    settings[m] = {"hidden": False}
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
    log_action "GUPPY_LOAD_FILAMENT, GUPPY_UNLOAD_FILAMENT, PRINT_FINI_ZDN visible in GuppyScreen"

    log_info "Restarting Klipper to load new macros..."
    $KLIPPER_SERVICE restart 2>&1 | while read line; do log_action "$line"; done
    sleep 10
    log_ok "E5M-CK macros installed and ready"
}

# ─── STEP EXTRA — SET EDDY OFFSETS ───
step_set_eddy_offsets() {
    log_step "EDDY" "Configure BTT Eddy X/Y offsets"

    if [ ! -f "$CONFIG_E5M_CK/eddy.cfg" ]; then
        log_error "eddy.cfg not found at $CONFIG_E5M_CK/eddy.cfg"
        log_error "Run the installation first before setting offsets"
        return 1
    fi

    # Read current offsets
    CUR_X=$(grep -E "^x_offset:" $CONFIG_E5M_CK/eddy.cfg | awk -F: "{print \$2}" | tr -d " ")
    CUR_Y=$(grep -E "^y_offset:" $CONFIG_E5M_CK/eddy.cfg | awk -F: "{print \$2}" | tr -d " ")

    [ -z "$CUR_X" ] && CUR_X="0"
    [ -z "$CUR_Y" ] && CUR_Y="0"

    p ""
    p "${WHITE}Current Eddy offsets:${NC}"

    # Explain sign for X
    if [ "${CUR_X%%.*}" -lt 0 ] 2>/dev/null; then
        p "  ${BOLD}x_offset: $CUR_X${NC}  ${GRAY}(Eddy is to the LEFT of the nozzle)${NC}"
    elif [ "${CUR_X%%.*}" -gt 0 ] 2>/dev/null; then
        p "  ${BOLD}x_offset: +$CUR_X${NC}  ${GRAY}(Eddy is to the RIGHT of the nozzle)${NC}"
    else
        p "  ${BOLD}x_offset: $CUR_X${NC}  ${GRAY}(Eddy aligned with nozzle on X axis)${NC}"
    fi

    # Explain sign for Y
    if [ "${CUR_Y%%.*}" -lt 0 ] 2>/dev/null; then
        p "  ${BOLD}y_offset: $CUR_Y${NC}  ${GRAY}(Eddy is in FRONT of the nozzle)${NC}"
    elif [ "${CUR_Y%%.*}" -gt 0 ] 2>/dev/null; then
        p "  ${BOLD}y_offset: +$CUR_Y${NC}  ${GRAY}(Eddy is BEHIND the nozzle)${NC}"
    else
        p "  ${BOLD}y_offset: $CUR_Y${NC}  ${GRAY}(Eddy aligned with nozzle on Y axis)${NC}"
    fi
    p ""

    p "${WHITE}Sign convention:${NC}"
    p "  ${GRAY}X: positive = Eddy to the RIGHT, negative = LEFT${NC}"
    p "  ${GRAY}Y: positive = Eddy BEHIND, negative = in FRONT${NC}"
    p ""

    printf "  ${WHITE}New X offset in mm [${BOLD}$CUR_X${NC}${WHITE}]: ${NC}"
    read NEW_X
    [ -z "$NEW_X" ] && NEW_X="$CUR_X"

    printf "  ${WHITE}New Y offset in mm [${BOLD}$CUR_Y${NC}${WHITE}]: ${NC}"
    read NEW_Y
    [ -z "$NEW_Y" ] && NEW_Y="$CUR_Y"

    # Validate and compute mesh bounds
    VALIDATION=$(python3 << PYEOF
import sys

try:
    x_off = float("$NEW_X")
    y_off = float("$NEW_Y")
except ValueError:
    print("ERROR:Invalid number format")
    sys.exit(0)

# Validation: absolute value must be < 100 mm
if abs(x_off) >= 100:
    print(f"ERROR:X offset {x_off} out of range (-100 to +100 mm)")
    sys.exit(0)
if abs(y_off) >= 100:
    print(f"ERROR:Y offset {y_off} out of range (-100 to +100 mm)")
    sys.exit(0)

POS_MAX_X = 406
POS_MAX_Y = 401
SCAN_OVERSHOOT = 8

# Correct formula for any sign of offsets:
# Nozzle position when Eddy is at (mesh_x, mesh_y):
#   nozzle_x = mesh_x + x_offset
#   nozzle_y = mesh_y + y_offset
# Nozzle must stay in [0, POS_MAX]
# => mesh_x in [-x_offset, POS_MAX - x_offset]
# With scan_overshoot for X axis only:
mesh_min_x = max(-x_off, 0) + SCAN_OVERSHOOT
mesh_max_x = POS_MAX_X - max(x_off, 0) - SCAN_OVERSHOOT
mesh_min_y = max(-y_off, 0)
mesh_max_y = POS_MAX_Y - max(y_off, 0)

# Validate usable area
usable_x = mesh_max_x - mesh_min_x
usable_y = mesh_max_y - mesh_min_y

if usable_x < 100:
    print(f"ERROR:Usable X area too small ({usable_x}mm, min 100mm)")
    sys.exit(0)
if usable_y < 100:
    print(f"ERROR:Usable Y area too small ({usable_y}mm, min 100mm)")
    sys.exit(0)

# Return: x_off|y_off|mesh_min_x|mesh_min_y|mesh_max_x|mesh_max_y|usable_x|usable_y
print(f"OK:{x_off}|{y_off}|{mesh_min_x:.0f}|{mesh_min_y:.0f}|{mesh_max_x:.0f}|{mesh_max_y:.0f}|{usable_x:.0f}|{usable_y:.0f}")
PYEOF
)

    # Parse validation result
    STATUS=$(echo "$VALIDATION" | cut -d: -f1)
    if [ "$STATUS" = "ERROR" ]; then
        ERR_MSG=$(echo "$VALIDATION" | cut -d: -f2-)
        log_error "$ERR_MSG"
        log_error "Offsets not applied - values rejected"
        return 1
    fi

    # Parse OK values
    DATA=$(echo "$VALIDATION" | cut -d: -f2)
    V_X_OFF=$(echo "$DATA" | cut -d"|" -f1)
    V_Y_OFF=$(echo "$DATA" | cut -d"|" -f2)
    V_MIN_X=$(echo "$DATA" | cut -d"|" -f3)
    V_MIN_Y=$(echo "$DATA" | cut -d"|" -f4)
    V_MAX_X=$(echo "$DATA" | cut -d"|" -f5)
    V_MAX_Y=$(echo "$DATA" | cut -d"|" -f6)
    V_USABLE_X=$(echo "$DATA" | cut -d"|" -f7)
    V_USABLE_Y=$(echo "$DATA" | cut -d"|" -f8)

    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${WHITE}${BOLD}Calculated parameters${NC}                                          ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p "  ${WHITE}Eddy offsets:${NC}  ${BOLD}x=$V_X_OFF${NC}  ${BOLD}y=$V_Y_OFF${NC}"
    p "  ${WHITE}mesh_min:${NC}     ${BOLD}$V_MIN_X, $V_MIN_Y${NC}"
    p "  ${WHITE}mesh_max:${NC}     ${BOLD}$V_MAX_X, $V_MAX_Y${NC}"
    p "  ${WHITE}Usable area:${NC}  ${BOLD}${V_USABLE_X}mm x ${V_USABLE_Y}mm${NC}"
    p ""
    printf "  ${YELLOW}Apply these changes? [y/N]: ${NC}"
    read CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        log_warn "Cancelled by user - no changes applied"
        return 0
    fi

    # Apply eddy.cfg
    log_info "Updating eddy.cfg..."
    sed -i "s|^x_offset:.*|x_offset: $V_X_OFF|" $CONFIG_E5M_CK/eddy.cfg
    sed -i "s|^y_offset:.*|y_offset: $V_Y_OFF|" $CONFIG_E5M_CK/eddy.cfg
    log_action "eddy.cfg: x_offset = $V_X_OFF"
    log_action "eddy.cfg: y_offset = $V_Y_OFF"
    log_ok "eddy.cfg updated"

    # Apply bed_mesh in printer.cfg
    log_info "Updating [bed_mesh] in printer.cfg..."
    python3 << PYEOF
import re
path = "$CONFIG_E5M_CK/printer.cfg"
with open(path) as f:
    content = f.read()

content = re.sub(r"mesh_min:\s*[\d.]+,\s*[\d.]+", f"mesh_min: $V_MIN_X, $V_MIN_Y", content)
content = re.sub(r"mesh_max:\s*[\d.]+,\s*[\d.]+", f"mesh_max: $V_MAX_X, $V_MAX_Y", content)

with open(path, "w") as f:
    f.write(content)
print("Done")
PYEOF
    log_action "mesh_min: $V_MIN_X, $V_MIN_Y"
    log_action "mesh_max: $V_MAX_X, $V_MAX_Y"
    log_ok "printer.cfg [bed_mesh] updated"

    log_info "Restarting Klipper to apply changes..."
    $KLIPPER_SERVICE restart 2>&1 | while read line; do log_action "$line"; done
    log_info "Waiting for Klipper to reload..."
    sleep 15

    STATE=$(python3 -c "
import urllib.request, json
try:
    d = json.loads(urllib.request.urlopen('http://localhost:7125/printer/info').read())
    print(d['result']['state'])
except:
    print('unknown')
" 2>/dev/null)

    if [ "$STATE" = "ready" ]; then
        log_ok "Klipper restarted - offsets applied successfully"
    else
        log_warn "Klipper state: $STATE"
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

# ─── EDDY CALIBRATION ASSISTANT ───

# Helper : check Klipper state
_check_klipper_ready() {
    STATE=$(python3 -c "
import urllib.request, json
try:
    d = json.loads(urllib.request.urlopen('http://localhost:7125/printer/info').read())
    print(d['result']['state'])
except:
    print('unknown')
" 2>/dev/null)
    if [ "$STATE" != "ready" ]; then
        log_error "Klipper is not ready (state: $STATE)"
        log_error "Fix Klipper first before running calibration."
        return 1
    fi
    return 0
}

# Helper : get nebula IP
_get_nebula_ip() {
    IP=$(ifconfig 2>/dev/null | grep -A1 'wlan0\|eth0' | grep 'inet ' | \
         awk '{print $2}' | sed 's/addr://' | head -1)
    [ -z "$IP" ] && IP="<nebula-ip>"
    echo "$IP"
}

# Helper : query a configfile setting via Moonraker
_query_saved_config() {
    KEY=$1
    python3 -c "
import urllib.request, json
try:
    url = 'http://localhost:7125/printer/objects/query?configfile'
    d = json.loads(urllib.request.urlopen(url).read())
    settings = d['result']['status']['configfile']['settings']
    # Flatten and search for the key
    import json as j
    s = j.dumps(settings)
    if '$KEY' in s:
        print('FOUND')
    else:
        print('MISSING')
except Exception as e:
    print(f'ERROR: {e}')
" 2>/dev/null
}

# Helper : wait for user confirmation with a specific keyword
_confirm_yes() {
    MSG=$1
    printf "  ${YELLOW}${BOLD}Type ${BR_RED}YES${YELLOW} (in capitals) to confirm %s: ${NC}" "$MSG"
    read CONFIRM
    [ "$CONFIRM" = "YES" ] && return 0
    return 1
}

# Helper : pause with ENTER
_wait_enter() {
    MSG=$1
    p ""
    printf "  ${WHITE}${BOLD}>${NC} ${WHITE}%s${NC}\n  ${DIM}Press ENTER when ready...${NC} " "$MSG"
    read DUMMY
}

# ─── MAIN EDDY CALIBRATION ASSISTANT ───
eddy_calibration_assistant() {
    clear
    show_banner

    log_step "+" "BTT Eddy Calibration Assistant"

    # Check Klipper ready first
    if ! _check_klipper_ready; then
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    NEBULA_IP=$(_get_nebula_ip)

    # ═══════════════════════════════════════════════════════
    # STEP 0 — GLOBAL WARNINGS AND PREREQUISITES
    # ═══════════════════════════════════════════════════════
    clear
    p ""
    p "${BG_RED}${WHITE}${BOLD}                                                                     ${NC}"
    p "${BG_RED}${WHITE}${BOLD}   ⚠  READ CAREFULLY BEFORE PROCEEDING  ⚠                            ${NC}"
    p "${BG_RED}${WHITE}${BOLD}                                                                     ${NC}"
    p ""
    p "  ${WHITE}${BOLD}This assistant will guide you through the complete Eddy calibration${NC}"
    p "  ${WHITE}${BOLD}procedure. ${BR_RED}Incorrect use can DAMAGE your printer.${NC}"
    p ""
    p "  ${YELLOW}${BOLD}Prerequisites:${NC}"
    p "  ${WHITE}  • ${BOLD}Fluidd must be open${NC} ${WHITE}in your browser for sending G-codes${NC}"
    p "  ${WHITE}    ${UNDER}${BR_RED}http://${NEBULA_IP}:4408${NC}"
    p "  ${WHITE}  • A ${BOLD}standard A4 80gsm paper sheet${NC}${WHITE} (for the paper test)${NC}"
    p "  ${WHITE}  • The printer ${BOLD}nozzle must be clean${NC}${WHITE} (no plastic residue)${NC}"
    p "  ${WHITE}  • The ${BOLD}bed surface must be clean${NC}${WHITE} (no debris)${NC}"
    p "  ${WHITE}  • The ${BOLD}Eddy probe must be securely mounted${NC}"
    p "  ${WHITE}  • Nothing on the bed during calibration movements${NC}"
    p ""
    p "  ${BR_RED}${BOLD}SAFETY RULES:${NC}"
    p "  ${BR_RED}  ⚠  ${WHITE}Keep hands AWAY from moving parts during Z moves${NC}"
    p "  ${BR_RED}  ⚠  ${WHITE}Never run calibration with filament hanging from the nozzle${NC}"
    p "  ${BR_RED}  ⚠  ${WHITE}Be ready to press EMERGENCY STOP at any moment${NC}"
    p "  ${BR_RED}  ⚠  ${WHITE}Never skip steps - follow the exact order${NC}"
    p ""
    p "  ${WHITE}${BOLD}Calibration steps (~30-60 minutes total):${NC}"
    p "  ${WHITE}    1. Bed Z-tilt leveling${NC}"
    p "  ${WHITE}    2. Drive current calibration${NC}"
    p "  ${WHITE}    3. Height mapping calibration ${BR_RED}(most critical!)${NC}"
    p "  ${WHITE}    4. Z=0 verification (paper test)${NC}"
    p "  ${WHITE}    5. Temperature drift calibration ${DIM}(optional)${NC}"
    p "  ${WHITE}    6. Bed mesh generation${NC}"
    p ""
    p "${BG_RED}${WHITE}${BOLD}                                                                     ${NC}"
    p ""

    if ! _confirm_yes "you understand and accept these risks"; then
        log_warn "Calibration cancelled by user"
        pause_user "Press ENTER to return to menu..."
        return 0
    fi

    # ═══════════════════════════════════════════════════════
    # STEP 1 — BED Z-TILT LEVELING
    # ═══════════════════════════════════════════════════════
    clear
    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} STEP 1/6 ${NC} ${WHITE}${BOLD}Bed Z-tilt leveling${NC}                                ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}This step ensures the bed is perfectly flat relative to the gantry.${NC}"
    p "  ${WHITE}It synchronizes the Z motors using FORCE_MOVE commands.${NC}"
    p ""
    p "  ${YELLOW}${BOLD}WARNING:${NC}"
    p "  ${YELLOW}  • The bed will move to Z=400 (max height)${NC}"
    p "  ${YELLOW}  • ${BOLD}Make sure NOTHING is on the bed${NC}"
    p "  ${YELLOW}  • ${BOLD}Make sure no cables can be pinched${NC}"
    p "  ${YELLOW}  • Duration: ~1 minute${NC}"
    p ""
    p "  ${WHITE}${BOLD}Instructions:${NC}"
    p "  ${WHITE}  1. Open Fluidd: ${UNDER}${BR_RED}http://${NEBULA_IP}:4408${NC}"
    p "  ${WHITE}  2. Open the Console panel${NC}"
    p "  ${WHITE}  3. Send command: ${BOLD}${BR_GREEN}CAL_BED_Z_TILT${NC}"
    p "  ${WHITE}  4. Wait for completion (bed will level itself)${NC}"
    p ""

    if ! _confirm_yes "bed is clear and you are ready to start Step 1"; then
        log_warn "Step 1 cancelled"
        pause_user "Press ENTER to return to menu..."
        return 0
    fi

    _wait_enter "When CAL_BED_Z_TILT is complete (bed fully lowered and homed)"

    if ! _check_klipper_ready; then
        log_error "Klipper state is not ready. Check Fluidd for errors."
        pause_user "Press ENTER to return to menu..."
        return 1
    fi
    log_ok "Step 1 complete — bed is leveled"

    # ═══════════════════════════════════════════════════════
    # STEP 2 — DRIVE CURRENT CALIBRATION
    # ═══════════════════════════════════════════════════════
    clear
    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} STEP 2/6 ${NC} ${WHITE}${BOLD}Drive current calibration${NC}                          ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}This step determines the optimal signal strength for the LDC1612 chip.${NC}"
    p "  ${WHITE}The toolhead must be centered and lifted ~20mm above the bed.${NC}"
    p ""
    p "  ${YELLOW}${BOLD}WARNING:${NC}"
    p "  ${YELLOW}  • Nozzle must be ${BOLD}20mm away from the bed${NC}"
    p "  ${YELLOW}  • If too close: magnetic interference → invalid calibration${NC}"
    p "  ${YELLOW}  • If too far: insufficient signal → invalid calibration${NC}"
    p ""
    p "  ${WHITE}${BOLD}Instructions (in Fluidd console):${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}1.${NC} ${BR_GREEN}G28${NC}                              ${DIM}# home all axes${NC}"
    p "  ${WHITE}  ${BR_GREEN}${BOLD}2.${NC} ${BR_GREEN}CENTER_TOOLHEAD${NC}                  ${DIM}# move to center${NC}"
    p "  ${WHITE}  ${BR_GREEN}${BOLD}3.${NC} ${BR_GREEN}SET_KINEMATIC_Z_200${NC}              ${DIM}# trick Klipper${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}4.${NC} ${WHITE}Using Fluidd ${BOLD}Z arrows${NC}${WHITE}, move bed DOWN by ${BOLD}20mm${NC}"
    p "  ${WHITE}     ${DIM}(use large step, e.g. 10mm then 10mm)${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}5.${NC} ${BR_GREEN}LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy${NC}"
    p "  ${WHITE}     ${DIM}(takes ~30 seconds)${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}6.${NC} ${BR_GREEN}SAVE_CONFIG${NC}                      ${DIM}# Klipper will restart${NC}"
    p ""

    if ! _confirm_yes "nozzle is 20mm above bed and you are ready to start Step 2"; then
        log_warn "Step 2 cancelled"
        pause_user "Press ENTER to return to menu..."
        return 0
    fi

    _wait_enter "When SAVE_CONFIG has finished and Klipper restarted"

    log_info "Checking reg_drive_current was saved..."
    sleep 5
    if ! _check_klipper_ready; then
        log_error "Klipper not ready after SAVE_CONFIG. Check Fluidd."
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    RESULT=$(_query_saved_config "reg_drive_current")
    if [ "$RESULT" = "FOUND" ]; then
        log_ok "Step 2 complete — reg_drive_current saved successfully"
    else
        log_warn "reg_drive_current not detected in saved_config"
        log_warn "Step 2 may have failed. Continue? (y/n)"
        printf "  ${WHITE}Your choice: ${NC}"
        read CONT
        [ "$CONT" != "y" ] && [ "$CONT" != "Y" ] && return 1
    fi

    # ═══════════════════════════════════════════════════════
    # STEP 3 — HEIGHT MAPPING CALIBRATION (CRITICAL)
    # ═══════════════════════════════════════════════════════
    clear
    p ""
    p "${BG_RED}${WHITE}${BOLD}                                                                     ${NC}"
    p "${BG_RED}${WHITE}${BOLD}   ⚠  STEP 3/6 — MOST CRITICAL STEP — READ CAREFULLY  ⚠              ${NC}"
    p "${BG_RED}${WHITE}${BOLD}                                                                     ${NC}"
    p ""
    p "  ${WHITE}This step maps sensor readings to actual Z heights.${NC}"
    p "  ${WHITE}It requires a ${BOLD}paper test${NC}${WHITE} — finding the exact point where the${NC}"
    p "  ${WHITE}nozzle ${BOLD}just touches${NC}${WHITE} an A4 80gsm paper.${NC}"
    p ""
    p "  ${BR_RED}${BOLD}⚠  DANGER — CRASH RISK:${NC}"
    p "  ${BR_RED}  • Going too low will ${BOLD}CRASH the nozzle into the bed${NC}"
    p "  ${BR_RED}  • Use ONLY ${BOLD}0.1mm steps${NC}${BR_RED} when approaching the bed${NC}"
    p "  ${BR_RED}  • STOP the moment the paper shows resistance${NC}"
    p "  ${BR_RED}  • If unsure → press EMERGENCY STOP immediately${NC}"
    p ""
    p "  ${WHITE}${BOLD}Required: standard A4 80gsm paper sheet (single sheet, dry)${NC}"
    p ""
    p "  ${WHITE}${BOLD}Instructions (in Fluidd console):${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}1.${NC} ${BR_GREEN}CAL_EDDY_MAPPING${NC}                 ${DIM}# moves head to center${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}2.${NC} ${WHITE}Place A4 paper between nozzle and bed${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}3.${NC} ${WHITE}Using Fluidd Z arrows with ${BOLD}0.1mm step${NC}${WHITE}:${NC}"
    p "  ${WHITE}     Move bed ${BOLD}UP${NC}${WHITE} slowly until paper catches with slight friction${NC}"
    p "  ${WHITE}     ${BR_RED}${BOLD}STOP IMMEDIATELY${NC}${WHITE} when paper drags${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}4.${NC} ${WHITE}REMOVE the paper sheet from the bed${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}5.${NC} ${BR_GREEN}PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy${NC}"
    p "  ${WHITE}     ${DIM}(Klipper will run its own sequence — wait patiently)${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}6.${NC} ${WHITE}When Klipper prompts ${BOLD}TESTZ / ACCEPT${NC}${WHITE}:${NC}"
    p "  ${WHITE}      Replace paper, use ${BR_GREEN}TESTZ Z=-0.1${NC}${WHITE} until paper catches,${NC}"
    p "  ${WHITE}      then send ${BR_GREEN}ACCEPT${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}7.${NC} ${WHITE}Wait for full calibration (~2 minutes, many moves)${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}8.${NC} ${BR_GREEN}SAVE_CONFIG${NC}                      ${DIM}# Klipper will restart${NC}"
    p ""

    if ! _confirm_yes "you have an A4 paper ready AND you understand the crash risk"; then
        log_warn "Step 3 cancelled"
        pause_user "Press ENTER to return to menu..."
        return 0
    fi

    _wait_enter "When SAVE_CONFIG has finished and Klipper restarted"

    log_info "Checking probe calibration was saved..."
    sleep 5
    if ! _check_klipper_ready; then
        log_error "Klipper not ready after SAVE_CONFIG. Check Fluidd."
        pause_user "Press ENTER to return to menu..."
        return 1
    fi
    log_ok "Step 3 complete — probe height mapping saved"

    # ═══════════════════════════════════════════════════════
    # STEP 4 — Z=0 VERIFICATION (MANDATORY)
    # ═══════════════════════════════════════════════════════
    clear
    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} STEP 4/6 ${NC} ${WHITE}${BOLD}Z=0 verification (MANDATORY)${NC}                        ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}This step verifies that after ${BOLD}G28${NC}${WHITE}, the nozzle at ${BOLD}Z=0${NC}${WHITE} is${NC}"
    p "  ${WHITE}correctly at the paper-contact position.${NC}"
    p ""
    p "  ${WHITE}If not, we correct via babystepping and save the offset.${NC}"
    p ""
    p "  ${YELLOW}${BOLD}This is the ONLY way to catch a bad calibration before printing.${NC}"
    p ""
    p "  ${WHITE}${BOLD}Instructions (in Fluidd console):${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}1.${NC} ${BR_GREEN}G28${NC}                              ${DIM}# home all axes${NC}"
    p "  ${WHITE}  ${BR_GREEN}${BOLD}2.${NC} ${BR_GREEN}CENTER_TOOLHEAD${NC}                  ${DIM}# move to center${NC}"
    p "  ${WHITE}  ${BR_GREEN}${BOLD}3.${NC} ${BR_GREEN}G1 Z0 F300${NC}                       ${DIM}# go to Z=0${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}4.${NC} ${WHITE}Place A4 paper between nozzle and bed${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}5.${NC} ${WHITE}Check paper resistance:${NC}"
    p "  ${WHITE}     ${BR_GREEN}• Paper catches slightly${NC} ${WHITE}→ calibration OK, go to step 7${NC}"
    p "  ${WHITE}     ${YELLOW}• Paper moves freely${NC} ${WHITE}→ nozzle too high, do step 6${NC}"
    p "  ${BR_RED}     • Paper is stuck / crushed${NC} ${WHITE}→ nozzle too low, do step 6${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}6.${NC} ${WHITE}If adjustment needed, use ${BOLD}babystepping${NC}${WHITE}:${NC}"
    p "  ${WHITE}     ${DIM}• If too high: ${BR_GREEN}SET_GCODE_OFFSET Z_ADJUST=-0.05 MOVE=1${NC}"
    p "  ${WHITE}     ${DIM}• If too low:  ${BR_GREEN}SET_GCODE_OFFSET Z_ADJUST=+0.05 MOVE=1${NC}"
    p "  ${WHITE}     ${DIM}Repeat until perfect${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}7.${NC} ${WHITE}Once correct, note the final ${BOLD}Z_OFFSET${NC}${WHITE} value shown${NC}"
    p "  ${WHITE}     and update it in ${BOLD}eddy.cfg${NC}${WHITE} if not zero${NC}"
    p ""

    _wait_enter "When Z=0 verification is complete"

    if ! _check_klipper_ready; then
        log_error "Klipper not ready."
        pause_user "Press ENTER to return to menu..."
        return 1
    fi
    log_ok "Step 4 complete — Z=0 verified"

    # ═══════════════════════════════════════════════════════
    # STEP 5 — TEMPERATURE DRIFT CALIBRATION (OPTIONAL)
    # ═══════════════════════════════════════════════════════
    clear
    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} STEP 5/6 ${NC} ${WHITE}${BOLD}Temperature drift calibration (OPTIONAL)${NC}            ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}Eddy sensors drift with temperature. This calibration records the${NC}"
    p "  ${WHITE}sensor response at several temperatures so Klipper can compensate.${NC}"
    p ""
    p "  ${YELLOW}${BOLD}This step is RECOMMENDED ONLY IF:${NC}"
    p "  ${YELLOW}  • You use an ${BOLD}enclosure${NC}${YELLOW} on your printer${NC}"
    p "  ${YELLOW}  • You print materials that need high chamber temperatures${NC}"
    p "  ${YELLOW}  • You notice first-layer issues after long prints${NC}"
    p ""
    p "  ${WHITE}${BOLD}Without enclosure: you can SKIP this step.${NC}"
    p ""
    p "  ${DIM}Duration: ~20-40 minutes (several paper tests as bed heats)${NC}"
    p ""

    printf "  ${WHITE}${BOLD}Do you want to run the temperature drift calibration? [y/N]: ${NC}"
    read RUN_TEMP
    if [ "$RUN_TEMP" = "y" ] || [ "$RUN_TEMP" = "Y" ]; then

        p ""
        printf "  ${WHITE}Target temperature in °C (default 49): ${NC}"
        read TEMP_TARGET
        [ -z "$TEMP_TARGET" ] && TEMP_TARGET=49

        # Validate
        if ! echo "$TEMP_TARGET" | grep -qE '^[0-9]+$'; then
            log_error "Invalid temperature: $TEMP_TARGET"
            pause_user "Press ENTER to skip temperature calibration..."
        elif [ "$TEMP_TARGET" -lt 30 ] || [ "$TEMP_TARGET" -gt 80 ]; then
            log_error "Temperature must be between 30 and 80 °C"
            pause_user "Press ENTER to skip temperature calibration..."
        else
            clear
            p ""
            p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
            p "${BR_RED}┃${NC}  ${WHITE}${BOLD}STEP 5 — Temperature drift calibration${NC}                           ${BR_RED}┃${NC}"
            p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
            p ""
            p "  ${WHITE}Parameters:${NC}"
            p "  ${WHITE}  • TARGET temperature: ${BOLD}${TEMP_TARGET}°C${NC}"
            p "  ${WHITE}  • STEP: ${BOLD}10°C${NC} ${DIM}(sample every 10°C rise)${NC}"
            p "  ${WHITE}  • Expected samples: ${BOLD}~$((TEMP_TARGET / 10))${NC}${WHITE} (paper tests)${NC}"
            p ""
            p "  ${YELLOW}${BOLD}WARNING:${NC}"
            p "  ${YELLOW}  • Each sample requires a ${BOLD}paper test${NC}${YELLOW} (A4 80gsm)${NC}"
            p "  ${YELLOW}  • The bed will be ${BOLD}HEATING throughout${NC}${YELLOW} — do NOT touch${NC}"
            p "  ${YELLOW}  • Keep the room at stable ambient temperature${NC}"
            p "  ${YELLOW}  • Close any AC/fan that might cause airflow${NC}"
            p ""
            p "  ${WHITE}${BOLD}Instructions (in Fluidd console):${NC}"
            p ""
            p "  ${WHITE}  ${BR_GREEN}${BOLD}1.${NC} ${BR_GREEN}G28${NC}                              ${DIM}# home${NC}"
            p "  ${WHITE}  ${BR_GREEN}${BOLD}2.${NC} ${BR_GREEN}CENTER_TOOLHEAD${NC}                  ${DIM}# move to center${NC}"
            p "  ${WHITE}  ${BR_GREEN}${BOLD}3.${NC} ${BR_GREEN}SET_IDLE_TIMEOUT TIMEOUT=36000${NC}   ${DIM}# long timeout${NC}"
            p ""
            p "  ${WHITE}  ${BR_GREEN}${BOLD}4.${NC} ${BR_GREEN}TEMPERATURE_PROBE_CALIBRATE PROBE=btt_eddy TARGET=${TEMP_TARGET} STEP=10${NC}"
            p ""
            p "  ${WHITE}  ${BR_GREEN}${BOLD}5.${NC} ${WHITE}Klipper will prompt for a paper test at current temperature${NC}"
            p "  ${WHITE}     Place paper, adjust with ${BR_GREEN}TESTZ Z=-0.1${NC}${WHITE}, then ${BR_GREEN}ACCEPT${NC}"
            p ""
            p "  ${WHITE}  ${BR_GREEN}${BOLD}6.${NC} ${WHITE}Manually heat the bed progressively:${NC}"
            p "  ${WHITE}     ${BR_GREEN}M140 S35${NC}${WHITE} (wait temp), repeat paper test${NC}"
            p "  ${WHITE}     ${BR_GREEN}M140 S45${NC}${WHITE} (wait temp), repeat paper test${NC}"
            p "  ${WHITE}     ... until TARGET=${TEMP_TARGET}°C reached${NC}"
            p ""
            p "  ${WHITE}  ${BR_GREEN}${BOLD}7.${NC} ${WHITE}Klipper auto-completes at TARGET, or send ${BR_GREEN}TEMPERATURE_PROBE_COMPLETE${NC}"
            p ""
            p "  ${WHITE}  ${BR_GREEN}${BOLD}8.${NC} ${BR_GREEN}SAVE_CONFIG${NC}                     ${DIM}# Klipper restarts${NC}"
            p "  ${WHITE}  ${BR_GREEN}${BOLD}9.${NC} ${BR_GREEN}M140 S0${NC}                         ${DIM}# cool down bed${NC}"
            p ""

            if _confirm_yes "you are ready for a long (~30min) calibration"; then
                _wait_enter "When SAVE_CONFIG has finished and bed is cooling"
                sleep 5
                if _check_klipper_ready; then
                    log_ok "Step 5 complete — temperature calibration saved"
                else
                    log_warn "Klipper state uncertain — check Fluidd"
                fi
            else
                log_info "Temperature calibration cancelled"
            fi
        fi
    else
        log_info "Step 5 skipped (no enclosure / not needed)"
    fi

    # ═══════════════════════════════════════════════════════
    # STEP 6 — BED MESH
    # ═══════════════════════════════════════════════════════
    clear
    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} STEP 6/6 ${NC} ${WHITE}${BOLD}Bed mesh generation${NC}                                 ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}This final step generates a precise height map of the bed.${NC}"
    p "  ${WHITE}We use ${BOLD}CAL_BED_MESH_PRECISE${NC}${WHITE} (25x25 points, method=scan) for maximum${NC}"
    p "  ${WHITE}accuracy. Takes ~2 minutes.${NC}"
    p ""
    p "  ${YELLOW}${BOLD}WARNING:${NC}"
    p "  ${YELLOW}  • ${BOLD}Nothing on the bed${NC}${YELLOW} during scan${NC}"
    p "  ${YELLOW}  • Stable bed temperature${NC}"
    p ""
    p "  ${WHITE}${BOLD}Instructions (in Fluidd console):${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}1.${NC} ${BR_GREEN}CAL_BED_MESH_PRECISE${NC}             ${DIM}# precise 25x25 scan${NC}"
    p "  ${WHITE}  ${BR_GREEN}${BOLD}2.${NC} ${BR_GREEN}SAVE_CONFIG${NC}                     ${DIM}# Klipper restarts${NC}"
    p ""

    if ! _confirm_yes "bed is clear and ready for mesh scan"; then
        log_warn "Step 6 cancelled"
        pause_user "Press ENTER to return to menu..."
        return 0
    fi

    _wait_enter "When SAVE_CONFIG has finished after the mesh scan"

    sleep 5
    if ! _check_klipper_ready; then
        log_error "Klipper not ready after final SAVE_CONFIG."
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    RESULT=$(_query_saved_config "bed_mesh default")
    log_ok "Step 6 complete — bed mesh saved"

    # ═══════════════════════════════════════════════════════
    # COMPLETION
    # ═══════════════════════════════════════════════════════
    clear
    p ""
    p "${BR_RED}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${BG_RED}${WHITE}${BOLD}  ✓  EDDY CALIBRATION COMPLETE  ${NC}                            ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Your printer is now calibrated and ready to print.${NC}            ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}${BOLD}Recommendations:${NC}                                             ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}• Run CAL_BED_MESH before each print${NC}                          ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}• Repeat CAL_BED_MESH_PRECISE monthly${NC}                         ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}• Re-calibrate Eddy if you move/replace the probe${NC}             ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ╚══════════════════════════════════════════════════════════════════╝${NC}"
    p ""

    pause_user "Press ENTER to return to menu..."
}

# ─── CONFIGURE EDDY OFFSETS ───
configure_eddy_offsets() {
    clear
    show_banner
    log_step "+" "Configure BTT Eddy offsets"

    # Check if eddy.cfg exists
    if [ ! -f "$CONFIG_DIR/eddy.cfg" ]; then
        log_error "eddy.cfg not found at $CONFIG_DIR/eddy.cfg"
        log_error "Please run the full installation first."
        pause_user "Press ENTER to continue..."
        return 1
    fi

    # Read current offsets
    CUR_X=$(grep "^x_offset:" $CONFIG_DIR/eddy.cfg | awk "{print \$2}")
    CUR_Y=$(grep "^y_offset:" $CONFIG_DIR/eddy.cfg | awk "{print \$2}")
    [ -z "$CUR_X" ] && CUR_X=0
    [ -z "$CUR_Y" ] && CUR_Y=0

    p ""
    p "  ${WHITE}${BOLD}Current BTT Eddy offsets:${NC}"
    p "    ${WHITE}x_offset: ${BOLD}${CUR_X} mm${NC}  ${DIM}(positive = right of nozzle, negative = left)${NC}"
    p "    ${WHITE}y_offset: ${BOLD}${CUR_Y} mm${NC}  ${DIM}(positive = behind nozzle, negative = front)${NC}"
    p ""
    p "  ${YELLOW}Offsets should be measured physically from nozzle tip to Eddy center.${NC}"
    p ""

    # Prompt for new values
    printf "  ${WHITE}New X offset in mm (default keep current ${CUR_X}): ${NC}"
    read NEW_X
    [ -z "$NEW_X" ] && NEW_X=$CUR_X

    printf "  ${WHITE}New Y offset in mm (default keep current ${CUR_Y}): ${NC}"
    read NEW_Y
    [ -z "$NEW_Y" ] && NEW_Y=$CUR_Y

    # Validate + compute mesh bounds via Python
    VALIDATION=$(python3 << PYEOF
import sys

try:
    x = float("$NEW_X")
    y = float("$NEW_Y")
except ValueError:
    print("INVALID_NUMBER")
    sys.exit(1)

# Sanity checks
if abs(x) > 100:
    print("X_TOO_LARGE")
    sys.exit(1)
if abs(y) > 100:
    print("Y_TOO_LARGE")
    sys.exit(1)

POS_MIN_X = 0
POS_MIN_Y = 0
POS_MAX_X = 406
POS_MAX_Y = 401
MARGIN = 15  # BTT recommended minimum margin

# BTT formula: max(15mm, |offset|)
mesh_min_x = POS_MIN_X + max(MARGIN, x if x > 0 else 0)
mesh_min_y = POS_MIN_Y + max(MARGIN, y if y > 0 else 0)
mesh_max_x = POS_MAX_X - max(MARGIN, abs(x) if x < 0 else 0)
mesh_max_y = POS_MAX_Y - max(MARGIN, abs(y) if y < 0 else 0)

usable_x = mesh_max_x - mesh_min_x
usable_y = mesh_max_y - mesh_min_y

if usable_x < 100 or usable_y < 100:
    print(f"TOO_SMALL|{usable_x:.1f}|{usable_y:.1f}")
    sys.exit(1)

print(f"OK|{x}|{y}|{mesh_min_x:.1f}|{mesh_min_y:.1f}|{mesh_max_x:.1f}|{mesh_max_y:.1f}|{usable_x:.1f}|{usable_y:.1f}")
PYEOF
)

    RESULT=$(echo "$VALIDATION" | cut -d"|" -f1)

    case "$RESULT" in
        "INVALID_NUMBER")
            log_error "Invalid number format. Please use decimal numbers (e.g. 38 or -12.5)"
            pause_user "Press ENTER to return to menu..."
            return 1
            ;;
        "X_TOO_LARGE")
            log_error "X offset too large (|x| > 100mm). Check your physical setup."
            pause_user "Press ENTER to return to menu..."
            return 1
            ;;
        "Y_TOO_LARGE")
            log_error "Y offset too large (|y| > 100mm). Check your physical setup."
            pause_user "Press ENTER to return to menu..."
            return 1
            ;;
        "TOO_SMALL")
            U_X=$(echo "$VALIDATION" | cut -d"|" -f2)
            U_Y=$(echo "$VALIDATION" | cut -d"|" -f3)
            log_error "Usable mesh area too small: ${U_X}x${U_Y} mm (minimum 100x100)"
            pause_user "Press ENTER to return to menu..."
            return 1
            ;;
        "OK")
            X=$(echo "$VALIDATION" | cut -d"|" -f2)
            Y=$(echo "$VALIDATION" | cut -d"|" -f3)
            MIN_X=$(echo "$VALIDATION" | cut -d"|" -f4)
            MIN_Y=$(echo "$VALIDATION" | cut -d"|" -f5)
            MAX_X=$(echo "$VALIDATION" | cut -d"|" -f6)
            MAX_Y=$(echo "$VALIDATION" | cut -d"|" -f7)
            U_X=$(echo "$VALIDATION" | cut -d"|" -f8)
            U_Y=$(echo "$VALIDATION" | cut -d"|" -f9)
            ;;
    esac

    # Display summary
    p ""
    p "${BR_RED}  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}  ┃${NC}  ${WHITE}${BOLD}Summary of changes:${NC}                                            ${BR_RED}┃${NC}"
    p "${BR_RED}  ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
    p "${BR_RED}  ┃${NC}  ${WHITE}Eddy offsets:${NC}                                                   ${BR_RED}┃${NC}"
    p "${BR_RED}  ┃${NC}    ${GRAY}x_offset: ${CUR_X} → ${BOLD}${WHITE}${X} mm${NC}                                     ${BR_RED}┃${NC}"
    p "${BR_RED}  ┃${NC}    ${GRAY}y_offset: ${CUR_Y} → ${BOLD}${WHITE}${Y} mm${NC}                                      ${BR_RED}┃${NC}"
    p "${BR_RED}  ┃${NC}                                                                 ${BR_RED}┃${NC}"
    p "${BR_RED}  ┃${NC}  ${WHITE}New bed_mesh parameters:${NC}                                        ${BR_RED}┃${NC}"
    p "${BR_RED}  ┃${NC}    ${WHITE}mesh_min: ${BOLD}${MIN_X}, ${MIN_Y}${NC}                                          ${BR_RED}┃${NC}"
    p "${BR_RED}  ┃${NC}    ${WHITE}mesh_max: ${BOLD}${MAX_X}, ${MAX_Y}${NC}                                         ${BR_RED}┃${NC}"
    p "${BR_RED}  ┃${NC}    ${WHITE}Usable area: ${BOLD}${U_X} x ${U_Y} mm${NC}                              ${BR_RED}┃${NC}"
    p "${BR_RED}  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""

    printf "  ${WHITE}${BOLD}Apply these changes? [y/N]: ${NC}"
    read CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        log_warn "Cancelled by user."
        pause_user "Press ENTER to return to menu..."
        return 0
    fi

    # Apply changes
    log_info "Updating eddy.cfg..."
    sed -i "s|^x_offset:.*|x_offset: ${X}|" $CONFIG_DIR/eddy.cfg
    sed -i "s|^y_offset:.*|y_offset: ${Y}|" $CONFIG_DIR/eddy.cfg
    log_action "eddy.cfg: x_offset=${X}, y_offset=${Y}"

    log_info "Updating bed_mesh in printer.cfg..."
    python3 << PYEOF
import re
path = "$CONFIG_DIR/printer.cfg"
with open(path) as f:
    content = f.read()
content = re.sub(r"mesh_min:\s*[\d.\-]+,\s*[\d.\-]+", "mesh_min: ${MIN_X}, ${MIN_Y}", content)
content = re.sub(r"mesh_max:\s*[\d.\-]+,\s*[\d.\-]+", "mesh_max: ${MAX_X}, ${MAX_Y}", content)
with open(path, "w") as f:
    f.write(content)
PYEOF
    log_action "bed_mesh: mesh_min=${MIN_X},${MIN_Y} mesh_max=${MAX_X},${MAX_Y}"

    log_info "Restarting Klipper service..."
    $KLIPPER_SERVICE restart 2>&1 | while read line; do log_action "$line"; done
    sleep 15

    STATE=$(python3 -c "
import urllib.request, json
try:
    d = json.loads(urllib.request.urlopen(\"http://localhost:7125/printer/info\").read())
    print(d[\"result\"][\"state\"])
except:
    print(\"unknown\")
" 2>/dev/null)

    if [ "$STATE" = "ready" ]; then
        log_ok "Klipper restarted successfully - new offsets applied"
    else
        log_warn "Klipper state: $STATE - check logs if unexpected"
    fi

    pause_user "Press ENTER to return to menu..."
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
    step10_install_macros
    show_completion
}

# ─── RUN SINGLE STEP BY NUMBER ───
run_step() {
    case $1 in
        "0")  step0_clone_helper    ;;
        "1")  step1_helper_base     ;;
        "2")  step2_helper_guppy    ;;
        "3")  step3_save_original   ;;
        "4")  step4_patch_servers   ;;
        "5")  step5_install_klipper ;;
        "6")  step6_create_config   ;;
        "7")  step7_configure_guppy ;;
        "8")  step8_flash_eddy      ;;
        "9")  step9_start_klipper   ;;
        "10") step10_install_macros ;;
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
            10|[0-9])
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
            10|[0-9])
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
        3)
            clear
            show_banner
            step_set_eddy_offsets
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
