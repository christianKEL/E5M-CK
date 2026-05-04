#!/bin/sh
# ============================================================
#   E5M-CK — install_klipper_patches.sh
#   Apply local patches to Klipper to suppress harmless warnings
#   that don't apply to our Creality MCU stack.
#
#   Currently applied patches:
#     1. Suppress STEPPER_STEP_BOTH_EDGE warning
#        (Creality MCU firmware Jul 2023 lacks this feature.
#         We compensate via step_pulse_duration in printer.cfg.)
#
#   Each patch is:
#     - Idempotent (script can be re-run safely)
#     - Surgical (only the targeted feature/code is modified)
#     - Committed locally so git status stays clean
#     - Reversible via the .bak files in /usr/data/klipper/klippy/
#
#   Repo:  https://github.com/christianKEL/E5M-CK
#   Docs:  https://e5mdocumentation.kinsta.cloud/
# ============================================================

set -e

# ─── PATHS ─────────────────────────────────────────────────
KLIPPER_DIR="/usr/data/klipper"
KLIPPY_DIR="$KLIPPER_DIR/klippy"
KLIPPER_SERVICE="/etc/init.d/S55klipper_service"

CONFIGFILE_PY="$KLIPPY_DIR/configfile.py"
CONFIGFILE_BAK="$KLIPPY_DIR/configfile.py.bak.before_e5m_ck"

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
    p "${WHITE}              install_klipper_patches.sh${NC}"
    p "${GRAY}     Local patches to suppress Creality MCU warnings${NC}"
    p ""
    p "                    ${BG_RED}${WHITE}${BOLD}  CR*ALITY S*CKS  ${NC}"
    p ""
    p "${DIM}                 github.com/christianKEL/E5M-CK${NC}"
    p ""
}

show_disclaimer() {
    p "${BR_RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}║${NC}  ${BG_RED}${WHITE}${BOLD}  KLIPPER LOCAL PATCHES  ${NC}                                        ${BR_RED}║${NC}"
    p "${BR_RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
    p "  ${WHITE}This script applies surgical patches to your local Klipper clone${NC}"
    p "  ${WHITE}to suppress warnings that don't apply to the Creality MCU stack.${NC}"
    p ""
    p "  ${WHITE}Patches applied:${NC}"
    p "    ${BR_GREEN}1.${NC} ${WHITE}Suppress STEPPER_STEP_BOTH_EDGE warning${NC}"
    p "       ${DIM}Compensated by step_pulse_duration: 0.000000501 in printer.cfg${NC}"
    p ""
    p "  ${YELLOW}Notes:${NC}"
    p "    ${DIM}• Each patch is committed locally — git status stays clean${NC}"
    p "    ${DIM}• Backups in /usr/data/klipper/klippy/*.bak.before_e5m_ck${NC}"
    p "    ${DIM}• If a future 'git pull' touches the patched lines, conflict resolution may be needed${NC}"
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
    log_step "1" "Pre-checks"

    log_info "Checking Klipper directory..."
    if [ ! -d "$KLIPPER_DIR" ]; then
        die "Klipper not found at $KLIPPER_DIR"
    fi
    if [ ! -d "$KLIPPER_DIR/.git" ]; then
        die "$KLIPPER_DIR is not a git repository (was Klipper installed via install_klipper.sh?)"
    fi
    log_ok "Klipper found at $KLIPPER_DIR"

    log_info "Checking configfile.py..."
    if [ ! -f "$CONFIGFILE_PY" ]; then
        die "configfile.py not found at $CONFIGFILE_PY"
    fi
    log_ok "configfile.py present"

    log_info "Looking for python3..."
    PYTHON3=$(find_python) || die "No python3 found"
    log_ok "Using python3: $PYTHON3"

    log_info "Checking Klipper service script..."
    if [ ! -x "$KLIPPER_SERVICE" ]; then
        die "Klipper init script not found or not executable: $KLIPPER_SERVICE"
    fi
    log_ok "Klipper service script ready"
}


# ════════════════════════════════════════════════════════════
# STEP 2 — BACKUP
# ════════════════════════════════════════════════════════════
step_backup() {
    log_step "2" "Backup configfile.py before patching"

    if [ -f "$CONFIGFILE_BAK" ]; then
        log_action "Backup already exists (preserved): $CONFIGFILE_BAK"
    else
        cp "$CONFIGFILE_PY" "$CONFIGFILE_BAK"
        log_ok "Backup created: $CONFIGFILE_BAK"
    fi
}


# ════════════════════════════════════════════════════════════
# STEP 3 — APPLY PATCH (STEPPER_STEP_BOTH_EDGE)
# ════════════════════════════════════════════════════════════
step_apply_patch_ssbe() {
    log_step "3" "Apply patch: suppress STEPPER_STEP_BOTH_EDGE warning"

    log_info "Patching $CONFIGFILE_PY..."

    PATCH_RESULT=$("$PYTHON3" << PYTHON_EOF
import sys

path = "$CONFIGFILE_PY"
with open(path, "r") as f:
    content = f.read()

old = """    def deprecate_mcu_code(self, mcu, feature, msg=None):
        mcu_name = mcu.get_name()"""

new = """    def deprecate_mcu_code(self, mcu, feature, msg=None):
        # E5M-CK: suppress STEPPER_STEP_BOTH_EDGE warning for Creality MCUs
        # (firmware Jul 2023, compensated by step_pulse_duration in printer.cfg)
        if feature == 'STEPPER_STEP_BOTH_EDGE':
            return
        mcu_name = mcu.get_name()"""

if new in content:
    print("ALREADY_PATCHED")
elif old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("APPLIED")
else:
    print("PATTERN_NOT_FOUND")
    sys.exit(1)
PYTHON_EOF
)

    case "$PATCH_RESULT" in
        APPLIED)
            log_ok "Patch applied successfully"
            ;;
        ALREADY_PATCHED)
            log_ok "Patch already applied (no change made)"
            ;;
        PATTERN_NOT_FOUND)
            die "Original pattern not found in configfile.py — Klipper version may differ. Aborting."
            ;;
        *)
            die "Unexpected patcher output: $PATCH_RESULT"
            ;;
    esac

    log_info "Showing patched code..."
    sed -n '530,545p' "$CONFIGFILE_PY"
}


# ════════════════════════════════════════════════════════════
# STEP 4 — COMMIT LOCAL
# ════════════════════════════════════════════════════════════
step_commit() {
    log_step "4" "Commit patch locally (so git status stays clean)"

    cd "$KLIPPER_DIR"

    # Check whether the file is actually different from HEAD
    if git diff --quiet HEAD -- klippy/configfile.py; then
        log_action "configfile.py matches HEAD already — no commit needed"
    else
        log_info "Staging change..."
        git add klippy/configfile.py
        log_action "Staged: klippy/configfile.py"

        log_info "Committing..."
        git -c user.email="e5m-ck@local" -c user.name="E5M-CK" \
            commit -m "E5M-CK: suppress STEPPER_STEP_BOTH_EDGE warning (Creality MCU)

The Creality MCU firmware (July 2023) lacks the STEPPER_STEP_BOTH_EDGE
feature added to Klipper later. We compensate via step_pulse_duration
in printer.cfg (501 ns), so the warning is purely informational.

Until we reflash the MCUs with mainline Klipper firmware, suppress the
warning at its source. This patch is surgical: only the
STEPPER_STEP_BOTH_EDGE feature is filtered, all other deprecated_mcu_code
warnings remain visible." 2>&1 | grep -v "^$" | head -3

        log_ok "Commit created"
    fi

    log_info "Showing recent log..."
    git log --oneline -3 | while read line; do log_action "$line"; done

    log_info "Showing git status..."
    GIT_STATUS=$(git status --porcelain)
    if [ -z "$GIT_STATUS" ]; then
        log_ok "Working tree clean"
    else
        log_warn "Working tree has changes:"
        printf "%s\n" "$GIT_STATUS" | while read line; do log_action "$line"; done
    fi
}


# ════════════════════════════════════════════════════════════
# STEP 5 — RESTART KLIPPER
# ════════════════════════════════════════════════════════════
step_restart_klipper() {
    log_step "5" "Restart Klipper to apply patch"

    log_info "Restarting Klipper service..."
    "$KLIPPER_SERVICE" restart 2>&1 | while read line; do log_action "$line"; done || true

    log_info "Waiting for Klipper to be ready (up to 30s)..."
    READY=0
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        sleep 2
        STATE=$(wget --no-check-certificate -q -O - "$MOONRAKER_API/printer/info" 2>/dev/null | \
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
        log_warn "Klipper did not reach 'ready' state in 30s — check klippy.log"
    fi
}


# ════════════════════════════════════════════════════════════
# STEP 6 — VERIFY WARNING IS GONE
# ════════════════════════════════════════════════════════════
step_verify() {
    log_step "6" "Verify the warning is gone"

    log_info "Querying Klipper warnings..."
    WARNINGS_OUTPUT=$(wget --no-check-certificate -q -O - "$MOONRAKER_API/printer/info" 2>/dev/null)

    if [ -z "$WARNINGS_OUTPUT" ]; then
        log_warn "Cannot reach Moonraker to verify"
        return 0
    fi

    SSBE_COUNT=$(echo "$WARNINGS_OUTPUT" | grep -c "STEPPER_STEP_BOTH_EDGE" || true)
    if [ "$SSBE_COUNT" -eq 0 ]; then
        log_ok "STEPPER_STEP_BOTH_EDGE warning is GONE"
    else
        log_warn "STEPPER_STEP_BOTH_EDGE still mentioned $SSBE_COUNT time(s)"
        log_warn "Reload Fluidd in your browser to refresh the warnings panel"
    fi

    log_info "Showing all current Klipper warnings..."
    echo "$WARNINGS_OUTPUT" | "$PYTHON3" -c "
import json, sys
try:
    data = json.load(sys.stdin)
    warnings = data.get('result', {}).get('warnings', [])
    if not warnings:
        print('  (no warnings)')
    else:
        for w in warnings:
            msg = w.get('message', str(w))
            print('  - ' + msg[:200])
except Exception as e:
    print('  (could not parse warnings: ' + str(e) + ')')
"
}


# ════════════════════════════════════════════════════════════
# COMPLETION
# ════════════════════════════════════════════════════════════
show_completion() {
    p ""
    p "${BR_RED}  ╔══════════════════════════════════════════════════════════════════╗${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${BG_RED}${WHITE}${BOLD}  ✓  KLIPPER PATCHES APPLIED  ${NC}                             ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${BR_GREEN}✓${NC} ${WHITE}STEPPER_STEP_BOTH_EDGE warning suppressed${NC}                 ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Backup:${NC}    /usr/data/klipper/klippy/configfile.py.bak.*    ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${WHITE}Commit:${NC}    in /usr/data/klipper local git history          ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}    ${YELLOW}NEXT:${NC}                                                          ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}      ${DIM}- Reload Fluidd in your browser to refresh warnings panel${NC}    ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}      ${DIM}- The 2 remaining warnings (HOST/MCU dirty) are by-design${NC}    ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}      ${DIM}  see MEMO_klipper_dirty_FR.md for full explanation${NC}          ${BR_RED}║${NC}"
    p "${BR_RED}  ║${NC}                                                                  ${BR_RED}║${NC}"
    p "${BR_RED}  ╚══════════════════════════════════════════════════════════════════╝${NC}"
    p ""
    p "  ${DIM}To revert the patch:${NC}"
    p "    ${DIM}cp /usr/data/klipper/klippy/configfile.py.bak.before_e5m_ck \\${NC}"
    p "    ${DIM}   /usr/data/klipper/klippy/configfile.py${NC}"
    p "    ${DIM}cd /usr/data/klipper && git reset --hard HEAD~1${NC}"
    p "    ${DIM}/etc/init.d/S55klipper_service restart${NC}"
    p ""
}


# ════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════
main() {
    show_banner
    show_disclaimer

    if ! confirm "Apply Klipper local patches?"; then
        log_warn "Cancelled by user"
        exit 0
    fi

    step_precheck
    step_backup
    step_apply_patch_ssbe
    step_commit
    step_restart_klipper
    step_verify
    show_completion
}

main "$@"
