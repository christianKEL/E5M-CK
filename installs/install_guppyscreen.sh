#!/bin/sh
# install_guppyscreen.sh — install GuppyScreen (touch UI for Klipper).
#
# Runs ON THE PRINTER (busybox sh, Entware /opt on PATH).
# Idempotent: re-running re-downloads if version mismatches.
#
# Source:  https://github.com/ballaswag/guppyscreen
# Pinned:  v0.0.26-beta (latest stable, April 2024)
# Variant: smallscreen — for screens ≤ 800px wide. Our Ender 5 Max
#          has a 480x272 panel.
#
# What it deploys:
#   - /usr/data/guppyscreen/         Guppy binary + assets + k1_mods/
#   - /etc/init.d/S50dropbear        (REPLACED with Guppy's version
#                                    that starts SSH BEFORE display,
#                                    critical for recovery if Guppy
#                                    hangs the framebuffer)
#   - /etc/init.d/S99guppyscreen     (from tarball's k1_mods/)
#
# What it MOVES out of /etc/init.d (backup to /usr/data/backup/):
#   - S12boot_display    — Creality boot splash (prevents flicker)
#
# What it does NOT touch:
#   - Creality services and S99start_app — handled by installs/creality_kill.sh.
#     Run that BEFORE this installer (or any time after deploying mainline
#     Klipper/Moonraker/Fluidd) so the display-server and friends are gone
#     and the framebuffer is free for GuppyScreen.
#   - Network daemons (wpa_supplicant, ifplugd, dropbear, mdns) — kept.
#
# Inherited approach from v1's installs/install_guppyscreen.sh (proven
# on the Ingenic X2000 / Nebula Pad), refactored: Creality shutdown
# extracted to creality_kill.sh in May 2026.
#
# Usage (after `scp -O` of guppyconfig.json if you have a customized one):
#   cat installs/install_guppyscreen.sh | ssh root@printer 'sh -s'
#   cat installs/install_guppyscreen.sh | ssh root@printer 'sh -s -- --tag=v0.0.26-beta'

set -eu

GUPPY_REPO="ballaswag/guppyscreen"
GUPPY_TAG="0.0.26-beta"
GUPPY_ASSET="guppyscreen-smallscreen.tar.gz"

GUPPY_DIR="/usr/data/guppyscreen"
BACKUP_DIR="/usr/data/backup/guppyscreen-stock"
TMP_TARBALL="/tmp/guppyscreen.tar.gz"
VERSION_STAMP="$GUPPY_DIR/.e5m-ck-version"

ts()   { date +'%H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(ts)" "$*" >&2; }
err()  { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; }
die()  { err "$*"; exit 1; }

for arg in "$@"; do
    case "$arg" in
        --tag=*)   GUPPY_TAG="${arg#--tag=}" ;;
        --asset=*) GUPPY_ASSET="${arg#--asset=}" ;;
        -h|--help)
            sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "Unknown argument: $arg" ;;
    esac
done

URL="https://github.com/${GUPPY_REPO}/releases/download/${GUPPY_TAG}/${GUPPY_ASSET}"

# -- Preflight ------------------------------------------------------------
info "=== Preflight ==="
[ -x /opt/bin/curl ] || die "Entware curl missing. Run install_entware.sh first."
export PATH=/opt/bin:/opt/sbin:$PATH

info "Tag       : $GUPPY_TAG"
info "Asset     : $GUPPY_ASSET"
info "Install to: $GUPPY_DIR"
info "Backup to : $BACKUP_DIR"

# -- Idempotency check ----------------------------------------------------
if [ -d "$GUPPY_DIR" ] && [ -f "$VERSION_STAMP" ]; then
    INSTALLED=$(cat "$VERSION_STAMP" 2>/dev/null || echo "?")
    if [ "$INSTALLED" = "$GUPPY_TAG" ]; then
        info "GuppyScreen $GUPPY_TAG already installed. Pass a different --tag to upgrade."
        info "(Init scripts and Creality cleanup are still re-run below for idempotency.)"
    else
        info "Installed version: $INSTALLED → replacing with $GUPPY_TAG."
        info "Stopping running GuppyScreen if any..."
        [ -x /etc/init.d/S99guppyscreen ] && /etc/init.d/S99guppyscreen stop 2>/dev/null || true
        kill -9 $(pidof guppyscreen 2>/dev/null) 2>/dev/null || true
        sleep 1
        rm -rf "$GUPPY_DIR"
    fi
fi

# -- 1. Download + extract -----------------------------------------------
if [ ! -f "$VERSION_STAMP" ]; then
    info ""
    info "=== Download ==="
    rm -f "$TMP_TARBALL"
    /opt/bin/curl -fL --silent --show-error -o "$TMP_TARBALL" "$URL" \
        || die "Download failed: $URL"
    SIZE=$(wc -c < "$TMP_TARBALL")
    info "Downloaded: $TMP_TARBALL ($SIZE bytes)"
    [ "$SIZE" -gt 200000 ] || die "Download too small ($SIZE bytes). Wrong URL?"

    info "=== Extract ==="
    rm -rf "$GUPPY_DIR"
    # Extract to a staging dir first so we control the final layout
    # regardless of whether the tarball nests under guppyscreen/ or not.
    STAGE_DIR="/tmp/guppyscreen-stage.$$"
    rm -rf "$STAGE_DIR"
    mkdir -p "$STAGE_DIR"
    cd "$STAGE_DIR"
    tar xzf "$TMP_TARBALL"
    rm -f "$TMP_TARBALL"

    # The k1_mods/S99guppyscreen init script (shipped IN the tarball)
    # expects FLAT layout:
    #     $GUPPY_DIR/guppyscreen           -> binary
    #     $GUPPY_DIR/k1_mods/
    #     $GUPPY_DIR/themes/
    # The 0.0.26-beta smallscreen tarball extracts NESTED:
    #     guppyscreen/guppyscreen          -> binary
    #     guppyscreen/k1_mods/
    # Flatten by promoting the inner guppyscreen/ dir to $GUPPY_DIR.
    if [ -d "$STAGE_DIR/guppyscreen" ] && [ -x "$STAGE_DIR/guppyscreen/guppyscreen" ]; then
        info "Tarball is nested — flattening to expected flat layout."
        mv "$STAGE_DIR/guppyscreen" "$GUPPY_DIR"
    else
        info "Tarball is already flat."
        mv "$STAGE_DIR" "$GUPPY_DIR"
    fi
    rm -rf "$STAGE_DIR"

    [ -x "$GUPPY_DIR/guppyscreen" ] || die "guppyscreen binary missing at $GUPPY_DIR/guppyscreen (layout error)."
    [ -d "$GUPPY_DIR/k1_mods" ]      || die "k1_mods/ directory missing — tarball layout changed?"
    echo "$GUPPY_TAG" > "$VERSION_STAMP"
    info "Installed at $GUPPY_DIR ($(du -sh "$GUPPY_DIR" | awk '{print $1}'))"
fi

# -- 2. Backup stock display init scripts (once) -------------------------
info ""
info "=== Backup stock display init scripts ==="
mkdir -p "$BACKUP_DIR"
for f in S12boot_display S99start_app; do
    src="/etc/init.d/$f"
    dst="$BACKUP_DIR/$f.orig"
    if [ ! -f "$dst" ] && [ -f "$src" ]; then
        cp "$src" "$dst"
        info "  Backed up $src → $dst"
    fi
done

# -- 3. Disable boot splash (move S12boot_display out) -------------------
if [ -f /etc/init.d/S12boot_display ]; then
    mv /etc/init.d/S12boot_display "$BACKUP_DIR/S12boot_display.disabled"
    info "Disabled boot splash (S12boot_display moved out of init.d)"
fi

# -- 4. Install GuppyScreen's init scripts -------------------------------
info ""
info "=== Install init scripts ==="
[ -f "$GUPPY_DIR/k1_mods/S99guppyscreen" ] || die "k1_mods/S99guppyscreen not in tarball."
[ -f "$GUPPY_DIR/k1_mods/S50dropbear" ]    || die "k1_mods/S50dropbear not in tarball."

# Critical: S50dropbear modified so SSH starts BEFORE the display takes
# over the framebuffer. Without this, if GuppyScreen hangs or the touch
# layer crashes, you have no way to recover except a factory reset.
cp "$GUPPY_DIR/k1_mods/S50dropbear" /etc/init.d/S50dropbear
chmod +x /etc/init.d/S50dropbear
info "Installed S50dropbear (Guppy variant — SSH starts early)"

cp "$GUPPY_DIR/k1_mods/S99guppyscreen" /etc/init.d/S99guppyscreen
chmod +x /etc/init.d/S99guppyscreen
info "Installed S99guppyscreen"

# The shipped S99guppyscreen has a bug in its `[ ! -f $LIBEINFO ]` check:
# it tests the SOURCE file rather than the symlink target, so the
# /lib/lib{einfo,rc}.so.1 symlinks supervise-daemon needs are never
# created. Create them ourselves (idempotent).
for lib in librc.so.1 libeinfo.so.1; do
    src="$GUPPY_DIR/k1_mods/respawn/$lib"
    dst="/lib/$lib"
    if [ -f "$src" ] && [ ! -e "$dst" ]; then
        ln -sf "$src" "$dst"
        info "Linked $dst → $src"
    fi
done

# -- 5. Check that Creality display is gone ------------------------------
# Killing display-server, master-server, etc. is now centralized in
# installs/creality_kill.sh. Refuse to proceed if the framebuffer is
# still owned by display-server — GuppyScreen would either fail to
# initialize the framebuffer or flicker against the Creality splash.
info ""
info "=== Check Creality display is stopped ==="
if pidof display-server >/dev/null 2>&1; then
    err "/usr/bin/display-server is still running (PIDs: $(pidof display-server))."
    err "Run installs/creality_kill.sh --permanent first, then re-run this installer."
    exit 1
fi
info "OK — display-server is not running."

# -- 6. Verify (don't start Guppy yet — config not pushed by sync.sh) ----
info ""
info "=== Verify ==="
"$GUPPY_DIR/guppyscreen" --version 2>&1 | head -3 || \
    info "  (binary present but --version not supported — harmless)"
file "$GUPPY_DIR/guppyscreen" 2>/dev/null || true

info ""
info "GuppyScreen $GUPPY_TAG ready at $GUPPY_DIR."
info ""
info "Next steps (from local host):"
info "  # 1. Confirm Creality services are dead (and won't respawn at boot):"
info "  cat installs/creality_kill.sh | ssh root@printer 'sh -s -- --list'"
info "  # 2. Push the GuppyScreen config:"
info "  bash scripts/sync.sh --apply"
info "  # 3. Start GuppyScreen:"
info "  ssh root@printer '/etc/init.d/S99guppyscreen start'"
