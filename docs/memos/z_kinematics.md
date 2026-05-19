# Z kinematics — the BED moves, not the toolhead

The Ender 5 Max is a CoreXY printer where the **toolhead is fixed in Z**
and the **bed moves vertically** on the Z axis. This is the opposite of
gantry-Z CoreXY designs (Voron 2.4, RatRig V-Core 3 stock) where the
toolhead descends/rises on a gantry-mounted Z stepper.

## Polarity

| Z command | What physically moves | Effect on clearance |
|-----------|----------------------|---------------------|
| Z increases (G0 Z+) | Bed moves **down** | Clearance grows (safer) |
| Z decreases (G0 Z-) | Bed moves **up** | Clearance shrinks (toward crash) |

Klipper's internal Z coordinate represents "nozzle-to-bed distance" the
same way as on a moving-toolhead machine — so all G-code, all probe
logic, and all calibration math is identical. **Only the mental model /
descriptions change.** When narrating a move to the user, never say "the
toolhead descends" or "the head moves down" — that's wrong. Say "the
bed rises" / "le plateau monte" instead.

## Why this matters for the UI configs

Fluidd's "Invert Z controls" defaults assume a bed-slinger (i3-style,
where Z+ in G-code means the bed-mounted nozzle assembly rises, which
visually feels like "go up"). On an E5M-CK CoreXY with moving bed:

- Pressing Fluidd's `Z+` button SHOULD result in more clearance (bed
  moves away from toolhead = bed goes down).
- Without the invert toggle, Fluidd's `Z+` button decreases clearance
  (bed comes up toward the static toolhead — dangerous).

The `uiSettings.general.axis.z.inverted = true` seeded by
`installs/install_fluidd.sh` corrects this. Guppy Screen has the same
toggle (`invert_z_icon` in `guppyscreen/guppyconfig.json`) but defaults
correctly for our paradigm, so no override needed there. The Klipper
`[stepper_z] dir_pin` is also correct out-of-the-box — no firmware-side
inversion needed.

## Implications for Eddy probe calibration

When the calibration procedure asks for "the Eddy 20 mm above the bed":

- The toolhead does NOT descend.
- The BED descends until there is 20 mm of clearance between the
  toolhead-mounted Eddy coil and the bed surface.
- From a Z-coordinate perspective, that's a **Z+ move** (clearance
  growing).

When the calibration procedure does its scan-down sweep (in
`PROBE_EDDY_CURRENT_CALIBRATE`), Klipper issues progressively-decreasing
Z targets. What's physically happening: the bed is creeping UP toward
the toolhead, while the toolhead stays put. The probe coil detects the
rising aluminum bed plate.

## Implications for the homing_override Z lift

In `klipper/config/macros/homing.cfg`, the line
`G1 Z30 F600` at the top of the override is **not** a "nozzle lift" — it
is a "bed drop". The bed descends 30 mm to give clearance before X/Y
homing moves can drag anything across it. Same outcome, different
mechanics. The comment in homing.cfg that mentions "nozzle" wording is
inaccurate but the move itself is correct.

## Sanity check protocol

Before sending any Z-move command (or asking the user to send one),
verify: **is this command increasing Z (= bed away = safe) or decreasing
Z (= bed toward toolhead = potential crash)?** Decreasing-Z is the only
direction that can damage anything — slow speeds, small steps, and a
known starting point are mandatory there.
