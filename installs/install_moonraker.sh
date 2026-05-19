#!/bin/sh
# install_moonraker.sh — install Moonraker (host process for Klipper).
#
# Runs ON THE PRINTER (busybox sh).
# Idempotent: re-running checks out the pinned tag, recreates venv from
# the bundled tarball if missing.
#
# Strategy:
#   - Moonraker source -> /usr/data/e5m-ck/moonraker (git clone, pinned tag)
#   - Python venv      -> /usr/data/venvs/moonraker  (extracted from
#                         /tmp/moonraker-env.tar.gz that the local script
#                         scp'd over)
#
# Why a pre-built venv tarball? Moonraker has several C-extension deps
# (pillow, streaming-form-data, dbus-fast, libnacl) that need gcc to build
# from source. We don't ship gcc on the printer. The shipped tarball is
# a lean, pure-Python install (no pillow, no streaming-form-data) which
# is enough for the core feature set: API, websocket, file management,
# database, history, jobs. Trade-offs:
#   - No thumbnail generation (pillow missing) -> Fluidd shows blank icons
#   - File uploads use the slower fallback path (no streaming-form-data)
#   - No D-Bus features (not used on this SoC anyway)
#
# Usage (after `scp -O moonraker-env.tar.gz /tmp/`):
#   cat installs/install_moonraker.sh | ssh root@printer 'sh -s'
#   cat installs/install_moonraker.sh | ssh root@printer 'sh -s -- --tag=v0.10.0'

set -eu

MOONRAKER_REPO="https://github.com/Arksine/moonraker.git"
MOONRAKER_TAG="v0.10.0"

MOONRAKER_DIR="/usr/data/e5m-ck/moonraker"
VENV_DIR="/usr/data/venvs/moonraker"
VENV_TAR_SRC="/tmp/moonraker-env.tar.gz"
BACKUP_DIR="/usr/data/backup/moonraker-stock"

ts()   { date +'%H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(ts)" "$*" >&2; }
err()  { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; }
die()  { err "$*"; exit 1; }

for arg in "$@"; do
    case "$arg" in
        --tag=*) MOONRAKER_TAG="${arg#--tag=}" ;;
        -h|--help)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "Unknown argument: $arg" ;;
    esac
done

# -- Preflight ------------------------------------------------------------
info "=== Preflight ==="
[ -x /opt/bin/git ] || die "Entware git not installed. Run install_entware.sh first."
export PATH=/opt/bin:/opt/sbin:$PATH
info "Moonraker tag : $MOONRAKER_TAG"
info "Install dir   : $MOONRAKER_DIR"
info "Venv dir      : $VENV_DIR"

# -- 1. Backup (Moonraker is fresh — nothing stock to back up) ------------
info ""
info "=== Backup ==="
mkdir -p "$BACKUP_DIR"
info "Moonraker is not part of stock Creality firmware — no backup needed."

# -- 2. Extract venv from tarball ----------------------------------------
info ""
info "=== Venv ==="
if [ -x "$VENV_DIR/bin/python3" ]; then
    info "Venv already present — reusing."
else
    [ -f "$VENV_TAR_SRC" ] || die "$VENV_TAR_SRC missing. From local: scp -O moonraker/binaries/mipsel-3.4/moonraker-env.tar.gz root@printer:/tmp/"
    mkdir -p "$(dirname "$VENV_DIR")"
    info "Extracting $VENV_TAR_SRC to /usr/data/venvs/ ..."
    cd /usr/data/venvs
    tar xzf "$VENV_TAR_SRC"
    [ -d "/usr/data/venvs/moonraker-env" ] || die "Tarball did not produce moonraker-env/ directory."
    mv /usr/data/venvs/moonraker-env "$VENV_DIR"
    info "Extracted to $VENV_DIR ($(du -sh "$VENV_DIR" | awk '{print $1}'))"
fi

# Python in the bundled venv has an absolute shebang that points to the
# original build location. Fix it to point at this venv.
PY_SHEBANG="$VENV_DIR/bin/python3"
if [ -L "$PY_SHEBANG" ]; then
    info "python3 in venv is a symlink — checking target."
    TARGET=$(readlink "$PY_SHEBANG")
    info "  -> $TARGET"
    if [ ! -x "$TARGET" ]; then
        info "Target invalid; relinking to /usr/share/klippy-env/bin/python3"
        rm "$PY_SHEBANG"
        ln -s /usr/share/klippy-env/bin/python3 "$PY_SHEBANG"
    fi
fi

# Sanity-check we can run python from the venv (sets sys.path correctly).
"$PY_SHEBANG" -c 'import sys; print("python OK:", sys.version.split()[0]); print("prefix:", sys.prefix)' \
    || die "Venv python3 doesn't run."

# -- 3. Clone / update Moonraker source ----------------------------------
info ""
info "=== Moonraker source ==="
mkdir -p "$(dirname "$MOONRAKER_DIR")"
if [ -d "$MOONRAKER_DIR/.git" ]; then
    info "Existing clone — fetching and checking out $MOONRAKER_TAG."
    cd "$MOONRAKER_DIR"
    /opt/bin/git fetch --tags origin
    /opt/bin/git -c advice.detachedHead=false checkout "$MOONRAKER_TAG"
else
    info "Cloning $MOONRAKER_REPO at $MOONRAKER_TAG..."
    /opt/bin/git clone --depth 1 --branch "$MOONRAKER_TAG" "$MOONRAKER_REPO" "$MOONRAKER_DIR" \
        || die "git clone failed."
fi
MR_DESC=$(cd "$MOONRAKER_DIR" && /opt/bin/git describe --tags --always)
MR_SHA=$(cd "$MOONRAKER_DIR" && /opt/bin/git rev-parse HEAD)
info "Checked out: $MR_DESC ($MR_SHA)"

# -- 4. Verify Moonraker can import --------------------------------------
info ""
info "=== Verify ==="
"$PY_SHEBANG" -c "
import sys
sys.path.insert(0, '$MOONRAKER_DIR')
try:
    import moonraker.server as s
    print('Moonraker imports OK')
except Exception as e:
    print('IMPORT FAILED:', type(e).__name__, str(e)[:200])
    sys.exit(1)
" || die "Moonraker fails to import — check missing deps in $VENV_DIR/lib/python3.8/site-packages/"

info ""
info "Moonraker $MR_DESC ready at $MOONRAKER_DIR."
info "Venv at $VENV_DIR."
info ""
info "Next: from local, push moonraker.conf + S56 init script via sync.sh."
