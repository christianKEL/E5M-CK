#!/bin/sh
# install_factory_reset.sh — deploy the E5M-CK custom S58factoryreset.
#
# Runs ON THE PRINTER (busybox sh).
# Reads our replacement script from stdin so the local caller can pipe it
# in over SSH without needing to first copy a file.
#
# What it does:
#   1. Back up the existing /etc/init.d/S58factoryreset to
#      /usr/data/backup/S58factoryreset.orig (only if not already backed up).
#   2. Write the new S58 to /etc/init.d/S58factoryreset.
#   3. Make it executable.
#   4. Verify size + md5 against expected values (passed as args).
#
# Usage (typical, from the user's machine):
#   cat system/etc/init.d/S58factoryreset | ssh root@printer \
#       'sh -s -- <expected_md5> <expected_size>' < installs/install_factory_reset.sh
#
# Or as a higher-level wrapper (preferred):
#   bash scripts/sync.sh --apply        (which deploys S58 + other files together)
#
# The check_md5 / check_size args are optional but recommended:
#   sh install_factory_reset.sh                   # no verification
#   sh install_factory_reset.sh <md5>             # md5 only
#   sh install_factory_reset.sh <md5> <size>      # md5 + size

set -eu

EXPECTED_MD5="${1:-}"
EXPECTED_SIZE="${2:-}"

S58_TARGET="/etc/init.d/S58factoryreset"
BACKUP_DIR="/usr/data/backup"
BACKUP_FILE="${BACKUP_DIR}/S58factoryreset.orig"
TMP_FILE="/tmp/S58factoryreset.new"

ts() { date +'%H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
err()  { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; }
die()  { err "$*"; exit 1; }

# -- Read new script from stdin ------------------------------------------
info "Reading new S58factoryreset from stdin..."
cat > "$TMP_FILE" || die "Failed to read stdin."
NEW_SIZE=$(wc -c < "$TMP_FILE")
NEW_MD5=$(md5sum "$TMP_FILE" | awk '{print $1}')
info "Received: $NEW_SIZE bytes, md5=$NEW_MD5"

# -- Verify against expected ---------------------------------------------
if [ -n "$EXPECTED_MD5" ] && [ "$NEW_MD5" != "$EXPECTED_MD5" ]; then
    rm -f "$TMP_FILE"
    die "md5 mismatch (expected $EXPECTED_MD5, got $NEW_MD5)"
fi
if [ -n "$EXPECTED_SIZE" ] && [ "$NEW_SIZE" != "$EXPECTED_SIZE" ]; then
    rm -f "$TMP_FILE"
    die "size mismatch (expected $EXPECTED_SIZE, got $NEW_SIZE)"
fi

# -- Backup the original (idempotent) ------------------------------------
mkdir -p "$BACKUP_DIR"
if [ -f "$BACKUP_FILE" ]; then
    info "Original already backed up at $BACKUP_FILE — keeping it."
elif [ -f "$S58_TARGET" ]; then
    cp "$S58_TARGET" "$BACKUP_FILE"
    info "Backed up original $S58_TARGET -> $BACKUP_FILE"
else
    info "No existing $S58_TARGET to back up."
fi

# -- Install the new script ----------------------------------------------
mv "$TMP_FILE" "$S58_TARGET"
chmod +x "$S58_TARGET"
LIVE_MD5=$(md5sum "$S58_TARGET" | awk '{print $1}')
info "Installed: $S58_TARGET (md5=$LIVE_MD5)"

# -- Smoke test -----------------------------------------------------------
# Calling it with no args should print usage and exit 1.
if "$S58_TARGET" 2>&1 | grep -q 'Usage:.*{start|reset}'; then
    info "Smoke test: usage output OK."
else
    die "Smoke test failed — script does not print expected usage."
fi

info "Done."
