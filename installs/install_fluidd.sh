#!/bin/sh
# install_fluidd.sh — download and extract Fluidd web UI.
#
# Runs ON THE PRINTER (busybox sh + Entware curl).
# Idempotent: re-running re-downloads the pinned version if the staged
# directory is missing or version mismatches.
#
# Fluidd is a static SPA (HTML/JS/CSS) — no runtime, just a folder served
# by nginx. We pin a release tag and fetch its `fluidd.zip` artifact from
# GitHub releases.
#
# Usage:
#   cat installs/install_fluidd.sh | ssh root@printer 'sh -s'
#   cat installs/install_fluidd.sh | ssh root@printer 'sh -s -- --tag=v1.37.0'

set -eu

FLUIDD_REPO="fluidd-core/fluidd"
FLUIDD_TAG="v1.37.0"

FLUIDD_DIR="/usr/data/e5m-ck/fluidd"
TMP_ZIP="/tmp/fluidd.zip"
VERSION_STAMP="$FLUIDD_DIR/.e5m-ck-version"

ts()   { date +'%H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(ts)" "$*" >&2; }
err()  { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; }
die()  { err "$*"; exit 1; }

for arg in "$@"; do
    case "$arg" in
        --tag=*) FLUIDD_TAG="${arg#--tag=}" ;;
        -h|--help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "Unknown argument: $arg" ;;
    esac
done

URL="https://github.com/${FLUIDD_REPO}/releases/download/${FLUIDD_TAG}/fluidd.zip"

# -- Preflight ------------------------------------------------------------
info "=== Preflight ==="
[ -x /opt/bin/curl ] || die "Entware curl missing. Run install_entware.sh first."
export PATH=/opt/bin:/opt/sbin:$PATH

info "Tag       : $FLUIDD_TAG"
info "Install to: $FLUIDD_DIR"
info "Fetching  : $URL"

# -- Idempotency check ----------------------------------------------------
if [ -d "$FLUIDD_DIR" ] && [ -f "$VERSION_STAMP" ]; then
    INSTALLED=$(cat "$VERSION_STAMP" 2>/dev/null)
    if [ "$INSTALLED" = "$FLUIDD_TAG" ]; then
        info "Fluidd $FLUIDD_TAG already installed. Pass a different --tag to upgrade."
        exit 0
    else
        info "Installed version: $INSTALLED. Replacing with $FLUIDD_TAG."
    fi
fi

# -- Download -------------------------------------------------------------
info ""
info "=== Download ==="
rm -f "$TMP_ZIP"
/opt/bin/curl -fL --silent --show-error --output "$TMP_ZIP" "$URL" \
    || die "Download failed: $URL"
SIZE=$(wc -c < "$TMP_ZIP")
info "Downloaded: $TMP_ZIP ($SIZE bytes)"
[ "$SIZE" -gt 100000 ] || die "Download too small ($SIZE bytes). Wrong URL?"

# -- Extract --------------------------------------------------------------
info ""
info "=== Extract ==="
# Wipe staging dir if upgrading.
rm -rf "$FLUIDD_DIR"
mkdir -p "$FLUIDD_DIR"

# busybox unzip is usually available; check.
if ! command -v unzip >/dev/null 2>&1; then
    die "unzip command missing. opkg install unzip ?"
fi
unzip -q "$TMP_ZIP" -d "$FLUIDD_DIR" || die "unzip failed."
rm -f "$TMP_ZIP"

# Stamp version for idempotency checks.
echo "$FLUIDD_TAG" > "$VERSION_STAMP"

[ -f "$FLUIDD_DIR/index.html" ] || die "Extracted dir missing index.html — release layout changed?"

info ""
info "Fluidd $FLUIDD_TAG installed at $FLUIDD_DIR ($(du -sh "$FLUIDD_DIR" | awk '{print $1}'))."
info "Files: $(find "$FLUIDD_DIR" -type f | wc -l)"
info ""
info "nginx serves this dir on port 80 once S99znginx is in place."

# -- Seed Fluidd UI preferences in Moonraker DB ---------------------------
# Fluidd reads its UI settings (axis invert toggles, jog speeds, theme,
# etc.) from Moonraker's database (namespace=fluidd, root key=uiSettings)
# on every page load / WebSocket reconnect. There is NO localStorage
# cache for these — seeding the DB once makes the values stick for every
# browser, fresh or otherwise.
#
# Reference: fluidd-core/fluidd src/store/socket/actions.ts:221-257
# (unconditional DB read on identify) + src/store/config/mutations.ts
# (deep-merge onto defaults).
#
# Keys set here (all under namespace=fluidd):
#   uiSettings.general.axis.z.inverted        -> true   (CoreXY: bed is fixed,
#                                                       gantry moves; Fluidd's
#                                                       bed-slinger default is
#                                                       wrong for us)
#   uiSettings.general.defaultToolheadXYSpeed -> 20     (mm/s; matches Guppy)
#   uiSettings.general.defaultToolheadZSpeed  -> 20     (mm/s; matches Guppy)
#
# Speeds chosen to match Guppy Screen so both UIs feel identical.
# Guppy hardcodes F1200 (= 20 mm/s) for all axes — see ballaswag/guppyscreen
# src/homing_panel.cpp:181-206 (lines emitting "G0 X|Y|Z{dist} F1200").
# Fluidd's defaults are 130 mm/s XY and 10 mm/s Z, which makes Z feel
# noticeably slower than Guppy. Both 20 values are well under our
# [printer] max_velocity=1000 / max_z_velocity=30.
info ""
info "=== Seed Fluidd UI preferences (Moonraker DB) ==="

MOONRAKER_URL="http://127.0.0.1:7125"

# Wait up to 30s for Moonraker to be reachable (it may have just been
# (re)started, or this might be running before S56moonraker_service is up).
MOONRAKER_READY=0
for i in $(seq 1 30); do
    if /opt/bin/curl -fsS "$MOONRAKER_URL/server/info" >/dev/null 2>&1; then
        MOONRAKER_READY=1
        break
    fi
    sleep 1
done

if [ "$MOONRAKER_READY" -eq 0 ]; then
    warn "Moonraker not reachable on $MOONRAKER_URL within 30s."
    warn "Skipping Fluidd preference seeding. To apply later, re-run this script"
    warn "once Moonraker is up, or POST manually to /server/database/item."
else
    info "Moonraker reachable. Seeding 3 preference keys..."

    seed_fluidd_pref() {
        # $1: dotted key under namespace=fluidd
        # $2: raw JSON value (true / false / number / "string")
        _key="$1"
        _value="$2"
        if /opt/bin/curl -fsS -X POST "$MOONRAKER_URL/server/database/item" \
            -H 'Content-Type: application/json' \
            -d "{\"namespace\":\"fluidd\",\"key\":\"$_key\",\"value\":$_value}" \
            >/dev/null; then
            info "  set $_key = $_value"
        else
            warn "  failed to set $_key"
        fi
    }

    seed_fluidd_pref "uiSettings.general.axis.z.inverted"        "true"
    seed_fluidd_pref "uiSettings.general.defaultToolheadXYSpeed" "20"
    seed_fluidd_pref "uiSettings.general.defaultToolheadZSpeed"  "20"

    info "Done. Refresh Fluidd in the browser to see the new defaults."
fi
