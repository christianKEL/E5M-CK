#!/usr/share/klippy-env/bin/python3
"""eddy_drift_watchdog.py — auto-finalize TEMPERATURE_PROBE_CALIBRATE.

Companion to the EDDY_DRIFT_CALIBRATE macro. Polls Moonraker for the
btt_eddy coil temperature every POLL_INTERVAL seconds and:

  1. If the coil temperature has not increased for STALL_TIMEOUT seconds
     while a calibration is in progress, posts TEMPERATURE_PROBE_COMPLETE
     to finalize the drift table with whatever samples were collected.
     This is the case when the bed plateaus before reaching TARGET
     (e.g. radiation losses cap the coil at ~75 C even with bed at 100 C).

  2. Once Klipper reports `in_calibration: False` — whether the calibration
     ended naturally at TARGET, via the stall-triggered COMPLETE above, or
     via a manual ABORT — posts TURN_OFF_HEATERS, drops the light, and
     emits a RESPOND message so the user sees the cleanup happened.

Safety net: HARD_TIMEOUT is the absolute maximum runtime. If something
goes wrong and Klipper never updates in_calibration (bug, disconnect),
the watchdog still cleans up the heaters and exits instead of running
forever.

The watchdog only watches the COIL thermistor (`temperature_probe btt_eddy`,
gpio26), NOT the RP2040 MCU die temp (`temperature_sensor btt_eddy_mcu`) —
those are different sensors with very different thermal time constants.
The MCU temp can be steady while the coil is still drifting up.

Polling Moonraker (not Klipper's status object directly) is intentional:
keeps this script independent of Klipper internals and means it can be
restarted/upgraded without touching klippy.
"""

import json
import sys
import time
import urllib.parse
import urllib.request

POLL_INTERVAL = 10        # seconds between polls
STALL_TIMEOUT = 600       # 10 min without coil temp rise -> COMPLETE
HARD_TIMEOUT = 5400       # 90 min absolute cap
MOONRAKER = "http://localhost:7125"
PROBE = "temperature_probe btt_eddy"
LIGHT_PIN = "light_pin"


def query_probe():
    body = json.dumps({"objects": {PROBE: None}}).encode()
    req = urllib.request.Request(
        MOONRAKER + "/printer/objects/query",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=5) as r:
        return json.load(r)["result"]["status"][PROBE]


def post_gcode(script):
    # Moonraker accepts the script as a urlencoded form field on this
    # endpoint. JSON body is not parsed here.
    body = ("script=" + urllib.parse.quote(script)).encode()
    req = urllib.request.Request(
        MOONRAKER + "/printer/gcode/script",
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=10) as r:
        return r.read()


def cleanup(reason):
    # Best-effort: ignore individual failures so all three lines get a shot.
    for script in (
        "TURN_OFF_HEATERS",
        "SET_PIN PIN=%s VALUE=0" % LIGHT_PIN,
        "RESPOND TYPE=command MSG=\"EDDY_DRIFT_CALIBRATE: %s. "
        "Run SAVE_CONFIG to persist the drift table.\"" % reason,
    ):
        try:
            post_gcode(script)
        except Exception as e:
            sys.stderr.write("cleanup: %s failed: %s\n" % (script, e))


def main():
    sys.stdout.write("eddy_drift_watchdog: starting (poll=%ds, stall=%ds)\n"
                     % (POLL_INTERVAL, STALL_TIMEOUT))
    sys.stdout.flush()

    started_at = time.monotonic()
    last_max = -1.0
    last_max_time = started_at
    saw_calibration = False
    stall_triggered = False

    while True:
        time.sleep(POLL_INTERVAL)
        now = time.monotonic()

        if now - started_at >= HARD_TIMEOUT:
            cleanup("hard timeout (%ds) reached" % HARD_TIMEOUT)
            return 0

        try:
            s = query_probe()
        except Exception as e:
            sys.stderr.write("watchdog: query failed: %s\n" % e)
            continue

        in_cal = bool(s.get("in_calibration", False))
        temp = float(s.get("temperature", 0))

        if not saw_calibration and in_cal:
            saw_calibration = True
            last_max = temp
            last_max_time = now

        # Calibration finished — clean up and exit.
        if saw_calibration and not in_cal:
            cleanup("calibration done")
            return 0

        if not in_cal:
            # CALIBRATE hasn't started yet (race at startup). Wait quietly,
            # but don't wait forever — if it never starts, the hard timeout
            # will catch us.
            continue

        if temp > last_max:
            last_max = temp
            last_max_time = now

        # Heartbeat: one line per poll so `tail -F` shows the watchdog
        # is alive. Includes the stall timer so the operator can see
        # how close we are to the COMPLETE trigger.
        stall_age = int(now - last_max_time)
        sys.stdout.write(
            "[%s] coil=%.2f max=%.2f stall_age=%ds/%ds\n"
            % (time.strftime("%H:%M:%S"), temp, last_max,
               stall_age, STALL_TIMEOUT))
        sys.stdout.flush()

        # Coil stuck: post COMPLETE once. The next poll iteration will see
        # in_calibration=False and run cleanup() then return.
        if (not stall_triggered and
                stall_age >= STALL_TIMEOUT):
            sys.stdout.write(
                "watchdog: coil plateaued at %.2f C for %ds — "
                "posting TEMPERATURE_PROBE_COMPLETE\n"
                % (last_max, STALL_TIMEOUT))
            sys.stdout.flush()
            try:
                post_gcode("TEMPERATURE_PROBE_COMPLETE")
                stall_triggered = True
            except Exception as e:
                sys.stderr.write("watchdog: COMPLETE post failed: %s\n" % e)


if __name__ == "__main__":
    sys.exit(main())
