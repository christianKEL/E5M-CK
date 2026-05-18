─────────────────────────────────────────────────────────
MEMO — Issue #17 : "Unable to detect tap: insufficient slope delta"
Project    : E5M-CK
File       : homing.cfg
─────────────────────────────────────────────────────────

PROBLEM
The first G28 after a Klipper restart consistently failed at the
Z refinement step with repeated "insufficient slope delta" errors.
Root cause : the original homing sequence performed the Z=0
refinement via tap, but at that point the nozzle still carried
residue from the previous print (no nozzle clean is possible
before the first home). A dirty nozzle dampens the tap signal
below the slope-detection threshold, so the tap aborts.

SOLUTION
Branch the Z=0 refinement on the actual homing state of the Z
axis at the moment G28 is invoked :

  • Z not yet homed  → SET_Z_FROM_PROBE METHOD=scan
                       (no contact, dirty nozzle is irrelevant)
  • Z already homed  → SET_Z_FROM_PROBE METHOD=tap
                       (5-sample median, original behaviour)

This means the very first home of the session always uses scan,
and any subsequent G28 in the same session keeps the tap
precision. The tap-based precision needed for the actual print
is still provided downstream by SET_SCAN_FROM_TAP in the start
G-code, executed AFTER NOZZLE_CLEAR_ON_BRUSH.

IMPLEMENTATION DETAIL
The 'set_position_z: 0' option of [homing_override] had to be
removed. Klipper applies set_position_z BEFORE the gcode template
runs and marks the axis as homed in the process, so the
'z in printer.toolhead.homed_axes' check would always be true and
the branching would never trigger. The unconditional Z=0 fake-home
was replaced with a conditional SET_KINEMATIC_POSITION Z=0 that
only fires when Z is actually unhomed.

KNOWN LIMITATION
A manual G28 issued after CAL_BED_Z_TILT (which leaves Z unhomed
and bed dropped) will correctly trigger the scan branch — good.
However, a G28 issued mid-session with a dirty nozzle (rare case)
will still attempt tap. Workaround : run FIRMWARE_RESTART first.

─────────────────────────────────────────────────────────
                                                  — E5M-CK
─────────────────────────────────────────────────────────
