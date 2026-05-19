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

The Eddy needs THREE calibrations in order:

### Step A — Drive current (LDC sensor sensitivity)

```
LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy
```

Klipper computes the optimal drive current for the LDC1612. **Cold** is fine.

### Step B — Frequency / height map (the probe-to-Z relationship)

This is what teaches Klipper "frequency F = Z height H". Done **cold** too.

```
G28 X Y
G0 X178 Y200          ; nozzle at (X=178, Y=200) so probe is at (200, 200)
G0 Z10                ; lift to safe height (>=10 mm — see "golden rule" below)
PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy
```

Klipper prompts: "Adjust the nozzle height so it just barely touches the bed" using `TESTZ Z=-0.1` style commands or paper test. Then `ACCEPT` to record Z=0. The probe sweeps from ~5 mm down to contact and builds the F-H table.

`SAVE_CONFIG` after to persist.

### Step C — Tap calibration (precision Z=0 from a physical tap)

This is the **thermal-dependent** one. Do it AT printing temperatures (bed at 60°C, nozzle at 150°C — hot enough that the bed plate and toolhead are at their print-time expansion state, cold enough not to ooze).

⚠️ Golden rule (from v1 memo): **always lift Z ≥ 10 mm before any tap**. Without the 10 mm baseline, the LDC1612 has no stable frequency window to detect contact slope, and tap fails with `Unable to detect tap: insufficient slope delta`.

```
M140 S60               ; bed
M104 S150              ; nozzle (no ooze at 150C for PLA)
M190 S60               ; wait bed
M109 S150              ; wait nozzle
G28 X Y
G0 X178 Y200
G0 Z10                 ; mandatory 10mm baseline
PROBE_EDDY_CURRENT_TAP_CALIBRATE CHIP=btt_eddy
```

Look at the suggested `tap_threshold` value (typically 20-50; v1 settled on 28). Then activate with:

```
SET_GCODE_OFFSET Z=0
PROBE METHOD=tap                ; test tap
```

If reproducible (σ ≤ 0.010 mm over 10 samples), `SAVE_CONFIG`.

### Verify probe accuracy

```
PROBE_ACCURACY METHOD=scan SAMPLES=10
PROBE_ACCURACY METHOD=tap SAMPLES=10    ; if tap is calibrated
```

Target: **σ ≤ 0.010 mm** (10 µm). v1 achieves σ ≈ 0.0026 mm in scan mode.

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
