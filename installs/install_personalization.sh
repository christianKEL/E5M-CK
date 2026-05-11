#!/bin/sh
# ============================================================
#   E5M-CK — install_personalization.sh
#   Personalization layer (post-install): Fluidd settings,
#   GuppyScreen config, Creality boot logo, calibration fixes.
#
#   Sections (each can be skipped interactively):
#     1. Restore Fluidd settings (theme, macros, charts) via
#        Moonraker DB API.
#     2. Deploy custom guppyconfig.json (E5M-CK fans, leds, theme).
#     3. Replace Creality boot logos with E5M-CK logo.
#     4. GuppyScreen calibration fixes (matplotlib, belts,
#        input shaper, dual-PNG, cosmetic patches).
#
#   Repo:  https://github.com/christianKEL/E5M-CK
#   Docs:  https://e5mdocumentation.kinsta.cloud/
# ============================================================

set -e

# ─── PATHS ─────────────────────────────────────────────────
GITHUB_RAW="https://raw.githubusercontent.com/christianKEL/E5M-CK/main"

FLUIDD_BACKUP_URL="$GITHUB_RAW/configs/backup-fluidd-v1.36.4-fluidd.json"
GUPPY_CONFIG_URL="$GITHUB_RAW/configs/guppyconfig.json"
LOGO_URL="$GITHUB_RAW/files/e5m_ck_logo.jpg"

GUPPY_DIR="/usr/data/guppyscreen"
GUPPY_CONFIG_FILE="$GUPPY_DIR/guppyconfig.json"
GUPPY_SERVICE="/etc/init.d/S99guppyscreen"
GUPPY_K1_MODS="$GUPPY_DIR/k1_mods"
GUPPY_SCRIPTS="/usr/data/printer_data/config/GuppyScreen/scripts"
GUPPY_CMD_CFG="/usr/data/printer_data/config/GuppyScreen/guppy_cmd.cfg"
GRAPH_BELTS_PY="$GUPPY_SCRIPTS/graph_belts.py"
CALIBRATE_SHAPER_PY="$GUPPY_SCRIPTS/calibrate_shaper.py"

KLIPPER_SERVICE="/etc/init.d/S55klipper_service"
PRINTER_CONFIG_DIR="/usr/data/printer_data/config"
PRINTER_BACKUP_CFG="/usr/data/printer_data/backup_cfg"
MATPLOTLIB_FT2FONT="/usr/lib/python3.8/site-packages/matplotlib/ft2font.cpython-38-mipsel-linux-gnu.so"
MATPLOTLIB_FT2FONT_SRC="$GUPPY_K1_MODS/ft2font.cpython-38-mipsel-linux-gnu.so"
PC_GRAPH_DIR="/usr/data/printer_data/config/printer_calibration_graphs"

LOGO_DIR="/etc/logo"
LOGO_BACKUP_DIR="/usr/data/logo_originals"
LOGO_LOCAL="/usr/data/e5m_ck_logo.jpg"

TMP_DIR="/usr/data/.tmp_install"
FLUIDD_BACKUP_LOCAL="$TMP_DIR/backup-fluidd.json"
GUPPY_CONFIG_LOCAL="$TMP_DIR/guppyconfig.json"

MOONRAKER_API="http://localhost:7125"

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
log_skip()    { p "  ${GRAY}~  $(date +%H:%M:%S) (skipped) $1${NC}"; }
log_already() { p "  ${BR_GREEN}=${NC}  ${GRAY}$(date +%H:%M:%S)${NC} ${DIM}$1 (already done)${NC}"; }

log_step() {
    p ""
    p "${BR_RED}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    p "${BR_RED}┃${NC}  ${BG_RED}${WHITE}${BOLD} STEP $1 ${NC}  ${WHITE}${BOLD}$2${NC}"
    p "${BR_RED}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
}

log_substep() {
    p ""
    p "${BR_RED}  ▸${NC} ${WHITE}${BOLD}$1${NC}"
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
    p "${WHITE}            install_personalization.sh${NC}"
    p "${GRAY}    Fluidd + GuppyScreen + boot logo + calibration fixes${NC}"
    p ""
    p "                    ${BG_RED}${WHITE}${BOLD}  CR*ALITY S*CKS  ${NC}"
    p ""
    p "${DIM}                 github.com/christianKEL/E5M-CK${NC}"
    p ""
}

show_disclaimer() {
    p "${BR_RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}║${NC}  ${BG_RED}${WHITE}${BOLD}  PERSONALIZATION SCRIPT  ${NC}                                       ${BR_RED}║${NC}"
    p "${BR_RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
    p "  ${WHITE}This script applies E5M-CK personalization on top of a working${NC}"
    p "  ${WHITE}install. Each section is OPTIONAL — you can skip any of them:${NC}"
    p ""
    p "    ${BR_GREEN}1.${NC} ${WHITE}Restore Fluidd settings${NC} ${DIM}(theme, macros, charts, console)${NC}"
    p "    ${BR_GREEN}2.${NC} ${WHITE}Deploy custom guppyconfig.json${NC} ${DIM}(E5M-CK fans, leds, theme)${NC}"
    p "    ${BR_GREEN}3.${NC} ${WHITE}Replace Creality boot logos${NC} ${DIM}(E5M-CK logo at startup)${NC}"
    p "    ${BR_GREEN}4.${NC} ${WHITE}GuppyScreen calibration fixes${NC} ${DIM}(matplotlib, belts, shaper, dual-PNG)${NC}"
    p ""
    p "  ${DIM}All changes are reversible (backups in /usr/data/).${NC}"
    p "  ${DIM}Script is idempotent — safe to re-run after partial completion.${NC}"
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

# Pick the best python3 available
find_python() {
    for candidate in /opt/bin/python3 /usr/bin/python3 \
                     /usr/share/klippy-env/bin/python \
                     /usr/data/moonraker/moonraker-env/bin/python; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}


# ════════════════════════════════════════════════════════════
# STEP 1 — PRECHECK
# ════════════════════════════════════════════════════════════
step_precheck() {
    log_step "1" "Pre-checks (network, Moonraker, python3)"

    log_info "Checking internet connectivity..."
    if ! ping -c 1 -W 3 raw.githubusercontent.com >/dev/null 2>&1; then
        die "Cannot reach raw.githubusercontent.com — check your network"
    fi
    log_ok "Internet OK"

    log_info "Checking Moonraker..."
    MRK_OK=$(wget --no-check-certificate -q -O - "$MOONRAKER_API/server/info" 2>/dev/null | \
             grep -o '"klippy_connected":true' | head -1)
    if [ -z "$MRK_OK" ]; then
        die "Moonraker is not responding at $MOONRAKER_API or Klippy not connected"
    fi
    log_ok "Moonraker responds, Klippy connected"

    log_info "Looking for python3..."
    PYTHON3=$(find_python) || die "No python3 found (expected /opt/bin/python3 from Entware)"
    log_ok "Using python3: $PYTHON3"

    mkdir -p "$TMP_DIR"
    log_action "Temp dir ready: $TMP_DIR"
}


# ════════════════════════════════════════════════════════════
# STEP 2 — RESTORE FLUIDD SETTINGS
# ════════════════════════════════════════════════════════════
step_fluidd_settings() {
    log_step "2" "Restore Fluidd settings (theme, macros, charts)"

    p ""
    p "  ${WHITE}This will restore the E5M-CK Fluidd settings via Moonraker DB API:${NC}"
    p "    ${DIM}• Theme:        Dark with E5M-CK red (#B12F36)${NC}"
    p "    ${DIM}• Macros:       Pre-organized into MAIN / CALIBRATION / PAUSE-RESUME${NC}"
    p "    ${DIM}• Charts:       Bed/Extruder visible, Eddy hidden${NC}"
    p "    ${DIM}• Z axis:       Inverted${NC}"
    p ""
    p "  ${YELLOW}Note:${NC} ${DIM}any current Fluidd settings will be OVERWRITTEN.${NC}"
    p "  ${DIM}You'll need to reload Fluidd in your browser after.${NC}"

    if ! confirm "Restore Fluidd settings?"; then
        log_skip "Section 2 — Fluidd settings"
        FLUIDD_DONE=0
        return 0
    fi

    log_info "Downloading Fluidd backup file..."
    rm -f "$FLUIDD_BACKUP_LOCAL"
    if ! wget --no-check-certificate -q -L "$FLUIDD_BACKUP_URL" \
            -O "$FLUIDD_BACKUP_LOCAL"; then
        die "Download failed: $FLUIDD_BACKUP_URL"
    fi

    SIZE=$(wc -c < "$FLUIDD_BACKUP_LOCAL")
    log_action "Downloaded: $SIZE bytes"
    if [ "$SIZE" -lt 100 ]; then
        die "Backup file too small ($SIZE bytes) — likely a 404"
    fi

    log_info "Validating JSON structure..."
    if ! "$PYTHON3" -c "
import json, sys
with open('$FLUIDD_BACKUP_LOCAL') as f:
    data = json.load(f)
meta = data.get('meta', {})
if meta.get('app') != 'Fluidd' or meta.get('type') != 'settings-backup':
    print('ERROR: not a Fluidd settings-backup file')
    sys.exit(1)
print('Backup version: ' + str(meta.get('version', 'unknown')))
print('Top-level data keys: ' + ', '.join(data.get('data', {}).keys()))
"; then
        die "Backup file is invalid"
    fi

    log_info "Posting each top-level key to Moonraker DB..."
    "$PYTHON3" << PYTHON_EOF
import json
import sys
import urllib.request
import urllib.error

with open('$FLUIDD_BACKUP_LOCAL') as f:
    backup = json.load(f)

data_section = backup.get('data', {})
total = len(data_section)
ok_count = 0
fail_count = 0

for key, value in data_section.items():
    payload = json.dumps({
        'namespace': 'fluidd',
        'key': key,
        'value': value
    }).encode('utf-8')
    req = urllib.request.Request(
        '$MOONRAKER_API/server/database/item',
        data=payload,
        method='POST',
        headers={'Content-Type': 'application/json'}
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status == 200:
                ok_count += 1
                # Compute approximate value size for logging
                val_size = len(json.dumps(value))
                print('  > OK: %s (%d bytes)' % (key, val_size))
            else:
                fail_count += 1
                print('  ! FAIL: %s (HTTP %d)' % (key, resp.status))
    except urllib.error.HTTPError as e:
        fail_count += 1
        body = e.read().decode('utf-8', errors='replace')[:200]
        print('  ! FAIL: %s (HTTP %d: %s)' % (key, e.code, body))
    except Exception as e:
        fail_count += 1
        print('  ! FAIL: %s (%s)' % (key, e))

print('')
print('Total: %d, OK: %d, FAIL: %d' % (total, ok_count, fail_count))
sys.exit(0 if fail_count == 0 else 1)
PYTHON_EOF

    if [ $? -eq 0 ]; then
        log_ok "Fluidd settings restored"
        log_action "Reload Fluidd in your browser to see the new theme/macros"
        FLUIDD_DONE=1
    else
        log_warn "Some keys failed to restore — see Python output above"
        FLUIDD_DONE=1
    fi

    rm -f "$FLUIDD_BACKUP_LOCAL"
}


# ════════════════════════════════════════════════════════════
# STEP 3 — DEPLOY GUPPYSCREEN CONFIG
# ════════════════════════════════════════════════════════════
step_guppy_config() {
    log_step "3" "Deploy custom GuppyScreen config (guppyconfig.json)"

    p ""
    p "  ${WHITE}This will replace $GUPPY_CONFIG_FILE${NC}"
    p "  ${WHITE}with the E5M-CK customized version:${NC}"
    p "    ${DIM}• Theme: red${NC}"
    p "    ${DIM}• Display sleep: disabled${NC}"
    p "    ${DIM}• Fans: fan0 (toolhead) + fan1 (back)${NC}"
    p "    ${DIM}• Light LED: output_pin light_pin${NC}"
    p "    ${DIM}• Macros: LOAD_FILAMENT / UNLOAD_FILAMENT (E5M-CK macros)${NC}"
    p "    ${DIM}• Touch calibration: reset to false (you'll recalibrate on first boot)${NC}"
    p ""

    if [ ! -d "$GUPPY_DIR" ]; then
        log_warn "GuppyScreen not installed at $GUPPY_DIR"
        log_warn "Run install_guppyscreen.sh first."
        GUPPY_DONE=0
        return 0
    fi

    if ! confirm "Deploy custom guppyconfig.json?"; then
        log_skip "Section 3 — GuppyScreen config"
        GUPPY_DONE=0
        return 0
    fi

    log_info "Downloading guppyconfig.json from repo..."
    rm -f "$GUPPY_CONFIG_LOCAL"
    if ! wget --no-check-certificate -q -L "$GUPPY_CONFIG_URL" \
            -O "$GUPPY_CONFIG_LOCAL"; then
        die "Download failed: $GUPPY_CONFIG_URL"
    fi
    SIZE=$(wc -c < "$GUPPY_CONFIG_LOCAL")
    log_action "Downloaded: $SIZE bytes"
    if [ "$SIZE" -lt 100 ]; then
        die "guppyconfig.json too small ($SIZE bytes) — likely a 404"
    fi

    log_info "Validating JSON..."
    if ! "$PYTHON3" -c "
import json, sys
try:
    with open('$GUPPY_CONFIG_LOCAL') as f:
        data = json.load(f)
    if 'printers' not in data:
        sys.exit(1)
    print('OK')
except Exception as e:
    print('ERROR: ' + str(e))
    sys.exit(1)
"; then
        die "guppyconfig.json invalid"
    fi

    log_info "Setting touch_calibrated=false (forces calibration on first boot)..."
    "$PYTHON3" << PYTHON_EOF
import json
with open('$GUPPY_CONFIG_LOCAL') as f:
    data = json.load(f)
# Reset touch calibration so the screen calibrates fresh on this device
data['touch_calibrated'] = False
# Also remove the saved coefficients (they're specific to one display)
if 'touch_calibration_coeff' in data:
    data['touch_calibration_coeff'] = None
with open('$GUPPY_CONFIG_LOCAL', 'w') as f:
    json.dump(data, f, indent=2)
print('  > touch_calibrated=false')
print('  > touch_calibration_coeff=null')
PYTHON_EOF
    log_ok "JSON patched"

    if [ -f "$GUPPY_CONFIG_FILE" ]; then
        BACKUP="$GUPPY_CONFIG_FILE.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$GUPPY_CONFIG_FILE" "$BACKUP"
        log_action "Backed up existing config: $BACKUP"
    fi

    log_info "Stopping GuppyScreen..."
    "$GUPPY_SERVICE" stop 2>/dev/null || true
    sleep 2

    log_info "Deploying new config..."
    cp "$GUPPY_CONFIG_LOCAL" "$GUPPY_CONFIG_FILE"
    log_action "Copied: $GUPPY_CONFIG_LOCAL -> $GUPPY_CONFIG_FILE"

    log_info "Restarting GuppyScreen..."
    "$GUPPY_SERVICE" start 2>/dev/null || true
    sleep 3

    if ps 2>/dev/null | grep "/usr/data/guppyscreen/guppyscreen" | \
       grep -v supervise-daemon | grep -v grep | head -1 | awk '{print $1}' | \
       xargs -I {} echo "running pid {}" >/dev/null 2>&1; then
        log_ok "GuppyScreen restarted"
    else
        log_warn "GuppyScreen may not be running — check the touchscreen"
    fi

    rm -f "$GUPPY_CONFIG_LOCAL"
    GUPPY_DONE=1
}


# ════════════════════════════════════════════════════════════
# STEP 4 — REPLACE BOOT LOGOS
# ════════════════════════════════════════════════════════════
step_boot_logo() {
    log_step "4" "Replace Creality boot logos with E5M-CK logo"

    p ""
    p "  ${WHITE}This will replace all *.jpg/*.jpeg files in $LOGO_DIR${NC}"
    p "  ${WHITE}with the E5M-CK logo. Originals are backed up to:${NC}"
    p "    ${DIM}$LOGO_BACKUP_DIR${NC}"
    p ""
    p "  ${YELLOW}Note:${NC} ${DIM}requires REBOOT to see the new boot screen.${NC}"
    p ""

    if [ ! -d "$LOGO_DIR" ]; then
        log_warn "$LOGO_DIR does not exist on this system — skipping"
        LOGO_DONE=0
        return 0
    fi

    if ! confirm "Replace Creality boot logos?"; then
        log_skip "Section 4 — boot logo"
        LOGO_DONE=0
        return 0
    fi

    log_info "Downloading E5M-CK logo from repo..."
    rm -f "$LOGO_LOCAL"
    if ! wget --no-check-certificate -q -L "$LOGO_URL" \
            -O "$LOGO_LOCAL"; then
        die "Download failed: $LOGO_URL"
    fi
    SIZE=$(wc -c < "$LOGO_LOCAL")
    log_action "Downloaded: $SIZE bytes"
    if [ "$SIZE" -lt 1000 ]; then
        die "Logo file too small ($SIZE bytes) — likely a 404"
    fi

    # Quick check: starts with JPEG magic bytes (FF D8 FF)
    MAGIC=$(head -c 3 "$LOGO_LOCAL" | od -An -tx1 | tr -d ' \n')
    if [ "$MAGIC" != "ffd8ff" ]; then
        die "Logo is not a valid JPEG file (magic: $MAGIC)"
    fi
    log_ok "Logo file validated"

    log_info "Backing up original Creality logos..."
    mkdir -p "$LOGO_BACKUP_DIR"
    BACKED=0
    for f in "$LOGO_DIR"/*.jpg "$LOGO_DIR"/*.jpeg; do
        [ -f "$f" ] || continue
        BASENAME=$(basename "$f")
        if [ ! -f "$LOGO_BACKUP_DIR/$BASENAME" ]; then
            cp "$f" "$LOGO_BACKUP_DIR/$BASENAME"
            BACKED=$((BACKED + 1))
            log_action "Backed up: $BASENAME"
        fi
    done
    if [ "$BACKED" -eq 0 ]; then
        log_action "No new files to back up (already backed up before)"
    else
        log_ok "Backed up $BACKED original logo(s) to $LOGO_BACKUP_DIR"
    fi

    log_info "Replacing all boot logos with E5M-CK logo..."
    REPLACED=0
    for f in "$LOGO_DIR"/*.jpg "$LOGO_DIR"/*.jpeg; do
        [ -f "$f" ] || continue
        cp "$LOGO_LOCAL" "$f"
        REPLACED=$((REPLACED + 1))
        log_action "Replaced: $(basename "$f")"
    done
    log_ok "Replaced $REPLACED logo file(s)"

    log_info "Syncing filesystem..."
    sync
    log_ok "Sync done"

    LOGO_DONE=1
}


# ════════════════════════════════════════════════════════════
# STEP 5 — GUPPYSCREEN CALIBRATION FIXES
#
# Fixes for the chain : matplotlib + GuppyScreen + Belts + Input
# Shaper on Klipper mainline. Each sub-step is idempotent:
# detects current state and only applies what's missing.
#
# Sub-steps :
#   5.1 ft2font.so swap (matplotlib ABI fix with K1 mod)
#   5.2 guppy_cmd.cfg paths (CSV filenames + -k /usr/data/klipper)
#   5.3 calibrate_shaper.py shebang fix
#   5.4 Dual-PNG wrappers (gen_belts_png.sh + gen_shaper_combo.sh)
#   5.5 guppy_cmd.cfg dual-PNG integration (shell_command + macro)
#   5.6 graph_belts.py cosmetic patches (3 fixes)
#   5.7 Move duplicate cfg backups out of config/
#   5.8 FIRMWARE_RESTART Klipper
#
# Full background : MEMO_guppyscreen_belts_ENG.md in the repo.
# ════════════════════════════════════════════════════════════
step_guppy_calibration_fixes() {
    log_step "5" "GuppyScreen calibration fixes (matplotlib, belts, shaper)"

    p ""
    p "  ${WHITE}This step applies the full set of fixes documented in${NC}"
    p "  ${WHITE}MEMO_guppyscreen_belts_ENG.md:${NC}"
    p ""
    p "    ${DIM}5.1 matplotlib ft2font ABI fix (K1 mod swap)${NC}"
    p "    ${DIM}5.2 guppy_cmd.cfg path corrections${NC}"
    p "    ${DIM}5.3 calibrate_shaper.py shebang to Klipper venv${NC}"
    p "    ${DIM}5.4 Dual-PNG wrappers (small for GuppyScreen, large for PC)${NC}"
    p "    ${DIM}5.5 guppy_cmd.cfg dual-PNG integration${NC}"
    p "    ${DIM}5.6 graph_belts.py cosmetic patches (X/Y belt naming, warnings)${NC}"
    p "    ${DIM}5.7 Move duplicate cfg backups out of config/${NC}"
    p "    ${DIM}5.8 Restart Klipper${NC}"
    p ""
    p "  ${YELLOW}Note:${NC} ${DIM}each sub-step is idempotent (safe to re-run).${NC}"
    p ""

    if [ ! -d "$GUPPY_DIR" ]; then
        log_warn "GuppyScreen not installed at $GUPPY_DIR — skipping"
        CALIB_DONE=0
        return 0
    fi

    if ! confirm "Apply GuppyScreen calibration fixes?"; then
        log_skip "Section 5 — calibration fixes"
        CALIB_DONE=0
        return 0
    fi

    # ─── 5.1 ft2font.so swap ──────────────────────────────
    log_substep "5.1  matplotlib ft2font ABI fix"
    do_ft2font_swap

    # ─── 5.2 guppy_cmd.cfg paths ──────────────────────────
    log_substep "5.2  guppy_cmd.cfg path corrections"
    do_guppy_cmd_paths

    # ─── 5.3 calibrate_shaper.py shebang ─────────────────
    log_substep "5.3  calibrate_shaper.py shebang fix"
    do_shaper_shebang

    # ─── 5.4 Dual-PNG wrappers ────────────────────────────
    log_substep "5.4  Dual-PNG wrapper scripts"
    do_install_wrappers

    # ─── 5.5 guppy_cmd.cfg dual-PNG integration ──────────
    log_substep "5.5  guppy_cmd.cfg dual-PNG integration"
    do_guppy_cmd_dualpng

    # ─── 5.6 graph_belts.py cosmetic patches ─────────────
    log_substep "5.6  graph_belts.py cosmetic patches"
    do_graph_belts_patches

    # ─── 5.7 Move duplicate cfg backups ──────────────────
    log_substep "5.7  Move duplicate cfg backups out of config/"
    do_cleanup_config_backups

    # ─── 5.8 Restart Klipper ─────────────────────────────
    log_substep "5.8  Restart Klipper to load all changes"
    do_restart_klipper

    CALIB_DONE=1
}


# ─── 5.1 ft2font.so swap ───────────────────────────────────
do_ft2font_swap() {
    if [ ! -f "$MATPLOTLIB_FT2FONT" ]; then
        log_warn "matplotlib ft2font not found at $MATPLOTLIB_FT2FONT"
        log_warn "Is matplotlib 2.2.3 installed in /usr/lib/python3.8 ? Skipping."
        return 0
    fi

    if [ ! -f "$MATPLOTLIB_FT2FONT_SRC" ]; then
        log_warn "K1 mod ft2font not found at $MATPLOTLIB_FT2FONT_SRC"
        log_warn "GuppyScreen k1_mods directory missing — skipping ft2font swap"
        return 0
    fi

    # Compare current vs K1 mod (md5 to detect already-swapped)
    CURRENT_MD5=$(md5sum "$MATPLOTLIB_FT2FONT" 2>/dev/null | cut -d' ' -f1)
    SOURCE_MD5=$(md5sum "$MATPLOTLIB_FT2FONT_SRC" 2>/dev/null | cut -d' ' -f1)

    if [ "$CURRENT_MD5" = "$SOURCE_MD5" ]; then
        log_already "ft2font.so already swapped (md5 matches K1 mod)"
        return 0
    fi

    # Backup current and swap
    BACKUP="$MATPLOTLIB_FT2FONT.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$MATPLOTLIB_FT2FONT" "$BACKUP"
    log_action "Backed up original: $BACKUP"

    cp "$MATPLOTLIB_FT2FONT_SRC" "$MATPLOTLIB_FT2FONT"
    log_ok "Replaced with K1 mod ft2font.so"

    # Clear matplotlib font cache (forces rebuild on next run)
    rm -rf /root/.cache/matplotlib /root/.matplotlib 2>/dev/null || true
    log_action "Cleared matplotlib font cache"
}


# ─── 5.2 guppy_cmd.cfg paths ──────────────────────────────
do_guppy_cmd_paths() {
    if [ ! -f "$GUPPY_CMD_CFG" ]; then
        log_warn "$GUPPY_CMD_CFG not found — skipping path fixes"
        return 0
    fi

    NEED_BACKUP=0
    CHANGES=0

    # Check what needs to be done
    if grep -q "raw_data_axis=1.000,-1.000_a.csv" "$GUPPY_CMD_CFG" 2>/dev/null; then
        NEED_BACKUP=1
    fi
    if grep -q "raw_data_axis=1.000,1.000_b.csv" "$GUPPY_CMD_CFG" 2>/dev/null; then
        NEED_BACKUP=1
    fi
    if grep -q "\-k /usr/share/klipper" "$GUPPY_CMD_CFG" 2>/dev/null; then
        NEED_BACKUP=1
    fi

    if [ "$NEED_BACKUP" -eq 0 ]; then
        log_already "guppy_cmd.cfg paths already correct"
        return 0
    fi

    BACKUP="$GUPPY_CMD_CFG.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$GUPPY_CMD_CFG" "$BACKUP"
    log_action "Backed up: $BACKUP"

    # Fix CSV filenames (Klipper mainline format adds ,0.000 Z component)
    if grep -q "raw_data_axis=1.000,-1.000_a.csv" "$GUPPY_CMD_CFG"; then
        sed -i 's|raw_data_axis=1.000,-1.000_a.csv|raw_data_axis=1.000,-1.000,0.000_a.csv|g' \
            "$GUPPY_CMD_CFG"
        log_action "Fixed CSV filename _a.csv (added ,0.000)"
        CHANGES=$((CHANGES + 1))
    fi
    if grep -q "raw_data_axis=1.000,1.000_b.csv" "$GUPPY_CMD_CFG"; then
        sed -i 's|raw_data_axis=1.000,1.000_b.csv|raw_data_axis=1.000,1.000,0.000_b.csv|g' \
            "$GUPPY_CMD_CFG"
        log_action "Fixed CSV filename _b.csv (added ,0.000)"
        CHANGES=$((CHANGES + 1))
    fi

    # Fix Klipper path
    if grep -q "\-k /usr/share/klipper" "$GUPPY_CMD_CFG"; then
        sed -i 's|-k /usr/share/klipper|-k /usr/data/klipper|g' "$GUPPY_CMD_CFG"
        log_action "Fixed -k path to /usr/data/klipper"
        CHANGES=$((CHANGES + 1))
    fi

    log_ok "guppy_cmd.cfg patched ($CHANGES change(s))"
}


# ─── 5.3 calibrate_shaper.py shebang ──────────────────────
do_shaper_shebang() {
    if [ ! -f "$CALIBRATE_SHAPER_PY" ]; then
        log_warn "$CALIBRATE_SHAPER_PY not found — skipping shebang fix"
        return 0
    fi

    FIRST_LINE=$(head -1 "$CALIBRATE_SHAPER_PY")
    EXPECTED="#!/usr/share/klippy-env/bin/python"

    if [ "$FIRST_LINE" = "$EXPECTED" ]; then
        log_already "calibrate_shaper.py shebang already correct"
        return 0
    fi

    BACKUP="$CALIBRATE_SHAPER_PY.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$CALIBRATE_SHAPER_PY" "$BACKUP"
    log_action "Backed up: $BACKUP"

    sed -i "1c\\$EXPECTED" "$CALIBRATE_SHAPER_PY"
    log_ok "calibrate_shaper.py shebang updated"
}


# ─── 5.4 Dual-PNG wrappers (inline) ───────────────────────
do_install_wrappers() {
    if [ ! -d "$GUPPY_SCRIPTS" ]; then
        log_warn "$GUPPY_SCRIPTS not found — skipping wrapper install"
        return 0
    fi

    # ─── gen_belts_png.sh ─────────────────────────────────
    WRAPPER_BELTS="$GUPPY_SCRIPTS/gen_belts_png.sh"
    if [ -f "$WRAPPER_BELTS" ] && grep -q "E5M-CK dual-PNG wrapper" "$WRAPPER_BELTS" 2>/dev/null; then
        log_already "gen_belts_png.sh already installed"
    else
        cat > "$WRAPPER_BELTS" <<'WRAPPER_EOF'
#!/bin/sh
# E5M-CK dual-PNG wrapper for belts — generates a PC-size PNG
# alongside the GuppyScreen one. Called as second RUN_SHELL_COMMAND
# from the GUPPY_BELTS_SHAPER_CALIBRATION macro.
# Usage : gen_belts_png.sh <csv_a> <csv_b>
set -e

CSV_A="$1"
CSV_B="$2"

OUT_DIR="/usr/data/printer_data/config/printer_calibration_graphs"
mkdir -p "$OUT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT_PNG="$OUT_DIR/belts_calibration_PC_SIZE_${TIMESTAMP}.png"

/usr/data/printer_data/config/GuppyScreen/scripts/graph_belts.py \
    -w 8 -l 4.8 -n -o "$OUT_PNG" \
    -k /usr/data/klipper \
    "$CSV_A" "$CSV_B"

echo "PC-sized belts PNG: $OUT_PNG"
WRAPPER_EOF
        chmod +x "$WRAPPER_BELTS"
        log_ok "Installed gen_belts_png.sh"
    fi

    # ─── gen_shaper_combo.sh ──────────────────────────────
    # Intercepts the guppy_input_shaper shell command : runs the
    # original calibrate_shaper.py (small PNG), then runs it again
    # with -w 8 -l 4.8 to produce a PC-size version.
    WRAPPER_SHAPER="$GUPPY_SCRIPTS/gen_shaper_combo.sh"
    if [ -f "$WRAPPER_SHAPER" ] && grep -q "E5M-CK combo wrapper" "$WRAPPER_SHAPER" 2>/dev/null; then
        log_already "gen_shaper_combo.sh already installed"
    else
        cat > "$WRAPPER_SHAPER" <<'WRAPPER_EOF'
#!/bin/sh
# E5M-CK combo wrapper for input shaper — produces both the
# GuppyScreen-sized PNG (default size) and a PC-size PNG.
# Intercepts the guppy_input_shaper shell command : GuppyScreen
# still calls it as before, this wrapper transparently fans out.
set -e

# 1. GuppyScreen sized PNG (original behavior, pass-through args)
/usr/data/printer_data/config/GuppyScreen/scripts/calibrate_shaper.py "$@"

# 2. Detect axis from CSV path
CSV="$1"
AXIS=$(echo "$CSV" | grep -oE "resonances_[xy]" | sed 's/resonances_//')
[ -z "$AXIS" ] && AXIS="unknown"

# 3. PC sized PNG
OUT_DIR="/usr/data/printer_data/config/printer_calibration_graphs"
mkdir -p "$OUT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT_PNG="$OUT_DIR/resonances_${AXIS}_PC_SIZE_${TIMESTAMP}.png"

/usr/data/printer_data/config/GuppyScreen/scripts/calibrate_shaper.py \
    "$CSV" -o "$OUT_PNG" -w 8 -l 4.8

echo "PC-sized shaper PNG: $OUT_PNG"
WRAPPER_EOF
        chmod +x "$WRAPPER_SHAPER"
        log_ok "Installed gen_shaper_combo.sh"
    fi
}


# ─── 5.5 guppy_cmd.cfg dual-PNG integration ──────────────
do_guppy_cmd_dualpng() {
    if [ ! -f "$GUPPY_CMD_CFG" ]; then
        log_warn "$GUPPY_CMD_CFG not found — skipping"
        return 0
    fi

    NEED_WORK=0
    # Check 1 : guppy_input_shaper redirected to combo wrapper ?
    if ! grep -qF "gen_shaper_combo.sh" "$GUPPY_CMD_CFG"; then
        NEED_WORK=1
    fi
    # Check 2 : new shell_command guppy_belts_calibration_pc present ?
    if ! grep -qF "guppy_belts_calibration_pc" "$GUPPY_CMD_CFG"; then
        NEED_WORK=1
    fi

    if [ "$NEED_WORK" -eq 0 ]; then
        log_already "guppy_cmd.cfg dual-PNG integration already in place"
        return 0
    fi

    BACKUP="$GUPPY_CMD_CFG.bak.dualpng.$(date +%Y%m%d_%H%M%S)"
    cp "$GUPPY_CMD_CFG" "$BACKUP"
    log_action "Backed up: $BACKUP"

    # Apply patches via Python for reliability on multi-line edits
    "$PYTHON3" << PYEOF
path = "$GUPPY_CMD_CFG"
with open(path) as f:
    content = f.read()

changes = 0

# Patch A : redirect guppy_input_shaper to combo wrapper
old_a = "command: /usr/data/printer_data/config/GuppyScreen/scripts/calibrate_shaper.py"
new_a = "command: /usr/data/printer_data/config/GuppyScreen/scripts/gen_shaper_combo.sh"
if old_a in content and "gen_shaper_combo.sh" not in content:
    content = content.replace(old_a, new_a)
    changes += 1
    print("  > Redirected guppy_input_shaper to gen_shaper_combo.sh")

# Patch B : add new shell_command guppy_belts_calibration_pc and
# extend GUPPY_BELTS_SHAPER_CALIBRATION macro with an extra RUN_SHELL_COMMAND
if "guppy_belts_calibration_pc" not in content:
    # Find a good insertion point : after the existing
    # [gcode_shell_command guppy_belts_calibration] block.
    import re
    # The shell_command block ends at next blank line or [section] marker.
    # Easier : append the new shell_command block at end of file
    # if not yet there, and patch the macro separately.
    new_shell_cmd = """

[gcode_shell_command guppy_belts_calibration_pc]
command: /usr/data/printer_data/config/GuppyScreen/scripts/gen_belts_png.sh
timeout: 600.0
verbose: True
"""
    content = content.rstrip() + new_shell_cmd
    changes += 1
    print("  > Added [gcode_shell_command guppy_belts_calibration_pc]")

    # Patch the macro : add a second RUN_SHELL_COMMAND for PC-size PNG.
    # The macro contains a line like :
    #   RUN_SHELL_COMMAND CMD=guppy_belts_calibration PARAMS="-w ... -k /usr/data/klipper /tmp/raw_data_axis=...,_a.csv /tmp/raw_data_axis=...,_b.csv"
    # We insert AFTER it :
    #   RESPOND MSG="Generating Belts Plot (PC size)..."
    #   RUN_SHELL_COMMAND CMD=guppy_belts_calibration_pc PARAMS="/tmp/raw_data_axis=...,_a.csv /tmp/raw_data_axis=...,_b.csv"
    macro_pattern = r'(RUN_SHELL_COMMAND CMD=guppy_belts_calibration PARAMS="[^"]+")'
    macro_match = re.search(macro_pattern, content)
    if macro_match:
        original_line = macro_match.group(1)
        # Extract the two CSV paths from the params
        csv_match = re.search(r'(/tmp/raw_data_axis=[^\s"]+_a\.csv)\s+(/tmp/raw_data_axis=[^\s"]+_b\.csv)',
                              original_line)
        if csv_match:
            csv_a = csv_match.group(1)
            csv_b = csv_match.group(2)
            addition = (
                original_line + "\n"
                "  RESPOND MSG=\"Generating Belts Plot (PC size)...\"\n"
                "  RUN_SHELL_COMMAND CMD=guppy_belts_calibration_pc PARAMS=\""
                + csv_a + " " + csv_b + "\""
            )
            content = content.replace(original_line, addition, 1)
            changes += 1
            print("  > Extended GUPPY_BELTS_SHAPER_CALIBRATION macro")

with open(path, "w") as f:
    f.write(content)
print("Total changes : %d" % changes)
PYEOF

    log_ok "guppy_cmd.cfg dual-PNG integration applied"
}


# ─── 5.6 graph_belts.py cosmetic patches ──────────────────
do_graph_belts_patches() {
    if [ ! -f "$GRAPH_BELTS_PY" ]; then
        log_warn "$GRAPH_BELTS_PY not found — skipping cosmetic patches"
        return 0
    fi

    # Detect if all 3 patches are already in place
    P1=$(grep -c "split('_')\[-1\]\[0\]\.upper()" "$GRAPH_BELTS_PY" 2>/dev/null || echo 0)
    P2=$(grep -c "os.path.getmtime" "$GRAPH_BELTS_PY" 2>/dev/null || echo 0)
    P3=$(grep -c "E5M-CK: remap A/B" "$GRAPH_BELTS_PY" 2>/dev/null || echo 0)

    if [ "$P1" -gt 0 ] && [ "$P2" -gt 0 ] && [ "$P3" -gt 0 ]; then
        log_already "graph_belts.py already patched (all 3 fixes present)"
        return 0
    fi

    BACKUP="$GRAPH_BELTS_PY.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$GRAPH_BELTS_PY" "$BACKUP"
    log_action "Backed up: $BACKUP"

    "$PYTHON3" << PYEOF
path = "$GRAPH_BELTS_PY"
with open(path) as f:
    content = f.read()

changes = 0

# Patch 1 : case-insensitive belt letter extraction (eliminates the
# "doesn't seem to have correct name A and B" warning)
old1 = "    signal1_belt = (lognames[0].split('/')[-1]).split('_')[-1][0]\n"
old1 += "    signal2_belt = (lognames[1].split('/')[-1]).split('_')[-1][0]"
new1 = "    signal1_belt = (lognames[0].split('/')[-1]).split('_')[-1][0].upper()\n"
new1 += "    signal2_belt = (lognames[1].split('/')[-1]).split('_')[-1][0].upper()"
if old1 in content:
    content = content.replace(old1, new1)
    changes += 1
    print("  > Patch 1 applied : .upper() on belt letter extraction")

# Patch 2 : fallback to file mtime for title date (eliminates
# "CSV filenames look to be different than expected" warning)
old2 = '''    try:
        filename = lognames[0].split('/')[-1]
        dt = datetime.strptime(f"{filename.split('_')[1]} {filename.split('_')[2]}", "%Y%m%d %H%M%S")
        title_line2 = dt.strftime('%x %X')
    except:
        print("Warning: CSV filenames look to be different than expected (%s , %s)" % (lognames[0], lognames[1]))
        title_line2 = lognames[0].split('/')[-1] + " / " +  lognames[1].split('/')[-1]'''

new2 = '''    try:
        filename = lognames[0].split('/')[-1]
        dt = datetime.strptime(f"{filename.split('_')[1]} {filename.split('_')[2]}", "%Y%m%d %H%M%S")
        title_line2 = dt.strftime('%x %X')
    except:
        # Klipper-native format (no date in filename): use file mtime as title date
        try:
            import os
            mtime = os.path.getmtime(lognames[0])
            dt = datetime.fromtimestamp(mtime)
            title_line2 = dt.strftime('%x %X')
        except:
            title_line2 = lognames[0].split('/')[-1] + " / " +  lognames[1].split('/')[-1]'''

if old2 in content:
    content = content.replace(old2, new2)
    changes += 1
    print("  > Patch 2 applied : mtime fallback for title date")

# Patch 3 : remap A/B (CoreXY convention) to X belt / Y belt
# (verified empirically via STEPPER_BUZZ + diagonal moves on Ender 5 Max)
old3 = '''    if signal1_belt == 'A' and signal2_belt == 'B':
        signal1_belt += " (axis 1,-1)"
        signal2_belt += " (axis 1, 1)"
    elif signal1_belt == 'B' and signal2_belt == 'A':
        signal1_belt += " (axis 1, 1)"
        signal2_belt += " (axis 1,-1)"
    else:
        print("Warning: belts doesn't seem to have the correct name A and B (extracted from the filename.csv)")'''

new3 = '''    # E5M-CK: remap A/B (CoreXY convention) to X/Y (physical belts on Ender 5 Max)
    #   Belt A = stepper_x rotation = X belt (verified via STEPPER_BUZZ + diagonal moves)
    #   Belt B = stepper_y rotation = Y belt
    if signal1_belt == 'A' and signal2_belt == 'B':
        signal1_belt = "X belt"
        signal2_belt = "Y belt"
    elif signal1_belt == 'B' and signal2_belt == 'A':
        signal1_belt = "Y belt"
        signal2_belt = "X belt"
    else:
        print("Warning: belts doesn't seem to have the correct name A and B (extracted from the filename.csv)")'''

if old3 in content:
    content = content.replace(old3, new3)
    changes += 1
    print("  > Patch 3a applied : remap A/B to X belt / Y belt")

# Patch 3b : remove the redundant "Belt " prefix in plot labels (since
# signal1_belt is now "X belt" not "X")
old3b = '''    ax.plot(signal1.freqs, signal1.psd, label="Belt " + signal1_belt, color=KLIPPAIN_COLORS['purple'])
    ax.plot(signal2.freqs, signal2.psd, label="Belt " + signal2_belt, color=KLIPPAIN_COLORS['orange'])'''

new3b = '''    ax.plot(signal1.freqs, signal1.psd, label=signal1_belt, color=KLIPPAIN_COLORS['purple'])
    ax.plot(signal2.freqs, signal2.psd, label=signal2_belt, color=KLIPPAIN_COLORS['orange'])'''

if old3b in content:
    content = content.replace(old3b, new3b)
    changes += 1
    print("  > Patch 3b applied : removed redundant 'Belt' prefix")

with open(path, "w") as f:
    f.write(content)

print("Total changes : %d" % changes)
PYEOF

    log_ok "graph_belts.py patched"
}


# ─── 5.7 Move duplicate cfg backups out of config/ ────────
do_cleanup_config_backups() {
    if [ ! -d "$PRINTER_CONFIG_DIR" ]; then
        log_warn "$PRINTER_CONFIG_DIR not found — skipping cleanup"
        return 0
    fi

    # Find dated backups of printer.cfg that Klipper would auto-include
    # (anything matching printer-*.cfg in config/ but NOT printer.cfg itself)
    DUPLICATES=$(find "$PRINTER_CONFIG_DIR" -maxdepth 1 -name "printer-*.cfg" 2>/dev/null)

    if [ -z "$DUPLICATES" ]; then
        log_already "No duplicate printer-*.cfg files in config/"
        return 0
    fi

    mkdir -p "$PRINTER_BACKUP_CFG"
    MOVED=0
    echo "$DUPLICATES" | while read f; do
        [ -f "$f" ] || continue
        BASENAME=$(basename "$f")
        mv "$f" "$PRINTER_BACKUP_CFG/$BASENAME"
        log_action "Moved $BASENAME -> $PRINTER_BACKUP_CFG/"
        MOVED=$((MOVED + 1))
    done
    log_ok "Duplicate cfg backups moved to $PRINTER_BACKUP_CFG/"
}


# ─── 5.8 Restart Klipper ──────────────────────────────────
do_restart_klipper() {
    if [ ! -x "$KLIPPER_SERVICE" ]; then
        log_warn "$KLIPPER_SERVICE not found — restart manually if needed"
        return 0
    fi

    log_info "Restarting Klipper service..."
    "$KLIPPER_SERVICE" restart >/dev/null 2>&1 || true
    sleep 5

    # Verify Klipper came back up
    STATE=$(wget --no-check-certificate -q -O - \
            "$MOONRAKER_API/printer/info" 2>/dev/null | \
            grep -o '"state_message":"[^"]*"' | head -1)
    case "$STATE" in
        *"Printer is ready"*)
            log_ok "Klipper restarted and is ready"
            ;;
        "")
            log_warn "Could not query Klipper state — check klippy.log"
            ;;
        *)
            log_warn "Klipper state : $STATE"
            log_warn "Check klippy.log for details"
            ;;
    esac
}


# ════════════════════════════════════════════════════════════
# COMPLETION
# ════════════════════════════════════════════════════════════
show_completion() {
    p ""
    p "${BR_RED}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${BG_RED}${WHITE}${BOLD}  ✓  PERSONALIZATION COMPLETE  ${NC}                            ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"

    if [ "${FLUIDD_DONE:-0}" -eq 1 ]; then
        p "${BR_RED}  ║${NC}    ${BR_GREEN}✓${NC} ${WHITE}Fluidd settings restored${NC}                                  ${BR_RED}║${NC}"
        p "${BR_RED}  ║${NC}      ${DIM}→ Reload Fluidd in your browser to see new theme/macros${NC}   ${BR_RED}║${NC}"
    else
        p "${BR_RED}  ║${NC}    ${GRAY}~ Fluidd settings: skipped${NC}                                  ${BR_RED}║${NC}"
    fi

    if [ "${GUPPY_DONE:-0}" -eq 1 ]; then
        p "${BR_RED}  ║${NC}    ${BR_GREEN}✓${NC} ${WHITE}GuppyScreen config deployed${NC}                                ${BR_RED}║${NC}"
        p "${BR_RED}  ║${NC}      ${DIM}→ First boot will prompt for touch calibration${NC}              ${BR_RED}║${NC}"
    else
        p "${BR_RED}  ║${NC}    ${GRAY}~ GuppyScreen config: skipped${NC}                               ${BR_RED}║${NC}"
    fi

    if [ "${LOGO_DONE:-0}" -eq 1 ]; then
        p "${BR_RED}  ║${NC}    ${BR_GREEN}✓${NC} ${WHITE}Boot logos replaced${NC}                                       ${BR_RED}║${NC}"
        p "${BR_RED}  ║${NC}      ${DIM}→ Reboot to see the new E5M-CK boot screen${NC}                  ${BR_RED}║${NC}"
    else
        p "${BR_RED}  ║${NC}    ${GRAY}~ Boot logo: skipped${NC}                                        ${BR_RED}║${NC}"
    fi

    if [ "${CALIB_DONE:-0}" -eq 1 ]; then
        p "${BR_RED}  ║${NC}    ${BR_GREEN}✓${NC} ${WHITE}GuppyScreen calibration fixes applied${NC}                     ${BR_RED}║${NC}"
        p "${BR_RED}  ║${NC}      ${DIM}→ Belts + Input Shaper now produce dual-PNG outputs${NC}         ${BR_RED}║${NC}"
        p "${BR_RED}  ║${NC}      ${DIM}→ View PC PNGs in printer_calibration_graphs/${NC}                ${BR_RED}║${NC}"
    else
        p "${BR_RED}  ║${NC}    ${GRAY}~ Calibration fixes: skipped${NC}                                ${BR_RED}║${NC}"
    fi

    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ╚══════════════════════════════════════════════════════════════════╝${NC}"
    p ""

    if [ "${LOGO_DONE:-0}" -eq 1 ] || [ "${GUPPY_DONE:-0}" -eq 1 ]; then
        p "  ${YELLOW}${BOLD}Reboot recommended${NC} ${WHITE}to fully apply changes:${NC}"
        p "    ${DIM}sync && reboot${NC}"
        p ""
    fi
}


# ════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════
main() {
    show_banner
    show_disclaimer

    if ! confirm "Continue with personalization?"; then
        log_warn "Cancelled by user"
        exit 0
    fi

    FLUIDD_DONE=0
    GUPPY_DONE=0
    LOGO_DONE=0
    CALIB_DONE=0

    step_precheck
    step_fluidd_settings
    step_guppy_config
    step_boot_logo
    step_guppy_calibration_fixes
    show_completion
}

main "$@"
