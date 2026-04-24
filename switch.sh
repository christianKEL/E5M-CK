#!/bin/sh
# ============================================================
# E5M-CK Switch Tool
# Toggles between Klipper Creality (for Input Shaper) and
# Klipper mainline (E5M-CK production)
# Creality Ender 5 Max — Nebula Pad
# https://github.com/christianKEL/E5M-CK
# ============================================================

GITHUB_RAW="https://raw.githubusercontent.com/christianKEL/E5M-CK/main"
E5M_DIR="/usr/data/E5M_CK"
SWITCH_DIR="$E5M_DIR/SWITCH"
ORIGINAL_SAVE_DIR="$E5M_DIR/ORIGINAL_SAVE"
CONFIG_DIR="/usr/data/printer_data/config"
LOG_DIR="/usr/data/printer_data/logs"
KLIPPER_SERVICE="/etc/init.d/S55klipper_service"

KLIPPER_MAINLINE_PATH="/usr/data/klipper/klippy/klippy.py"
KLIPPER_CREALITY_PATH="/usr/share/klipper/klippy/klippy.py"

# ─── ANSI COLORS (Red/White/Black theme) ───
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
UNDER='\033[4m'
INV='\033[7m'
NC='\033[0m'

GREEN='\033[0;32m'
BR_GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BR_YELLOW='\033[1;93m'

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
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} $STEP_NUM ${NC}  ${WHITE}${BOLD}$STEP_TITLE${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
}

# ─── BANNER ───
show_banner() {
    clear
    p ""
    p "${BR_RED}    ███████╗██╗    ██╗██╗████████╗ ██████╗██╗  ██╗${NC}"
    p "${BR_RED}    ██╔════╝██║    ██║██║╚══██╔══╝██╔════╝██║  ██║${NC}"
    p "${BR_RED}    ███████╗██║ █╗ ██║██║   ██║   ██║     ███████║${NC}"
    p "${BR_RED}    ╚════██║██║███╗██║██║   ██║   ██║     ██╔══██║${NC}"
    p "${BR_RED}    ███████║╚███╔███╔╝██║   ██║   ╚██████╗██║  ██║${NC}"
    p "${BR_RED}    ╚══════╝ ╚══╝╚══╝ ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝${NC}"
    p ""
    p "${WHITE}          Klipper Creality ⇄ Mainline switch tool${NC}"
    p "${GRAY}          for Creality Ender 5 Max — Nebula Pad${NC}"
    p ""
    p "${DIM}                  github.com/christianKEL/E5M-CK${NC}"
    p ""
}

# ─── UTILITIES ───
pause_user() {
    p ""
    printf "  ${YELLOW}>${NC} ${WHITE}$1${NC}"
    read DUMMY
}

_wait_enter() {
    MSG=$1
    p ""
    printf "  ${WHITE}${BOLD}>${NC} ${WHITE}%s${NC}\n  ${DIM}Press ENTER when ready...${NC} " "$MSG"
    read DUMMY
}

_confirm_yes() {
    MSG=$1
    printf "  ${YELLOW}${BOLD}Type ${BR_RED}YES${YELLOW} (in capitals) to confirm %s: ${NC}" "$MSG"
    read CONFIRM
    [ "$CONFIRM" = "YES" ] && return 0
    return 1
}

# ─── DETECT CURRENT MODE ───
current_mode() {
    if [ ! -f "$KLIPPER_SERVICE" ]; then
        echo "unknown"
        return
    fi
    if grep -q "PY_SCRIPT=$KLIPPER_CREALITY_PATH" "$KLIPPER_SERVICE" 2>/dev/null; then
        echo "creality"
    elif grep -q "PY_SCRIPT=$KLIPPER_MAINLINE_PATH" "$KLIPPER_SERVICE" 2>/dev/null; then
        echo "mainline"
    else
        echo "unknown"
    fi
}

# ─── CHECK KLIPPER STATE ───
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
        return 1
    fi
    return 0
}

_klipper_state_message() {
    python3 -c "
import urllib.request, json
try:
    d = json.loads(urllib.request.urlopen('http://localhost:7125/printer/info').read())
    r = d.get('result', {})
    print('state:', r.get('state'))
    print('message:', (r.get('state_message') or '')[:400])
except Exception as e:
    print(f'query error: {e}')
" 2>/dev/null
}

# ─── ENSURE SWITCH DIRECTORIES EXIST ───
_ensure_dirs() {
    mkdir -p "$SWITCH_DIR"
    mkdir -p "$SWITCH_DIR/MAINLINE_BACKUP"
    mkdir -p "$SWITCH_DIR/HISTORY"
}

# ─── VALIDATE PREREQUISITES ───
_check_prerequisites() {
    MISSING=""
    [ ! -f "$KLIPPER_MAINLINE_PATH" ] && MISSING="${MISSING}  - $KLIPPER_MAINLINE_PATH\n"
    [ ! -f "$KLIPPER_CREALITY_PATH" ] && MISSING="${MISSING}  - $KLIPPER_CREALITY_PATH\n"
    [ ! -d "$ORIGINAL_SAVE_DIR" ] && MISSING="${MISSING}  - $ORIGINAL_SAVE_DIR (original Creality config backup)\n"
    [ ! -f "$ORIGINAL_SAVE_DIR/printer_creality_ORIGINAL.cfg" ] && MISSING="${MISSING}  - printer_creality_ORIGINAL.cfg\n"

    if [ -n "$MISSING" ]; then
        log_error "Missing required files/directories:"
        printf "$MISSING"
        log_error "Make sure install.sh has been run before using switch.sh"
        return 1
    fi
    return 0
}

# ═══════════════════════════════════════════════════════
# BACKUP / RESTORE HELPERS
# ═══════════════════════════════════════════════════════

_backup_mainline_config() {
    log_info "Backing up current mainline config..."
    rm -rf "$SWITCH_DIR/MAINLINE_BACKUP"
    mkdir -p "$SWITCH_DIR/MAINLINE_BACKUP"
    cp -a "$CONFIG_DIR/." "$SWITCH_DIR/MAINLINE_BACKUP/"
    log_action "Saved to $SWITCH_DIR/MAINLINE_BACKUP/"
}

_backup_service() {
    BAK="$SWITCH_DIR/S55klipper_service.$(current_mode).bak"
    cp "$KLIPPER_SERVICE" "$BAK"
    log_action "Service backed up: $BAK"
}

_switch_service_to() {
    TARGET=$1   # "creality" or "mainline"

    case "$TARGET" in
        creality)
            sed -i "s|PY_SCRIPT=$KLIPPER_MAINLINE_PATH|PY_SCRIPT=$KLIPPER_CREALITY_PATH|" "$KLIPPER_SERVICE"
            ;;
        mainline)
            sed -i "s|PY_SCRIPT=$KLIPPER_CREALITY_PATH|PY_SCRIPT=$KLIPPER_MAINLINE_PATH|" "$KLIPPER_SERVICE"
            ;;
    esac

    ACTIVE=$(grep "^PY_SCRIPT=" "$KLIPPER_SERVICE" | head -1)
    log_action "Service now uses: $ACTIVE"
}

# ═══════════════════════════════════════════════════════
# OPTION 2 : SWITCH TO CREALITY
# ═══════════════════════════════════════════════════════
switch_to_creality() {
    log_step "→ CREALITY" "Switch to Klipper Creality"

    MODE=$(current_mode)
    if [ "$MODE" = "creality" ]; then
        log_warn "Already running Klipper Creality"
        pause_user "Press ENTER to return to menu..."
        return 0
    fi

    _ensure_dirs

    if ! _check_prerequisites; then
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    p ""
    p "  ${WHITE}This operation will:${NC}"
    p "  ${WHITE}  1. Backup your current E5M-CK config${NC}"
    p "  ${WHITE}  2. Ask you to unplug the BTT Eddy USB${NC}"
    p "  ${WHITE}  3. Restore the original Creality config${NC}"
    p "  ${WHITE}  4. Switch the Klipper service to /usr/share/klipper${NC}"
    p "  ${WHITE}  5. Restart Klipper${NC}"
    p ""
    p "  ${YELLOW}${BOLD}Purpose: enable SHAPER_CALIBRATE which requires the${NC}"
    p "  ${YELLOW}${BOLD}Creality nozzle_mcu firmware ADXL345 support.${NC}"
    p ""

    if ! _confirm_yes "proceed with the switch to Creality"; then
        log_warn "Cancelled by user"
        pause_user "Press ENTER to return to menu..."
        return 0
    fi

    # Step 1 : Backup current mainline config
    _backup_mainline_config
    _backup_service

    # Step 2 : Unplug Eddy
    p ""
    p "${BG_RED}${WHITE}${BOLD}                                                                     ${NC}"
    p "${BG_RED}${WHITE}${BOLD}   ⚠  PHYSICAL ACTION REQUIRED  ⚠                                    ${NC}"
    p "${BG_RED}${WHITE}${BOLD}                                                                     ${NC}"
    p ""
    p "  ${WHITE}${BOLD}Unplug the BTT Eddy USB cable now.${NC}"
    p "  ${WHITE}Klipper Creality does not support the Eddy USB device and${NC}"
    p "  ${WHITE}will fail to start if it's still connected.${NC}"
    p ""

    _wait_enter "When you have UNPLUGGED the BTT Eddy USB"

    # Step 3 : Stop Klipper
    log_info "Stopping Klipper..."
    $KLIPPER_SERVICE stop 2>&1 | while read line; do log_action "$line"; done
    sleep 3

    # Step 4 : Replace configs
    log_info "Removing E5M-CK specific config files..."
    rm -f "$CONFIG_DIR/eddy.cfg"
    rm -f "$CONFIG_DIR/homing.cfg"
    rm -f "$CONFIG_DIR/adxl.cfg"
    rm -f "$CONFIG_DIR/macros_calibration.cfg"
    rm -f "$CONFIG_DIR/macros_E5M_CK.cfg"
    log_action "E5M-CK files removed"

    log_info "Restoring Creality original config..."
    cp -a "$ORIGINAL_SAVE_DIR/printer_creality_ORIGINAL.cfg" "$CONFIG_DIR/printer.cfg"
    cp -a "$ORIGINAL_SAVE_DIR/gcode_macro_creality_ORIGINAL.cfg" "$CONFIG_DIR/gcode_macro.cfg"
    cp -a "$ORIGINAL_SAVE_DIR/printer_params_creality_ORIGINAL.cfg" "$CONFIG_DIR/printer_params.cfg"
    cp -a "$ORIGINAL_SAVE_DIR/sensorless_creality_ORIGINAL.cfg" "$CONFIG_DIR/sensorless.cfg"
    log_action "Creality config restored"

    # Step 5 : Switch service
    log_info "Switching Klipper service to Creality..."
    _switch_service_to creality

    echo "creality" > "$SWITCH_DIR/MODE"

    # Step 6 : Start Klipper
    log_info "Starting Klipper Creality..."
    $KLIPPER_SERVICE start 2>&1 | while read line; do log_action "$line"; done
    sleep 12

    if _check_klipper_ready; then
        log_ok "Klipper Creality is ready"
        p ""
        p "  ${BR_GREEN}✓${NC} ${WHITE}You are now on Klipper Creality${NC}"
        p "  ${GRAY}  To calibrate Input Shaper, run option 1 (Full workflow)${NC}"
        p "  ${GRAY}  To return to mainline, run option 3${NC}"
    else
        log_error "Klipper Creality failed to start"
        _klipper_state_message
    fi

    pause_user "Press ENTER to return to menu..."
}

# ═══════════════════════════════════════════════════════
# OPTION 3 : SWITCH BACK TO MAINLINE
# ═══════════════════════════════════════════════════════
switch_to_mainline() {
    log_step "→ MAINLINE" "Switch back to Klipper mainline (E5M-CK)"

    MODE=$(current_mode)
    if [ "$MODE" = "mainline" ]; then
        log_warn "Already running Klipper mainline"
        pause_user "Press ENTER to return to menu..."
        return 0
    fi

    if [ ! -d "$SWITCH_DIR/MAINLINE_BACKUP" ] || [ -z "$(ls -A $SWITCH_DIR/MAINLINE_BACKUP 2>/dev/null)" ]; then
        log_error "No mainline backup found at $SWITCH_DIR/MAINLINE_BACKUP/"
        log_error "Cannot restore mainline config. Run install.sh to reinstall."
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    p ""
    p "  ${WHITE}This operation will:${NC}"
    p "  ${WHITE}  1. Save any SHAPER_CALIBRATE results present in klippy.log${NC}"
    p "  ${WHITE}  2. Restore the E5M-CK config from backup${NC}"
    p "  ${WHITE}  3. Switch the Klipper service to /usr/data/klipper${NC}"
    p "  ${WHITE}  4. Ask you to plug the BTT Eddy USB back in${NC}"
    p "  ${WHITE}  5. Restart Klipper${NC}"
    p ""

    if ! _confirm_yes "proceed with the switch to mainline"; then
        log_warn "Cancelled by user"
        pause_user "Press ENTER to return to menu..."
        return 0
    fi

    # Parse shaper values from klippy.log (if available)
    _extract_shaper_values

    # Step 1 : Stop Klipper
    log_info "Stopping Klipper..."
    $KLIPPER_SERVICE stop 2>&1 | while read line; do log_action "$line"; done
    sleep 3

    # Step 2 : Restore mainline config
    log_info "Restoring mainline E5M-CK config..."
    # Remove the Creality files
    rm -f "$CONFIG_DIR/printer.cfg"
    rm -f "$CONFIG_DIR/gcode_macro.cfg"
    rm -f "$CONFIG_DIR/printer_params.cfg"
    rm -f "$CONFIG_DIR/sensorless.cfg"
    # Restore everything from backup
    cp -a "$SWITCH_DIR/MAINLINE_BACKUP/." "$CONFIG_DIR/"
    log_action "Config restored from MAINLINE_BACKUP/"

    # Step 3 : Switch service
    log_info "Switching Klipper service to mainline..."
    _switch_service_to mainline

    echo "mainline" > "$SWITCH_DIR/MODE"

    # Step 4 : Plug Eddy back
    p ""
    p "${BG_RED}${WHITE}${BOLD}                                                                     ${NC}"
    p "${BG_RED}${WHITE}${BOLD}   ⚠  PHYSICAL ACTION REQUIRED  ⚠                                    ${NC}"
    p "${BG_RED}${WHITE}${BOLD}                                                                     ${NC}"
    p ""
    p "  ${WHITE}${BOLD}Plug the BTT Eddy USB cable back in now.${NC}"
    p ""

    _wait_enter "When you have PLUGGED the BTT Eddy USB back in"

    # Step 5 : Start Klipper
    log_info "Starting Klipper mainline..."
    $KLIPPER_SERVICE start 2>&1 | while read line; do log_action "$line"; done
    sleep 12

    if _check_klipper_ready; then
        log_ok "Klipper mainline is ready"
    else
        log_error "Klipper mainline failed to start"
        _klipper_state_message
    fi

    pause_user "Press ENTER to return to menu..."
}

# ═══════════════════════════════════════════════════════
# EXTRACT SHAPER VALUES FROM KLIPPY.LOG
# ═══════════════════════════════════════════════════════
# Parses the most recent "Recommended shaper_type_*" lines from
# klippy.log (and .1 backup if needed). Sets SHAPER_X_TYPE,
# SHAPER_X_FREQ, SHAPER_Y_TYPE, SHAPER_Y_FREQ, SHAPER_FOUND.
_extract_shaper_values() {
    SHAPER_X_TYPE=""
    SHAPER_X_FREQ=""
    SHAPER_Y_TYPE=""
    SHAPER_Y_FREQ=""
    SHAPER_FOUND="no"

    OUT=$(python3 << 'PYEOF'
import re, os, glob

# Gather candidate log files (current + rotated), recent first
log_files = []
for candidate in ['/usr/data/printer_data/logs/klippy.log',
                  '/usr/data/printer_data/logs/klippy.log.1',
                  '/usr/data/printer_data/logs/klippy.log.2']:
    if os.path.exists(candidate):
        log_files.append(candidate)

x_match = None
y_match = None

# Scan files in priority order; within each, scan bottom-up
for f in log_files:
    try:
        with open(f, 'r', errors='ignore') as fh:
            lines = fh.readlines()
    except Exception:
        continue
    for line in reversed(lines):
        if y_match is None and 'Recommended shaper_type_y' in line:
            m = re.search(r'shaper_type_y\s*=\s*(\w+),\s*shaper_freq_y\s*=\s*([\d.]+)', line)
            if m:
                y_match = (m.group(1), m.group(2))
        if x_match is None and 'Recommended shaper_type_x' in line:
            m = re.search(r'shaper_type_x\s*=\s*(\w+),\s*shaper_freq_x\s*=\s*([\d.]+)', line)
            if m:
                x_match = (m.group(1), m.group(2))
        if x_match and y_match:
            break
    if x_match and y_match:
        break

if x_match and y_match:
    print(f"OK|{x_match[0]}|{x_match[1]}|{y_match[0]}|{y_match[1]}")
else:
    print("NOT_FOUND")
PYEOF
)

    RESULT=$(echo "$OUT" | cut -d'|' -f1)
    if [ "$RESULT" = "OK" ]; then
        SHAPER_X_TYPE=$(echo "$OUT" | cut -d'|' -f2)
        SHAPER_X_FREQ=$(echo "$OUT" | cut -d'|' -f3)
        SHAPER_Y_TYPE=$(echo "$OUT" | cut -d'|' -f4)
        SHAPER_Y_FREQ=$(echo "$OUT" | cut -d'|' -f5)
        SHAPER_FOUND="yes"
        log_info "Found shaper values in klippy.log:"
        log_action "shaper_type_x: $SHAPER_X_TYPE  shaper_freq_x: $SHAPER_X_FREQ"
        log_action "shaper_type_y: $SHAPER_Y_TYPE  shaper_freq_y: $SHAPER_Y_FREQ"
    else
        log_warn "No SHAPER_CALIBRATE results found in klippy.log"
    fi
}

# ═══════════════════════════════════════════════════════
# INJECT [input_shaper] INTO printer.cfg
# ═══════════════════════════════════════════════════════
_inject_input_shaper() {
    X_TYPE=$1
    X_FREQ=$2
    Y_TYPE=$3
    Y_FREQ=$4
    TARGET_CFG=$5   # usually $CONFIG_DIR/printer.cfg

    log_info "Injecting [input_shaper] section into $(basename $TARGET_CFG)..."

    python3 << PYEOF
import re
path = "$TARGET_CFG"
with open(path) as f:
    content = f.read()

# 1) Remove any SAVE_CONFIG-managed [input_shaper] block (in #*# comments)
#    It starts at "#*# [input_shaper]" and continues until next "#*# [" or EOF
content = re.sub(
    r'#\*# \[input_shaper\].*?(?=\n#\*# \[|\Z)',
    '',
    content,
    flags=re.DOTALL
)
# Clean dangling #*# lines
content = re.sub(r'(\n#\*#\s*)+\n(?=#\*# \[)', '\n', content)
content = re.sub(r'(\n#\*#\s*)+\Z', '\n', content)

# 2) Remove any existing non-SAVE_CONFIG [input_shaper] section
#    [input_shaper] ... until next [ section at start of line or EOF
content = re.sub(
    r'\n\[input_shaper\][^\[]*?(?=\n\[|\Z)',
    '',
    content,
    flags=re.DOTALL
)

# 3) Inject new section before [printer]
block = """[input_shaper]
shaper_type_x: $X_TYPE
shaper_freq_x: $X_FREQ
shaper_type_y: $Y_TYPE
shaper_freq_y: $Y_FREQ

"""

if '[printer]' in content:
    content = content.replace('[printer]\n', block + '[printer]\n', 1)
else:
    # fallback : prepend to file
    content = block + content

with open(path, 'w') as f:
    f.write(content)

print("injected")
PYEOF

    if grep -q "^\[input_shaper\]" "$TARGET_CFG"; then
        log_ok "[input_shaper] injected successfully"
        return 0
    else
        log_error "Injection failed — [input_shaper] not found in $TARGET_CFG"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════
# SAVE TO HISTORY
# ═══════════════════════════════════════════════════════
_save_calibration_history() {
    X_TYPE=$1
    X_FREQ=$2
    Y_TYPE=$3
    Y_FREQ=$4

    _ensure_dirs
    TS=$(date +%Y%m%d_%H%M%S)
    HFILE="$SWITCH_DIR/HISTORY/${TS}.txt"

    cat > "$HFILE" << EOF
Date: $(date)
Host: $(hostname 2>/dev/null || echo unknown)
shaper_type_x: $X_TYPE
shaper_freq_x: $X_FREQ
shaper_type_y: $Y_TYPE
shaper_freq_y: $Y_FREQ
EOF
    cp "$HFILE" "$SWITCH_DIR/LAST_CALIBRATION.txt"
    log_action "Saved to HISTORY/${TS}.txt"
}

# ═══════════════════════════════════════════════════════
# OPTION 1 : FULL WORKFLOW
# ═══════════════════════════════════════════════════════
full_workflow() {
    log_step "WORKFLOW" "Full Input Shaper calibration workflow"

    MODE=$(current_mode)
    if [ "$MODE" != "mainline" ]; then
        log_error "Workflow must start from Klipper mainline (current: $MODE)"
        log_error "Run option 3 to return to mainline first."
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    _ensure_dirs
    if ! _check_prerequisites; then
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    p ""
    p "  ${WHITE}${BOLD}Full Input Shaper calibration workflow${NC}"
    p ""
    p "  ${WHITE}Steps this workflow performs:${NC}"
    p "  ${WHITE}   1. Backup your E5M-CK mainline config${NC}"
    p "  ${WHITE}   2. Ask you to unplug the BTT Eddy USB${NC}"
    p "  ${WHITE}   3. Switch to Klipper Creality${NC}"
    p "  ${WHITE}   4. Display instructions for SHAPER_CALIBRATE${NC}"
    p "  ${WHITE}   5. Wait for you to run calibration in Fluidd${NC}"
    p "  ${WHITE}   6. Parse klippy.log for recommended shaper values${NC}"
    p "  ${WHITE}   7. Show values, ask for confirmation${NC}"
    p "  ${WHITE}   8. Switch back to Klipper mainline${NC}"
    p "  ${WHITE}   9. Ask you to plug the BTT Eddy USB back in${NC}"
    p "  ${WHITE}  10. Inject [input_shaper] into printer.cfg${NC}"
    p "  ${WHITE}  11. Restart, verify, save history${NC}"
    p ""
    p "  ${YELLOW}Total time: ~10-15 minutes${NC}"
    p "  ${YELLOW}Physical actions required: 2 (unplug + plug Eddy USB)${NC}"
    p ""

    if ! _confirm_yes "start the full workflow"; then
        log_warn "Cancelled by user"
        pause_user "Press ENTER to return to menu..."
        return 0
    fi

    # ─── PHASE 1 : SWITCH TO CREALITY ───
    log_info "Phase 1 — Switching to Klipper Creality..."
    _backup_mainline_config
    _backup_service

    p ""
    p "${BG_RED}${WHITE}${BOLD}                                                                     ${NC}"
    p "${BG_RED}${WHITE}${BOLD}   ⚠  PHYSICAL ACTION 1/2  — UNPLUG Eddy USB  ⚠                      ${NC}"
    p "${BG_RED}${WHITE}${BOLD}                                                                     ${NC}"
    p ""
    p "  ${WHITE}${BOLD}Unplug the BTT Eddy USB cable now.${NC}"
    p "  ${WHITE}It must be physically disconnected before Klipper Creality starts.${NC}"
    p ""
    _wait_enter "When Eddy USB is UNPLUGGED"

    log_info "Stopping Klipper..."
    $KLIPPER_SERVICE stop 2>&1 >/dev/null
    sleep 3

    log_info "Replacing configs with Creality originals..."
    rm -f "$CONFIG_DIR/eddy.cfg"
    rm -f "$CONFIG_DIR/homing.cfg"
    rm -f "$CONFIG_DIR/adxl.cfg"
    rm -f "$CONFIG_DIR/macros_calibration.cfg"
    rm -f "$CONFIG_DIR/macros_E5M_CK.cfg"
    cp -a "$ORIGINAL_SAVE_DIR/printer_creality_ORIGINAL.cfg" "$CONFIG_DIR/printer.cfg"
    cp -a "$ORIGINAL_SAVE_DIR/gcode_macro_creality_ORIGINAL.cfg" "$CONFIG_DIR/gcode_macro.cfg"
    cp -a "$ORIGINAL_SAVE_DIR/printer_params_creality_ORIGINAL.cfg" "$CONFIG_DIR/printer_params.cfg"
    cp -a "$ORIGINAL_SAVE_DIR/sensorless_creality_ORIGINAL.cfg" "$CONFIG_DIR/sensorless.cfg"

    _switch_service_to creality
    echo "creality" > "$SWITCH_DIR/MODE"

    log_info "Starting Klipper Creality..."
    $KLIPPER_SERVICE start 2>&1 >/dev/null
    sleep 12

    if ! _check_klipper_ready; then
        log_error "Klipper Creality failed to start — aborting workflow"
        _klipper_state_message
        p ""
        log_warn "You are still on Klipper Creality. Use option 3 to return to mainline."
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    log_ok "Klipper Creality is ready"

    # ─── PHASE 2 : DISPLAY CALIBRATION INSTRUCTIONS ───
    clear
    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} SHAPER_CALIBRATE ${NC} ${WHITE}${BOLD}Run these commands in Fluidd${NC}              ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}Open Fluidd, copy-paste the following block in the console,${NC}"
    p "  ${WHITE}wait for each command to complete before the next.${NC}"
    p ""
    p "${WHITE}${BOLD}  ┌─────────────────────────────────────────────────────────────────┐${NC}"
    p "${WHITE}${BOLD}  │ ${BR_GREEN}G28${WHITE}                                                              │${NC}"
    p "${WHITE}${BOLD}  │ ${BR_GREEN}G1 X200 Y200 F6000${WHITE}                                               │${NC}"
    p "${WHITE}${BOLD}  │ ${BR_GREEN}G1 Z50 F600${WHITE}                                                      │${NC}"
    p "${WHITE}${BOLD}  │ ${BR_GREEN}ACCELEROMETER_QUERY${WHITE}                  ${DIM}# verify ADXL responds${WHITE}         │${NC}"
    p "${WHITE}${BOLD}  │ ${BR_GREEN}MEASURE_AXES_NOISE${WHITE}                   ${DIM}# noise < 100 required${WHITE}         │${NC}"
    p "${WHITE}${BOLD}  │ ${BR_GREEN}SET_PRESSURE_ADVANCE ADVANCE=0${WHITE}                                   │${NC}"
    p "${WHITE}${BOLD}  │ ${BR_GREEN}SET_INPUT_SHAPER SHAPER_FREQ_X=0 SHAPER_FREQ_Y=0${WHITE}                 │${NC}"
    p "${WHITE}${BOLD}  │ ${BR_GREEN}SHAPER_CALIBRATE${WHITE}                     ${DIM}# the big one (~5 min)${WHITE}         │${NC}"
    p "${WHITE}${BOLD}  └─────────────────────────────────────────────────────────────────┘${NC}"
    p ""
    p "  ${BR_RED}${BOLD}⚠  DO NOT run SAVE_CONFIG afterwards.${NC}"
    p "  ${BR_RED}${BOLD}   Leave Creality config untouched — this script handles injection.${NC}"
    p ""
    p "  ${YELLOW}Safety:${NC}"
    p "  ${YELLOW}  • Machine will vibrate vigorously on X then Y axes${NC}"
    p "  ${YELLOW}  • Do not touch the machine during calibration${NC}"
    p "  ${YELLOW}  • Be ready for emergency stop if anything seems wrong${NC}"
    p ""
    p "  ${WHITE}At the end, Klipper prints something like:${NC}"
    p "  ${DIM}    Recommended shaper_type_x = zv, shaper_freq_x = 50.6 Hz${NC}"
    p "  ${DIM}    Recommended shaper_type_y = mzv, shaper_freq_y = 41.8 Hz${NC}"
    p ""

    _wait_enter "When SHAPER_CALIBRATE has FINISHED"

    # ─── PHASE 3 : PARSE RESULTS ───
    log_info "Parsing klippy.log for shaper values..."
    _extract_shaper_values

    if [ "$SHAPER_FOUND" != "yes" ]; then
        log_error "No shaper values found in klippy.log"
        log_error "The calibration may not have completed successfully."
        log_warn "The script will still switch back to mainline, but [input_shaper] won't be updated."
        pause_user "Press ENTER to continue with return to mainline..."
        SHAPER_FOUND="no"
    else
        p ""
        p "${BR_RED}  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
        p "${BR_RED}  ┃${NC}  ${WHITE}${BOLD}Detected shaper values:${NC}                                       ${BR_RED}┃${NC}"
        p "${BR_RED}  ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
        p "${BR_RED}  ┃${NC}    ${WHITE}shaper_type_x: ${BOLD}${SHAPER_X_TYPE}${NC}${WHITE}     shaper_freq_x: ${BOLD}${SHAPER_X_FREQ} Hz${NC}                 ${BR_RED}┃${NC}"
        p "${BR_RED}  ┃${NC}    ${WHITE}shaper_type_y: ${BOLD}${SHAPER_Y_TYPE}${NC}${WHITE}     shaper_freq_y: ${BOLD}${SHAPER_Y_FREQ} Hz${NC}                ${BR_RED}┃${NC}"
        p "${BR_RED}  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
        p ""

        printf "  ${WHITE}${BOLD}Accept these values and continue? [Y/n]: ${NC}"
        read ACCEPT
        if [ "$ACCEPT" = "n" ] || [ "$ACCEPT" = "N" ]; then
            log_warn "Values not accepted"
            log_warn "The script will switch back to mainline without updating [input_shaper]"
            SHAPER_FOUND="no"
        fi
    fi

    # ─── PHASE 4 : SWITCH BACK TO MAINLINE ───
    log_info "Phase 4 — Switching back to Klipper mainline..."

    log_info "Stopping Klipper..."
    $KLIPPER_SERVICE stop 2>&1 >/dev/null
    sleep 3

    log_info "Restoring mainline config..."
    rm -f "$CONFIG_DIR/printer.cfg"
    rm -f "$CONFIG_DIR/gcode_macro.cfg"
    rm -f "$CONFIG_DIR/printer_params.cfg"
    rm -f "$CONFIG_DIR/sensorless.cfg"
    cp -a "$SWITCH_DIR/MAINLINE_BACKUP/." "$CONFIG_DIR/"

    _switch_service_to mainline
    echo "mainline" > "$SWITCH_DIR/MODE"

    # ─── PHASE 5 : INJECT SHAPER VALUES ───
    if [ "$SHAPER_FOUND" = "yes" ]; then
        _inject_input_shaper "$SHAPER_X_TYPE" "$SHAPER_X_FREQ" \
                             "$SHAPER_Y_TYPE" "$SHAPER_Y_FREQ" \
                             "$CONFIG_DIR/printer.cfg"
        _save_calibration_history "$SHAPER_X_TYPE" "$SHAPER_X_FREQ" \
                                  "$SHAPER_Y_TYPE" "$SHAPER_Y_FREQ"
    fi

    # ─── PHASE 6 : PLUG EDDY BACK ───
    p ""
    p "${BG_RED}${WHITE}${BOLD}                                                                     ${NC}"
    p "${BG_RED}${WHITE}${BOLD}   ⚠  PHYSICAL ACTION 2/2  — PLUG Eddy USB BACK IN  ⚠                ${NC}"
    p "${BG_RED}${WHITE}${BOLD}                                                                     ${NC}"
    p ""
    p "  ${WHITE}${BOLD}Plug the BTT Eddy USB cable back in now.${NC}"
    p "  ${WHITE}The Eddy probe is required for Klipper mainline to home Z.${NC}"
    p ""
    _wait_enter "When Eddy USB is PLUGGED back in"

    # ─── PHASE 7 : START KLIPPER MAINLINE ───
    log_info "Starting Klipper mainline..."
    $KLIPPER_SERVICE start 2>&1 >/dev/null
    sleep 12

    if ! _check_klipper_ready; then
        log_error "Klipper mainline failed to start"
        _klipper_state_message
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    log_ok "Klipper mainline is ready"

    # ─── PHASE 8 : VERIFY INPUT SHAPER IS ACTIVE ───
    if [ "$SHAPER_FOUND" = "yes" ]; then
        log_info "Verifying input shaper is active..."
        VERIFY=$(curl -s -X POST http://localhost:7125/printer/gcode/script -d 'script=SET_INPUT_SHAPER' 2>/dev/null)
        sleep 2
        # The response returns OK, actual output is in klippy.log
        LAST=$(tail -20 "$LOG_DIR/klippy.log" 2>/dev/null | grep -i "shaper_type_x\|shaper_freq_x" | tail -2)
        if [ -n "$LAST" ]; then
            p ""
            log_action "Last SET_INPUT_SHAPER output:"
            echo "$LAST" | while read ln; do log_action "  $ln"; done
        fi
    fi

    # ─── PHASE 9 : COMPLETION ───
    clear
    p ""
    p "${BR_RED}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${BG_RED}${WHITE}${BOLD}  ✓  INPUT SHAPER WORKFLOW COMPLETE  ${NC}                       ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    if [ "$SHAPER_FOUND" = "yes" ]; then
        p "${BR_RED}  ║${NC}    ${WHITE}Active shaper values:${NC}                                        ${BR_RED}║${NC}"
        printf "${BR_RED}  ║${NC}      shaper_type_x: %-6s  shaper_freq_x: %-6s Hz          ${BR_RED}║${NC}\n" "$SHAPER_X_TYPE" "$SHAPER_X_FREQ"
        printf "${BR_RED}  ║${NC}      shaper_type_y: %-6s  shaper_freq_y: %-6s Hz          ${BR_RED}║${NC}\n" "$SHAPER_Y_TYPE" "$SHAPER_Y_FREQ"
        p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
        p "${BR_RED}  ║${NC}    ${GRAY}History: $SWITCH_DIR/HISTORY/${NC}              ${BR_RED}║${NC}"
    else
        p "${BR_RED}  ║${NC}    ${YELLOW}No shaper values applied (not found or not accepted)${NC}         ${BR_RED}║${NC}"
        p "${BR_RED}  ║${NC}    ${YELLOW}System restored to mainline with previous settings${NC}             ${BR_RED}║${NC}"
    fi
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}${BOLD}You can now run a test print${NC}                                ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ╚══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
    pause_user "Press ENTER to return to menu..."
}

# ═══════════════════════════════════════════════════════
# OPTION 4 : SHOW STATUS
# ═══════════════════════════════════════════════════════
show_status() {
    log_step "STATUS" "System status"

    p ""
    p "  ${WHITE}${BOLD}Klipper service:${NC}"
    MODE=$(current_mode)
    case "$MODE" in
        mainline)
            p "    ${BR_GREEN}●${NC} Running ${BOLD}Klipper mainline${NC} ${DIM}(/usr/data/klipper)${NC}"
            ;;
        creality)
            p "    ${BR_YELLOW}●${NC} Running ${BOLD}Klipper Creality${NC} ${DIM}(/usr/share/klipper)${NC}"
            ;;
        *)
            p "    ${BR_RED}●${NC} ${BR_RED}Unknown mode${NC}"
            ;;
    esac

    if [ -f "$SWITCH_DIR/MODE" ]; then
        LAST_MODE=$(cat "$SWITCH_DIR/MODE")
        p "    ${GRAY}Last recorded mode: $LAST_MODE${NC}"
    fi

    p ""
    p "  ${WHITE}${BOLD}Klipper state:${NC}"
    STATE_OUT=$(_klipper_state_message)
    echo "$STATE_OUT" | while read ln; do
        p "    ${WHITE}$ln${NC}"
    done

    p ""
    p "  ${WHITE}${BOLD}Installed Klipper versions:${NC}"
    if [ -f "$KLIPPER_MAINLINE_PATH" ]; then
        MAINLINE_VER=$(cd /usr/data/klipper 2>/dev/null && git describe --tags --always 2>/dev/null || echo "unknown")
        p "    ${BR_GREEN}✓${NC} Mainline: $MAINLINE_VER"
    else
        p "    ${BR_RED}✗${NC} Mainline: missing"
    fi
    if [ -f "$KLIPPER_CREALITY_PATH" ]; then
        p "    ${BR_GREEN}✓${NC} Creality: present at /usr/share/klipper"
    else
        p "    ${BR_RED}✗${NC} Creality: missing"
    fi

    p ""
    p "  ${WHITE}${BOLD}Backups:${NC}"
    if [ -d "$SWITCH_DIR/MAINLINE_BACKUP" ] && [ -n "$(ls -A $SWITCH_DIR/MAINLINE_BACKUP 2>/dev/null)" ]; then
        BACKUP_COUNT=$(ls "$SWITCH_DIR/MAINLINE_BACKUP" 2>/dev/null | wc -l)
        p "    ${BR_GREEN}✓${NC} MAINLINE_BACKUP: $BACKUP_COUNT files"
    else
        p "    ${GRAY}○${NC} MAINLINE_BACKUP: empty or missing"
    fi

    if [ -f "$SWITCH_DIR/LAST_CALIBRATION.txt" ]; then
        p ""
        p "  ${WHITE}${BOLD}Last calibration:${NC}"
        while read ln; do
            p "    ${DIM}$ln${NC}"
        done < "$SWITCH_DIR/LAST_CALIBRATION.txt"
    fi

    if [ -d "$SWITCH_DIR/HISTORY" ]; then
        HIST_COUNT=$(ls "$SWITCH_DIR/HISTORY" 2>/dev/null | wc -l)
        p ""
        p "  ${WHITE}${BOLD}History:${NC} $HIST_COUNT calibration(s) stored in HISTORY/"
    fi

    p ""
    p "  ${WHITE}${BOLD}Current [input_shaper] in printer.cfg:${NC}"
    SHAPER_BLOCK=$(grep -A4 "^\[input_shaper\]" "$CONFIG_DIR/printer.cfg" 2>/dev/null | head -5)
    if [ -n "$SHAPER_BLOCK" ]; then
        echo "$SHAPER_BLOCK" | while read ln; do
            p "    ${DIM}$ln${NC}"
        done
    else
        p "    ${GRAY}(no [input_shaper] section — run option 1 to calibrate)${NC}"
    fi

    p ""
    pause_user "Press ENTER to return to menu..."
}

# ═══════════════════════════════════════════════════════
# OPTION 5 : IMPORT SHAPER VALUES (standalone)
# ═══════════════════════════════════════════════════════
import_shaper_values() {
    log_step "IMPORT" "Import last SHAPER_CALIBRATE results into printer.cfg"

    MODE=$(current_mode)
    if [ "$MODE" != "mainline" ]; then
        log_error "You must be on Klipper mainline to import values (current: $MODE)"
        log_error "Run option 3 to return to mainline first."
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    p ""
    p "  ${WHITE}This option parses the last SHAPER_CALIBRATE results from${NC}"
    p "  ${WHITE}klippy.log and injects them into printer.cfg [input_shaper].${NC}"
    p ""
    p "  ${YELLOW}Use this if you ran SHAPER_CALIBRATE manually (outside this${NC}"
    p "  ${YELLOW}script's workflow) and want to update the E5M-CK config.${NC}"
    p ""

    _extract_shaper_values

    if [ "$SHAPER_FOUND" != "yes" ]; then
        log_error "No SHAPER_CALIBRATE results found in klippy.log"
        log_error "Did you run SHAPER_CALIBRATE first (on Creality, ideally)?"
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    p ""
    p "${BR_RED}  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}  ┃${NC}  ${WHITE}${BOLD}Detected shaper values:${NC}                                       ${BR_RED}┃${NC}"
    p "${BR_RED}  ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
    p "${BR_RED}  ┃${NC}    ${WHITE}shaper_type_x: ${BOLD}${SHAPER_X_TYPE}${NC}${WHITE}     shaper_freq_x: ${BOLD}${SHAPER_X_FREQ} Hz${NC}                 ${BR_RED}┃${NC}"
    p "${BR_RED}  ┃${NC}    ${WHITE}shaper_type_y: ${BOLD}${SHAPER_Y_TYPE}${NC}${WHITE}     shaper_freq_y: ${BOLD}${SHAPER_Y_FREQ} Hz${NC}                ${BR_RED}┃${NC}"
    p "${BR_RED}  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""

    if ! _confirm_yes "inject these values into printer.cfg"; then
        log_warn "Cancelled by user"
        pause_user "Press ENTER to return to menu..."
        return 0
    fi

    # Backup current printer.cfg
    TS=$(date +%Y%m%d_%H%M%S)
    cp "$CONFIG_DIR/printer.cfg" "$SWITCH_DIR/printer.cfg.before_import_${TS}.bak"
    log_action "Backup: $SWITCH_DIR/printer.cfg.before_import_${TS}.bak"

    if _inject_input_shaper "$SHAPER_X_TYPE" "$SHAPER_X_FREQ" \
                            "$SHAPER_Y_TYPE" "$SHAPER_Y_FREQ" \
                            "$CONFIG_DIR/printer.cfg"; then
        _save_calibration_history "$SHAPER_X_TYPE" "$SHAPER_X_FREQ" \
                                  "$SHAPER_Y_TYPE" "$SHAPER_Y_FREQ"

        log_info "Restarting Klipper to apply changes..."
        $KLIPPER_SERVICE restart 2>&1 >/dev/null
        sleep 12

        if _check_klipper_ready; then
            log_ok "Klipper restarted successfully with new shaper values"
        else
            log_error "Klipper restart failed"
            _klipper_state_message
        fi
    else
        log_error "Injection failed"
    fi

    pause_user "Press ENTER to return to menu..."
}

# ═══════════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════════
show_main_menu() {
    MODE=$(current_mode)
    case "$MODE" in
        mainline)
            MODE_LINE="${BR_GREEN}●${NC} ${WHITE}Klipper mainline ${DIM}(E5M-CK)${NC}"
            ;;
        creality)
            MODE_LINE="${BR_YELLOW}●${NC} ${WHITE}Klipper Creality ${DIM}(for calibration)${NC}"
            ;;
        *)
            MODE_LINE="${BR_RED}●${NC} ${BR_RED}Unknown mode${NC}"
            ;;
    esac

    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${WHITE}${BOLD}SWITCH — Klipper Creality ⇄ Mainline${NC}                             ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}Current: $MODE_LINE"
    p ""
    p "  ${BG_RED}${WHITE}${BOLD} 1 ${NC}  ${WHITE}${BOLD}Full Input Shaper calibration workflow${NC} ${GRAY}(recommended)${NC}"
    p "       ${DIM}Auto-switches to Creality, guides you through SHAPER_CALIBRATE,${NC}"
    p "       ${DIM}parses results, switches back to mainline, injects values${NC}"
    p ""
    p "  ${BG_RED}${WHITE}${BOLD} 2 ${NC}  ${WHITE}Switch to Klipper Creality${NC}                ${GRAY}(manual mode)${NC}"
    p "  ${BG_RED}${WHITE}${BOLD} 3 ${NC}  ${WHITE}Switch to Klipper mainline${NC}                ${GRAY}(manual mode)${NC}"
    p ""
    p "  ${BG_RED}${WHITE}${BOLD} 4 ${NC}  ${WHITE}Show current status${NC}"
    p "  ${BG_RED}${WHITE}${BOLD} 5 ${NC}  ${WHITE}Import last SHAPER_CALIBRATE results${NC} ${GRAY}(from klippy.log)${NC}"
    p ""
    p "  ${BG_BLACK}${WHITE} q ${NC}  ${GRAY}Quit${NC}"
    p ""
    printf "  ${WHITE}Your choice [1-5/q]: ${NC}"
    read MAIN_CHOICE
}

# ═══════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════
main() {
    _ensure_dirs

    while true; do
        show_banner
        show_main_menu

        case $MAIN_CHOICE in
            1) full_workflow ;;
            2) switch_to_creality ;;
            3) switch_to_mainline ;;
            4) show_status ;;
            5) import_shaper_values ;;
            q|Q|"")
                p ""
                p "  ${WHITE}Goodbye!${NC}"
                p ""
                exit 0
                ;;
            *)
                log_warn "Invalid choice: $MAIN_CHOICE"
                sleep 2
                ;;
        esac
    done
}

main "$@"
