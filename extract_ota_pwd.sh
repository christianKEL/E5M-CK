#!/bin/sh
# Capture the password 7z is invoked with by ota_file.
# Method: start ota_file extraction in background, then in a tight loop
# read /proc/*/cmdline looking for a 7z process. Save argv on first hit.
set -eu

OTA=/usr/data/F004_ota_img_V1.2.0.21-copie.img
DEST=/tmp/ota_pwd_capture
mkdir -p "$DEST"
rm -rf "$DEST"/*

# Start ota_file in the background
/usr/bin/ota_file e "$OTA" "$DEST" >/dev/null 2>&1 &
OTA_PID=$!

# Poll /proc for any 7z process. Read its cmdline (null-separated args).
# Loop ~5 seconds max.
CAPTURED=""
for i in $(seq 1 500); do
    for pid in $(ls /proc 2>/dev/null | grep '^[0-9]'); do
        if [ -r "/proc/$pid/cmdline" ]; then
            cmd=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
            case "$cmd" in
                */7z*)
                    if [ -z "$CAPTURED" ]; then
                        CAPTURED="$cmd"
                        echo "CAPTURED PID=$pid: $cmd"
                    fi
                    ;;
            esac
        fi
    done
    if [ -n "$CAPTURED" ]; then
        break
    fi
    # Tiny sleep — 0.01s if available, else nothing
    usleep 10000 2>/dev/null || true
done

# Wait for ota_file to finish
wait $OTA_PID 2>/dev/null || true

# Cleanup the re-extracted files (we already had the extraction)
rm -rf "$DEST"

if [ -z "$CAPTURED" ]; then
    echo "FAIL: never observed 7z process" >&2
    exit 1
fi
