#!/bin/sh
# capture_stepcompress_diag.sh
#
# Extract any stepcompress / flush_handler / Internal error diagnostic
# from klippy.log files (including rotated ones). Designed for the
# enriched output from Klipper master PR #7271 (commit 4bc5646).
#
# Usage (run from your PC):
#   ssh root@192.168.1.94 'sh -' < scripts/capture_stepcompress_diag.sh
# OR locally on the printer:
#   sh capture_stepcompress_diag.sh
#
# Outputs to stdout. Pipe to a file if you want to save the report.
set -eu

LOG_DIR=/usr/data/printer_data/logs
OUT_LINES_BEFORE=10
OUT_LINES_AFTER=60

if [ ! -d "$LOG_DIR" ]; then
    echo "ERROR: log dir $LOG_DIR not found"
    exit 1
fi

# Find every klippy.log file (current + rotated). Newer files first.
LOGS=$(ls -t "$LOG_DIR"/klippy.log* 2>/dev/null || true)
if [ -z "$LOGS" ]; then
    echo "No klippy.log* files in $LOG_DIR"
    exit 1
fi

echo "Scanning $(echo "$LOGS" | wc -l) klippy.log file(s)..."
echo ""

# Patterns from the PR #7271 enriched diagnostic:
#   - Old (pre-7271): "Error in syncemitter '...'", "Internal error in stepcompress"
#   - New (post-7271): includes motion_queuing debug dump, motion_report stepper dump
PATTERNS='Internal error in stepcompress|Error in syncemitter|Exception in flush_handler|Transition to shutdown|stepcompress o='

for log in $LOGS; do
    if grep -qE "$PATTERNS" "$log" 2>/dev/null; then
        echo "================================================================"
        echo "  FOUND IN: $log  (size $(wc -c < "$log") bytes)"
        echo "================================================================"
        # Show line numbers where pattern matched, then ±context
        grep -nE "$PATTERNS" "$log" | head -5 | while IFS=: read -r linenum rest; do
            start=$((linenum - OUT_LINES_BEFORE))
            [ $start -lt 1 ] && start=1
            end=$((linenum + OUT_LINES_AFTER))
            echo ""
            echo "--- line $linenum (context $start..$end) ---"
            sed -n "${start},${end}p" "$log"
            echo ""
        done
    fi
done

echo ""
echo "================================================================"
echo "  ALSO useful: last 30 non-Stats lines from current klippy.log"
echo "================================================================"
awk '!/^Stats /' "$LOG_DIR/klippy.log" 2>/dev/null | tail -30
