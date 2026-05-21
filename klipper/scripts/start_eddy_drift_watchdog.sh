#!/bin/sh
# start_eddy_drift_watchdog.sh — fire-and-forget launcher.
#
# Installed at: /usr/data/e5m-ck/bin/start_eddy_drift_watchdog.sh
# Invoked by:   [gcode_shell_command start_eddy_drift_watchdog]
# Backend:      /usr/data/e5m-ck/bin/eddy_drift_watchdog.py
#
# Purpose: keep the gcode_shell_command return fast (so the EDDY_DRIFT_CALIBRATE
# macro doesn't block its own gcode pipeline) while the python watchdog runs
# detached for the whole calibration. Mirrors the pattern used by
# restart_guppyscreen.sh and gen_belts_for_guppy.sh — detached subshell with
# stdin/stdout/stderr fully redirected so the parent shell exits cleanly.
#
# The watchdog's stdout/stderr go to /tmp/eddy_drift_watchdog.log for
# post-mortem if anything misbehaves.

LOG=/tmp/eddy_drift_watchdog.log
WATCHDOG=/usr/data/e5m-ck/bin/eddy_drift_watchdog.py

# Truncate prior log so each run starts clean.
: > "$LOG"

( /usr/share/klippy-env/bin/python3 "$WATCHDOG" ) </dev/null >>"$LOG" 2>&1 &

echo "Eddy drift watchdog started (PID $!, log $LOG)."
