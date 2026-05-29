#!/bin/sh
# Search for OTA password / 7z command line in Creality binaries
set -u

echo "=== app-server strings related to OTA ==="
strings /usr/bin/app-server | grep -iE 'ota|\.img|7z|password|extract' | head -40
echo ""
echo "=== web-server strings related to OTA ==="
strings /usr/bin/web-server | grep -iE 'ota|\.img|7z|password|extract' | head -40
echo ""
echo "=== unique long string candidates for password ==="
strings /usr/bin/app-server | awk 'length>=8 && length<=32 && !/^\// && !/\./ && !/[ \t]/' | sort -u | head -30
