# BTT Eddy probe — operations guide

Phase 6 adds the BTT Eddy USB probe (RP2040 + LDC1612 inductive sensor) for Z homing, bed mesh, and tap-precision Z=0 reset.

## Versions pinned

| Component        | Pinned         | Source                                                             |
|------------------|----------------|--------------------------------------------------------------------|
| Klipper firmware | v0.13.0 RP2040 | `klipper/binaries/rp2040/btteddy.uf2` (built in Codespace)         |
| Mount offsets    | x=22, y=0      | Post-29/04/2026 remount per v1 calibration memo                    |

## Install procedure

### 1. Local: push artifacts + new printer.cfg

```bash
# (Local) fresh backup
bash scripts/backup.sh

# (Local) push the UF2 to the printer's /tmp
scp -O klipper/binaries/rp2040/btteddy.uf2 root@192.168.1.94:/tmp/

# (Local) push eddy.cfg and the updated printer.cfg (Z endstop → probe)
bash scripts/sync.sh --apply
```

### 2. Put the Eddy in BOOTSEL mode

The Eddy is mounted on the toolhead but USB is **not** plugged in yet.

1. Make sure the Eddy USB cable is unplugged.
2. Press and HOLD the `BOOT` button on the Eddy board.
3. Plug the USB cable into the Nebula Pad (button still held).
4. Release the button after 1 second.

The Eddy now presents as a USB mass-storage device (label `RPI-RP2`) instead of a serial device. The Nebula Pad sees it as `/dev/sda1` with FAT32.

### 3. Flash + register

```bash
# (Local) run the install script
cat installs/install_eddy.sh | ssh root@192.168.1.94 'sh -s'
```

The script:
- Detects RPI-RP2 mass-storage on the printer
- Mounts it, drops in `/tmp/btteddy.uf2`, unmounts
- Waits up to 30 s for the Eddy to re-enumerate as `/dev/serial/by-id/usb-Klipper_rp2040_XXXX-if00`
- Patches `/usr/data/printer_data/config/eddy.cfg` to point `[mcu eddy] serial:` at the detected path

The detected serial-id is **printer-specific** (derived from the RP2040 chip ID at build time). Pull the patched eddy.cfg back into the repo so future deploys carry the right path:

```bash
ssh root@192.168.1.94 'cat /usr/data/printer_data/config/eddy.cfg' > klipper/config/eddy.cfg
git add klipper/config/eddy.cfg
git commit -m "eddy.cfg: pin serial-id for this printer"
git push
```

### 4. Restart Klipper

```bash
ssh root@192.168.1.94 '/etc/init.d/S55klipper_service restart'
sleep 12
curl -s http://192.168.1.94/printer/info | jq .result.state   # expect: "ready"
```

If Klipper errors with `Unable to open serial port /dev/serial/by-id/...`, the patched serial path is wrong — re-run `install_eddy.sh`.

## Calibration sequence

Source: <https://www.klipper3d.org/Eddy_Probe.html>. Steps MUST run in this order.

With BTT Eddy mount offsets `x_offset=22, y_offset=0`, the **probe is 22 mm
to the +X of the nozzle**. So:
- Nozzle at X=200, Y=200 → probe at X=222, Y=200
- Nozzle at X=178, Y=200 → probe at X=200, Y=200 (= bed center)

**Which one to use depends on the operation:**

| Operation                          | What needs to be at center | XY command         |
|------------------------------------|----------------------------|--------------------|
| `LDC_CALIBRATE_DRIVE_CURRENT`      | The probe (sensor cal)     | `G0 X178 Y200`     |
| `PROBE_EDDY_CURRENT_CALIBRATE`     | The nozzle (paper test)    | `G0 X200 Y200` ⭐  |
| `PROBE_EDDY_CURRENT_TAP_CALIBRATE` | The nozzle (it taps)       | `G0 X200 Y200`     |
| `TEMPERATURE_PROBE_CALIBRATE`      | The nozzle (paper test)    | `G0 X200 Y200`     |
| `PROBE_ACCURACY METHOD=scan`       | The probe (measure probe)  | `G0 X178 Y200`     |
| `PROBE_ACCURACY METHOD=tap`        | The nozzle (it taps)       | `G0 X200 Y200`     |

⭐ **Important for cal**: after the paper-test ACCEPT, Klipper
**automatically shifts the toolhead by (-x_offset, -y_offset)** to put the
probe over the paper-test XY. So you do NOT pre-shift to put the probe at
the center — Klipper does it for you after ACCEPT. The doc rule is "put
what's being measured at the center, Klipper handles the rest".

### Step 1 — Drive current (LDC sensor sensitivity)

> "Home the printer and navigate the toolhead so that the sensor is near the
> center of the bed and is about 20mm above the bed." — Klipper docs

```
G28
G0 X178 Y200 F6000          ; probe over bed center (sensor cal needs probe-at-center)
G0 Z20 F600                 ; 20 mm above bed (per doc)
LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy
SAVE_CONFIG                 ; (triggers Klipper restart)
```

Completes in a few seconds. No heating required.

### Step 2 — Frequency / height map (probe-to-Z curve)

> "For best results the calibration done here and the subsequent probing
> that utilizes that calibration should be done at the same temperature."
> "Home the printer and navigate the toolhead so that the nozzle is near
> the center of the bed." — Klipper docs

The bed plate's thermal expansion (~0.3 mm across a 300 mm Z-axis swing on
a 6mm aluminium plate at 60 °C) shifts the LDC frequency. Calibrate at the
temperature you'll print at — typically **bed = 60 °C**, nozzle warm enough
to not drag filament on the bed during the paper test but cool enough not
to ooze (M104 S150 is the safe sweet spot for PLA).

```
M140 S60                    ; bed → 60 °C
M104 S150                   ; nozzle → 150 °C (no-ooze)
M190 S60                    ; wait bed
M109 S150                   ; wait nozzle
G28
G0 X200 Y200 F6000          ; NOZZLE at bed center (Klipper shifts probe after ACCEPT)
PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy
```

Klipper opens the `manual_probe` paper test (the bed rises toward the
toolhead until the nozzle is close to the bed). Adjust with `TESTZ Z=-0.1`
(bed up, smaller gap) / `TESTZ Z=+0.02` (bed down, bigger gap) until paper
drags, then `ACCEPT`. Klipper then auto-shifts the toolhead by (-22, 0)
so the probe is over the paper-test XY, and sweeps probe heights to build
the F→H table.

```
SAVE_CONFIG                 ; persists z_offset + frequency map
```

After this, the placeholder `z_offset: 1.0` in `eddy.cfg` is replaced by
the real value via autosave. Pull live → repo as usual.

#### Verify scan accuracy

```
G0 X178 Y200 F6000
G0 Z5 F600
PROBE_ACCURACY PROBE_METHOD=scan SAMPLES=10
```

Target: **σ ≤ 0.010 mm** (10 µm). v1 achieves σ ≈ 0.0026 mm. If σ is too
high, re-run Step 2 — usually means temperature wasn't settled or there
was debris under the probe.

### Step 3 — Tap calibration (precision Z=0 from physical tap)

Three sub-steps in order. Klipper docs note that **tap does NOT have the
thermal drift issues** that scan probing has — but the threshold still
needs calibrating against this specific bed plate + nozzle combo.

Preconditions:
- `[stepper_z] position_min: <= -1` — checked (we have `-2`).
- Nozzle and bed CLEAN — any filament or debris invalidates results.
- **Be ready to slam M112** if the nozzle drives into the bed.

```
G28
G0 X200 Y200 F6000          ; NOZZLE at bed center (it does the physical tap)
G0 Z5 F600                  ; doc: "between 3 - 10 mm from the bed"
PROBE_EDDY_CURRENT_TAP_CALIBRATE TAP=guess        ; coarse threshold from scan data
PROBE_EDDY_CURRENT_TAP_CALIBRATE TAP=refine       ; improve threshold from a real tap
PROBE_EDDY_CURRENT_TAP_CALIBRATE TAP=verify       ; probes the bed 5x in a row
SAVE_CONFIG                                       ; persists tap_threshold + tap_z_offset
```

If `TAP=verify` fails (any of the 5 probes inconsistent), do NOT
`SAVE_CONFIG` — clean the nozzle/bed, re-run `TAP=refine` then `TAP=verify`.

#### Verify tap accuracy

```
PROBE_ACCURACY PROBE_METHOD=tap SAMPLES=10
```

Target: **σ ≤ 0.010 mm**.

### Step 4 — Thermal drift compensation (optional)

Only if you see Z drift between cold and hot prints. Uses our
`[temperature_probe btt_eddy]` thermistor to model frequency-vs-coil-temp.

Preconditions:
- Bed, nozzle, AND probe coil all **cold** at start.
- Tool at bed center, Z ≥ 30 mm.
- Extruder pre-heated to 150-170 °C (above max bed temp, so the nozzle's
  thermal state doesn't change during the bed sweep).

```
M104 S160 ; M109 S160         ; nozzle hot before starting
G28
G0 X200 Y200 F6000            ; NOZZLE at bed center (paper test is interactive)
G0 Z30 F600                   ; ≥ 30 mm above bed (doc requirement)
TEMPERATURE_PROBE_CALIBRATE PROBE=btt_eddy TARGET=70
```

Then drop Z to ~1 mm, run paper test, `ACCEPT`. Klipper heats the bed and
asks for a manual probe every 2 °C of coil rise (use `TEMPERATURE_PROBE_NEXT`
to step, `TEMPERATURE_PROBE_COMPLETE` to stop, `ABORT` to bail). At the end:

```
SAVE_CONFIG
```

We'll skip Step 4 on first install and only run it if drift shows up in
actual prints.

## Syncing autosave back into the repo

After any `PROBE_EDDY_CURRENT_CALIBRATE` / `LDC_CALIBRATE_DRIVE_CURRENT` /
`PROBE_EDDY_CURRENT_TAP_CALIBRATE` + `SAVE_CONFIG` cycle, Klipper writes
the new values into the autosave block at the bottom of the LIVE
`/usr/data/printer_data/config/printer.cfg`. The repo's
`klipper/config/eddy.cfg` then lags behind. To re-sync:

```bash
# 1. Read the live autosave block
ssh root@192.168.1.94 'awk "/^#\*# <----------/,0" /usr/data/printer_data/config/printer.cfg | sed "s/^#\*# //"' > /tmp/autosave.txt

# 2. Look at the [probe_eddy_current btt_eddy] and [temperature_probe btt_eddy]
#    sections in /tmp/autosave.txt. Copy:
#      - reg_drive_current
#      - tap_threshold  (only after Step 3 ran)
#      - calibrate (the full F→H table)
#    into klipper/config/eddy.cfg under [probe_eddy_current btt_eddy], and
#      - calibration_temp
#    under [temperature_probe btt_eddy].

# 3. Commit. The live autosave block stays — Klipper merges it on top of
#    the regular section at load time; the two now match.
git add klipper/config/eddy.cfg
git commit -m "eddy.cfg: re-sync autosave (cal date YYYY-MM-DD)"
```

**Why this dual-storage pattern**: Klipper insists on owning the
autosave block in the live `printer.cfg`. We can't write our repo values
there directly without losing them on the next SAVE_CONFIG. Instead we
mirror them into the regular config sections; Klipper happily merges
both. The repo therefore stays self-sufficient (a clean `sync.sh` from
scratch reproduces the calibrated state), while live cals still work.

If you push our repo's `printer.cfg` to a printer whose live file has a
DIFFERENT autosave block, do NOT raw-`scp printer.cfg` — that wipes the
live autosave and loses any cal not yet re-synced. Edit in place with
`sed`/`awk` instead. See
`~/.claude/projects/.../memory/feedback_dont_scp_printer_cfg.md` for
the full burn-postmortem.

## What changes in printer.cfg

- `[include eddy.cfg]` added near the top.
- `[stepper_z] endstop_pin` changed from `tmc2209_stepper_z:virtual_endstop` (sensorless stand-in) to `probe:z_virtual_endstop` (Eddy).
- `[stepper_z] position_endstop` removed (probe provides the trigger point).
- `[homing_override]` Z branch simplified — no more TMC current dance, just `G0 X200 Y200; G28 Z`.

## Rollback

If the Eddy is broken or you want to test without it:

```bash
# (Local) edit klipper/config/printer.cfg:
#   - remove [include eddy.cfg]
#   - change [stepper_z] endstop_pin back to tmc2209_stepper_z:virtual_endstop
#   - add: position_endstop: 0
# Then:
bash scripts/sync.sh --apply
ssh root@192.168.1.94 '/etc/init.d/S55klipper_service restart'
```

## Known issues (from v1, may resurface)

- **Klipper bug**: `PROBE_ACCURACY METHOD=tap SAMPLES>1` fails on 2nd sample with `Unable to detect tap: insufficient slope delta`. v1 worked around it with a custom `PROBE_ACCURACY_TAP` macro that manually lifts between samples. We'll port it from v1 if/when we hit the issue.
- **Klipper bug**: `SET_GCODE_OFFSET Z_ADJUST=` is incremental, not absolute. Multiple successive calls cumulate. v1 documents the workaround.

## Files

- `klipper/binaries/rp2040/btteddy.uf2` — firmware (78 KB)
- `klipper/config/eddy.cfg` — probe configuration
- `installs/install_eddy.sh` — flasher + serial-id patcher
- `klipper/config/printer.cfg` — `[stepper_z] endstop_pin: probe:z_virtual_endstop` + `[include eddy.cfg]`
- `klipper/config/macros/homing.cfg` — Z branch uses the probe
