# Flash mainline Klipper firmware on the main MCU via SWD

Procedure to replace the Creality 2023 stock firmware on the Ender 5 Max
main MCU (GD32F303xE, which is STM32F103-compatible) with mainline Klipper
firmware. Used in the investigation of the `Internal error in stepcompress`
bug — see `docs/research/stepcompress_bug_investigation.md`.

## What this changes

| Before | After |
|---|---|
| Main MCU runs Creality fork firmware `341a2c18-dirty Jul 17 2023` | Main MCU runs mainline Klipper master `4bc56464` built as `MACH_STM32F103` |
| Bootloader present at flash `0x08000000-0x08002FFF` (12K) | **Bootloader erased**, Klipper at `0x08000000` |
| App at `0x08003000`, started via Creality bootloader CRC16 launcher | Klipper started directly at chip reset |
| `S13mcu_update` would re-flash if version mismatches stock label | `S13mcu_update` will detect the version mismatch but cannot re-flash (no bootloader to talk to) — see rollback below |

The Creality nozzle MCU stays untouched. Only the main MCU is modified.

## Safety net

A full SWD dump of the current flash is taken BEFORE any erase. This dump
contains the Creality bootloader + the live app + all factory calibration
data living in flash. It is the **only** way to fully restore the printer to
factory state post-flash, since the bootloader is not redistributable.

## Files in this repo

| File | Purpose |
|---|---|
| `klipper/firmwares/mainline_F103_mcu_72MHz.bin` | The mainline Klipper firmware to flash. Built from Klipper master `4bc56464` with `MACH_STM32F103`, no bootloader, serial on PA2/PA3 @ 230400 baud. MD5: `1E204B315B03F8F9BD128890C6F57972`. |
| `klipper/firmwares/mainline_F103_mcu_72MHz.config` | The exact `.config` used to build it, for reproducibility |
| `klipper/firmwares/F004_mcu0_001_G32-mcu0_005_000.bin` | Creality stock app-only — useful if bootloader is restored separately |
| (Generated during procedure) `klipper/firmwares/F004_main_mcu_full_dump.bin` | The 256K full flash dump taken before any erase — the real rollback artifact |

## Hardware setup

### SWD wiring (5 pins)

The mainboard exposes a 5-pin header labeled `VCC, DIO, CLK, GND, NRST`
(the silkscreen says "DIO" not "SWDIO", and "CLK" not "SWCLK"; the "BIO"
some users read is just a worn-down "DIO").

Connections to ST-Link V2 clone (standard 20-pin connector pinout):

| Mainboard SWD pad | ST-Link V2 pin # | ST-Link V2 signal | Wire color suggestion |
|---|---|---|---|
| VCC | 1 | T_VCC | Red |
| DIO | 7 | SWDIO | Yellow |
| CLK | 9 | SWCLK | Orange |
| GND | 8 (or 4, 6, 12, 14, 16, 18, 20) | GND | Black |
| NRST | 15 | NRST | Blue |

The printer should be **POWERED ON** during SWD operations. The ST-Link
reads VCC from the target to know what voltage to use. Do NOT power the
target through the ST-Link (no jumper to VCC).

## Software setup on the Windows PC

Use **STM32CubeProgrammer** (free from ST, GUI tool) OR **OpenOCD**
command-line.

### Option A — STM32CubeProgrammer (GUI)

1. Install from https://www.st.com/en/development-tools/stm32cubeprog.html
2. Plug ST-Link V2 USB into PC, connect SWD pads
3. Open STM32CubeProgrammer
4. Select "ST-LINK" in the right panel, click "Connect"
5. Target should appear as `STM32F103` family (the chip ID is shared
   between STM32F103 and GD32F303 at the SWD identification level)

### Option B — OpenOCD command line

Install OpenOCD for Windows (e.g. via `winget install openocd` or from
https://openocd.org/).

OpenOCD config for ST-Link V2 + STM32F103 (works for GD32F303xE) :

```cfg
# openocd_main_mcu.cfg
source [find interface/stlink.cfg]
transport select hla_swd
set CHIPNAME stm32f103xe
source [find target/stm32f1x.cfg]
```

## Procedure

### Step 1 — Power off the printer, connect SWD

1. Power OFF the printer. Confirm all LEDs are dark.
2. Connect ST-Link to the mainboard SWD pads (5 wires).
3. Connect ST-Link USB to the PC.
4. Power ON the printer. (ST-Link will read 3.3V on T_VCC = target alive.)

### Step 2 — Dump the current flash (CRITICAL — do not skip)

#### Via STM32CubeProgrammer

1. Connect (button in top-right).
2. Set "Address" = `0x08000000`, "Size" = `0x40000` (256K = 262144 bytes).
3. Click "Read" to read flash, then "Save As..." to save as
   `F004_main_mcu_full_dump.bin`.
4. Copy this file to the repo at
   `klipper/firmwares/F004_main_mcu_full_dump.bin` and compute its MD5
   for the record.

#### Via OpenOCD

```bash
openocd -f openocd_main_mcu.cfg \
        -c "init; halt; dump_image F004_main_mcu_full_dump.bin 0x08000000 0x40000; exit"
```

**Verify the dump:**

The first 4 bytes at offset 0x00 should be the initial stack pointer
(a 32-bit value typically starting with `0x20...` for SRAM addresses).
The first 4 bytes at offset 0x04 are the reset handler (typically
`0x08...0001` for thumb-mode reset).

If the dump file is all 0xFF or all 0x00, the SWD connection failed.

### Step 3 — Flash mainline Klipper firmware

#### Via STM32CubeProgrammer

1. With ST-Link still connected.
2. In "Erasing & Programming" tab, select file
   `mainline_F103_mcu_72MHz.bin`.
3. Set "Start address" = `0x08000000`.
4. Check "Verify programming" and "Run after programming".
5. Click "Start Programming".

#### Via OpenOCD

```bash
openocd -f openocd_main_mcu.cfg \
        -c "init; halt; program mainline_F103_mcu_72MHz.bin verify reset 0x08000000; exit"
```

### Step 4 — Disconnect SWD, restart printer

1. Power OFF the printer.
2. Unplug ST-Link from the SWD pads.
3. Power ON the printer.
4. The main MCU should now boot mainline Klipper directly (no Creality
   bootloader).

### Step 5 — Verify Klipper host connection

```bash
ssh root@192.168.1.94 'awk "!/^Stats /" /usr/data/printer_data/logs/klippy.log | grep "Loaded MCU.*mcu" | tail -3'
```

Expected new output (compared to before) :

```
Loaded MCU 'mcu' XXX commands (v0.13.0-686-g4bc56464f / gcc: ...) 2.42)
                                ^^^^^^^^^^^^^^^^^^^^^ — was 341a2c18-dirty 20230717
MCU 'mcu' config: ADC_MAX=4095 CLOCK_FREQ=72000000 ...
                                          ^^^^^^^^ — was 120000000
```

`STEPPER_STEP_BOTH_EDGE=1` should be present (mainline name, was
`STEPPER_BOTH_EDGE=1` in the old firmware). The
`mcu_deprecation_filter` warning will stop firing.

If Klipper fails to connect — check `klippy.log` for the actual error.
Most likely cause : pin mapping mismatch (the printer.cfg expects pins
that don't exist or map differently on the mainline build). See
"Rollback" below if blocked.

### Step 6 — Run the test print

Launch the same gcode that crashed all 7 times before. Observe:

- If `Internal error in stepcompress` returns → firmware mismatch was
  NOT the cause. Rollback or escalate to upstream.
- If the print completes (or at least runs for many hours without the
  crash) → firmware mismatch WAS the cause. Document for upstream.

## Rollback

If Klipper can't connect, or any issue arises, restore the original
Creality firmware via SWD:

```bash
openocd -f openocd_main_mcu.cfg \
        -c "init; halt; program F004_main_mcu_full_dump.bin verify reset 0x08000000; exit"
```

Or in STM32CubeProgrammer : flash the `F004_main_mcu_full_dump.bin` at
address `0x08000000`.

The printer is now bit-identical to its pre-experiment state, including
the Creality bootloader, the stock app, and any factory calibration
data in flash.

## What's NOT covered by this procedure

- **Nozzle MCU** : stays on Creality stock firmware. Reasoning detailed
  in `docs/research/stepcompress_bug_investigation.md` (it never fired
  `Invalid sequence`, the bug is main-MCU-correlated).
- **Eddy MCU** : already on mainline Klipper firmware (BTT Eddy).
- **`S13mcu_update` script** : will detect the version mismatch (it
  expects `mcu0_005_000` and now sees the mainline version string).
  We have not yet patched it to ignore the main MCU's mismatch. It
  will log a warning at boot but will NOT attempt to re-flash, because
  the Creality bootloader is gone and mcu_util has no path to talk to
  the chip without it.
