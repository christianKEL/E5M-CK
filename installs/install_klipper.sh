#!/bin/sh
# install_klipper.sh — install upstream Klipper (host-only, reuses stock venv).
#
# Runs ON THE PRINTER (busybox sh).
# Idempotent: re-running upgrades to the pinned tag.
#
# Strategy (inherited from v1, validated on this SoC):
#   We REUSE Creality's stock Python venv at /usr/share/klippy-env instead
#   of creating a new one. Why:
#     - The stock venv ships pre-built greenlet + cffi for Python 3.8 on
#       MIPS32r2. These C extensions need gcc to build, and we don't ship
#       gcc on the printer (~100 MB on the tiny overlay partition).
#     - Entware ships python3 3.13 but its C extensions don't load against
#       the stock venv, and the Entware build lacks the `venv` stdlib.
#     - The stock venv is on /usr/share (squashfs); writes are transparently
#       overlaid on /overlay/upper, so pip install for any missing pure-Python
#       dep just works.
#
# What we DO install:
#   - Klipper source at the pinned tag -> /usr/data/e5m-ck/klipper
#   - Pre-built c_helper.so (from klipper/binaries/mipsel-3.4/) -> klippy/chelper/
#   - python-can (pure-Python; only needed if any [mcu] uses canbus_uuid)
#
# What we DON'T touch:
#   - /etc/init.d/S55klipper_service (handled by scripts/sync.sh on the host)
#   - /usr/data/printer_data/config/printer.cfg (handled by sync.sh)
#
# Usage (over SSH from local, after `scp -O c_helper.so /tmp/`):
#   cat installs/install_klipper.sh | ssh root@printer 'sh -s'
#   cat installs/install_klipper.sh | ssh root@printer 'sh -s -- --tag=v0.13.0'

set -eu

KLIPPER_REPO="https://github.com/Klipper3d/klipper.git"
KLIPPER_TAG="v0.13.0"

KLIPPER_DIR="/usr/data/e5m-ck/klipper"
STOCK_VENV="/usr/share/klippy-env"
STOCK_PYTHON="$STOCK_VENV/bin/python3"
STOCK_PIP="$STOCK_VENV/bin/pip"
BACKUP_DIR="/usr/data/backup/klipper-stock"

ts()   { date +'%H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(ts)" "$*" >&2; }
err()  { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; }
die()  { err "$*"; exit 1; }

for arg in "$@"; do
    case "$arg" in
        --tag=*) KLIPPER_TAG="${arg#--tag=}" ;;
        -h|--help)
            sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "Unknown argument: $arg" ;;
    esac
done

# -- Preflight ------------------------------------------------------------
info "=== Preflight ==="
[ -x /opt/bin/git ]      || die "Entware git not installed. Run install_entware.sh first."
[ -x "$STOCK_PYTHON" ]   || die "Stock Creality venv missing at $STOCK_VENV"
export PATH=/opt/bin:/opt/sbin:$PATH

info "Klipper tag : $KLIPPER_TAG"
info "Install dir : $KLIPPER_DIR"
info "Python      : $STOCK_PYTHON ($("$STOCK_PYTHON" --version 2>&1))"
info "Backup dir  : $BACKUP_DIR"

# -- 1. Backup stock klippy artifacts ------------------------------------
info ""
info "=== Backup stock artifacts ==="
mkdir -p "$BACKUP_DIR"

if [ ! -f "$BACKUP_DIR/S55klipper_service.orig" ] && [ -f /etc/init.d/S55klipper_service ]; then
    cp /etc/init.d/S55klipper_service "$BACKUP_DIR/S55klipper_service.orig"
    info "Backed up S55klipper_service.orig"
else
    info "S55klipper_service.orig already backed up."
fi

if [ ! -f "$BACKUP_DIR/config.stock.tar.gz" ]; then
    tar c -C /usr/data/printer_data/config . 2>/dev/null | gzip -1 > "$BACKUP_DIR/config.stock.tar.gz"
    info "Backed up stock printer_data/config/ -> config.stock.tar.gz ($(wc -c < "$BACKUP_DIR/config.stock.tar.gz") bytes)"
else
    info "config.stock.tar.gz already exists — not overwriting."
fi

# -- 2. Verify Python dependencies ---------------------------------------
info ""
info "=== Python dependencies ==="
"$STOCK_PYTHON" -c "
import sys
required = ['cffi', 'greenlet', 'jinja2', 'markupsafe', 'serial']
missing = []
for mod in required:
    try:
        __import__(mod)
    except ImportError:
        missing.append(mod)
if missing:
    print('Missing:', missing); sys.exit(1)
print('All core deps present.')
" || die "Stock venv missing required Python modules."

# python-can is only needed for CAN-bus MCUs; ours are all serial. Try to
# install it pure-Python style, ignore failure (Klipper imports it lazily).
if ! "$STOCK_PYTHON" -c 'import can' 2>/dev/null; then
    info "Installing python-can (used only by [mcu] canbus_uuid configs)..."
    "$STOCK_PIP" install --quiet --no-deps python-can 2>/dev/null \
        && info "python-can installed." \
        || warn "python-can install failed — OK as long as no [mcu] uses canbus_uuid."
fi

# -- 3. Clone / update Klipper -------------------------------------------
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

# -- 4. Place pre-built c_helper.so --------------------------------------
info ""
info "=== c_helper.so ==="
CHELPER_DIR="$KLIPPER_DIR/klippy/chelper"
CHELPER_DEST="$CHELPER_DIR/c_helper.so"
CHELPER_SRC="/tmp/c_helper.so"

[ -f "$CHELPER_SRC" ] || die "/tmp/c_helper.so missing. From local: scp -O klipper/binaries/mipsel-3.4/c_helper.so root@printer:/tmp/"
cp "$CHELPER_SRC" "$CHELPER_DEST"
# Touch .c/.h sources to a far-past date so klippy's freshness check
# considers the .so newer and skips its (gcc-requiring) rebuild attempt.
find "$CHELPER_DIR" \( -name '*.c' -o -name '*.h' \) -exec touch -t 202001010000.00 {} \;
touch "$CHELPER_DEST"
chmod 0755 "$CHELPER_DEST"
info "Placed c_helper.so at $CHELPER_DEST ($(wc -c < "$CHELPER_DEST") bytes)"

# -- 5. Verify chelper loads ---------------------------------------------
info ""
info "=== Verify chelper ==="
cd "$KLIPPER_DIR/klippy"
"$STOCK_PYTHON" -c "
import sys, os
sys.path.insert(0, '$KLIPPER_DIR/klippy')
try:
    import chelper
    ffi_main, ffi_lib = chelper.get_ffi()
    print('chelper loaded OK')
    print('  ffi_lib =', repr(ffi_lib)[:80])
except Exception as e:
    print('CHELPER LOAD FAILED:', type(e).__name__, str(e))
    sys.exit(1)
" || die "chelper failed to load — c_helper.so ABI mismatch with klippy v$KLIPPER_TAG."

info ""
info "Klipper $KLIPPER_DESC ready at $KLIPPER_DIR."
info "Using stock venv: $STOCK_PYTHON"
info ""
info "Next step (from local host): bash scripts/sync.sh --apply"
info "  (deploys klipper/config/ + system/etc/init.d/S55klipper_service)"
