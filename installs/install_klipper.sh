#!/bin/sh
# install_klipper.sh — install upstream Klipper (klippy host process only).
#
# Runs ON THE PRINTER (busybox sh, with Entware /opt on PATH).
# Idempotent: re-running upgrades to the pinned tag, recreates venv if dirty.
#
# What it does:
#   1. Backs up stock klippy artifacts to /usr/data/backup/klipper-stock/:
#       - /etc/init.d/S55klipper_service        -> S55klipper_service.orig
#       - /usr/data/printer_data/config/*.cfg   -> config.stock.tar.gz
#   2. Clones upstream Klipper at the pinned tag to /usr/data/e5m-ck/klipper.
#   3. Creates Python venv at /usr/data/venvs/klippy and installs deps.
#   4. Verifies klippy can import (`python -c 'import klippy.klippy'` won't
#      work since klippy isn't a package — instead we check the venv has
#      the right requirements by `pip list`).
#   5. Does NOT touch /etc/init.d/S55klipper_service or printer.cfg —
#      that's done by scripts/sync.sh from the host, after this script
#      successfully prepares the venv.
#
# Out of scope (handled later):
#   - MCU firmware compile / flash (kept stock through Phase 3-9)
#   - ADXL Creality patch (Phase 10)
#   - klipper/config/ deployment (done by sync.sh)
#
# Usage (over SSH from local):
#   cat installs/install_klipper.sh | ssh root@printer 'sh -s'
#   cat installs/install_klipper.sh | ssh root@printer 'sh -s -- --tag=v0.13.0'

set -eu

# -- Pinned Klipper version (default; --tag overrides) -------------------
KLIPPER_REPO="https://github.com/Klipper3d/klipper.git"
KLIPPER_TAG="v0.13.0"

KLIPPER_DIR="/usr/data/e5m-ck/klipper"
VENV_DIR="/usr/data/venvs/klippy"
BACKUP_DIR="/usr/data/backup/klipper-stock"

ts()   { date +'%H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(ts)" "$*" >&2; }
err()  { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; }
die()  { err "$*"; exit 1; }

# -- Args -----------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        --tag=*) KLIPPER_TAG="${arg#--tag=}" ;;
        -h|--help)
            sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "Unknown argument: $arg" ;;
    esac
done

# -- Preflight ------------------------------------------------------------
info "=== Preflight ==="
[ -x /opt/bin/opkg ]    || die "Entware not installed. Run install_entware.sh first."
[ -x /opt/bin/python3 ] || die "Entware python3 not installed."
[ -x /opt/bin/git ]     || die "Entware git not installed."
export PATH=/opt/bin:/opt/sbin:$PATH
info "Klipper tag : $KLIPPER_TAG"
info "Install dir : $KLIPPER_DIR"
info "Venv dir    : $VENV_DIR"
info "Backup dir  : $BACKUP_DIR"

# -- 1. Backup stock klippy artifacts ------------------------------------
info ""
info "=== Backup stock artifacts ==="
mkdir -p "$BACKUP_DIR"

if [ ! -f "$BACKUP_DIR/S55klipper_service.orig" ] && [ -f /etc/init.d/S55klipper_service ]; then
    cp /etc/init.d/S55klipper_service "$BACKUP_DIR/S55klipper_service.orig"
    info "Backed up S55klipper_service.orig"
else
    info "S55klipper_service.orig already backed up (or stock not present)."
fi

if [ ! -f "$BACKUP_DIR/config.stock.tar.gz" ]; then
    tar c -C /usr/data/printer_data/config . 2>/dev/null | gzip -1 > "$BACKUP_DIR/config.stock.tar.gz"
    info "Backed up stock config -> config.stock.tar.gz ($(wc -c < "$BACKUP_DIR/config.stock.tar.gz") bytes)"
else
    info "config.stock.tar.gz already exists — not overwriting."
fi

# -- 2. Clone / update Klipper -------------------------------------------
info ""
info "=== Klipper source ==="
mkdir -p "$(dirname "$KLIPPER_DIR")"

if [ -d "$KLIPPER_DIR/.git" ]; then
    info "Existing clone at $KLIPPER_DIR — fetching and checking out $KLIPPER_TAG."
    cd "$KLIPPER_DIR"
    /opt/bin/git fetch --tags origin
    /opt/bin/git -c advice.detachedHead=false checkout "$KLIPPER_TAG"
else
    info "Cloning $KLIPPER_REPO at $KLIPPER_TAG..."
    /opt/bin/git clone --depth 1 --branch "$KLIPPER_TAG" "$KLIPPER_REPO" "$KLIPPER_DIR" \
        || die "git clone failed."
fi

KLIPPER_SHA=$(cd "$KLIPPER_DIR" && /opt/bin/git rev-parse HEAD)
KLIPPER_DESC=$(cd "$KLIPPER_DIR" && /opt/bin/git describe --tags --always)
info "Checked out: $KLIPPER_DESC ($KLIPPER_SHA)"

# -- 3. Python venv ------------------------------------------------------
info ""
info "=== Python venv ==="
if [ ! -x "$VENV_DIR/bin/python3" ]; then
    info "Creating venv at $VENV_DIR ..."
    mkdir -p "$(dirname "$VENV_DIR")"
    /opt/bin/python3 -m venv "$VENV_DIR" || die "venv creation failed."
else
    info "Venv already exists — reusing."
fi

REQ_FILE="$KLIPPER_DIR/scripts/klippy-requirements.txt"
[ -f "$REQ_FILE" ] || die "klippy-requirements.txt not found at $REQ_FILE (wrong tag?)."

info "Installing klippy-requirements.txt ..."
"$VENV_DIR/bin/pip" install --upgrade pip >/dev/null
"$VENV_DIR/bin/pip" install -r "$REQ_FILE" || die "pip install failed."

# -- 4. c_helper.so (pre-built binary) -----------------------------------
# Klipper's `klippy/chelper/c_helper.so` is normally compiled on first run
# by gcc. We don't ship gcc on the printer (saves ~100MB on the small
# overlay partition). Instead, we pre-place a known-good binary that was
# built for the Ingenic X2000 (MIPS32r2 little-endian, soft-float).
#
# Source: derived from the v1 E5M-CK install (proven to work on this SoC).
# The binary is downloaded from the v2 repo via the host install path:
# we expect the caller to have pushed it to /tmp/c_helper.so first via:
#
#     scp klipper/binaries/mipsel-3.4/c_helper.so root@printer:/tmp/
#
# Then klippy/chelper/__init__.py finds c_helper.so and doesn't try to
# recompile (we touch -d its mtime to be newer than the source files).
info ""
info "=== c_helper.so ==="
CHELPER_DIR="$KLIPPER_DIR/klippy/chelper"
CHELPER_DEST="$CHELPER_DIR/c_helper.so"
CHELPER_SRC="/tmp/c_helper.so"

if [ -f "$CHELPER_SRC" ]; then
    cp "$CHELPER_SRC" "$CHELPER_DEST"
    # Touch newer than every .c source so klippy doesn't try to recompile.
    # Use a far-future date relative to the source files (now is plenty).
    find "$CHELPER_DIR" -name '*.c' -o -name '*.h' | xargs -I {} touch -t 202001010000.00 {}
    touch "$CHELPER_DEST"
    chmod 0755 "$CHELPER_DEST"
    info "Placed c_helper.so at $CHELPER_DEST"
    file "$CHELPER_DEST" 2>/dev/null || true
else
    warn "/tmp/c_helper.so not found — klippy will try to compile c_helper on first run."
    warn "If gcc is absent, klippy will fail. To recover:"
    warn "  scp klipper/binaries/mipsel-3.4/c_helper.so root@printer:/tmp/"
    warn "  ssh root@printer 'sh /usr/data/e5m-ck/install_klipper.sh'"
fi

# -- 5. Verify ------------------------------------------------------------
info ""
info "=== Verify ==="
"$VENV_DIR/bin/python3" --version
"$VENV_DIR/bin/python3" -c 'import cffi, greenlet, jinja2; print("python deps OK")'

# Check that klippy.py is present and chelper loads (this is the real test).
KLIPPY_ENTRY="$KLIPPER_DIR/klippy/klippy.py"
[ -f "$KLIPPY_ENTRY" ] || die "klippy.py not found at $KLIPPY_ENTRY"

"$VENV_DIR/bin/python3" -c "
import sys, os
sys.path.insert(0, '$KLIPPER_DIR/klippy')
os.chdir('$KLIPPER_DIR/klippy')
try:
    import chelper
    ffi_main, ffi_lib = chelper.get_ffi()
    print('chelper loaded OK; lib =', ffi_lib)
except Exception as e:
    print('CHELPER LOAD FAILED:', type(e).__name__, str(e))
    sys.exit(1)
"

info ""
info "Klipper $KLIPPER_DESC ready at $KLIPPER_DIR."
info "Venv ready at $VENV_DIR."
info ""
info "NOTE: This script did NOT install S55klipper_service or printer.cfg."
info "Next step (from local host): bash scripts/sync.sh --apply"
