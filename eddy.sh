#!/bin/sh
# ============================================================
# E5M-CK Eddy Calibration Tool
# Dedicated Eddy configuration and calibration utility
# Creality Ender 5 Max — Nebula Pad
# https://github.com/christianKEL/E5M-CK
# ============================================================

GITHUB_RAW="https://raw.githubusercontent.com/christianKEL/E5M-CK/main"
E5M_DIR="/usr/data/E5M_CK"
CONFIG_DIR="/usr/data/printer_data/config"
KLIPPER_SERVICE="/etc/init.d/S55klipper_service"
MOONRAKER_API="http://localhost:7125"

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

# Minimal status colors
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
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} $STEP_NUM ${NC}  ${WHITE}${BOLD}$STEP_TITLE${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
}

# ─── BANNER ───
show_banner() {
    clear
    p ""
    p "${BR_RED}    ███████╗██████╗ ██████╗ ██╗   ██╗    ████████╗ ██████╗  ██████╗ ██╗${NC}"
    p "${BR_RED}    ██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝    ╚══██╔══╝██╔═══██╗██╔═══██╗██║${NC}"
    p "${BR_RED}    █████╗  ██║  ██║██║  ██║ ╚████╔╝        ██║   ██║   ██║██║   ██║██║${NC}"
    p "${BR_RED}    ██╔══╝  ██║  ██║██║  ██║  ╚██╔╝         ██║   ██║   ██║██║   ██║██║${NC}"
    p "${BR_RED}    ███████╗██████╔╝██████╔╝   ██║          ██║   ╚██████╔╝╚██████╔╝███████╗${NC}"
    p "${BR_RED}    ╚══════╝╚═════╝ ╚═════╝    ╚═╝          ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝${NC}"
    p ""
    p "${WHITE}              Eddy USB — Configuration and calibration tool${NC}"
    p "${GRAY}                 for Creality Ender 5 Max (E5M-CK)${NC}"
    p ""
    p "${DIM}                    github.com/christianKEL/E5M-CK${NC}"
    p ""
}

# ─── UTILITIES ───
die() { log_error "$1"; exit 1; }

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
        log_error "Fix Klipper first before running calibration."
        return 1
    fi
    return 0
}

# ─── GET NEBULA IP ───
_get_nebula_ip() {
    IP=$(ifconfig 2>/dev/null | grep -A1 'wlan0\|eth0' | grep 'inet ' | \
         awk '{print $2}' | sed 's/addr://' | head -1)
    [ -z "$IP" ] && IP="<nebula-ip>"
    echo "$IP"
}

# ─── QUERY SAVED CONFIG ───
_query_saved_config() {
    KEY=$1
    python3 -c "
import urllib.request, json
try:
    url = 'http://localhost:7125/printer/objects/query?configfile'
    d = json.loads(urllib.request.urlopen(url).read())
    settings = d['result']['status']['configfile']['settings']
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

# ─── BACKUP FILE ───
_backup_file() {
    FILE=$1
    if [ -f "$FILE" ]; then
        BACKUP_DIR="$E5M_DIR/BACKUP_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        cp "$FILE" "$BACKUP_DIR/$(basename $FILE)"
        log_action "Backup: $BACKUP_DIR/$(basename $FILE)"
    fi
}

# ═══════════════════════════════════════════════════════
# FONCTION 1 : APPLY OFFICIAL EDDY CONFIG (fix all issues)
# ═══════════════════════════════════════════════════════
apply_official_config() {
    log_step "CONFIG" "Apply official Klipper Eddy configuration"

    p ""
    p "  ${WHITE}This function applies the ${BOLD}official Klipper documentation${NC}${WHITE}${NC}"
    p "  ${WHITE}recommendations for Eddy USB probe:${NC}"
    p ""
    p "  ${WHITE}  • ${BOLD}descend_z: 0.5${NC}${WHITE} (not 2.5 — that was z_offset old value)${NC}"
    p "  ${WHITE}  • Official macros: ${BOLD}SET_Z_FROM_PROBE${NC}${WHITE} + ${BOLD}_RELOAD_Z_OFFSET_FROM_PROBE${NC}"
    p "  ${WHITE}  • Homing with ${BOLD}PROBE refinement${NC}${WHITE} after G28 Z${NC}"
    p "  ${WHITE}  • ${BOLD}position_min: -2${NC}${WHITE} for stepper_z (sample config)${NC}"
    p "  ${WHITE}  • Remove custom BTT macros that confuse Z offset tracking${NC}"
    p ""
    p "  ${YELLOW}Current files will be backed up in ${BOLD}$E5M_DIR/BACKUP_<timestamp>/${NC}"
    p ""

    if ! _confirm_yes "apply the official Eddy configuration"; then
        log_warn "Cancelled by user"
        pause_user "Press ENTER to return to menu..."
        return 0
    fi

    # Keep existing offsets from current eddy.cfg
    CUR_X=38
    CUR_Y=6
    CUR_SERIAL=""
    if [ -f "$CONFIG_DIR/eddy.cfg" ]; then
        X_TMP=$(grep "^x_offset:" $CONFIG_DIR/eddy.cfg | awk '{print $2}' | head -1)
        Y_TMP=$(grep "^y_offset:" $CONFIG_DIR/eddy.cfg | awk '{print $2}' | head -1)
        S_TMP=$(grep "^serial:" $CONFIG_DIR/eddy.cfg | awk '{print $2}' | head -1)
        [ -n "$X_TMP" ] && CUR_X=$X_TMP
        [ -n "$Y_TMP" ] && CUR_Y=$Y_TMP
        [ -n "$S_TMP" ] && CUR_SERIAL=$S_TMP
    fi

    if [ -z "$CUR_SERIAL" ]; then
        log_info "Searching for Eddy serial device..."
        CUR_SERIAL=$(ls /dev/serial/by-id/ 2>/dev/null | grep rp2040 | head -1)
        [ -n "$CUR_SERIAL" ] && CUR_SERIAL="/dev/serial/by-id/$CUR_SERIAL"
    fi

    if [ -z "$CUR_SERIAL" ] || [ "$CUR_SERIAL" = "TO_BE_FILLED_AFTER_FLASH" ]; then
        log_error "Eddy serial not found. Make sure Eddy USB is plugged in."
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    log_info "Current settings detected:"
    log_action "x_offset: $CUR_X"
    log_action "y_offset: $CUR_Y"
    log_action "serial: $CUR_SERIAL"

    # Backup existing files
    log_info "Backing up current files..."
    _backup_file "$CONFIG_DIR/eddy.cfg"
    _backup_file "$CONFIG_DIR/homing.cfg"
    _backup_file "$CONFIG_DIR/printer.cfg"

    # ─── Write eddy.cfg ───
    log_info "Writing ${BOLD}eddy.cfg${NC} (official Klipper config)..."
    cat > $CONFIG_DIR/eddy.cfg << EDDYEOF
# ═══════════════════════════════════════════════════════
# BTT Eddy USB — Klipper mainline configuration
# Aligned with OFFICIAL Klipper documentation
# https://www.klipper3d.org/Eddy_Probe.html
# ═══════════════════════════════════════════════════════

[mcu eddy]
serial: $CUR_SERIAL
restart_method: command

[temperature_sensor btt_eddy_mcu]
sensor_type: temperature_mcu
sensor_mcu: eddy
min_temp: 10
max_temp: 100

[probe_eddy_current btt_eddy]
sensor_type: ldc1612
descend_z: 0.5
i2c_mcu: eddy
i2c_bus: i2c0f
x_offset: $CUR_X
y_offset: $CUR_Y

[temperature_probe btt_eddy]
sensor_type: Generic 3950
sensor_pin: eddy:gpio26
horizontal_move_z: 2

# ─── OFFICIAL KLIPPER HOMING CORRECTION MACROS ───
# https://www.klipper3d.org/Eddy_Probe.html#homing-correction-macros

[gcode_macro _RELOAD_Z_OFFSET_FROM_PROBE]
gcode:
  {% set Z = printer.toolhead.position.z %}
  SET_KINEMATIC_POSITION Z={Z - printer.probe.last_probe_position.z}

[gcode_macro SET_Z_FROM_PROBE]
gcode:
  {% set METHOD = params.METHOD | default("automatic") %}
  PROBE METHOD={METHOD}
  _RELOAD_Z_OFFSET_FROM_PROBE
  G0 Z5
EDDYEOF
    log_ok "eddy.cfg written"

    # ─── Write homing.cfg ───
    log_info "Writing ${BOLD}homing.cfg${NC} with probe refinement..."
    cat > $CONFIG_DIR/homing.cfg << 'HOMEOF'
# ═══════════════════════════════════════════════════════
# HOMING — CoreXY sequence (Y -> X -> Z at bed center)
# Uses PROBE + SET_Z_FROM_PROBE for precise Z after G28 Z
# Required because Eddy homing alone is not precise
# ═══════════════════════════════════════════════════════

[homing_override]
axes: xyz
set_position_z: 0
gcode:
  G90
  {% set home_all = 'X' not in params and 'Y' not in params and 'Z' not in params %}
  # Lift Z first to avoid Eddy saturation / collisions
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
    # Move to bed center for Z homing
    G0 X200 Y200 F6000
    # Rough Z homing via Eddy virtual endstop
    G28 Z
    G1 Z10 F600
    # Refine Z with a PROBE (Eddy homing is NOT precise, official doc says so)
    SET_Z_FROM_PROBE
  {% endif %}
HOMEOF
    log_ok "homing.cfg written"

    # ─── Patch printer.cfg : position_min for stepper_z ───
    log_info "Patching printer.cfg : position_min for stepper_z..."
    python3 << 'PYEOF'
import re
path = '/usr/data/printer_data/config/printer.cfg'
with open(path) as f:
    content = f.read()

# Find stepper_z section and set position_min: -2 (Klipper sample recommendation)
# Match [stepper_z] ... up to next section
pattern = r'(\[stepper_z\][^\[]*?position_min:\s*)-?\d+\.?\d*'
new_content = re.sub(pattern, r'\g<1>-2', content, count=1, flags=re.DOTALL)

if new_content != content:
    with open(path, 'w') as f:
        f.write(new_content)
    print("position_min set to -2 for stepper_z")
else:
    print("position_min unchanged (may already be correct)")
PYEOF
    log_ok "printer.cfg patched"

    # ─── Patch printer.cfg : bed_mesh bounds with scan_overshoot clearance ───
    log_info "Patching bed_mesh in printer.cfg (scan_overshoot-safe bounds)..."
    python3 << PYEOF
import re
path = '/usr/data/printer_data/config/printer.cfg'
with open(path) as f:
    content = f.read()

x = float("$CUR_X")
y = float("$CUR_Y")

POS_MIN_X = 0
POS_MIN_Y = 0
POS_MAX_X = 406
POS_MAX_Y = 401
MARGIN = 15
SCAN_OVERSHOOT = 8

if x >= 0:
    mesh_min_x = POS_MIN_X + max(MARGIN, x + SCAN_OVERSHOOT)
    mesh_max_x = POS_MAX_X - MARGIN
else:
    mesh_min_x = POS_MIN_X + MARGIN
    mesh_max_x = POS_MAX_X - max(MARGIN, abs(x) + SCAN_OVERSHOOT)

if y >= 0:
    mesh_min_y = POS_MIN_Y + max(MARGIN, y)
    mesh_max_y = POS_MAX_Y - MARGIN
else:
    mesh_min_y = POS_MIN_Y + MARGIN
    mesh_max_y = POS_MAX_Y - max(MARGIN, abs(y))

content = re.sub(r'mesh_min:\s*[\d.\-]+,\s*[\d.\-]+', f'mesh_min: {mesh_min_x:.1f}, {mesh_min_y:.1f}', content)
content = re.sub(r'mesh_max:\s*[\d.\-]+,\s*[\d.\-]+', f'mesh_max: {mesh_max_x:.1f}, {mesh_max_y:.1f}', content)

# Ensure scan_overshoot: 8 is explicit
if re.search(r'^\s*scan_overshoot:', content, re.MULTILINE):
    content = re.sub(r'(^\s*scan_overshoot:\s*)[\d.]+', r'\g<1>8', content, count=1, flags=re.MULTILINE)
else:
    content = re.sub(
        r'(\[bed_mesh\][^\[]*?mesh_max:\s*[\d.\-]+,\s*[\d.\-]+\n)',
        r'\g<1>scan_overshoot: 8\n',
        content,
        count=1,
        flags=re.DOTALL
    )

with open(path, 'w') as f:
    f.write(content)

print(f"mesh_min={mesh_min_x:.1f},{mesh_min_y:.1f} mesh_max={mesh_max_x:.1f},{mesh_max_y:.1f} scan_overshoot=8")
PYEOF
    log_ok "bed_mesh bounds updated with scan_overshoot clearance"

    # ─── Restart Klipper ───
    log_info "Restarting Klipper service..."
    $KLIPPER_SERVICE restart 2>&1 | while read line; do log_action "$line"; done
    sleep 15

    if _check_klipper_ready; then
        log_ok "Klipper ready with new official Eddy config"
    else
        log_warn "Klipper state uncertain — check klippy.log"
    fi

    pause_user "Press ENTER to return to menu..."
}

# ═══════════════════════════════════════════════════════
# FONCTION 2 : CONFIGURE EDDY OFFSETS (was option 3)
# ═══════════════════════════════════════════════════════
configure_eddy_offsets() {
    log_step "OFFSETS" "Configure BTT Eddy X/Y offsets"

    if [ ! -f "$CONFIG_DIR/eddy.cfg" ]; then
        log_error "eddy.cfg not found at $CONFIG_DIR/eddy.cfg"
        log_error "Please run the full installation first."
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    # Read current offsets
    CUR_X=$(grep "^x_offset:" $CONFIG_DIR/eddy.cfg | awk '{print $2}' | head -1)
    CUR_Y=$(grep "^y_offset:" $CONFIG_DIR/eddy.cfg | awk '{print $2}' | head -1)
    [ -z "$CUR_X" ] && CUR_X=0
    [ -z "$CUR_Y" ] && CUR_Y=0

    p ""
    p "  ${WHITE}${BOLD}Current BTT Eddy offsets:${NC}"

    # Explain sign for X
    case "$CUR_X" in
        -*)  p "    ${WHITE}x_offset: ${BOLD}$CUR_X mm${NC}  ${GRAY}(Eddy is LEFT of nozzle)${NC}" ;;
        0|0.0) p "    ${WHITE}x_offset: ${BOLD}$CUR_X mm${NC}  ${GRAY}(Eddy aligned on X axis)${NC}" ;;
        *)   p "    ${WHITE}x_offset: ${BOLD}+$CUR_X mm${NC}  ${GRAY}(Eddy is RIGHT of nozzle)${NC}" ;;
    esac

    # Explain sign for Y
    case "$CUR_Y" in
        -*)  p "    ${WHITE}y_offset: ${BOLD}$CUR_Y mm${NC}  ${GRAY}(Eddy is in FRONT of nozzle)${NC}" ;;
        0|0.0) p "    ${WHITE}y_offset: ${BOLD}$CUR_Y mm${NC}  ${GRAY}(Eddy aligned on Y axis)${NC}" ;;
        *)   p "    ${WHITE}y_offset: ${BOLD}+$CUR_Y mm${NC}  ${GRAY}(Eddy is BEHIND nozzle)${NC}" ;;
    esac

    p ""
    p "  ${YELLOW}Offsets should be measured physically from nozzle tip to Eddy center.${NC}"
    p ""

    printf "  ${WHITE}New X offset in mm (default keep current ${CUR_X}): ${NC}"
    read NEW_X
    [ -z "$NEW_X" ] && NEW_X=$CUR_X

    printf "  ${WHITE}New Y offset in mm (default keep current ${CUR_Y}): ${NC}"
    read NEW_Y
    [ -z "$NEW_Y" ] && NEW_Y=$CUR_Y

    # Validate + compute mesh bounds
    # IMPORTANT: rapid_scan needs scan_overshoot clearance BEYOND mesh_min/max
    # because the nozzle (not the probe) accelerates/decelerates over that margin.
    # Formula: mesh_min_nozzle_side >= offset + SCAN_OVERSHOOT
    VALIDATION=$(python3 << PYEOF
import sys
try:
    x = float("$NEW_X")
    y = float("$NEW_Y")
except ValueError:
    print("INVALID_NUMBER")
    sys.exit(1)

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
MARGIN = 15
SCAN_OVERSHOOT = 8  # default rapid_scan overshoot in Klipper

# X axis (rapid_scan moves along X, so overshoot applies)
# If probe is to the RIGHT of nozzle (x_offset > 0):
#   at mesh_min, nozzle is at mesh_min - x_offset
#   nozzle must overshoot by SCAN_OVERSHOOT to the left
#   so: mesh_min - x_offset - SCAN_OVERSHOOT >= POS_MIN_X
#   => mesh_min >= POS_MIN_X + x_offset + SCAN_OVERSHOOT
# If probe is to the LEFT (x_offset < 0):
#   at mesh_max, nozzle is at mesh_max - x_offset = mesh_max + |x_offset|
#   nozzle must overshoot by SCAN_OVERSHOOT to the right
#   => mesh_max <= POS_MAX_X - |x_offset| - SCAN_OVERSHOOT
if x >= 0:
    mesh_min_x = POS_MIN_X + max(MARGIN, x + SCAN_OVERSHOOT)
    mesh_max_x = POS_MAX_X - MARGIN
else:
    mesh_min_x = POS_MIN_X + MARGIN
    mesh_max_x = POS_MAX_X - max(MARGIN, abs(x) + SCAN_OVERSHOOT)

# Y axis (rapid_scan scans in X, no overshoot in Y, just clearance for probe)
if y >= 0:
    mesh_min_y = POS_MIN_Y + max(MARGIN, y)
    mesh_max_y = POS_MAX_Y - MARGIN
else:
    mesh_min_y = POS_MIN_Y + MARGIN
    mesh_max_y = POS_MAX_Y - max(MARGIN, abs(y))

usable_x = mesh_max_x - mesh_min_x
usable_y = mesh_max_y - mesh_min_y

if usable_x < 100 or usable_y < 100:
    print(f"TOO_SMALL|{usable_x:.1f}|{usable_y:.1f}")
    sys.exit(1)

print(f"OK|{x}|{y}|{mesh_min_x:.1f}|{mesh_min_y:.1f}|{mesh_max_x:.1f}|{mesh_max_y:.1f}|{usable_x:.1f}|{usable_y:.1f}")
PYEOF
)

    RESULT=$(echo "$VALIDATION" | cut -d'|' -f1)

    case "$RESULT" in
        "INVALID_NUMBER")
            log_error "Invalid number format (use e.g. 38 or -12.5)"
            pause_user "Press ENTER to return to menu..."
            return 1
            ;;
        "X_TOO_LARGE"|"Y_TOO_LARGE")
            log_error "Offset too large (|offset| > 100mm). Check physical setup."
            pause_user "Press ENTER to return to menu..."
            return 1
            ;;
        "TOO_SMALL")
            U_X=$(echo "$VALIDATION" | cut -d'|' -f2)
            U_Y=$(echo "$VALIDATION" | cut -d'|' -f3)
            log_error "Usable mesh too small: ${U_X}x${U_Y} mm (min 100x100)"
            pause_user "Press ENTER to return to menu..."
            return 1
            ;;
        "OK")
            X=$(echo "$VALIDATION" | cut -d'|' -f2)
            Y=$(echo "$VALIDATION" | cut -d'|' -f3)
            MIN_X=$(echo "$VALIDATION" | cut -d'|' -f4)
            MIN_Y=$(echo "$VALIDATION" | cut -d'|' -f5)
            MAX_X=$(echo "$VALIDATION" | cut -d'|' -f6)
            MAX_Y=$(echo "$VALIDATION" | cut -d'|' -f7)
            U_X=$(echo "$VALIDATION" | cut -d'|' -f8)
            U_Y=$(echo "$VALIDATION" | cut -d'|' -f9)
            ;;
    esac

    # Display summary
    p ""
    p "${BR_RED}  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}  ┃${NC}  ${WHITE}${BOLD}Summary of changes:${NC}                                            ${BR_RED}┃${NC}"
    p "${BR_RED}  ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
    p "${BR_RED}  ┃${NC}  ${GRAY}x_offset: ${CUR_X} → ${BOLD}${WHITE}${X} mm${NC}                                       ${BR_RED}┃${NC}"
    p "${BR_RED}  ┃${NC}  ${GRAY}y_offset: ${CUR_Y} → ${BOLD}${WHITE}${Y} mm${NC}                                       ${BR_RED}┃${NC}"
    p "${BR_RED}  ┃${NC}  ${WHITE}New bed_mesh (with scan_overshoot=8 clearance):${NC}               ${BR_RED}┃${NC}"
    p "${BR_RED}  ┃${NC}    mesh_min: ${BOLD}${MIN_X}, ${MIN_Y}${NC}                                        ${BR_RED}┃${NC}"
    p "${BR_RED}  ┃${NC}    mesh_max: ${BOLD}${MAX_X}, ${MAX_Y}${NC}                                       ${BR_RED}┃${NC}"
    p "${BR_RED}  ┃${NC}    Usable area: ${BOLD}${U_X} x ${U_Y} mm${NC}                             ${BR_RED}┃${NC}"
    p "${BR_RED}  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""

    printf "  ${WHITE}${BOLD}Apply these changes? [y/N]: ${NC}"
    read CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        log_warn "Cancelled by user"
        pause_user "Press ENTER to return to menu..."
        return 0
    fi

    # Backup and apply
    _backup_file "$CONFIG_DIR/eddy.cfg"
    _backup_file "$CONFIG_DIR/printer.cfg"

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

# Ensure scan_overshoot: 8 is explicit in [bed_mesh] section
if re.search(r'^\s*scan_overshoot:', content, re.MULTILINE):
    content = re.sub(r'(^\s*scan_overshoot:\s*)[\d.]+', r'\g<1>8', content, count=1, flags=re.MULTILINE)
else:
    # Insert scan_overshoot: 8 right after mesh_max line in [bed_mesh] section
    content = re.sub(
        r'(\[bed_mesh\][^\[]*?mesh_max:\s*[\d.\-]+,\s*[\d.\-]+\n)',
        r'\g<1>scan_overshoot: 8\n',
        content,
        count=1,
        flags=re.DOTALL
    )

with open(path, "w") as f:
    f.write(content)
PYEOF
    log_action "bed_mesh: mesh_min=${MIN_X},${MIN_Y} mesh_max=${MAX_X},${MAX_Y} scan_overshoot=8"

    log_info "Restarting Klipper service..."
    $KLIPPER_SERVICE restart 2>&1 | while read line; do log_action "$line"; done
    sleep 15

    if _check_klipper_ready; then
        log_ok "Klipper restarted successfully — new offsets applied"
    else
        log_warn "Klipper state uncertain — check logs"
    fi

    pause_user "Press ENTER to return to menu..."
}

# ═══════════════════════════════════════════════════════
# FONCTION 3 : FULL CALIBRATION ASSISTANT
# ═══════════════════════════════════════════════════════
full_calibration_assistant() {
    if ! _check_klipper_ready; then
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    NEBULA_IP=$(_get_nebula_ip)

    # ───── STEP 0 — PREREQUISITES ─────
    clear
    p ""
    p "${BG_RED}${WHITE}${BOLD}                                                                     ${NC}"
    p "${BG_RED}${WHITE}${BOLD}   ⚠  FULL EDDY CALIBRATION — READ CAREFULLY  ⚠                      ${NC}"
    p "${BG_RED}${WHITE}${BOLD}                                                                     ${NC}"
    p ""
    p "  ${WHITE}${BOLD}Prerequisites:${NC}"
    p "  ${WHITE}  • ${BOLD}Fluidd open${NC}${WHITE} in your browser:${NC}"
    p "  ${WHITE}    ${UNDER}${BR_RED}http://${NEBULA_IP}:4408${NC}"
    p "  ${WHITE}  • A ${BOLD}standard A4 80gsm paper sheet${NC}${WHITE} for the paper test${NC}"
    p "  ${WHITE}  • ${BOLD}Clean nozzle${NC}${WHITE} (no plastic residue)${NC}"
    p "  ${WHITE}  • ${BOLD}Clean bed${NC}${WHITE} (no debris)${NC}"
    p "  ${WHITE}  • ${BOLD}Eddy probe mounted securely${NC}"
    p ""
    p "  ${BR_RED}${BOLD}SAFETY RULES:${NC}"
    p "  ${BR_RED}  ⚠  ${WHITE}Keep hands AWAY from moving parts${NC}"
    p "  ${BR_RED}  ⚠  ${WHITE}Be ready for EMERGENCY STOP at any moment${NC}"
    p "  ${BR_RED}  ⚠  ${WHITE}Follow the exact order of steps${NC}"
    p ""
    p "  ${WHITE}${BOLD}Calibration steps (~30-60 min):${NC}"
    p "  ${WHITE}    1. Preparation check (G28 XY works?)${NC}"
    p "  ${WHITE}    2. Drive current calibration${NC}"
    p "  ${WHITE}    3. Height mapping calibration ${BR_RED}(most critical)${NC}"
    p "  ${WHITE}    4. Z=0 verification (paper test)${NC}"
    p "  ${WHITE}    5. Temperature drift calibration ${DIM}(optional)${NC}"
    p "  ${WHITE}    6. Bed mesh generation${NC}"
    p ""

    if ! _confirm_yes "you understand and accept these risks"; then
        log_warn "Calibration cancelled"
        pause_user "Press ENTER to return to menu..."
        return 0
    fi

    _eddy_step1_preparation || return 1
    _eddy_step2_drive_current || return 1
    _eddy_step3_height_mapping || return 1
    _eddy_step4_z_verification || return 1
    _eddy_step5_temperature
    _eddy_step6_bed_mesh || return 1

    _eddy_show_completion
}

# ───── STEP 1 : PREPARATION ─────
_eddy_step1_preparation() {
    NEBULA_IP=$(_get_nebula_ip)
    clear
    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} STEP 1/6 ${NC} ${WHITE}${BOLD}Preparation check${NC}                                 ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}Verify that XY homing and toolhead movements work correctly${NC}"
    p "  ${WHITE}before starting Eddy calibration.${NC}"
    p ""
    p "  ${YELLOW}${BOLD}NOTE: CAL_BED_Z_TILT and G28 Z don't work yet — they need a${NC}"
    p "  ${YELLOW}${BOLD}calibrated Eddy probe, which is what we're about to set up.${NC}"
    p ""
    p "  ${WHITE}${BOLD}Quick checks (in Fluidd console):${NC}"
    p "  ${WHITE}  ${BR_GREEN}${BOLD}1.${NC} ${BR_GREEN}G28 X Y${NC}                          ${DIM}# home X and Y only${NC}"
    p "  ${WHITE}  ${BR_GREEN}${BOLD}2.${NC} ${BR_GREEN}CENTER_TOOLHEAD${NC}                  ${DIM}# move to 200,200${NC}"
    p "  ${WHITE}     ${DIM}Verify toolhead moves correctly — no grinding, no collisions${NC}"
    p ""
    p "  ${WHITE}${BOLD}Open Fluidd:${NC} ${UNDER}${BR_RED}http://${NEBULA_IP}:4408${NC}"
    p ""

    if ! _confirm_yes "XY homing works and toolhead reaches center"; then
        log_warn "Step 1 cancelled"
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    if ! _check_klipper_ready; then
        log_error "Klipper state is not ready"
        pause_user "Press ENTER to return to menu..."
        return 1
    fi
    log_ok "Step 1 complete — XY movements OK"
    return 0
}

# ───── STEP 2 : DRIVE CURRENT ─────
_eddy_step2_drive_current() {
    clear
    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} STEP 2/6 ${NC} ${WHITE}${BOLD}Drive current calibration${NC}                          ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}This step finds the optimal signal strength for the LDC1612 chip.${NC}"
    p "  ${WHITE}The nozzle must be ${BOLD}~20mm above the bed${NC}${WHITE} (Eddy 17mm above).${NC}"
    p ""
    p "  ${YELLOW}${BOLD}WARNING:${NC}"
    p "  ${YELLOW}  • Too close: magnetic interference → invalid calibration${NC}"
    p "  ${YELLOW}  • Too far: insufficient signal → invalid calibration${NC}"
    p ""
    p "  ${WHITE}${BOLD}Instructions (in Fluidd console):${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}1.${NC} ${BR_GREEN}G28 X Y${NC}                          ${DIM}# home X and Y only${NC}"
    p "  ${WHITE}  ${BR_GREEN}${BOLD}2.${NC} ${BR_GREEN}CENTER_TOOLHEAD${NC}                  ${DIM}# move to center${NC}"
    p "  ${WHITE}  ${BR_GREEN}${BOLD}3.${NC} ${BR_GREEN}SET_KINEMATIC_Z_200${NC}              ${DIM}# trick Klipper (Z=200)${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}4.${NC} ${WHITE}Using Fluidd ${BOLD}Z arrows${NC}${WHITE}, move bed to get ~${BOLD}20mm gap${NC}"
    p "  ${WHITE}     ${DIM}10mm step, click to increase gap between nozzle and bed.${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}5.${NC} ${BR_GREEN}LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy${NC}"
    p "  ${WHITE}     ${DIM}(takes ~30 seconds)${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}6.${NC} ${BR_GREEN}SAVE_CONFIG${NC}                      ${DIM}# Klipper restarts${NC}"
    p ""

    if ! _confirm_yes "nozzle is ~20mm above bed and you are ready"; then
        log_warn "Step 2 cancelled"
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    _wait_enter "When SAVE_CONFIG has finished and Klipper has restarted"

    log_info "Checking that reg_drive_current was saved..."
    sleep 5
    if ! _check_klipper_ready; then
        log_error "Klipper not ready after SAVE_CONFIG"
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    RESULT=$(_query_saved_config "reg_drive_current")
    if [ "$RESULT" = "FOUND" ]; then
        log_ok "Step 2 complete — reg_drive_current saved"
    else
        log_warn "reg_drive_current not detected in saved_config"
        printf "  ${WHITE}Continue anyway? (y/n): ${NC}"
        read CONT
        [ "$CONT" != "y" ] && [ "$CONT" != "Y" ] && return 1
    fi
    return 0
}

# ───── STEP 3 : HEIGHT MAPPING ─────
_eddy_step3_height_mapping() {
    clear
    p ""
    p "${BG_RED}${WHITE}${BOLD}                                                                     ${NC}"
    p "${BG_RED}${WHITE}${BOLD}   ⚠  STEP 3/6 — MOST CRITICAL — READ CAREFULLY  ⚠                   ${NC}"
    p "${BG_RED}${WHITE}${BOLD}                                                                     ${NC}"
    p ""
    p "  ${WHITE}This step maps sensor readings to actual Z heights.${NC}"
    p "  ${WHITE}It requires a ${BOLD}paper test${NC}${WHITE} (A4 80gsm).${NC}"
    p ""
    p "  ${BR_RED}${BOLD}⚠  CRASH RISK:${NC}"
    p "  ${BR_RED}  • Going too low will ${BOLD}CRASH the nozzle into the bed${NC}"
    p "  ${BR_RED}  • Use ${BOLD}0.1mm steps${NC}${BR_RED} near the bed${NC}"
    p "  ${BR_RED}  • STOP the moment the paper shows resistance${NC}"
    p ""
    p "  ${WHITE}${BOLD}Instructions (in Fluidd console):${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}1.${NC} ${BR_GREEN}CAL_EDDY_MAPPING${NC}                 ${DIM}# prepare position${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}2.${NC} ${WHITE}Place A4 paper between nozzle and bed${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}3.${NC} ${WHITE}Using Fluidd Z arrows with ${BOLD}0.1mm step${NC}${WHITE}:${NC}"
    p "  ${WHITE}     Move bed so nozzle approaches paper until paper drags slightly${NC}"
    p "  ${WHITE}     ${BR_RED}${BOLD}STOP IMMEDIATELY${NC}${WHITE} when paper drags${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}4.${NC} ${WHITE}REMOVE the paper sheet from the bed${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}5.${NC} ${BR_GREEN}PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}6.${NC} ${WHITE}When prompted ${BOLD}TESTZ / ACCEPT${NC}${WHITE}:${NC}"
    p "  ${WHITE}      Replace paper, use ${BR_GREEN}TESTZ Z=-0.1${NC}${WHITE} until catches${NC}"
    p "  ${WHITE}      then send ${BR_GREEN}ACCEPT${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}7.${NC} ${WHITE}Wait for full calibration (~2 min, many moves)${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}8.${NC} ${BR_GREEN}SAVE_CONFIG${NC}                      ${DIM}# Klipper restarts${NC}"
    p ""

    if ! _confirm_yes "you have A4 paper ready AND understand crash risk"; then
        log_warn "Step 3 cancelled"
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    _wait_enter "When SAVE_CONFIG has finished and Klipper has restarted"

    sleep 5
    if ! _check_klipper_ready; then
        log_error "Klipper not ready after SAVE_CONFIG"
        pause_user "Press ENTER to return to menu..."
        return 1
    fi
    log_ok "Step 3 complete — probe height mapping saved"
    return 0
}

# ───── STEP 4 : Z=0 VERIFICATION (with FORCE_MOVE fix) ─────
_eddy_step4_z_verification() {
    clear
    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} STEP 4/6 ${NC} ${WHITE}${BOLD}Z=0 verification (MANDATORY)${NC}                        ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}Verify that after ${BOLD}G28${NC}${WHITE}, the nozzle at ${BOLD}Z=0${NC}${WHITE} matches paper-contact.${NC}"
    p ""
    p "  ${YELLOW}${BOLD}IMPORTANT:${NC}"
    p "  ${YELLOW}  After SAVE_CONFIG at step 3, the bed may be VERY close to the${NC}"
    p "  ${YELLOW}  nozzle. A direct G28 would trigger 'Probe triggered prior to${NC}"
    p "  ${YELLOW}  movement'. We must move the bed away FIRST using FORCE_MOVE.${NC}"
    p ""
    p "  ${WHITE}${BOLD}Instructions (in Fluidd console):${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}1.${NC} ${BR_GREEN}FORCE_MOVE STEPPER=stepper_z DISTANCE=20 VELOCITY=5${NC}"
    p "  ${WHITE}     ${DIM}# Move bed 20mm away from nozzle (safe distance for G28)${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}2.${NC} ${BR_GREEN}G28${NC}                              ${DIM}# full home (Y→X→Z probe)${NC}"
    p "  ${WHITE}     ${DIM}Homing includes PROBE refinement — Z=0 will be accurate${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}3.${NC} ${BR_GREEN}CENTER_TOOLHEAD${NC}                  ${DIM}# move to center${NC}"
    p "  ${WHITE}  ${BR_GREEN}${BOLD}4.${NC} ${BR_GREEN}G1 Z0 F300${NC}                       ${DIM}# go to Z=0${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}5.${NC} ${WHITE}Place A4 paper between nozzle and bed${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}6.${NC} ${WHITE}Check paper resistance:${NC}"
    p "  ${WHITE}     ${BR_GREEN}• Paper catches slightly${NC} ${WHITE}→ calibration OK${NC}"
    p "  ${WHITE}     ${YELLOW}• Paper moves freely${NC} ${WHITE}→ nozzle too high${NC}"
    p "  ${BR_RED}     • Paper is stuck / crushed${NC} ${WHITE}→ nozzle too low${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}7.${NC} ${WHITE}If adjustment needed, use ${BR_GREEN}Z_OFFSET_APPLY_PROBE${NC}${WHITE}:${NC}"
    p "  ${WHITE}      ${BR_GREEN}SET_GCODE_OFFSET Z_ADJUST=-0.05 MOVE=1${NC}${WHITE} (too low → raise)${NC}"
    p "  ${WHITE}      ${BR_GREEN}SET_GCODE_OFFSET Z_ADJUST=+0.05 MOVE=1${NC}${WHITE} (too high → lower)${NC}"
    p "  ${WHITE}      Then: ${BR_GREEN}Z_OFFSET_APPLY_PROBE${NC}${WHITE} + ${BR_GREEN}SAVE_CONFIG${NC}"
    p ""

    _wait_enter "When Z=0 verification is complete"

    if ! _check_klipper_ready; then
        log_error "Klipper not ready"
        pause_user "Press ENTER to return to menu..."
        return 1
    fi
    log_ok "Step 4 complete — Z=0 verified"
    return 0
}

# ───── STEP 5 : TEMPERATURE DRIFT (optional) ─────
_eddy_step5_temperature() {
    clear
    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} STEP 5/6 ${NC} ${WHITE}${BOLD}Temperature drift (OPTIONAL)${NC}                        ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}Eddy sensors drift with temperature. This calibration records${NC}"
    p "  ${WHITE}the sensor response at several temperatures.${NC}"
    p ""
    p "  ${YELLOW}${BOLD}RECOMMENDED ONLY IF:${NC}"
    p "  ${YELLOW}  • You use an ${BOLD}enclosure${NC}${YELLOW} on your printer${NC}"
    p "  ${YELLOW}  • You print materials needing high chamber temps${NC}"
    p "  ${YELLOW}  • You notice first-layer issues after long prints${NC}"
    p ""
    p "  ${WHITE}${BOLD}Without enclosure: you can SKIP this step.${NC}"
    p ""
    p "  ${DIM}Duration: ~20-40 min (paper tests as bed heats up)${NC}"
    p ""

    printf "  ${WHITE}${BOLD}Run temperature drift calibration? [y/N]: ${NC}"
    read RUN_TEMP
    if [ "$RUN_TEMP" != "y" ] && [ "$RUN_TEMP" != "Y" ]; then
        log_info "Step 5 skipped (no enclosure / not needed)"
        return 0
    fi

    p ""
    printf "  ${WHITE}Target temperature in °C (default 49): ${NC}"
    read TEMP_TARGET
    [ -z "$TEMP_TARGET" ] && TEMP_TARGET=49

    if ! echo "$TEMP_TARGET" | grep -qE '^[0-9]+$'; then
        log_error "Invalid temperature: $TEMP_TARGET"
        pause_user "Press ENTER to skip..."
        return 0
    fi
    if [ "$TEMP_TARGET" -lt 30 ] || [ "$TEMP_TARGET" -gt 80 ]; then
        log_error "Temperature must be 30-80 °C"
        pause_user "Press ENTER to skip..."
        return 0
    fi

    clear
    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${WHITE}${BOLD}Temperature drift calibration${NC}                                    ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}Parameters:${NC}"
    p "  ${WHITE}  • TARGET: ${BOLD}${TEMP_TARGET}°C${NC}"
    p "  ${WHITE}  • STEP: ${BOLD}10°C${NC} ${DIM}(sample every 10°C rise)${NC}"
    p ""
    p "  ${YELLOW}${BOLD}WARNING: Each sample requires a paper test (A4).${NC}"
    p ""
    p "  ${WHITE}${BOLD}Instructions (in Fluidd console):${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}1.${NC} ${BR_GREEN}G28${NC}"
    p "  ${WHITE}  ${BR_GREEN}${BOLD}2.${NC} ${BR_GREEN}CENTER_TOOLHEAD${NC}"
    p "  ${WHITE}  ${BR_GREEN}${BOLD}3.${NC} ${BR_GREEN}SET_IDLE_TIMEOUT TIMEOUT=36000${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}4.${NC} ${BR_GREEN}TEMPERATURE_PROBE_CALIBRATE PROBE=btt_eddy TARGET=${TEMP_TARGET} STEP=10${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}5.${NC} ${WHITE}Klipper prompts paper test at current temp${NC}"
    p "  ${WHITE}     Place paper, adjust with ${BR_GREEN}TESTZ Z=-0.1${NC}${WHITE}, then ${BR_GREEN}ACCEPT${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}6.${NC} ${WHITE}Heat bed progressively:${NC}"
    p "  ${WHITE}     ${BR_GREEN}M140 S35${NC}${WHITE} (wait temp), paper test${NC}"
    p "  ${WHITE}     ${BR_GREEN}M140 S45${NC}${WHITE} (wait temp), paper test${NC}"
    p "  ${WHITE}     ... until TARGET=${TEMP_TARGET}°C${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}7.${NC} ${BR_GREEN}SAVE_CONFIG${NC}"
    p "  ${WHITE}  ${BR_GREEN}${BOLD}8.${NC} ${BR_GREEN}M140 S0${NC}                          ${DIM}# cool bed${NC}"
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
    return 0
}

# ───── STEP 6 : BED MESH ─────
_eddy_step6_bed_mesh() {
    clear
    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} STEP 6/6 ${NC} ${WHITE}${BOLD}Bed mesh generation${NC}                                 ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${WHITE}Generates a precise height map using ${BOLD}CAL_BED_MESH_PRECISE${NC}"
    p "  ${WHITE}(25x25 points, method=scan, ~2 minutes)${NC}"
    p ""
    p "  ${YELLOW}${BOLD}WARNING:${NC}"
    p "  ${YELLOW}  • ${BOLD}Nothing on the bed${NC}${YELLOW} during scan${NC}"
    p "  ${YELLOW}  • Stable bed temperature${NC}"
    p ""
    p "  ${WHITE}${BOLD}Instructions (in Fluidd console):${NC}"
    p ""
    p "  ${WHITE}  ${BR_GREEN}${BOLD}1.${NC} ${BR_GREEN}CAL_BED_Z_TILT${NC}                   ${DIM}# now Z is calibrated, this works${NC}"
    p "  ${WHITE}  ${BR_GREEN}${BOLD}2.${NC} ${BR_GREEN}CAL_BED_MESH_PRECISE${NC}             ${DIM}# 25x25 precise scan${NC}"
    p "  ${WHITE}  ${BR_GREEN}${BOLD}3.${NC} ${BR_GREEN}SAVE_CONFIG${NC}"
    p ""

    if ! _confirm_yes "bed is clear and ready"; then
        log_warn "Step 6 cancelled"
        pause_user "Press ENTER to return to menu..."
        return 1
    fi

    _wait_enter "When SAVE_CONFIG has finished after the mesh scan"

    sleep 5
    if ! _check_klipper_ready; then
        log_error "Klipper not ready after SAVE_CONFIG"
        pause_user "Press ENTER to return to menu..."
        return 1
    fi
    log_ok "Step 6 complete — bed mesh saved"
    return 0
}

# ───── COMPLETION ─────
_eddy_show_completion() {
    clear
    p ""
    p "${BR_RED}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${BG_RED}${WHITE}${BOLD}  ✓  EDDY CALIBRATION COMPLETE  ${NC}                            ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Your printer is calibrated and ready to print.${NC}                ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}${BOLD}Recommendations:${NC}                                             ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}• Run CAL_BED_MESH before each print${NC}                          ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}• Repeat CAL_BED_MESH_PRECISE monthly${NC}                         ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${DIM}• Re-run this tool if you move/replace the Eddy${NC}               ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ╚══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
    pause_user "Press ENTER to return to menu..."
}

# ═══════════════════════════════════════════════════════
# INDIVIDUAL STEP FUNCTIONS (for options 4, 5, 6, 7)
# ═══════════════════════════════════════════════════════

recalibrate_drive_current_only() {
    if ! _check_klipper_ready; then
        pause_user "Press ENTER to return to menu..."
        return 1
    fi
    _eddy_step2_drive_current
}

recalibrate_height_mapping_only() {
    if ! _check_klipper_ready; then
        pause_user "Press ENTER to return to menu..."
        return 1
    fi
    _eddy_step3_height_mapping
    _eddy_step4_z_verification
}

recalibrate_bed_mesh_only() {
    if ! _check_klipper_ready; then
        pause_user "Press ENTER to return to menu..."
        return 1
    fi
    _eddy_step6_bed_mesh
}

recalibrate_temperature_only() {
    if ! _check_klipper_ready; then
        pause_user "Press ENTER to return to menu..."
        return 1
    fi
    _eddy_step5_temperature
}

# ═══════════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════════
show_main_menu() {
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${WHITE}${BOLD}EDDY TOOL — Select operation${NC}                                    ${BR_RED}┃${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    p ""
    p "  ${BG_RED}${WHITE}${BOLD} 1 ${NC}  ${WHITE}${BOLD}Apply official Eddy configuration${NC}"
    p "       ${DIM}Rewrites eddy.cfg + homing.cfg with Klipper official recommendations${NC}"
    p "       ${DIM}(fixes descend_z, adds SET_Z_FROM_PROBE, proper homing)${NC}"
    p ""
    p "  ${BG_RED}${WHITE}${BOLD} 2 ${NC}  ${WHITE}${BOLD}Configure X/Y offsets${NC}"
    p "       ${DIM}Set x_offset and y_offset, recompute bed_mesh${NC}"
    p ""
    p "  ${BG_RED}${WHITE}${BOLD} 3 ${NC}  ${WHITE}${BOLD}Full calibration assistant${NC} ${GRAY}(6 steps)${NC}"
    p "       ${DIM}Complete guided calibration — use this for a fresh install${NC}"
    p ""
    p "  ${BG_RED}${WHITE}${BOLD} 4 ${NC}  ${WHITE}Re-run drive current calibration only${NC}"
    p "  ${BG_RED}${WHITE}${BOLD} 5 ${NC}  ${WHITE}Re-run height mapping + Z=0 verification only${NC}"
    p "  ${BG_RED}${WHITE}${BOLD} 6 ${NC}  ${WHITE}Re-run bed mesh only${NC}"
    p "  ${BG_RED}${WHITE}${BOLD} 7 ${NC}  ${WHITE}Run temperature drift calibration only${NC}"
    p ""
    p "  ${BG_BLACK}${WHITE} q ${NC}  ${GRAY}Quit${NC}"
    p ""
    printf "  ${WHITE}Your choice [1-7/q]: ${NC}"
    read MAIN_CHOICE
}

# ═══════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════
main() {
    # Loop menu
    while true; do
        show_banner
        show_main_menu

        case $MAIN_CHOICE in
            1)
                apply_official_config
                ;;
            2)
                configure_eddy_offsets
                ;;
            3)
                full_calibration_assistant
                ;;
            4)
                recalibrate_drive_current_only
                ;;
            5)
                recalibrate_height_mapping_only
                ;;
            6)
                recalibrate_bed_mesh_only
                ;;
            7)
                recalibrate_temperature_only
                ;;
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
