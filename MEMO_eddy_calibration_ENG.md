# MEMO — Complete BTT Eddy USB Calibration on Ender 5 Max + Klipper mainline

**Date:** April 28, 2026
**Machine:** Creality Ender 5 Max (CoreXY) + Nebula Pad
**Klipper:** mainline `v0.13.0-628-g373f200ca` (commit March 2026)
**Probe:** BTT Eddy USB (RP2040 + LDC1612) — serial `usb-Klipper_rp2040_50445059303E9B1C-if00`
**Goal:** establish a precise, thermally independent Z=0 reference using Klipper mainline's native **TAP** functionality, and generate accurate hot bed meshes.

---

## 1. Initial context and problem

The stock Ender 5 Max uses a Klipper Creality fork with a proprietary Nebula Pad-based Z calibration. The E5M-CK project aims to migrate to **pure Klipper mainline** + **BTT Eddy USB** sensor to leverage modern features (input shaper, high-density bed mesh, tap).

The mainline `probe_eddy_current` module suffers from significant **thermal drift**: when hot (bed at 65°C, probe coil at 45°C), the LDC1612 sensor frequency drifts and skews the Z measurement.

Three competing sources of truth emerge:

| Method | Z measured (hot) | Thermal sensitivity |
|---|---|---|
| Paper test | 0 (subjective reference, ±0.05mm) | none |
| PROBE scan | +0.010 to +0.030mm | **strong** (drift) |
| **PROBE tap** | **−0.121mm** | **none (theoretical)** |

The ~0.15mm gap between scan and tap demonstrates the magnitude of the thermal problem. Without tap, the bed mesh is incorrect.

---

## 2. Key insights from Klipper PRs

Two PRs clarify the correct strategy on Klipper mainline:

### PR #7186 — `temperature_probe: use tap for calibration` (open)

Opened by nefelim4ag (Klipper collaborator). Would enable `TEMPERATURE_PROBE_CALIBRATE METHOD=tap` to automate sensor thermal calibration. **Not yet merged** at the time of this memo, so unusable directly, but shows the direction taken by developers.

### PR #7179 — `runtime calibration curve adjustment` (closed/wontfix)

Opened by nefelim4ag, closed after PR #7220 was merged adding `tap_z_offset` as a config option. **The author confirms**:

> *"this PR is mostly not necessary, because now the scan curve can be compensated with 1 G-Code Z Offset"*

PR #7179 still provides **the `_ADJ_SCAN_FROM_TAP` and `SET_SCAN_FROM_TAP` macros** which implement the complete **tap-then-scan** pattern: perform a tap for true Z=0, then scan at the same point to dynamically calibrate the bed mesh at actual print temperature.

**Central insight**: tap is the only reliable Z=0 when hot. But bed mesh uses scan mode (at ~0.5mm height). Without correction, scan reads a frequency biased by thermal drift → incorrect mesh. The `SET_SCAN_FROM_TAP` macro computes the difference and applies it via `SET_GCODE_OFFSET`.

### PR #7220 — `tap_z_offset` (merged)

Allows adding a constant offset after tap directly in config:

```ini
[probe_eddy_current btt_eddy]
tap_z_offset: 0.05
```

Direction verified experimentally (see §6): `z_reported = z_actual − tap_z_offset` (positive value makes the reported value more negative).

---

## 3. Final `eddy.cfg` architecture

```ini
[mcu eddy]
serial: /dev/serial/by-id/usb-Klipper_rp2040_50445059303E9B1C-if00
restart_method: command

[temperature_sensor btt_eddy_mcu]
sensor_type: temperature_mcu
sensor_mcu: eddy
min_temp: 10
max_temp: 100

[probe_eddy_current btt_eddy]
sensor_type: ldc1612
descend_z: 0.5
i2c_mcu: eddy
i2c_bus: i2c0f
x_offset: 38.0
y_offset: 6.0
tap_threshold: 50

[temperature_probe btt_eddy]
sensor_type: Generic 3950
sensor_pin: eddy:gpio26
horizontal_move_z: 2

# --- Official Klipper macros ---
[gcode_macro _RELOAD_Z_OFFSET_FROM_PROBE]
gcode:
  {% set Z = printer.toolhead.position.z %}
  SET_KINEMATIC_POSITION Z={Z - printer.probe.last_probe_position.z}

[gcode_macro SET_Z_FROM_PROBE]
description: Refine Z=0 with a probe (use METHOD=tap for thermal-independent reference)
gcode:
  {% set METHOD = params.METHOD | default("automatic") %}
  PROBE METHOD={METHOD}
  _RELOAD_Z_OFFSET_FROM_PROBE
  G0 Z5

# --- Tap-then-scan pattern (from PR #7179) ---
[gcode_macro _ADJ_SCAN_FROM_TAP]
gcode:
  {% set OFFSET = printer.probe.last_probe_position.z %}
  SET_GCODE_OFFSET Z={(-OFFSET)}

[gcode_macro SET_SCAN_FROM_TAP]
description: Tap-then-scan: precise Z + thermally compensated bed mesh reference
gcode:
  SET_Z_FROM_PROBE METHOD=tap
  {% set is_absolute = printer.gcode_move.absolute_coordinates %}
  G90
  {% set cf = printer.configfile.settings %}
  {% set eddy = cf["probe_eddy_current btt_eddy"] %}
  {% set amap = printer.gcode_move.axis_map %}
  {% set tpos = printer.gcode_move.position %}
  G0 Z5 F300
  G0 Y{tpos[amap["Y"]] - eddy.y_offset} X{tpos[amap["X"]] - eddy.x_offset} F3000
  G0 Z{eddy.descend_z} F300
  PROBE METHOD=scan
  _ADJ_SCAN_FROM_TAP
  {% if not is_absolute %}
  G91
  {% endif %}
```

**Important notes on unsupported options**:
- `tap_speed` and `tap_drive_current` do **not** exist as section options in this Klipper version. They are passable only at runtime via `PROBE METHOD=tap TAP_SPEED=5 TAP_DRIVE_CURRENT=16`.
- `tap_z_offset` is valid but ultimately not used (see §6).

---

## 4. `homing.cfg` architecture

```ini
[homing_override]
axes: xyz
set_position_z: 0
gcode:
  G90
  {% set home_all = 'X' not in params and 'Y' not in params and 'Z' not in params %}
  G1 Z30 F600
  {% if home_all or 'X' in params or 'Y' in params %}
    G28 Y
    G1 Y400 F2400
  {% endif %}
  {% if home_all or 'X' in params %}
    G28 X
    G1 X380 F2400
  {% endif %}
  {% if home_all or 'Z' in params %}
    G0 X200 Y200 F6000
    G28 Z                          # rough Z homing via Eddy virtual_endstop
    G1 Z10 F600
    SET_Z_FROM_PROBE METHOD=tap    # precise refinement via TAP
  {% endif %}
```

The initial `G28 Z` performs a fast scan-based homing (virtual_endstop), then `SET_Z_FROM_PROBE METHOD=tap` refines with a precise tap. Result: Z=0 = real physical contact position between nozzle and bed at current temperature.

---

## 5. Complete calibration procedure (chronological)

Strict order, each step produces data needed by the next.

### Step 1 — `LDC_CALIBRATE_DRIVE_CURRENT` calibration (cold, 1 time)

Calibrates the LDC1612 sensor signal amplitude. Low thermal sensitivity, only needs to be done once when cold.

```
G28
G0 X200 Y200 F6000
G1 Z20 F600
LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy
SAVE_CONFIG
```

**Result obtained:** `reg_drive_current = 15`

### Step 2 — Preheat + thermal homogenization

```
M140 S65          ; bed at PLA print temperature
M104 S150         ; nozzle hot but no oozing (Arksine recommendation)
TEMPERATURE_WAIT SENSOR=heater_bed MINIMUM=64
TEMPERATURE_WAIT SENSOR=extruder MINIMUM=148
G4 P30000         ; 30s homogenization
```

### Step 3 — Height map calibration (hot)

```
G1 X200 Y200 F6000
G1 Z30 F600
SET_KINEMATIC_POSITION Z=200    ; trick to enable manual Z movements
```

Manual paper test via Z arrows (0.1mm step), then:

```
SET_KINEMATIC_POSITION Z=0
G1 Z1 F300
PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy
```

Follow interactive prompts `TESTZ Z=-0.1` / `ACCEPT`. Klipper sweeps for ~3 minutes.

```
SAVE_CONFIG
```

**Result obtained (hot calibration):**

```
Calibration temp:    45.53°C
Total freq range:    47268.777 Hz
Global MAD_Hz:       17.612
Per-Z noise:
  z=0.250:  MAD_Hz = 25.370
  z=0.530:  MAD_Hz = 24.114
  z=1.010:  MAD_Hz = 26.179
  z=2.010:  MAD_Hz =  9.242
  z=3.010:  MAD_Hz = 11.083
```

**Important observation**: noise is ~2× higher near the bed (z<1mm) than far from it (z>2mm). Expected — mechanical vibrations affect inductance.

### Step 4 — `tap_threshold` calibration

The `tap_threshold` determines contact detection sensitivity during tap.

**Official Klipper method**:
- Initial estimate: `tap_threshold = MAD_Hz_global × 2 = 17.6 × 2 ≈ 35`
- But since noise is higher near the bed (actual tap zone), prefer `MAD_Hz_zone × 2 = 25.2 × 2 ≈ 50`
- Refinement by **bracketing**: start high (safety), decrement in steps

**Bracketing performed**:

| Threshold | Behavior |
|---|---|
| 25 | No detection (under noise floor) |
| 26 | Detection at z=−0.083 (lower limit) |
| 50 | Stable detection at z≈−0.121 |

→ The rule of thumb **2× the lower limit** (= 26 × 2 = 52) confirms `tap_threshold = 50` as a good compromise.

### Step 5 — `PROBE_ACCURACY METHOD=tap` validation

```
G28
G1 X200 Y200 F6000
G1 Z10 F600
SET_KINEMATIC_POSITION X=200 Y=200 Z=10
G0 Z5
PROBE_ACCURACY METHOD=tap
```

**Result obtained (hot, threshold=50)**:

```
range:     0.0089 mm   (Klipper doc target: <0.020 mm)  ← 2× better than required
stddev:    0.0031 mm
average:  -0.1213 mm   (stable offset vs paper test)
samples:   10
```

**Verdict**: excellent precision. Machine taps with ±5 microns repeatability.

### Step 6 — Thermally compensated bed mesh test

```
G28
G1 X200 Y200 F6000
SET_SCAN_FROM_TAP
```

**Observed result**:
```
probe: at 161.997,193.999 bed will contact at z=0.023446    ← TAP at target point (corrected via x_offset/y_offset)
Result: at 161.995,193.999 estimate contact at z=0.052404   ← SCAN at same point
```

The macro automatically applied `SET_GCODE_OFFSET Z=-0.052` to compensate the tap↔scan difference. Subsequent bed mesh in scan mode is therefore thermally correct.

---

## 6. Final decision on `tap_z_offset`

The systematic offset of **−0.121mm** (hot, coil cal at 47°C) then **−0.113mm** (coil at 53°C) means tap detects contact ~0.1 to 0.12mm **below** the Z=0 defined by paper test.

**Three hypotheses**:

1. Paper test too high (paper thickness ~0.1mm + subjective feel)
2. Mechanical compression under tap (~0.02-0.05mm)
3. Combination of both

**Test of `tap_z_offset` direction**:

With `tap_z_offset: 0.100`, successive measurements:

```
Without offset: z = -0.121 (reference)
With offset:    z = -0.213 (shift of -0.092 ≈ -0.100)
```

**Conclusion**: positive `tap_z_offset` **makes the reported value more negative**. Formula: `z_reported = z_actual − tap_z_offset`.

**Final decision: DO NOT use `tap_z_offset`**. Tap becomes the **true physical Z=0 reference**. Consequences:
- Machine will print **0.1mm lower** than what paper test produced
- First layer will be more squished than before
- Compensation to apply in Orca via `SET_GCODE_OFFSET Z=+0.05` or `Z=+0.10` per preference

**Experimental validation**: `G1 Z0` after `G28` strongly squishes the paper — confirms tap is more precise than paper test, which was systematically ~0.1mm too high.

---

## 7. Stepcompress Klipper bug and O'Connor fix

**Symptom**: crash after ~2h47 of printing with:

```
Error in syncemitter 'stepper_x' step generation
stepcompress o=5 i=-1034346 c=1 a=0: Invalid sequence
mcu.error: Internal error in stepcompress
```

**Root cause**: overly aggressive "step on both edges" optimization in recent Klipper mainline (commits around `b7c243db`, April 2025).

**Kevin O'Connor's fix** (Klipper creator, source: [Discourse #23304](https://klipper.discourse.group/t/issues-with-stepper-drift-on-latest-klipper/23304)):

> *"set `step_pulse_duration: 0.000000501` in all stepper config sections (the 501ns is just enough to turn off "step on both edges" optimization)"*

**Application**: added to `[stepper_x]`, `[stepper_y]`, `[stepper_z]`, `[extruder]`:

```ini
step_pulse_duration: 0.000000501
```

**Effect**: ~0.4µs more per step, theoretical max speed drops by ~5% (negligible in normal use), but step generation becomes robust to rapid parameter changes.

**Important note**: Orca with `gcode_flavor = klipper` generates ~35k `SET_VELOCITY_LIMIT` commands on a 2h print. With `gcode_flavor = marlin (Legacy)` it's ~80k `M204 + M205`. The stepcompress bug is sensitive to command frequency. The `step_pulse_duration: 501ns` solution makes Klipper tolerant regardless of command count — the problem is solved firmware-side, not slicer-side.

---

## 8. Bed mesh: final configuration

```ini
[bed_mesh]
horizontal_move_z: 2
scan_overshoot: 8
speed: 200
mesh_min: 46.0, 15.0
mesh_max: 391.0, 386.0
probe_count: 25, 25
fade_start: 1.0
fade_end: 20
fade_target: 0
mesh_pps: 4, 4
algorithm: bicubic
bicubic_tension: 0.2
```

**`horizontal_move_z = 2` choice**: protects against collisions in case of bed warp or object on the plate. PR #7179 docs recommend 0.5mm for max precision, but 2mm is an acceptable safety compromise. The `SET_SCAN_FROM_TAP` compensation remains partially valid at 2mm (thermal drift at 2mm differs from at 0.5mm, but tap remains the absolute Z=0 reference).

**`mesh_min/max` choice**: computed to respect the official Klipper formula:
- `mesh_min_x = max(15, x_offset + scan_overshoot) = max(15, 38 + 8) = 46`
- `mesh_min_y = max(15, y_offset + scan_overshoot) = max(15, 6 + 8) = 15`
- `mesh_max_x = bed_max - scan_overshoot - margin = 400 - 8 - 1 = 391`
- `mesh_max_y = bed_max - scan_overshoot - margin = 400 - 8 - 6 = 386`

---

## 9. NOZZLE_CLEAR_ON_BRUSH macro (consistency with tap)

**Why essential**: a plastic blob at the nozzle tip completely skews the tap measurement (the sensor detects contact with the blob, not with the actual nozzle).

**4-phase architecture**:
1. Brush at 180°C (5 zigzag passes) — extract fluid plastic
2. **Active cooldown**: continuous zigzag passes + part fans at 100% during 180→140°C descent
3. Stabilization `M109 S140` (fans off)
4. Final brush at 140°C (5 passes) — finish with solid plastic

**Active cooldown advantages**:
- More effective: plastic passes through semi-solid phase (160°C) where it tears off better
- Faster: ~50s total instead of ~60-65s with static cooldown
- Guarantees nozzle perfectly clean at 140°C — ideal temperature for tap (no oozing)

**Important about Creality fans**:
- Stock Ender 5 Max uses `[output_pin fan0]` and `[output_pin fan1]` (PWM via `SET_PIN`), not the standard Klipper `[fan]`
- `scale: 255` in config — so use `VALUE=255` for 100%, **not** `VALUE=1.0`
- Alternative: `M106 S255` (the custom macro in `gcode_macro.cfg` redirects to both fans)

---

## 10. Final Orca start G-code

```gcode
; ═══════════════════════════════════════════════════════════
; E5M-CK Start G-code — TAP-based Z reference + clean nozzle
; ═══════════════════════════════════════════════════════════

; --- Reset state ---
PRINT_FLAG_CLEAR
BED_MESH_CLEAR
G92 E0
M220 S100
M221 S100

; --- Heat bed first ---
M140 S{first_layer_bed_temperature[0]}
M190 S{first_layer_bed_temperature[0]}
G4 P300000                                         ; 5min thermal homogenization

; --- Pre-heat nozzle just enough to clean ---
M104 S140                                          ; raised to 180 by NOZZLE_CLEAR_ON_BRUSH

; --- Initial home (uses TAP refinement automatically) ---
G28

; --- Clean nozzle on brush, ends at 140°C ---
NOZZLE_CLEAR_ON_BRUSH

; --- Re-home Z with clean nozzle for accurate tap ---
G1 X200 Y200 F6000
G1 Z25 F600
SET_Z_FROM_PROBE METHOD=tap

; --- Bed mesh (thermally compensated via tap-then-scan) ---
G1 Z25 F600
SET_SCAN_FROM_TAP
BED_MESH_CALIBRATE METHOD=rapid_scan

; --- Final nozzle heat to print temperature ---
M104 S{first_layer_temperature[0]}
M109 S{first_layer_temperature[0]}

; --- Optional first-layer Z compensation (tune if needed) ---
; SET_GCODE_OFFSET Z=0.05 MOVE=1

; --- Prime line ---
G92 E0
G1 Z2.0 F3000
G1 X-1.0 Y120 Z0.28 F5000.0
G1 X-1.0 Y245.0 Z0.28 F1500.0 E7
G1 X-0.6 Y245.0 Z0.28 F5000.0
G1 X-0.6 Y120 Z0.28 F1500.0 E15
G92 E0
G1 E-1.0000 F1800
G1 Z2.0 F3000
G1 E0.0000 F1800
```

**Chronological sequence**:
1. Bed at temp → 5min homogenization
2. Nozzle at 140°C → G28 (with tap during, possibly with slightly dirty nozzle)
3. NOZZLE_CLEAR_ON_BRUSH → clean nozzle at 140°C
4. Final clean tap → precise Z=0
5. SET_SCAN_FROM_TAP → computes scan↔tap thermal offset
6. BED_MESH_CALIBRATE rapid_scan → thermally compensated mesh
7. Final nozzle heat to print temp
8. Prime line + printing

---

## 11. Watch-outs and golden rules

### Key takeaways
1. **Tap is the only reliable Z=0 reference when hot.** Scan drifts thermally, paper test is subjective.
2. **Always tap with a clean nozzle.** Otherwise measurement is skewed.
3. **Tap with nozzle at 140°C.** Not hotter (oozing), not colder (dried filament can cause false contact).
4. **`tap_threshold` is calibrated by bracketing**: 2× the lower detection limit is a good starting point.
5. **`PROBE_ACCURACY METHOD=tap` should give range < 0.02mm** (Klipper doc target). If higher, threshold needs adjustment.
6. **`step_pulse_duration: 0.000000501` is mandatory** on recent Klipper mainline to avoid stepcompress crashes.

### Known pitfalls
- `tap_speed` and `tap_drive_current` are **not** section options, only runtime parameters of `PROBE METHOD=tap`.
- `tap_z_offset` acts in the counterintuitive direction (positive → reported value more negative).
- Creality fans have `scale: 255`, so `SET_PIN VALUE=255` for 100% (not 1.0).
- Eddy USB can freeze after MCU crash — full power cycle of the printer fixes it.
- Klipper stuck at init `mcu 'eddy': Starting serial connect` with burst of `webhooks shakehands` = Eddy not responding → unplug/replug USB cable or power cycle.

### Workflow best practices
- **drive_current calibration**: 1 time when cold, never to redo
- **Height map calibration**: 1 time **when hot** (typical print temperature), redo if plate/nozzle/thermal config changes
- **`tap_threshold` calibration**: 1 time after height map calibration, redo if probe noise changes significantly
- **Hot bed mesh before each print**: automatic via `SET_SCAN_FROM_TAP + BED_MESH_CALIBRATE METHOD=rapid_scan ADAPTIVE=1` in start G-code

---

## 12. Validated final state

| Element | Value |
|---|---|
| `reg_drive_current` | 15 |
| Temp probe calibration | 45.53°C |
| Global MAD_Hz (hot) | 17.612 |
| **`tap_threshold`** | **50** |
| `tap_z_offset` | not used (tap = true Z=0 reference) |
| PROBE_ACCURACY tap range | 0.0089mm |
| PROBE_ACCURACY tap stddev | 0.0031mm |
| Tap vs paper test offset | -0.113mm (paper test too high) |
| `step_pulse_duration` | 0.000000501 (501ns) on all steppers |
| Input shaper X | zv 50.6 Hz |
| Input shaper Y | mzv 41.8 Hz |
| Bed mesh | 25×25, scan_overshoot=8, mesh_min=46/15, mesh_max=391/386 |

**Validation date:** April 28, 2026
**Validation:** PROBE_ACCURACY METHOD=tap → range 0.009mm < target 0.020mm ✅

---

## References

- Official Klipper Eddy documentation: https://www.klipper3d.org/Eddy_Probe.html
- PR #7186 (open): `temperature_probe: use tap for calibration`
- PR #7179 (closed): `runtime calibration curve adjustment` — provides SET_SCAN_FROM_TAP pattern
- PR #7220 (merged): adds `tap_z_offset` config option
- Discourse Klipper #23304: O'Connor's recommendation `step_pulse_duration: 0.000000501`
