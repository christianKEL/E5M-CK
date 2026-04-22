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
CONFIG_MAINLINE="/usr/data/printer_data/config_mainline"
CONFIG_CREALITY="/usr/data/printer_data/config_creality_bak"
KLIPPER_SERVICE="/etc/init.d/S55klipper_service"
MOONRAKER_API="http://localhost:7125"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo "${BLUE}[INFO]${NC} $1"; }
log_ok()      { echo "${GREEN}[OK]${NC}   $1"; }
log_warn()    { echo "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo "${RED}[ERROR]${NC} $1"; }
log_step()    { echo ""; echo "${GREEN}════════════════════════════════════════${NC}"; echo "${GREEN} $1${NC}"; echo "${GREEN}════════════════════════════════════════${NC}"; }

die() { log_error "$1"; exit 1; }

# ─── STEP 4 — SAVE ORIGINAL CREALITY CONFIG ───
step4_save_original() {
    log_step "STEP 4 — Saving original Creality config"
    mkdir -p $SAVE_DIR
    cp $CONFIG_DIR/printer.cfg $SAVE_DIR/printer_creality_ORIGINAL.cfg
    cp $CONFIG_DIR/gcode_macro.cfg $SAVE_DIR/gcode_macro_creality_ORIGINAL.cfg
    cp $CONFIG_DIR/printer_params.cfg $SAVE_DIR/printer_params_creality_ORIGINAL.cfg 2>/dev/null || true
    cp $CONFIG_DIR/sensorless.cfg $SAVE_DIR/sensorless_creality_ORIGINAL.cfg 2>/dev/null || true
    log_ok "Original Creality config saved to $SAVE_DIR"
}

# ─── STEP 5 — PATCH CREALITY SERVERS ───
step5_patch_servers() {
    log_step "STEP 5 — Patching Creality servers"
    killall app-server 2>/dev/null; killall master-server 2>/dev/null
    sleep 2

    # Backup
    [ -f /usr/bin/app-server.orig ] || cp /usr/bin/app-server /usr/bin/app-server.orig
    [ -f /usr/bin/master-server.orig ] || cp /usr/bin/master-server /usr/bin/master-server.orig

    # Patch app-server
    python3 << 'PY'
path = "/usr/bin/app-server"
old = b"/tmp/klippy_uds"
new = b"/tmp/klippy_udx"
with open(path, "rb") as f:
    data = f.read()
if old in data:
    data = data.replace(old, new)
    open(path, "wb").write(data)
    print("[OK]   app-server patched")
else:
    print("[WARN] app-server: already patched or pattern not found")
PY

    # Patch master-server
    python3 << 'PY'
path = "/usr/bin/master-server"
old = b"SET_HEATER_TEMPERATURE HEATER=heater_bed"
new = b"NOP_HEATER_TEMPERATURE HEATER=heater_bed"
with open(path, "rb") as f:
    data = f.read()
count = data.count(old)
if count > 0:
    data = data.replace(old, new)
    open(path, "wb").write(data)
    print(f"[OK]   master-server patched ({count} occurrence(s))")
else:
    print("[WARN] master-server: already patched or pattern not found")
PY

    chmod +x /usr/bin/app-server /usr/bin/master-server
    log_ok "Creality servers patched"
}

# ─── STEP 6 — INSTALL KLIPPER MAINLINE ───
step6_install_klipper() {
    log_step "STEP 6 — Installing Klipper mainline"

    # Backup service
    cp $KLIPPER_SERVICE $E5M_DIR/S55klipper_service.creality.bak

    # Download c_helper.so
    log_info "Downloading c_helper.so (MIPS nan2008)..."
    mkdir -p $E5M_DIR
    wget --no-check-certificate \
        "$GITHUB_RAW/c_helper.so" \
        -O $E5M_DIR/c_helper.so || die "Failed to download c_helper.so"
    log_ok "c_helper.so downloaded"

    # Clone Klipper mainline
    log_info "Cloning Klipper mainline..."
    [ -d /usr/data/klipper ] && rm -rf /usr/data/klipper
    git clone https://github.com/Klipper3d/klipper.git /usr/data/klipper || die "Failed to clone Klipper"
    log_ok "Klipper mainline cloned"

    # Install c_helper.so
    cp $E5M_DIR/c_helper.so /usr/data/klipper/klippy/chelper/c_helper.so
    log_ok "c_helper.so installed"

    # Copy Creality extras
    cp /usr/share/klipper/klippy/extras/gcode_shell_command.py /usr/data/klipper/klippy/extras/
    cp /usr/share/klipper/klippy/extras/custom_macro.py /usr/data/klipper/klippy/extras/

    # Copy GuppyScreen modules
    cp /usr/data/guppyscreen/k1_mods/guppy_module_loader.py /usr/data/klipper/klippy/extras/
    cp /usr/data/guppyscreen/k1_mods/calibrate_shaper_config.py /usr/data/klipper/klippy/extras/
    cp /usr/data/guppyscreen/k1_mods/tmcstatus.py /usr/data/klipper/klippy/extras/
    log_ok "Klipper extras installed"

    # Patch stepper.py (MCU deprecated warning)
    sed -i '105s/^/# /' /usr/data/klipper/klippy/stepper.py
    rm -f /usr/data/klipper/klippy/stepper.pyc
    log_ok "stepper.py patched (MCU deprecated warning suppressed)"

    # Update service
    sed -i 's|PY_SCRIPT=/usr/share/klipper/klippy/klippy.py|PY_SCRIPT=/usr/data/klipper/klippy/klippy.py|' \
        $KLIPPER_SERVICE
    log_ok "Klipper service updated"
}

# ─── STEP 7 — CREATE CONFIG MAINLINE ───
step7_create_config() {
    log_step "STEP 7 — Creating mainline config"

    # Create config_mainline
    mkdir -p $CONFIG_MAINLINE
    mkdir -p $CONFIG_MAINLINE/GuppyScreen

    # Copy base Creality config
    cp $CONFIG_DIR/printer.cfg $CONFIG_MAINLINE/printer.cfg
    cp $CONFIG_DIR/gcode_macro.cfg $CONFIG_MAINLINE/gcode_macro.cfg
    cp $CONFIG_DIR/printer_params.cfg $CONFIG_MAINLINE/printer_params.cfg 2>/dev/null || true
    cp $CONFIG_DIR/sensorless.cfg $CONFIG_MAINLINE/sensorless.cfg 2>/dev/null || true
    cp /usr/data/moonraker/moonraker/moonraker.conf $CONFIG_MAINLINE/moonraker.conf 2>/dev/null || \
        cp $CONFIG_DIR/../moonraker.conf $CONFIG_MAINLINE/moonraker.conf 2>/dev/null || true

    # Patch printer.cfg
    log_info "Patching printer.cfg..."
    python3 << 'PYEOF'
import re

with open('/usr/data/printer_data/config_mainline/printer.cfg', 'r') as f:
    content = f.read()

# Comment incompatible sections
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

# Fix deprecated parameters
content = content.replace('CXSAVE_CONFIG', 'SAVE_CONFIG')
content = re.sub(r'max_accel_to_decel\s*:\s*\d+', 'minimum_cruise_ratio: 0.5', content)
content = re.sub(r'max_accel\s*:\s*100000', 'max_accel: 10000', content)
content = content.replace('[include sensorless.cfg]', '#[include sensorless.cfg]')

# Fix stepper_z endstop
content = re.sub(
    r'(endstop_pin: tmc2209_stepper_z:virtual_endstop)',
    r'#\1\nendstop_pin: probe:z_virtual_endstop\nhoming_retract_dist: 0',
    content
)
content = re.sub(r'^(position_endstop: 0.*)$', r'#\1', content, flags=re.MULTILINE)

# Uncomment control and PID values for heater_bed
content = re.sub(r'#(control\s*=\s*(?:pid|watermark))', r'\1', content)
content = re.sub(r'#(pid_kp\s*=\s*[\d.]+)', r'\1', content)
content = re.sub(r'#(pid_ki\s*=\s*[\d.]+)', r'\1', content)
content = re.sub(r'#(pid_kd\s*=\s*[\d.]+)', r'\1', content)

with open('/usr/data/printer_data/config_mainline/printer.cfg', 'w') as f:
    f.write(content)
print("[OK]   printer.cfg patched")
PYEOF

    # Fix bed_mesh
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

with open('/usr/data/printer_data/config_mainline/printer.cfg', 'r') as f:
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

# Add pwm_cycle_time to heater_bed
content = re.sub(r'\[heater_bed\]', '[heater_bed]\npwm_cycle_time: 0.3', content)

with open('/usr/data/printer_data/config_mainline/printer.cfg', 'w') as f:
    f.write(content)
print(f"[OK]   bed_mesh updated: mesh_min={mesh_min_x},{mesh_min_y} mesh_max={mesh_max_x},{mesh_max_y}")
PYEOF

    # Add includes at top (before SAVE_CONFIG)
    python3 << 'PYEOF'
with open('/usr/data/printer_data/config_mainline/printer.cfg', 'r') as f:
    content = f.read()

includes = """[include macros_calibration.cfg]
[include GuppyScreen/*.cfg]
[include eddy.cfg]
[include homing.cfg]
"""

if '[include eddy.cfg]' not in content:
    content = includes + content

with open('/usr/data/printer_data/config_mainline/printer.cfg', 'w') as f:
    f.write(content)
print("[OK]   includes added to printer.cfg")
PYEOF

    log_ok "printer.cfg created and patched"

    # Create eddy.cfg
    EDDY_SERIAL=$(ls /dev/serial/by-id/ 2>/dev/null | grep rp2040 | head -1)
    cat > $CONFIG_MAINLINE/eddy.cfg << EDDYEOF
[mcu eddy]
serial: /dev/serial/by-id/${EDDY_SERIAL}

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
    log_ok "eddy.cfg created"

    # Create homing.cfg
    cat > $CONFIG_MAINLINE/homing.cfg << 'HOMEOF'
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
    log_ok "homing.cfg created"

    # Create macros_calibration.cfg
    cat > $CONFIG_MAINLINE/macros_calibration.cfg << 'MACROEOF'
# ═══════════════════════════════════════════════════════
# CALIBRATION MACROS — Ender 5 Max
# ═══════════════════════════════════════════════════════

# ─── MECHANICAL BED LEVELING ───
[gcode_macro CAL_BED_Z_TILT]
description: Mechanical bed Z tilt leveling via FORCE_MOVE
gcode:
  RESPOND TYPE=command MSG="🔄 Starting mechanical bed leveling..."
  RESPOND TYPE=command MSG="🔄 Homing all axes..."
  G28
  RESPOND TYPE=command MSG="✅ Homing complete"
  RESPOND TYPE=command MSG="🔄 Moving bed to lowest position..."
  G1 Z400 F300
  RESPOND TYPE=command MSG="🔄 Synchronizing Z motors - step 1/8..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=5 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Synchronizing Z motors - step 2/8..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=5 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Synchronizing Z motors - step 3/8..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=5 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Synchronizing Z motors - step 4/8..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=5 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Synchronizing Z motors - step 5/8..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=5 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Synchronizing Z motors - step 6/8..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=5 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Synchronizing Z motors - step 7/8..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=5 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Synchronizing Z motors - step 8/8..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=5 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Raising bed..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=-200 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Final homing..."
  G28
  RESPOND TYPE=command MSG="✅ Mechanical leveling complete - Printer is ready"

# ─── BED PID CALIBRATION ───
[gcode_macro CAL_BED_PID]
description: Bed PID calibration (default 65C, usage: CAL_BED_PID TEMP=80)
gcode:
  {% set temp = params.TEMP|default(65)|int %}
  RESPOND TYPE=command MSG="🔄 Starting bed PID calibration at {temp}C..."
  RESPOND TYPE=command MSG="ℹ️ This may take several minutes"
  PID_CALIBRATE HEATER=heater_bed TARGET={temp}
  RESPOND TYPE=command MSG="✅ Bed PID calibration complete - Run SAVE_CONFIG to save"

# ─── NOZZLE PID CALIBRATION ───
[gcode_macro CAL_NOZZLE_PID]
description: Nozzle PID calibration (default 220C, usage: CAL_NOZZLE_PID TEMP=250)
gcode:
  {% set temp = params.TEMP|default(220)|int %}
  RESPOND TYPE=command MSG="🔄 Starting nozzle PID calibration at {temp}C..."
  RESPOND TYPE=command MSG="ℹ️ This may take several minutes"
  PID_CALIBRATE HEATER=extruder TARGET={temp}
  RESPOND TYPE=command MSG="✅ Nozzle PID calibration complete - Run SAVE_CONFIG to save"

# ─── EDDY DRIVE CURRENT CALIBRATION ───
[gcode_macro CAL_EDDY_DRIVE_CURRENT]
description: Calibrate BTT Eddy drive current - position Eddy ~20mm above bed first
gcode:
  RESPOND TYPE=command MSG="🔄 Starting Eddy drive current calibration..."
  G28 X Y
  CENTER_TOOLHEAD
  RESPOND TYPE=command MSG="ℹ️ Use SET_KINEMATIC_Z_200 then move bed to ~20mm below Eddy"
  RESPOND TYPE=command MSG="ℹ️ Then run: LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy"
  RESPOND TYPE=command MSG="✅ Toolhead centered - position bed manually then calibrate"

# ─── EDDY HEIGHT MAPPING CALIBRATION ───
[gcode_macro CAL_EDDY_MAPPING]
description: Calibrate BTT Eddy height mapping - nozzle must touch bed first
gcode:
  RESPOND TYPE=command MSG="🔄 Starting Eddy height mapping calibration..."
  G28 X Y
  CENTER_TOOLHEAD
  RESPOND TYPE=command MSG="ℹ️ Use SET_KINEMATIC_Z_200 and lower bed until nozzle touches bed"
  RESPOND TYPE=command MSG="ℹ️ Then run: SET_KINEMATIC_POSITION Z=0"
  RESPOND TYPE=command MSG="ℹ️ Then run: G1 Z1 F300"
  RESPOND TYPE=command MSG="ℹ️ Then run: PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy"
  RESPOND TYPE=command MSG="✅ Toolhead centered - follow instructions above"

# ─── BED MESH CALIBRATION ───
[gcode_macro CAL_BED_MESH]
description: Full rapid bed mesh scan
gcode:
  RESPOND TYPE=command MSG="🔄 Starting bed mesh calibration..."
  G28
  RESPOND TYPE=command MSG="✅ Homing complete"
  BED_MESH_CLEAR
  RESPOND TYPE=command MSG="🔄 Scanning bed surface (40x40 points)..."
  BED_MESH_CALIBRATE METHOD=rapid_scan
  RESPOND TYPE=command MSG="✅ Bed mesh complete - Run SAVE_CONFIG to save"

# ─── INPUT SHAPER AUTO CALIBRATION ───
[gcode_shell_command input_shaper_auto]
command: sh /usr/data/E5M_CK/input_shaper_launcher.sh
timeout: 600
verbose: True

[gcode_macro CAL_INPUT_SHAPER]
description: Automatic input shaper calibration
gcode:
  RESPOND TYPE=command MSG="🔄 Starting automatic input shaper calibration..."
  RESPOND TYPE=command MSG="ℹ️ Klipper will restart twice - this is normal"
  RESPOND TYPE=command MSG="ℹ️ Check log at /tmp/input_shaper_auto.log"
  RUN_SHELL_COMMAND CMD=input_shaper_auto
MACROEOF
    log_ok "macros_calibration.cfg created"

    # Create GuppyScreen macros
    cat > $CONFIG_MAINLINE/GuppyScreen/macros_guppy.cfg << 'GUPPYEOF'
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
    log_ok "GuppyScreen macros created"

    # Copy guppy_cmd.cfg
    cp /usr/data/guppyscreen/scripts/guppy_cmd.cfg \
       $CONFIG_MAINLINE/GuppyScreen/guppy_cmd.cfg
    log_ok "guppy_cmd.cfg copied"

    # Update Moonraker service to point to config_mainline
    mv $CONFIG_DIR /usr/data/printer_data/config_creality_bak
    ln -sf $CONFIG_MAINLINE /usr/data/printer_data/config
    log_ok "Config symlink created: config -> config_mainline"

    # Remove deprecated config_path from moonraker.conf if present
    sed -i '/config_path:.*config_mainline/d' $CONFIG_MAINLINE/moonraker.conf 2>/dev/null || true

    log_ok "Mainline config structure complete"
}

# ─── STEP 8 — CONFIGURE GUPPYSCREEN ───
step8_configure_guppy() {
    log_step "STEP 8 — Configuring GuppyScreen"

    # Set red theme
    python3 << 'PYEOF'
import json
with open('/usr/data/guppyscreen/guppyconfig.json', 'r') as f:
    c = json.load(f)
c['theme'] = 'red'
with open('/usr/data/guppyscreen/guppyconfig.json', 'w') as f:
    json.dump(c, f, indent=4)
print("[OK]   GuppyScreen theme set to red")
PYEOF

    # Set macros visibility via Moonraker API
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
    "CAL_BED_MESH", "CAL_INPUT_SHAPER"
]

settings = {}
for m in macros_visible:
    settings[m] = {"hidden": False}
for m in macros_hidden:
    settings[m] = {"hidden": True}

data = json.dumps({
    "namespace": "guppyscreen",
    "key": "macros.settings",
    "value": settings
}).encode()

req = urllib.request.Request(
    "http://localhost:7125/server/database/item",
    data=data,
    headers={"Content-Type": "application/json"},
    method="POST"
)
print("[OK]   GuppyScreen macros configured")
urllib.request.urlopen(req)
PYEOF

    # Set Fluidd Z axis inverted
    python3 << 'PYEOF'
import urllib.request, json
data = json.dumps({
    "namespace": "fluidd",
    "key": "uiSettings.general.axis",
    "value": {"z": {"inverted": True}}
}).encode()
req = urllib.request.Request(
    "http://localhost:7125/server/database/item",
    data=data,
    headers={"Content-Type": "application/json"},
    method="POST"
)
urllib.request.urlopen(req)
print("[OK]   Fluidd Z axis inverted")
PYEOF

    log_ok "GuppyScreen configured"
}

# ─── STEP 9 — FLASH BTT EDDY USB ───
step9_flash_eddy() {
    log_step "STEP 9 — Flashing BTT Eddy USB"

    log_info "Downloading btteddy.uf2..."
    wget --no-check-certificate \
        "$GITHUB_RAW/btteddy.uf2" \
        -O $E5M_DIR/btteddy.uf2 || die "Failed to download btteddy.uf2"
    log_ok "btteddy.uf2 downloaded"

    # Wait for Eddy in BOOT mode
    log_info "Waiting for Eddy in BOOT mode..."
    TIMEOUT=60
    while [ $TIMEOUT -gt 0 ]; do
        if mount | grep -q "/tmp/udisk/sda1"; then
            log_ok "Eddy detected in BOOT mode"
            break
        fi
        sleep 2
        TIMEOUT=$((TIMEOUT - 2))
    done

    if [ $TIMEOUT -le 0 ]; then
        log_warn "Eddy not detected. Make sure it's connected in BOOT mode (button held)"
        log_warn "Trying anyway..."
    fi

    # Flash
    if [ -d /tmp/udisk/sda1 ]; then
        cp $E5M_DIR/btteddy.uf2 /tmp/udisk/sda1/
        sync
        log_ok "Eddy flashed successfully"
        sleep 5
    else
        log_warn "Eddy mount point not found — flash manually if needed"
    fi
}

# ─── STEP 10 — START KLIPPER MAINLINE ───
step10_start_klipper() {
    log_step "STEP 10 — Starting Klipper mainline"

    $KLIPPER_SERVICE restart
    log_info "Waiting for Klipper to start..."
    sleep 30

    STATE=$(python3 -c "
import urllib.request, json
try:
    d = json.loads(urllib.request.urlopen('http://localhost:7125/printer/info').read())
    print(d['result']['state'])
except:
    print('unknown')
" 2>/dev/null)

    if [ "$STATE" = "ready" ]; then
        log_ok "Klipper mainline is READY"
    else
        log_warn "Klipper state: $STATE — check logs at /usr/data/printer_data/logs/klippy.log"
    fi
}

# ─── MAIN ───
main() {
    echo ""
    echo "${GREEN}╔════════════════════════════════════════════╗${NC}"
    echo "${GREEN}║     E5M-CK Installation Script             ║${NC}"
    echo "${GREEN}║     Klipper Mainline + BTT Eddy USB        ║${NC}"
    echo "${GREEN}║     Creality Ender 5 Max — Nebula Pad      ║${NC}"
    echo "${GREEN}╚════════════════════════════════════════════╝${NC}"
    echo ""

    STEP=${1:-"all"}

    case $STEP in
        "4")  step4_save_original ;;
        "5")  step5_patch_servers ;;
        "6")  step6_install_klipper ;;
        "7")  step7_create_config ;;
        "8")  step8_configure_guppy ;;
        "9")  step9_flash_eddy ;;
        "10") step10_start_klipper ;;
        "all")
            step4_save_original
            step5_patch_servers
            step6_install_klipper
            step7_create_config
            step8_configure_guppy
            step9_flash_eddy
            step10_start_klipper
            ;;
        *)
            log_error "Unknown step: $STEP"
            echo "Usage: $0 [4|5|6|7|8|9|10|all]"
            exit 1
            ;;
    esac

    echo ""
    echo "${GREEN}╔════════════════════════════════════════════╗${NC}"
    echo "${GREEN}║     Installation complete!                 ║${NC}"
    echo "${GREEN}║     Fluidd: http://$(hostname -I | awk '{print $1}'):4408   ║${NC}"
    echo "${GREEN}╚════════════════════════════════════════════╝${NC}"
    echo ""
}

main "$@"
