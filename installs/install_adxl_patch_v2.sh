#!/bin/sh
# ═══════════════════════════════════════════════════════════════════
# install.sh — ADXL345 Creality firmware bridge for Klipper mainline
#
# Deploys two Python modules into Klipper extras and patches
# printer.cfg so [resonance_tester] / SHAPER_CALIBRATE can talk to
# the Creality 2023 firmware on the nozzle_mcu (which uses the
# legacy "query_adxl345 oid clock rest_ticks" wire format).
#
# Also patches klippy/configfile.py to suppress two harmless but
# permanent deprecation warnings emitted by the Creality 2023
# firmware (spi_set_sw_bus, STEPPER_STEP_BOTH_EDGE).
#
# Usage from SSH on the printer:
#   curl -sSL https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh | sh
#   curl -sSL https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh | sh -s -- status
#   curl -sSL https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh | sh -s -- update
#   curl -sSL https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh | sh -s -- uninstall
#
# Or download once and run locally:
#   wget https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh
#   sh install_adxl_patch_v2.sh install
# ═══════════════════════════════════════════════════════════════════

set -e

# ─── Configuration (edit before publishing) ────────────────────────
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/christianKEL/E5M-CK/main/files}"

# ─── Paths (Creality K-stack defaults) ─────────────────────────────
KLIPPER_EXTRAS="/usr/data/klipper/klippy/extras"
KLIPPY_ENV_PYTHON="/usr/share/klippy-env/bin/python"
PRINTER_CFG="/usr/data/printer_data/config/printer.cfg"
KLIPPY_LOG="/usr/data/printer_data/logs/klippy.log"
SERVICE_SCRIPT="/etc/init.d/S55klipper_service"
CONFIGFILE_PY="/usr/data/klipper/klippy/configfile.py"

# ─── Internal markers ──────────────────────────────────────────────
MODULES="adxl345_creality.py accel_chip_proxy.py"
CFG_MARKER_BEGIN="# >>> adxl345-creality-bridge >>>"
CFG_MARKER_END="# <<< adxl345-creality-bridge <<<"
CFG_BACKUP_SUFFIX=".bak.adxl345-creality"
CONFIGFILE_PATCH_MARKER="E5M_CK_SUPPRESSED_FEATURES"
CONFIGFILE_BACKUP_SUFFIX=".bak.before_e5m_ck"

# ─── Console helpers ───────────────────────────────────────────────
RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; RESET=""
if [ -t 1 ]; then
  RED="$(printf '\033[31m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  BLUE="$(printf '\033[34m')"
  BOLD="$(printf '\033[1m')"
  RESET="$(printf '\033[0m')"
fi

log()  { printf '%s[*]%s %s\n' "$BLUE"   "$RESET" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$GREEN"  "$RESET" "$*"; }
warn() { printf '%s[!]%s %s\n' "$YELLOW" "$RESET" "$*"; }
err()  { printf '%s[-]%s %s\n' "$RED"    "$RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ═══════════════════════════════════════════════════════════════════
# Sanity checks
# ═══════════════════════════════════════════════════════════════════
preflight() {
  [ "$(id -u)" -eq 0 ] || die "Run as root."
  [ -d "$KLIPPER_EXTRAS" ] || die "Not found: $KLIPPER_EXTRAS — is Klipper installed?"
  [ -x "$KLIPPY_ENV_PYTHON" ] || die "Not found: $KLIPPY_ENV_PYTHON — wrong venv path?"
  [ -f "$PRINTER_CFG" ] || die "Not found: $PRINTER_CFG"
  [ -f "$CONFIGFILE_PY" ] || die "Not found: $CONFIGFILE_PY"
  [ -x "$SERVICE_SCRIPT" ] || die "Not found: $SERVICE_SCRIPT"
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    die "Neither curl nor wget is available."
  fi
  case "$REPO_RAW" in
    *CHANGE_ME*)
      die "REPO_RAW is not configured. Edit install_adxl_patch_v2.sh and set the GitHub raw URL, or run with REPO_RAW=https://... sh install_adxl_patch_v2.sh"
      ;;
  esac
}

fetch() {
  # fetch <url> <dest>
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$2" || return 1
  else
    wget -qO "$2" "$1" || return 1
  fi
  [ -s "$2" ] || return 1
}

py_check() {
  # py_check <file>
  "$KLIPPY_ENV_PYTHON" -m py_compile "$1" 2>&1
}

klipper_running() {
  pgrep -f "klippy.py" >/dev/null 2>&1
}

klipper_stop() {
  if klipper_running; then
    log "Stopping Klipper..."
    "$SERVICE_SCRIPT" stop >/dev/null 2>&1 || true
    sleep 2
  fi
}

klipper_start() {
  log "Starting Klipper..."
  "$SERVICE_SCRIPT" start >/dev/null 2>&1 || true
  sleep 3
}

klipper_restart() {
  log "Restarting Klipper..."
  "$SERVICE_SCRIPT" restart >/dev/null 2>&1 || true
  sleep 5
}

# ═══════════════════════════════════════════════════════════════════
# Module download & install
# ═══════════════════════════════════════════════════════════════════
download_modules() {
  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR"' EXIT
  for f in $MODULES; do
    log "Downloading $f..."
    if ! fetch "$REPO_RAW/$f" "$TMPDIR/$f"; then
      die "Download failed: $REPO_RAW/$f"
    fi
    # Sanity: must be Python (not a 404 HTML page)
    if ! head -1 "$TMPDIR/$f" | grep -qE '^(#|import|from|""")'; then
      die "Downloaded $f does not look like Python — bad URL?"
    fi
  done
  ok "All modules downloaded."
}

install_modules() {
  for f in $MODULES; do
    if [ -f "$KLIPPER_EXTRAS/$f" ]; then
      cp -a "$KLIPPER_EXTRAS/$f" "$KLIPPER_EXTRAS/$f$CFG_BACKUP_SUFFIX"
    fi
    cp "$TMPDIR/$f" "$KLIPPER_EXTRAS/$f"
    log "Verifying $f syntax..."
    if ! py_check "$KLIPPER_EXTRAS/$f"; then
      err "Syntax check failed on $f"
      die "Aborting — restore via 'uninstall' or check $f manually."
    fi
    ok "Installed: $KLIPPER_EXTRAS/$f"
  done
}

remove_modules() {
  for f in $MODULES; do
    if [ -f "$KLIPPER_EXTRAS/$f" ]; then
      rm -f "$KLIPPER_EXTRAS/$f"
      ok "Removed: $KLIPPER_EXTRAS/$f"
    fi
    # Also clean .pyc Klipper might have generated
    rm -f "$KLIPPER_EXTRAS/${f}c"
    rm -f "$KLIPPER_EXTRAS/$f$CFG_BACKUP_SUFFIX"
  done
}

# ═══════════════════════════════════════════════════════════════════
# printer.cfg patching
# ═══════════════════════════════════════════════════════════════════
cfg_already_patched() {
  grep -qF "$CFG_MARKER_BEGIN" "$PRINTER_CFG"
}

cfg_patch() {
  if cfg_already_patched; then
    warn "printer.cfg already contains the bridge config — skipping patch."
    return 0
  fi

  BACKUP="$PRINTER_CFG$CFG_BACKUP_SUFFIX"
  log "Backing up printer.cfg → $BACKUP"
  cp -a "$PRINTER_CFG" "$BACKUP"

  # Klipper's SAVE_CONFIG appends a block at the end of printer.cfg
  # (lines starting with #*#). Anything ADDED AFTER that block will
  # be silently moved or corrupted on the next SAVE_CONFIG. So we
  # must insert our block BEFORE the SAVE_CONFIG block.
  SAVE_BLOCK_LINE="$(grep -n '^#\*#' "$PRINTER_CFG" | head -1 | cut -d: -f1)"

  BLOCK_FILE="$(mktemp)"
  cat > "$BLOCK_FILE" <<EOF
$CFG_MARKER_BEGIN
# Auto-added by adxl345-creality-bridge install_adxl_patch_v2.sh
# To remove this block, run install.sh uninstall (or delete manually
# everything between the BEGIN/END markers).
[accel_chip_proxy]
accel_use_chip:                adxl345
adxl345_cs_pin:                nozzle_mcu:PA4
adxl345_spi_speed:             5000000
adxl345_axes_map:              x,-z,y
adxl345_spi_software_sclk_pin: nozzle_mcu:PA5
adxl345_spi_software_mosi_pin: nozzle_mcu:PA7
adxl345_spi_software_miso_pin: nozzle_mcu:PA6

lis2dw_cs_pin:                 nozzle_mcu:PA4
lis2dw_spi_speed:              5000000
lis2dw_axes_map:               x,-z,y
lis2dw_spi_software_sclk_pin:  nozzle_mcu:PA5
lis2dw_spi_software_mosi_pin:  nozzle_mcu:PA7
lis2dw_spi_software_miso_pin:  nozzle_mcu:PA6

[resonance_tester]
accel_chip: accel_chip_proxy
probe_points: 200, 200, 10
accel_per_hz: 50
$CFG_MARKER_END
EOF

  if [ -n "$SAVE_BLOCK_LINE" ]; then
    log "Found SAVE_CONFIG block at line $SAVE_BLOCK_LINE — inserting block before it"
    # Split: lines 1..(SAVE_BLOCK_LINE-1), our block, lines SAVE_BLOCK_LINE..end
    BEFORE_LINE=$((SAVE_BLOCK_LINE - 1))
    TMPCFG="$(mktemp)"
    head -n "$BEFORE_LINE" "$PRINTER_CFG" > "$TMPCFG"
    cat "$BLOCK_FILE" >> "$TMPCFG"
    tail -n +"$SAVE_BLOCK_LINE" "$PRINTER_CFG" >> "$TMPCFG"
    mv "$TMPCFG" "$PRINTER_CFG"
    ok "printer.cfg patched (inserted before SAVE_CONFIG block)."
  else
    log "No SAVE_CONFIG block found — appending at end of file"
    cat "$BLOCK_FILE" >> "$PRINTER_CFG"
    ok "printer.cfg patched (appended at end)."
  fi

  rm -f "$BLOCK_FILE"
}

cfg_unpatch() {
  if ! cfg_already_patched; then
    warn "No bridge block found in printer.cfg — nothing to unpatch."
    return 0
  fi
  BACKUP="$PRINTER_CFG$CFG_BACKUP_SUFFIX"
  if [ -f "$BACKUP" ]; then
    log "Restoring printer.cfg from backup $BACKUP"
    # Save current as .pre-restore in case user wants it back
    cp -a "$PRINTER_CFG" "${PRINTER_CFG}.pre-uninstall"
    cp -a "$BACKUP" "$PRINTER_CFG"
    ok "printer.cfg restored. (Pre-restore version saved to ${PRINTER_CFG}.pre-uninstall)"
  else
    warn "Backup $BACKUP not found — stripping markers in place."
    # Use sed to delete from BEGIN to END marker inclusive.
    # Use a temp file to avoid sed -i portability issues.
    TMPCFG="$(mktemp)"
    awk -v b="$CFG_MARKER_BEGIN" -v e="$CFG_MARKER_END" '
      $0 ~ b { skip=1 }
      !skip
      $0 ~ e { skip=0 }
    ' "$PRINTER_CFG" > "$TMPCFG"
    mv "$TMPCFG" "$PRINTER_CFG"
    ok "Bridge block removed from printer.cfg."
  fi
}

# ═══════════════════════════════════════════════════════════════════
# configfile.py patching — suppress harmless deprecation warnings
#
# The Creality 2023 nozzle MCU firmware lacks two commands that
# mainline Klipper expects: 'spi_set_sw_bus' (newer signature) and
# 'STEPPER_STEP_BOTH_EDGE'. Both are functionally compensated:
#   - spi_set_sw_bus: bus.py falls back to legacy form (still works)
#   - STEPPER_STEP_BOTH_EDGE: step_pulse_duration in printer.cfg
# We patch deprecate_mcu_code() to silently skip these two features,
# eliminating the permanent red banner in Fluidd.
#
# Idempotent: detects presence via E5M_CK_SUPPRESSED_FEATURES marker.
# ═══════════════════════════════════════════════════════════════════
configfile_already_patched() {
  grep -qF "$CONFIGFILE_PATCH_MARKER" "$CONFIGFILE_PY"
}

configfile_patch() {
  if configfile_already_patched; then
    warn "configfile.py already patched (warning suppression in place) — skipping."
    return 0
  fi

  # Verify the target function exists in the expected form
  if ! grep -q "def deprecate_mcu_code(self, mcu, feature, msg=None):" "$CONFIGFILE_PY"; then
    warn "deprecate_mcu_code() signature differs in this Klipper version."
    warn "Skipping configfile.py patch — warnings will remain visible but harmless."
    return 0
  fi

  # Always create a fresh dated backup. Also create .bak.before_e5m_ck
  # if it doesn't exist yet (this is our canonical "factory" reference).
  TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
  DATED_BACKUP="$CONFIGFILE_PY.bak.before_warning_patch.$TIMESTAMP"
  cp -a "$CONFIGFILE_PY" "$DATED_BACKUP"
  if [ ! -f "$CONFIGFILE_PY$CONFIGFILE_BACKUP_SUFFIX" ]; then
    cp -a "$CONFIGFILE_PY" "$CONFIGFILE_PY$CONFIGFILE_BACKUP_SUFFIX"
    log "Created reference backup: $CONFIGFILE_PY$CONFIGFILE_BACKUP_SUFFIX"
  fi
  log "Created dated backup: $DATED_BACKUP"

  # Apply patch via Python (more robust than sed on multi-line code)
  "$KLIPPY_ENV_PYTHON" - "$CONFIGFILE_PY" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()

old = "    def deprecate_mcu_code(self, mcu, feature, msg=None):\n        mcu_name = mcu.get_name()"

new = """    def deprecate_mcu_code(self, mcu, feature, msg=None):
        # E5M-CK: suppress known deprecated-feature warnings for Creality
        # 2023 firmware which we deliberately keep (cannot reflash nozzle MCU
        # safely — see MEMO_adxl345_bridge_ENG.md).
        #   STEPPER_STEP_BOTH_EDGE: compensated by step_pulse_duration in cfg
        #   spi_set_sw_bus: legacy software-SPI command name (still functional)
        E5M_CK_SUPPRESSED_FEATURES = (
            'STEPPER_STEP_BOTH_EDGE',
            'spi_set_sw_bus',
        )
        if feature in E5M_CK_SUPPRESSED_FEATURES:
            return
        mcu_name = mcu.get_name()"""

if old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("OK")
    sys.exit(0)
else:
    print("PATTERN_NOT_FOUND")
    sys.exit(1)
PYEOF

  PATCH_RESULT=$?
  if [ "$PATCH_RESULT" -ne 0 ]; then
    warn "configfile.py patch failed — pattern not found."
    warn "Klipper version may have changed deprecate_mcu_code() implementation."
    warn "Skipping warning suppression (the bridge itself is unaffected)."
    return 0
  fi

  # Validate Python syntax after patching
  if ! py_check "$CONFIGFILE_PY" >/dev/null 2>&1; then
    err "configfile.py syntax broken after patch — restoring from dated backup."
    cp -a "$DATED_BACKUP" "$CONFIGFILE_PY"
    return 1
  fi

  ok "configfile.py patched (warning suppression active)."
}

configfile_unpatch() {
  if ! configfile_already_patched; then
    warn "configfile.py is not patched — nothing to revert."
    return 0
  fi

  # Prefer the canonical backup; fall back to dated backups if needed
  REVERT_FROM="$CONFIGFILE_PY$CONFIGFILE_BACKUP_SUFFIX"
  if [ ! -f "$REVERT_FROM" ]; then
    # Try the most recent dated backup
    REVERT_FROM="$(ls -1t "$CONFIGFILE_PY".bak.before_warning_patch.* 2>/dev/null | head -1)"
  fi

  if [ -n "$REVERT_FROM" ] && [ -f "$REVERT_FROM" ]; then
    log "Restoring configfile.py from $REVERT_FROM"
    cp -a "$REVERT_FROM" "$CONFIGFILE_PY"
    ok "configfile.py restored."
  else
    warn "No backup found — attempting in-place revert via Python."
    "$KLIPPY_ENV_PYTHON" - "$CONFIGFILE_PY" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()

old = """    def deprecate_mcu_code(self, mcu, feature, msg=None):
        # E5M-CK: suppress known deprecated-feature warnings for Creality
        # 2023 firmware which we deliberately keep (cannot reflash nozzle MCU
        # safely — see MEMO_adxl345_bridge_ENG.md).
        #   STEPPER_STEP_BOTH_EDGE: compensated by step_pulse_duration in cfg
        #   spi_set_sw_bus: legacy software-SPI command name (still functional)
        E5M_CK_SUPPRESSED_FEATURES = (
            'STEPPER_STEP_BOTH_EDGE',
            'spi_set_sw_bus',
        )
        if feature in E5M_CK_SUPPRESSED_FEATURES:
            return
        mcu_name = mcu.get_name()"""

new = "    def deprecate_mcu_code(self, mcu, feature, msg=None):\n        mcu_name = mcu.get_name()"

if old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("OK")
    sys.exit(0)
else:
    print("MANUAL_REVIEW_NEEDED")
    sys.exit(1)
PYEOF
  fi
}

# ═══════════════════════════════════════════════════════════════════
# Subcommands
# ═══════════════════════════════════════════════════════════════════
cmd_install() {
  log "${BOLD}Installing adxl345-creality-bridge${RESET}"
  preflight
  download_modules
  klipper_stop
  install_modules
  cfg_patch
  configfile_patch
  klipper_start
  echo
  ok "Installation complete."
  log "Watch the log for errors:"
  echo "    tail -f $KLIPPY_LOG"
  log "Then in Fluidd / GuppyScreen, run:"
  echo "    ACCELEROMETER_QUERY"
  echo "    SHAPER_CALIBRATE"
}

cmd_update() {
  log "${BOLD}Updating modules only (no printer.cfg changes)${RESET}"
  preflight
  download_modules
  klipper_stop
  install_modules
  # Re-apply configfile.py patch if a Klipper update removed it
  configfile_patch
  klipper_start
  ok "Update complete."
}

cmd_uninstall() {
  log "${BOLD}Uninstalling adxl345-creality-bridge${RESET}"
  preflight
  klipper_stop
  cfg_unpatch
  configfile_unpatch
  remove_modules
  klipper_start
  ok "Uninstall complete."
}

cmd_status() {
  preflight
  echo
  printf "${BOLD}Klipper service:${RESET} "
  if klipper_running; then
    printf "${GREEN}running${RESET} (pid %s)\n" "$(pgrep -f klippy.py | head -1)"
  else
    printf "${RED}not running${RESET}\n"
  fi

  printf "${BOLD}Klipper venv python:${RESET} "
  [ -x "$KLIPPY_ENV_PYTHON" ] && printf "${GREEN}OK${RESET} (%s)\n" "$KLIPPY_ENV_PYTHON" \
    || printf "${RED}MISSING${RESET}\n"

  echo
  printf "${BOLD}Modules in extras:${RESET}\n"
  for f in $MODULES; do
    if [ -f "$KLIPPER_EXTRAS/$f" ]; then
      SIZE=$(wc -c < "$KLIPPER_EXTRAS/$f")
      printf "    ${GREEN}[installed]${RESET} %-30s (%s bytes)\n" "$f" "$SIZE"
    else
      printf "    ${RED}[missing]${RESET}   %s\n" "$f"
    fi
  done

  echo
  printf "${BOLD}printer.cfg patch:${RESET} "
  if cfg_already_patched; then
    printf "${GREEN}present${RESET}\n"
  else
    printf "${YELLOW}absent${RESET}\n"
  fi
  if [ -f "$PRINTER_CFG$CFG_BACKUP_SUFFIX" ]; then
    printf "${BOLD}printer.cfg backup:${RESET}   ${GREEN}present${RESET} (%s)\n" \
      "$PRINTER_CFG$CFG_BACKUP_SUFFIX"
  fi

  printf "${BOLD}configfile.py patch:${RESET} "
  if configfile_already_patched; then
    printf "${GREEN}present${RESET} (warnings suppressed)\n"
  else
    printf "${YELLOW}absent${RESET} (deprecation warnings will appear)\n"
  fi
  if [ -f "$CONFIGFILE_PY$CONFIGFILE_BACKUP_SUFFIX" ]; then
    printf "${BOLD}configfile.py backup:${RESET} ${GREEN}present${RESET} (%s)\n" \
      "$CONFIGFILE_PY$CONFIGFILE_BACKUP_SUFFIX"
  fi

  echo
  printf "${BOLD}Last 5 lines of klippy.log:${RESET}\n"
  if [ -f "$KLIPPY_LOG" ]; then
    tail -5 "$KLIPPY_LOG" | sed 's/^/    /'
  else
    echo "    (no log file)"
  fi
}

cmd_help() {
  cat <<EOF
${BOLD}install_adxl_patch_v2.sh — adxl345-creality-bridge installer${RESET}

Subcommands:
  install     Download modules, patch printer.cfg + configfile.py, restart Klipper
  update      Download modules + re-apply configfile.py patch if missing
  uninstall   Restore printer.cfg + configfile.py, remove modules, restart Klipper
  status      Show what's installed / running
  help        This message

What gets installed:
  1. Python modules in /usr/data/klipper/klippy/extras/
     - adxl345_creality.py
     - accel_chip_proxy.py
  2. Bridge config block in /usr/data/printer_data/config/printer.cfg
     [accel_chip_proxy] + [resonance_tester]
  3. Warning suppression in /usr/data/klipper/klippy/configfile.py
     Filters out 'spi_set_sw_bus' and 'STEPPER_STEP_BOTH_EDGE'
     deprecated-feature warnings that the Creality 2023 firmware
     would otherwise emit permanently.

Environment:
  REPO_RAW   GitHub raw URL base. Currently: $REPO_RAW

Examples:
  curl -sSL https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh | sh
  curl -sSL https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh | sh -s -- status
  curl -sSL https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh | sh -s -- uninstall
EOF
}

# ═══════════════════════════════════════════════════════════════════
# Dispatch
# ═══════════════════════════════════════════════════════════════════
CMD="${1:-install}"
case "$CMD" in
  install)   cmd_install ;;
  update)    cmd_update ;;
  uninstall) cmd_uninstall ;;
  status)    cmd_status ;;
  help|-h|--help) cmd_help ;;
  *)
    err "Unknown subcommand: $CMD"
    cmd_help
    exit 1
    ;;
esac
