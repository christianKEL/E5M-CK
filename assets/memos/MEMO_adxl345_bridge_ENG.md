# TECHNICAL MEMO — ADXL345 Bridge

## Klipper mainline + Creality nozzle MCU 2023 firmware

**Author:** Christian KELHETTER
**Project:** E5M-CK — https://github.com/christianKEL/E5M-CK
**Date:** May 2026

---

## 1. Context and problem statement

### 1.1 The hardware

The Ender 5 Max printer ships with two MCUs:

- **Mainboard MCU** (`mcu`): Creality CR4NS200323C10, GD32F303RET6, on `/dev/ttyS1`. Runs Klipper-compatible firmware that has been successfully ported to mainline.
- **Nozzle MCU** (`nozzle_mcu`): Creality CR-NOZZLE_V21, GD32F303CBT6, on `/dev/ttyS7`. Runs a **Creality 2023 firmware build** (`341a2c18-dirty-20230717_152940-cxsw`). This firmware drives the hotend heater, the part fans, the filament sensor, and **the embedded ADXL345 accelerometer**.

The nozzle MCU firmware is **not flashable** through the standard Klipper mainline `make flash` workflow without significant rework: the bootloader signature, build environment, and pin map are Creality-specific. Replacing it would be possible but risky — the nozzle MCU controls the heater, and a bad flash bricks the toolhead.

**Therefore the nozzle MCU must keep running its 2023 Creality firmware** while the rest of the system runs Klipper mainline 2026.

### 1.2 The protocol mismatch

When Klipper mainline 2026 talks to the nozzle MCU, low-level commands like motor steps and heater PWM work fine: those signatures haven't changed in years. However, the **ADXL345 sensor protocol** has diverged significantly between the Creality 2023 fork and Klipper mainline.

Symptoms when trying to use a stock `[adxl345]` config block with the Creality nozzle MCU:

```
Got error -1 in adxl345 query_status: cmd query_adxl345 unknown
```

or:

```
Unknown adxl345_data sequence
```

Klipper mainline issues a different `query_adxl345` command than what the 2023 firmware understands, and parses the bulk data response differently.

### 1.3 What `accel_chip_proxy` is

The Creality fork of Klipper ships a custom Python module called `accel_chip_proxy.py` (in `/usr/share/klipper/klippy/extras/`). This module is the glue between the Creality `[accel_chip_proxy]` config section and the Creality firmware ADXL345 driver. It does:

1. Listens for the legacy Creality `klippy:mcu_identified` event.
2. When that event fires, dynamically constructs an ADXL345 chip object using the Creality fork's `ADXL345Creality` class (also custom).
3. Registers the chip as an accelerometer and exposes the standard accelerometer API (`start_internal_client`, `read_reg`, `set_reg`, `last_query_time`).

When the user installs Klipper mainline (which has its own, modern `adxl345.py` and no `accel_chip_proxy` whatsoever), `[accel_chip_proxy]` configs become unrecognized and ADXL345 functionality is lost.

---

## 2. Investigation — what differs between Creality 2023 and Klipper mainline

This is the most useful part of the memo: the precise wire-level differences. Knowing them is what made the bridge possible.

### 2.1 `query_adxl345` command signature

**Creality 2023 firmware (`/usr/data/klipper/src/sensor_adxl345.c`):**

```c
DECL_COMMAND(command_query_adxl345,
             "query_adxl345 oid=%c clock=%u rest_ticks=%u");
```

Three parameters: `oid`, `clock`, `rest_ticks`.

**Klipper mainline:**

```c
DECL_COMMAND(command_query_adxl345,
             "query_adxl345 oid=%c rest_ticks=%u");
```

Two parameters: `oid`, `rest_ticks`. The `clock` parameter has been removed.

A mainline `[adxl345]` driver issuing the 2-parameter form is rejected by the Creality firmware as "unknown command".

### 2.2 `adxl345_data` response format

**Creality 2023 firmware** sends bulk samples packed **5 bytes per sample**:

- Each batch: `oid(1) + sequence(2) + samples(N×5)`
- Sample bit-packing (per `_extract_samples` in the Creality `adxl345.py`):

```python
xlow  = msg[0]
ylow  = msg[2]
zlow  = msg[4]
xzhigh = msg[6]
xhigh  = (msg[1] & 0x1f) | ((xzhigh & 0xe0) << 0)
yhigh  = (msg[3] & 0x1f) | ((xzhigh << 5) & 0xe0)
zhigh  = (msg[5] & 0x1f) | ((xzhigh << 2) & 0x60)   # 2 bits only
```

**Critical:** `zhigh` only takes **2 bits** from `xzhigh`, masked with `0x60`, NOT `0xe0`. This is non-obvious. If you assume symmetry with X and Y and apply `0xe0`, the Z axis values are wrong.

**Klipper mainline** uses a different layout (FixedFreqReader + BatchBulkHelper, 6 bytes per sample, no bit-packing). It can't decode the Creality format and vice versa.

### 2.3 API hooks

**Creality 2023 fork:** uses an `klippy:mcu_identified` event that fires once per MCU. This is custom — not present in mainline.

**Klipper mainline:** uses `register_config_callback()` on the MCU object, fired during config parsing. Different timing, different signature.

**Implication:** any code that hooks into `klippy:mcu_identified` (such as the original `accel_chip_proxy.py`) silently does nothing on mainline. The chip is never instantiated.

### 2.4 `mcu.register_response` location

**Creality 2023 fork:** `mcu.register_response(...)` directly on the MCU object.

**Klipper mainline 2026:** `mcu._serial.register_response(...)`. The method moved one level deeper as part of an internal refactor.

A direct copy of the Creality `ADXL345Creality` class will fail with:

```
AttributeError: 'MCU' object has no attribute 'register_response'
```

at the moment it tries to register its bulk data callback.

### 2.5 SPI — software bus

Creality 2023 uses a software SPI implementation (bit-banging on GPIOs). The pins on the Ender 5 Max nozzle MCU are:

- `cs_pin = nozzle_mcu:PA4`
- `clock_pin = nozzle_mcu:PA5`
- `mosi_pin = nozzle_mcu:PA7`
- `miso_pin = nozzle_mcu:PA6`
- `spi_speed = 5000000`

The Klipper mainline `[adxl345]` driver will refuse software SPI on Creality firmware because the MCU command name has changed (`config_software_spi` → `spi_set_software_bus` deprecation warning, but functional). The code path through the bridge has to call the firmware command Creality understands.

### 2.6 Sample rate ceiling

Klipper mainline default is `rate: 3200 Hz`. The Creality 2023 firmware MCU **cannot sustain 3200 Hz** during a TEST_RESONANCES sweep — the host scheduler reports `Stepper too far in past` because the bulk data flood saturates the UART link.

**Empirically determined ceiling: `adxl345_rate: 1600`.** At 1600 Hz, the link is stable and TEST_RESONANCES completes cleanly. SHAPER_CALIBRATE works at 1600 Hz with no measurable accuracy loss.

---

## 3. Solution — the bridge

### 3.1 Design

Two Python files, dropped into `klippy/extras/`:

1. **`adxl345_creality.py`** (~415 lines): a port of the Creality `ADXL345` class.
   - Reuses Klipper mainline `AccelCommandHelper` and `AccelQueryHelper` (no need to reinvent the standard accelerometer machinery).
   - Keeps the **hardware logic intact** from Creality: software SPI handshake, ClockSyncRegression, `_extract_samples` with the correct `0x60` mask for Z high bits.
   - Replaces the **transport layer** with `bulk_sensor.BatchBulkHelper`, which is the modern equivalent of the deprecated `motion_report.APIDumpHelper`.
   - Uses `mcu._serial.register_response(...)` for the data callback (the new location).
   - Provides two classes: `ADXL345Creality` and `LIS2DWCreality`. Both default to `register_commands=False`, so they don't conflict with potential mainline `[adxl345]` registration.

2. **`accel_chip_proxy.py`** (~120 lines): a **drop-in replacement** for the Creality stock proxy.
   - Same `[accel_chip_proxy]` config section name — slicer scripts and existing `printer.cfg` blocks don't need changes.
   - Instantiates `ADXL345Creality` directly during `__init__` (no event handler — it just runs immediately at config load).
   - Exposes the accelerometer API by direct delegation: `start_internal_client`, `read_reg`, `set_reg`, `last_query_time`.
   - Provides a small `_ConfigWrapperProxy` that re-prefixes options (`cs_pin` → `adxl345_cs_pin`) so the existing Creality config style is preserved without breaking the underlying ADXL345Creality class.

### 3.2 Why two files

Single-file approaches were tried first but ran into config-parsing collisions: the moment the proxy registered a chip with the same name, Klipper mainline complained `Accelerometer with name 'X' already defined`. The two-file split lets the inner ADXL345 class register without naming conflict (`register_commands=False`), and the outer proxy presents the stable name to the rest of Klipper.

### 3.3 Configuration block (in `printer.cfg`)

```ini
[accel_chip_proxy]
accel_use_chip: adxl345
adxl345_cs_pin: nozzle_mcu:PA4
adxl345_spi_speed: 5000000
adxl345_spi_software_sclk_pin: nozzle_mcu:PA5
adxl345_spi_software_mosi_pin: nozzle_mcu:PA7
adxl345_spi_software_miso_pin: nozzle_mcu:PA6
adxl345_axes_map: x,-z,y
adxl345_rate: 1600

# Same block duplicated for lis2dw if present (omitted here).

[resonance_tester]
accel_chip: accel_chip_proxy
probe_points: 200, 200, 10
accel_per_hz: 50
```

**Notes:**

- `axes_map: x,-z,y` is specific to the Ender 5 Max accelerometer mounting orientation. Other printers will have different maps.
- `accel_per_hz: 50` (lower than the 75 default) reduces excitation amplitude. Helpful on a heavy Ender 5 Max gantry.

### 3.4 Acceptable raw-output anomaly

When idle, the bridge reports static gravity vectors that are **wrong in absolute terms**:

```
ACCELEROMETER_QUERY
Recv: // accel_chip_proxy values: x=-32700 y=-11360 z=-9230 (magnitude 3.66g)
```

Expected magnitude at rest = 1.000g. Observed = 3.66g. The cause is unclear (possibly a sign-extension bug in the Creality 5-byte unpacking that we didn't fix because it doesn't matter for our use case).

**This is acceptable.** SHAPER_CALIBRATE and TEST_RESONANCES operate on the **dynamics** (deltas), not the absolute values. The frequency response curves are correct, the recommended shapers match a manual calibration, and the printed parts confirm.

---

## 4. Installer — `install_adxl_patch_v2.sh`

### 4.1 Distribution model

Installer hosted on GitHub Raw to enable one-line install on the printer:

```sh
sh -c "$(wget --no-check-certificate -qO - \
  https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh)" \
  install
```

The two `.py` files are also fetched from raw.githubusercontent during install.

### 4.2 Subcommands

- `install` — fresh install (idempotent — won't break a system that's already patched).
- `update` — fetch latest `.py` files and reinstall.
- `uninstall` — restore from backup.
- `status` — report what's currently installed.
- `help` — usage.

### 4.3 What it does

1. Verifies prerequisites: Klipper mainline path (`/usr/data/klipper/klippy/extras`), Python version, write permissions.
2. Downloads `adxl345_creality.py` and `accel_chip_proxy.py` from GitHub Raw to `/tmp`.
3. Validates each file with `python -m py_compile` (catches transport corruption).
4. Backs up `printer.cfg` to `printer.cfg.bak.adxl345-creality`.
5. Detects whether the bridge config block is already present (markers `# >>> adxl345-creality-bridge >>>` / `# <<< ... <<<`).
6. **Inserts the bridge block in `printer.cfg`** (this is the tricky part — see 4.4).
7. Copies the `.py` files to `/usr/data/klipper/klippy/extras/`.
8. Optionally restarts Klipper.

### 4.4 The `printer.cfg` insertion bug — and the fix

**Initial bug:** the installer appended the bridge block at the **end** of `printer.cfg`. This put the block **after** the auto-generated `#*# SAVE_CONFIG` section. Klipper rejected the file at restart with:

```
Section 'accel_chip_proxy' not in '#*#' SAVE_CONFIG marker; or possibly malformed file
```

**Fix:** detect the start of the SAVE_CONFIG block and insert **before** it.

```sh
# Find first line starting with '#*#' (SAVE_CONFIG block start)
SAVE_CONFIG_LINE=$(grep -n '^#\*#' "$PRINTER_CFG" | head -1 | cut -d: -f1)

if [ -n "$SAVE_CONFIG_LINE" ]; then
    # Insert before line $SAVE_CONFIG_LINE
    head -n $((SAVE_CONFIG_LINE - 1)) "$PRINTER_CFG" > "$PRINTER_CFG.tmp"
    cat "$BRIDGE_BLOCK" >> "$PRINTER_CFG.tmp"
    tail -n +$SAVE_CONFIG_LINE "$PRINTER_CFG" >> "$PRINTER_CFG.tmp"
    mv "$PRINTER_CFG.tmp" "$PRINTER_CFG"
else
    # No SAVE_CONFIG block yet — safe to append
    cat "$BRIDGE_BLOCK" >> "$PRINTER_CFG"
fi
```

This is the same trick a Klipper SAVE_CONFIG uses internally. The block markers (`# >>> adxl345-creality-bridge >>>`) are left in place so future runs of the installer can detect "already installed" and skip.

---

## 5. Validation procedure

### 5.1 Health check

```bash
# Klipper started cleanly?
curl -s http://localhost:7125/printer/info | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['result']['state'])"
# Expected: ready

# Chip is registered?
echo "ACCELEROMETER_QUERY" | <send via Fluidd console>
# Expected: live X/Y/Z values (any magnitude — see §3.4)

# Noise floor?
echo "MEASURE_AXES_NOISE" | <send via Fluidd console>
# Expected: noise values in 1-100 range; > 1000 indicates a real issue
```

### 5.2 Calibration test

```
SHAPER_CALIBRATE
```

Successful output ends with something like:

```
Recommended shaper_type_x = mzv, shaper_freq_x = 50.8 Hz
Recommended shaper_type_y = mzv, shaper_freq_y = 40.0 Hz
```

Apply via:

```ini
[input_shaper]
shaper_type_x: mzv
shaper_freq_x: 50.8
shaper_type_y: mzv
shaper_freq_y: 40.0
```

Then `SAVE_CONFIG` (or edit by hand and `FIRMWARE_RESTART`).

### 5.3 Belt test (CoreXY only)

```
TEST_RESONANCES AXIS=1,1 OUTPUT=raw_data
TEST_RESONANCES AXIS=1,-1 OUTPUT=raw_data
```

Generates two CSVs in `/tmp`. Used by the GuppyScreen Belts function — see the separate `MEMO_guppyscreen_belts_ENG.md`.

---

## 6. Failure modes encountered (and resolved)

The route to a working bridge passed through several failures. Documenting them avoids repeating them.

| Symptom | Root cause | Fix |
|---|---|---|
| `'accel_chip_proxy' is not an accelerometer` | Proxy didn't expose `start_internal_client` | Added direct delegation methods |
| `Accelerometer with name 'accel_chip_proxy' already defined` | Inner chip was registering with the same name as outer proxy | Added `register_commands=False` flag on inner chip |
| `MCU already configured` | Inner chip instantiated too early (during another callback) | Moved instantiation to `__init__` of the proxy via `register_config_callback` |
| `'MCU' object has no attribute 'register_response'` | API moved in mainline | Use `mcu._serial.register_response` |
| `Stepper too far in past` during TEST_RESONANCES | UART link saturation at 3200 Hz | Set `adxl345_rate: 1600` |
| `Section 'accel_chip_proxy' not in '#*#' SAVE_CONFIG marker` | Installer appended config to end of file, after SAVE_CONFIG | Insert before SAVE_CONFIG line |
| Z values wildly wrong | Wrong mask `0xe0` instead of `0x60` for Z high bits | Apply correct mask in `_extract_samples` |

---

## 7. Limits of the bridge

### 7.1 What works

- `ACCELEROMETER_QUERY` (returns values, magnitudes wrong but readable)
- `MEASURE_AXES_NOISE`
- `TEST_RESONANCES AXIS=X|Y|Z`
- `TEST_RESONANCES AXIS=1,1` and `AXIS=1,-1` (CoreXY belt tests)
- `SHAPER_CALIBRATE`
- `ACCELEROMETER_MEASURE` (raw data dump)

### 7.2 What doesn't work

- Absolute gravity-vector measurements (see §3.4) — not used by anything important
- Fast scan modes (resonance auto-tuning at maximum frequencies) — limited by `adxl345_rate: 1600`

### 7.3 Failure modes that would require a re-port

- Future Klipper mainline refactor of `bulk_sensor.BatchBulkHelper` API
- Creality firmware update to the nozzle MCU (would change wire format again)

The bridge is therefore a **frozen-in-time** solution. It's tied to:

- Klipper mainline ~v0.13.0-628 (and presumably nearby commits — the `bulk_sensor` API stable around this point)
- Creality nozzle firmware `341a2c18-dirty-20230717_152940-cxsw`

If either side moves significantly, the bridge needs to be re-tested and possibly re-ported.

---

## 8. Repository layout

```
E5M-CK/
├── files/
│   ├── adxl345_creality.py
│   └── accel_chip_proxy.py
├── installs/
│   └── install_adxl_patch_v2.sh
└── docs/
    ├── MEMO_c_helper_ENG.md
    └── MEMO_adxl345_bridge_ENG.md   ← this file
```

URLs (raw):

- `https://raw.githubusercontent.com/christianKEL/E5M-CK/main/files/adxl345_creality.py`
- `https://raw.githubusercontent.com/christianKEL/E5M-CK/main/files/accel_chip_proxy.py`
- `https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh`

---

## 9. Recap — minimum commands

### 9.1 Install on a fresh system

```bash
sh -c "$(wget --no-check-certificate -qO - \
  https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh)" \
  install

/etc/init.d/S55klipper_service restart
```

### 9.2 Uninstall

```bash
sh -c "$(wget --no-check-certificate -qO - \
  https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_adxl_patch_v2.sh)" \
  uninstall

/etc/init.d/S55klipper_service restart
```

### 9.3 Validate

```bash
curl -s http://localhost:7125/printer/info | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['result']['state'])"
# Expected: ready
```

Then from Fluidd console:

```
ACCELEROMETER_QUERY
SHAPER_CALIBRATE
```

---

*Document written in May 2026 as part of the E5M-CK project. Companion to `MEMO_c_helper_ENG.md` and `MEMO_guppyscreen_belts_ENG.md`.*
