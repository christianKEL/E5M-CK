#!/bin/sh
# Extract Creality OTA archive password.
#
# Strategy A: use strace to capture execve() syscall — argv is intact
#             at that moment, BEFORE 7z overwrites its argv.
# Strategy B: trace what ota_file does with mkpasswd, infer the password
#             derivation algorithm.
# Strategy C: dump strings from ota_file binary that look like a password.
#
# All read-only against an OTA you already own.
set -eu

OTA=/usr/data/F004_ota_img_V1.2.0.21-copie.img
DEST=/tmp/ota_pwd_capture
mkdir -p "$DEST"
rm -rf "$DEST"/*

echo "===== Strategy A: strace execve() of ota_file ====="
if command -v strace >/dev/null 2>&1; then
    echo "strace available — capturing execve calls..."
    strace -f -e trace=execve -s 256 /usr/bin/ota_file e "$OTA" "$DEST" 2>&1 \
        | grep -F 'execve(' \
        | grep -F '7z' \
        | head -3
else
    echo "strace not installed (would need: opkg install strace)"
fi

echo ""
echo "===== Strategy B: how is mkpasswd called? ====="
echo "mkpasswd binary info:"
ls -la /usr/bin/mkpasswd 2>/dev/null || echo "  no mkpasswd"
echo ""
echo "mkpasswd help/usage:"
/usr/bin/mkpasswd 2>&1 | head -10 || true
/usr/bin/mkpasswd --help 2>&1 | head -10 || true
echo ""
echo "Strings in mkpasswd binary that look like algo/salt hints:"
strings -n 4 /usr/bin/mkpasswd 2>/dev/null | grep -iE 'salt|password|cxsw|crealit|hash' | head -20 || true
echo ""

echo "===== Strategy C: strings of ota_file (offset shown) ====="
# Print strings with offset so we can spot suspicious constants
strings -t x -n 6 /usr/bin/ota_file 2>/dev/null

echo ""
echo "===== Strategy D: race condition catch — read /proc faster ====="
# Try reading /proc immediately after exec but using inotify-style polling
# at much higher frequency. Spawn ota_file, then poll /proc rapidly.
rm -rf "$DEST"/*
/usr/bin/ota_file e "$OTA" "$DEST" >/dev/null 2>&1 &
OF_PID=$!

# Poll as fast as possible. Look at every /proc/<pid>/cmdline and
# /proc/<pid>/stat (which shows process state).
for i in $(seq 1 50000); do
    for pid in $(ls /proc 2>/dev/null | grep '^[0-9]'); do
        if [ -r "/proc/$pid/cmdline" ]; then
            cmd=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null || true)
            case "$cmd" in
                */7z\ *)
                    # Got a 7z process - dump argv NOW. May or may not be
                    # cleared yet.
                    echo "Found 7z PID=$pid argv: $cmd"
                    # Try cat /proc/<pid>/environ too (just in case)
                    env_data=$(tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | head -10 || true)
                    echo "  environ first lines: $env_data"
                    break 2
                    ;;
            esac
        fi
    done
done

wait $OF_PID 2>/dev/null || true
rm -rf "$DEST"
