#!/bin/sh
# install_entware.sh — install Entware (opkg) and base packages on the printer.
#
# Runs ON THE PRINTER (busybox sh).
# Idempotent: re-running upgrades existing install + reinstalls missing packages.
# Non-interactive by default. Pass --interactive for confirmations.
#
# Architecture: Ingenic XBurst II V2 (MIPS32r2 little-endian, soft float)
# matching Entware's `mipselsf-k3.4` build. This covers Nebula Pad printers
# (K1, K1 Max, Ender 5 Max, CR-10 SE, ...).
#
# Usage (from the printer over SSH):
#   sh install_entware.sh                # non-interactive
#   sh install_entware.sh --interactive  # ask before each destructive step
#   sh install_entware.sh --force        # wipe existing /opt without asking
#   sh install_entware.sh --help

set -eu

# -- Configuration --------------------------------------------------------
ENTWARE_ARCH="mipselsf-k3.4"
ENTWARE_URL="http://bin.entware.net/${ENTWARE_ARCH}/installer/generic.sh"

# Base packages required by the rest of the E5M-CK toolchain.
# Comments below explain notable exclusions inherited from v1 experience.
#
#   no `virtualenv`   -> deprecated; use `python3 -m venv` instead
#   no `libsodium-dev`-> headers ship with the runtime package on Entware
#   no `libssl-dev`   -> Entware ships `libopenssl`, already pulled by curl/wget
#   no `gcc`/`make`   -> 143 MB on /opt (shares the small overlay partition).
#                        Python wheels cover Klipper/Moonraker.
BASE_PACKAGES="ca-certificates ca-bundle wget-ssl curl python3 python3-pip python3-dev git git-http nginx jq libffi libsodium nano htop"

PATH_LINE='export PATH=/opt/bin:/opt/sbin:$PATH'

# -- Logging --------------------------------------------------------------
ts() { date +'%H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(ts)" "$*" >&2; }
err()  { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; }
die()  { err "$*"; exit 1; }

# -- Args -----------------------------------------------------------------
INTERACTIVE=0
FORCE=0
for arg in "$@"; do
    case "$arg" in
        --interactive) INTERACTIVE=1 ;;
        --force) FORCE=1 ;;
        -h|--help)
            sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "Unknown argument: $arg" ;;
    esac
done

confirm() {
    [ "$INTERACTIVE" = "0" ] && return 0
    printf '%s [y/N] ' "$1"
    read -r ans
    case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# -- Preflight ------------------------------------------------------------
info "=== Preflight ==="
ARCH=$(uname -m)
info "arch: $ARCH (expected: mips)"
[ "$ARCH" = "mips" ] || warn "Architecture is not mips — Entware URL may not match."

YEAR=$(date +%Y)
info "date: $(date '+%Y-%m-%d %H:%M:%S')"
if [ "$YEAR" -lt 2024 ]; then
    err "System date is in the past (year $YEAR). HTTPS will fail."
    err "Fix with: ntpd -d -q -n -p pool.ntp.org"
    die "Aborting."
fi

info "Testing internet reachability..."
if ping -c 1 -W 3 bin.entware.net >/dev/null 2>&1; then
    info "bin.entware.net reachable."
else
    warn "Cannot ping bin.entware.net (firewall?). Trying wget anyway."
fi

# -- Existing install handling -------------------------------------------
info ""
info "=== Existing /opt ==="
if [ -d /opt ] && [ -x /opt/bin/opkg ]; then
    info "Entware already installed at /opt."
    OPKG_COUNT=$(/opt/bin/opkg list-installed 2>/dev/null | wc -l)
    info "Installed packages: $OPKG_COUNT"
    if [ "$FORCE" = "1" ]; then
        info "--force: will wipe and reinstall."
        WIPE=1
    elif confirm "Wipe and reinstall? Choose No to only upgrade + add missing packages."; then
        WIPE=1
    else
        info "Keeping existing install — will upgrade + add missing packages."
        WIPE=0
    fi
else
    info "No existing Entware install."
    WIPE=1
fi

# -- Wipe (if needed) ----------------------------------------------------
if [ "$WIPE" = "1" ] && [ -d /opt ] && [ -x /opt/bin/opkg ]; then
    info ""
    info "=== Wipe ==="
    rm -rf /opt
    sync
    info "/opt removed."
fi
mkdir -p /opt

# -- Install or upgrade --------------------------------------------------
if [ "$WIPE" = "1" ]; then
    info ""
    info "=== Install Entware ==="
    info "Downloading $ENTWARE_URL"
    wget --no-check-certificate -O - "$ENTWARE_URL" | sh \
        || die "Entware installer failed."
    [ -x /opt/bin/opkg ] || die "/opt/bin/opkg missing after install."
    info "Entware installed."
fi

# -- PATH ----------------------------------------------------------------
info ""
info "=== PATH ==="
export PATH=/opt/bin:/opt/sbin:$PATH
info "PATH updated for current session."

if grep -qF "/opt/bin:/opt/sbin" /etc/profile 2>/dev/null; then
    info "/etc/profile already has the Entware PATH — skipping."
else
    {
        echo ""
        echo "# E5M-CK: Entware PATH"
        echo "$PATH_LINE"
    } >> /etc/profile
    info "Added Entware PATH to /etc/profile."
fi

# -- Package index -------------------------------------------------------
info ""
info "=== opkg update ==="
/opt/bin/opkg update >/dev/null 2>&1 || die "opkg update failed."
info "Package index refreshed."

# -- Base packages -------------------------------------------------------
info ""
info "=== Install base packages ==="
info "Packages: $BASE_PACKAGES"
# shellcheck disable=SC2086 -- intentional word splitting
if ! /opt/bin/opkg install $BASE_PACKAGES; then
    warn "opkg install returned non-zero — check messages above."
fi

# -- Verify --------------------------------------------------------------
info ""
info "=== Verify ==="
MISSING=""
for tool in opkg python3 pip3 git nginx wget curl jq nano htop; do
    if command -v "$tool" >/dev/null 2>&1; then
        info "  ok: $tool ($(command -v "$tool"))"
    else
        MISSING="$MISSING $tool"
    fi
done

if [ -n "$MISSING" ]; then
    warn "Missing tools after install:$MISSING"
    exit 1
fi

info ""
info "Entware installation complete. Reboot recommended."
info "  opkg list-installed | wc -l  ->  $(/opt/bin/opkg list-installed | wc -l) packages"
