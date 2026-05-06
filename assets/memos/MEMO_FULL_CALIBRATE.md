# MEMO — FULL_CALIBRATE workflow

**Project**: E5M-CK
**Date**: 2026-05-06
**Scope**: BTT Eddy USB on Ender 5 Max, Klipper mainline

---

## 1. Problem statement

The BTT Eddy probe is highly sensitive to the temperature of its sensing
coil. The frequency/Z calibration table and the `tap_threshold` value
calibrated at one coil temperature are only valid within a narrow
window (typically ±5 °C) around that temperature. Outside of that
window, taps fail with `insufficient slope delta`, `invalid depress
distance`, or `Probe triggered prior to movement`, and scan readings
report a Z position several mm away from the true bed surface.

A persistent calibration is therefore unreliable across thermal
sessions: a print may start with the coil cold (≈ 30 °C), warm up to
its operating point during heat soak, and end with the coil at yet
another temperature once chamber convection stabilises. There is no
"good enough for all conditions" set of values.

## 2. Strategy: recalibrate at every print

Instead of trying to find robust persisted values, the chosen approach
is to **rebuild the entire Eddy state at the beginning of each print**,
in the actual thermal conditions of that print:

1. Heat the bed to print temperature
2. Heat the nozzle to 140 °C (warm enough for tap mechanics to work,
   cold enough to avoid filament ooze that would foul the bed)
3. Heat-soak 5 min so the coil reaches a stable temperature
4. Run `FULL_CALIBRATE`, which rebuilds:
   - `tap_threshold` (re-calibrated from current slope coefficients)
   - kinematic Z=0 (located by tap, median of 5 samples)
   - the frequency/Z table (rebuilt around the freshly located Z=0)
5. Run `BED_MESH_CALIBRATE METHOD=rapid_scan` with the fresh table
6. Heat the nozzle to print temperature, brush off the ooze drop,
   then `FINAL_TAP_OFFSET` to compensate for hotend thermal expansion
   (140 °C → print temp delta is typically 60–100 °C, producing
   ~50–100 µm of nozzle extension)
7. Prime line, print

Total overhead: ~4–5 min added to the start G-code, dominated by the
heat soak (5 min) and the Eddy table rebuild (~3 min). The user
intervention is zero.

## 3. Why a custom Klipper plugin is required

The native Klipper Eddy module has two limitations that make the
above strategy impossible without instrumentation:

### Limitation 1 — paper test in the calibration loop

`PROBE_EDDY_CURRENT_CALIBRATE` opens an interactive `manual_probe`
session and waits for the user to type `ACCEPT` after performing a
paper test at the bed surface. There is no programmatic way to feed
that `ACCEPT` from a G-code macro reliably.

### Limitation 2 — calibration values do not activate in RAM

Both `_save_calibration` (frequency/Z table) and `_save_tap_threshold`
end with a single call to `configfile.set(...)`, which only writes to
the **pending SAVE_CONFIG** block. The runtime attributes
(`cal_freqs`, `cal_zpos`, `_tap_threshold`) are **not** updated.
Without a Klipper restart (which would interrupt the print), every
subsequent tap or scan continues to use the old, possibly inadequate
boot-time values.

The custom plugin
[`probe_eddy_auto_calibrate.py`](https://raw.githubusercontent.com/christianKEL/E5M-CK/refs/heads/main/files/probe_eddy_auto_calibrate.py)
addresses both limitations by direct instrumentation of the runtime
Python objects, without modifying any Klipper source file. The native
`probe_eddy_current.py` stays vanilla and survives Klipper updates.

## 4. The plugin in detail

The plugin registers three G-code commands.

### 4.1 `PROBE_EDDY_CALIBRATE_AUTO`

Reproduces the native frequency/Z calibration sequence, but uses the
**current toolhead position** as the Z=0 reference instead of the
interactive paper test. Builds a fake `ManualProbeResult` from the
current `(x, y, z)` and feeds it into `eddy_cal.post_manual_probe()`,
which then runs the standard 40 µm-step sweep up to ~4 mm.

Activates the resulting table in RAM by monkey-patching
`_save_calibration` for the duration of the call. The patched version
calls the original (which writes to pending SAVE_CONFIG) and then also
calls `eddy_cal.load_calibration()` to update `cal_freqs`/`cal_zpos`.

### 4.2 `EDDY_APPLY_TAP_THRESHOLD`

Activates a `tap_threshold` value in RAM after
`PROBE_EDDY_CURRENT_TAP_CALIBRATE TAP=verify`. Reads the value
from the pending SAVE_CONFIG (via
`configfile.get_status().save_config_pending_items`, **not** from
`settings`, which only reflects the boot-time content) and assigns
it directly to `eddy_tap._tap_threshold`.

### 4.3 `EDDY_RESET_TO_CONFIG`

Restores the runtime Eddy state to what was parsed from `printer.cfg`
at boot — the frequency/Z table and the `tap_threshold`. Used at the
start of every print to guarantee a deterministic starting state,
regardless of what manual operations were performed earlier in the
session. Does not reset `tap_z_offset` (immutable from config),
`calibration_temp` (read-only), or `reg_drive_current` (hardware-set
at boot).

## 5. Macros that orchestrate the plugin

### 5.1 `FULL_CALIBRATE`

Located in `macros_calibration.cfg`. Four steps:

1. **`PROBE_EDDY_CURRENT_TAP_CALIBRATE TAP=guess` / `refine` / `verify`**
   then **`EDDY_APPLY_TAP_THRESHOLD`** to make the new threshold
   active. The tap calibration is run **before** the table refresh
   because `TAP=guess` derives its threshold from the slope
   coefficients of the current table; refreshing the table first
   would change those coefficients and break `TAP=guess`.
2. **`SET_Z_FROM_PROBE METHOD=tap SAMPLES=5`** to locate kinematic
   Z=0 by tap impact, with median filtering.
3. **`PROBE_EDDY_CALIBRATE_AUTO`** to rebuild the frequency/Z table
   referenced on the freshly-located Z=0.
4. **`PROBE_ACCURACY_TAP SAMPLES=5`** to validate the result.

### 5.2 `FINAL_TAP_OFFSET`

Run after the final M109 to print temperature. Performs 3 taps and
applies the median as `SET_GCODE_OFFSET Z=` (absolute, not
incremental). Compensates for hotend thermal expansion between
calibration temperature (140 °C) and print temperature.

### 5.3 `EDDY_RESET_TO_CONFIG`

Called as the very first step of the start G-code, ensures we begin
each print from a clean, persisted state.

## 6. SSH installation procedure

The following steps assume:
- Klipper is running on a Creality K1/E5M-class board
- The config directory is `/usr/data/printer_data/config/`
- Klipper sources are at `/usr/data/klipper/`
- You have SSH access as `root`

If your installation differs (e.g. RPi running stock Klippermainline,
config at `~/printer_data/config/`), adjust the paths accordingly.

### 6.1 Install the plugin

```bash
# SSH into the printer
ssh root@<printer-ip>

# Download the plugin into Klipper's extras directory
cd /usr/data/klipper/klippy/extras/
wget https://raw.githubusercontent.com/christianKEL/E5M-CK/refs/heads/main/files/probe_eddy_auto_calibrate.py

# Verify download
ls -la probe_eddy_auto_calibrate.py

# Remove any previously cached .pyc that could shadow the new .py
# (Klipper compiles .py to .pyc; when you replace the .py, the .pyc
#  may still be loaded if its timestamp is newer.)
rm -f probe_eddy_auto_calibrate.pyc __pycache__/probe_eddy_auto_calibrate.*
```

> **Note**: every time you update the plugin (e.g. `wget` a new
> version), repeat the `rm -f` step. This is a common pitfall.

### 6.2 Register the plugin in `printer.cfg`

Add the following section to `/usr/data/printer_data/config/printer.cfg`,
typically near the top with other `[include]` and chip declarations:

```ini
[probe_eddy_auto_calibrate]
chip: btt_eddy
probe_speed: 5.0
z_ref_max: 0.5
```

The `chip` value must match your `[probe_eddy_current <name>]`
section name. `probe_speed` is the Z descend speed during calibration
(mm/s). `z_ref_max` caps the tolerated Z reference position to avoid
running auto-cal from a wrong height (the plugin will refuse to run
if Z > z_ref_max).

### 6.3 Required macro dependencies

The `FULL_CALIBRATE` macro depends on the following helpers, which
must be present in your config:

- **`SET_Z_FROM_PROBE`** (from `eddy.cfg`) — refines Z=0 with median
  filtering.
- **`PROBE_ACCURACY_TAP`** (from `eddy.cfg`) — accuracy validator
  with proper retract between samples (workaround for a Klipper bug
  where `samples_retract_dist=0` is hardcoded for tap method).

Both are provided in the
[`E5M-CK` repository](https://github.com/christianKEL/E5M-CK) under
`files/eddy.cfg`.

The `FULL_CALIBRATE` macro itself, `PREP_COLD`, and `FINAL_TAP_OFFSET`
are in `files/macros_calibration.cfg`.

### 6.4 Restart and verify

```bash
# In Klipper console (Fluidd/Mainsail) or via SSH curl:
FIRMWARE_RESTART
```

Check the boot-time log:

```bash
tail -50 /usr/data/printer_data/logs/klippy.log | grep -i eddy_auto
```

You should see no errors and the three commands should be available.
Test them:

```
EDDY_RESET_TO_CONFIG
```

Should respond with the table point count and the `tap_threshold`
value being applied to RAM.

## 7. Bootstrap state required

`FULL_CALIBRATE` is **not** a from-scratch calibrator. It expects an
already-bootstrapped Eddy probe with:

- `reg_drive_current` set (via `LDC_CALIBRATE_DRIVE_CURRENT`)
- `calibrate = ...` table present (via `PROBE_EDDY_CURRENT_CALIBRATE`)
- `tap_threshold = ...` set (via `PROBE_EDDY_CURRENT_TAP_CALIBRATE`)

These are produced by the standard Klipper bootstrap procedure
documented at https://www.klipper3d.org/Eddy_Probe.html and persisted
in the `#*# SAVE_CONFIG` block at the bottom of `printer.cfg`.

If those values are missing (e.g. fresh repo clone on a new machine),
`FULL_CALIBRATE` step 1 will fail with `insufficient slope delta`
because `TAP=guess` cannot derive a threshold without a calibration
table to read slope coefficients from.

For a from-scratch installation, follow the standard Klipper
procedure first, then use `FULL_CALIBRATE` for ongoing operation.

## 8. Typical start G-code structure

```gcode
EDDY_RESET_TO_CONFIG
SET_GCODE_OFFSET Z=0
BED_MESH_CLEAR

M140 S{first_layer_bed_temperature[0]}
M104 S140
M190 S{first_layer_bed_temperature[0]}
M109 S140

G4 P300000                  ; 5 min heat soak
G28                         ; scan-only Z homing
NOZZLE_CLEAR_ON_BRUSH       ; ends at 140 °C, heater off
M104 S140                   ; re-arm
M109 S140

FULL_CALIBRATE              ; ~4 min
BED_MESH_CALIBRATE METHOD=rapid_scan

NOZZLE_CLEAR_AT_PRINT_TEMP TEMP={first_layer_temperature[0]}
FINAL_TAP_OFFSET

; ... prime line + print ...
```

---

**Reference**: full source and current configuration files are
available at https://github.com/christianKEL/E5M-CK

— christianKEL, project *E5M-CK*
