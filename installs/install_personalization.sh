#!/bin/sh
# ============================================================
#   E5M-CK — install_personalization.sh
#   Personalization layer (post-install): Fluidd settings,
#   GuppyScreen config, Creality boot logo.
#
#   Sections (each can be skipped interactively):
#     1. Restore Fluidd settings (theme, macros, charts) via
#        Moonraker DB API.
#     2. Deploy custom guppyconfig.json (E5M-CK fans, leds, theme).
#     3. Replace Creality boot logos with E5M-CK logo.
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
    p "${WHITE}            install_personalization.sh${NC}"
    p "${GRAY}    Fluidd settings + GuppyScreen config + boot logo${NC}"
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
    p ""
    p "  ${DIM}All changes are reversible (backups in /usr/data/).${NC}"
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

    step_precheck
    step_fluidd_settings
    step_guppy_config
    step_boot_logo
    show_completion
}

main "$@"
