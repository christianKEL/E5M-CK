# Bed MCU (leveling_mcu) porting — research log

**Status**: Work In Progress / experimental. Not a production process.

## Hardware

- Chip: **GD32E230F8P6TR** (Cortex-M23, 64 KB flash, 8 KB SRAM, TSSOP-20)
- Confirmed visually by operator + identified by Klipper's MCU info from mainline host
- 4× HX711 strain gauges read in parallel by this MCU via custom sync (`pres_swap_pin: leveling_mcu:PB1`)
- Connected to main MCU via `/dev/ttyS6` @ stock 230400 baud (cryoz build uses 921600)
- PCB silkscreen says "K1" → Creality reuses the bed PCB across K1 / CR-10 SE / Ender 5 Max (F004) families

## What Creality does on F004

- Stock chip identifies as `bed0_110_G21-bed0_004_000` (HW 1.10, FW 0.04)
- Creality **does not ship the bed firmware** in any OTA package (verified 4 versions: V1.2.0.09, 10, 20, 21 — only the K1-board variant bins are present, in `/usr/share/klipper/fw/K1/`)
- `S13mcu_update` did NOT handshake `bed0` in stock F004 case (we patched it to do so)
- bed MCU is factory-burned, never updated by Creality on this model family

## Bootloader behavior (empirically determined)

- Creality custom serial bootloader resides in flash at `0x08000000-0x08002FFF` (12 KB region, protected)
- Application region starts at `CONFIG_FLASH_APPLICATION_ADDRESS = 0x08003000`
- Bootloader responds to `mcu_util -c` (handshake), `-g` (get version), `-u -f <bin>` (flash), `-s` (startup app)
- After power-cycle the bootloader window is open for `mcu_util` commands until `-s` is called (then app runs)
- **Tried and failed flashes** :
  - K1 stock `bed0_110_G21-bed0_003_000.bin` (42 KB, with `prtouch_v2_compile.c`) → flash writes (10s elapsed), but `start_app` times out (state=12). Chip stays in bootloader. App region's version label region erased — `get_version` now reports `bed0_110_G21-000000000000` until a successful flash overwrites it.
  - K1 stock label-patched to `bed0_005_000` (single byte patch at offset 0x207) → identical failure. Disproves the "label-only" hypothesis: K1 stock's code itself doesn't initialize on our E5M board.

## Build pipeline (cryoz fork)

We build from the cryoz K1_Series_Klipper fork because :

1. Mainline Klipper has **no GD32E230 / Cortex-M23 support** (verified — no `src/gd32/` directory, no `MACH_GD32` Kconfig)
2. The cryoz fork uses `sensor_hx71x.c` (mainline-style) **instead of** the legacy `prtouch_v2_compile.c` — so the resulting firmware is closer to mainline philosophy than CrealityOfficial's K1 fork
3. The chip-support code in `src/gd32/` is essentially BSP (datasheet-mechanical, not innovation) — `gd32e23x.c` (202 lines), `gd32e23x_gpio.c` (311 lines), `gd32e23x_timer.c` (154 lines), shared `serial.c` (188 lines), etc.

**Build instructions** (in a GitHub Codespace or any Linux env with `arm-none-eabi-gcc-13` available):

```bash
git clone --depth 1 https://github.com/cryoz/K1_Series_Klipper /tmp/K1klipper
cd /tmp/K1klipper
cp .config.bed .config
sed -i 's/CONFIG_MCU_BOARD_FW_VER=004/CONFIG_MCU_BOARD_FW_VER=008/' .config
make olddefconfig
make
# → out/klipper.bin (28,868 bytes for a clean build, ~28.2 KB)
```

The `FW_VER=008` bump is to identify the firmware in `mcu_util -g` output and force a flash if the chip currently has a different version.

**Bin structure produced**:

| Offset | Content |
|---|---|
| 0x000-0x0AF | ARM Cortex-M vector table (MSP, reset, IRQ handlers) |
| 0x0B0-0x1FF | Zero padding |
| 0x200-0x20B | Version label string (e.g. `bed0_008_000`) |
| 0x20C-0x20F | Build CRC16 + bin size (little-endian) |
| 0x210+ | Code |

MSP must be `0x20002000` (top of SRAM). Reset PC `0x08003000 + N` where N is the file offset of the reset handler.

## Test plan

### Pre-conditions to verify before flashing

- `S13mcu_update` patched (bed0_serial=/dev/ttyS6 in F004 case) → confirmed deployed previously
- `bed_klipper_v008.bin` available locally at `C:\Users\AUXINE\Downloads\bed_klipper_v008.bin`
  - SHA256: `eef8f6ae241dceb33d2fcbc7d7ec09cd35d3d03f3233cf144a7c9c0caad6af25`
  - Verified version label `bed0_008_000` at offset 0x200 ✓
- `/usr/share/klipper/fw/F004/` currently has only `mcu0_*` + `noz0_*` (no bed bin staged)

### Deployment

```bash
# Rename to match S13mcu_update's expected naming convention
scp -O /c/Users/AUXINE/Downloads/bed_klipper_v008.bin \
    root@192.168.1.94:/usr/share/klipper/fw/F004/bed0_110_G21-bed0_008_000.bin

# Verify on printer
ssh root@192.168.1.94 'ls -la /usr/share/klipper/fw/F004/ && md5sum /usr/share/klipper/fw/F004/bed0_110_G21-bed0_008_000.bin'

# Operator: power-cycle the printer (full off-then-on)
```

### Post-boot reading

```bash
ssh root@192.168.1.94 'cat /tmp/.mcu_version ; echo === ; cat /tmp/mcu_update.log'
```

### Interpretation matrix

| Result | Meaning |
|---|---|
| Log shows `fw_update success` + `startup app success` for bed0 + `/tmp/.mcu_version` reports `bed0_110_G21-bed0_008_000` | **WIN**: bed MCU is running our build, sensor_hx71x available, ready for klippy integration |
| Log shows `fw_update fail, ret=2` + `start_app fail, state=12` | Firmware writes to flash but bootloader refuses to commit start_app. Same failure mode as K1 stock — would suggest the cryoz build also fails on E5M. Hypothesis "prtouch was the blocker" is invalidated. |
| Handshake fails entirely | Bootloader state changed since last test — would need investigation |

### If success → klippy integration (separate task)

Will require:
- Adding `[mcu leveling_mcu] serial: /dev/ttyS6 baud: 921600 restart_method: command` to printer.cfg
- 4× `[load_cell sensorN]` declarations (mainline-style) with the HX711 clk/sdo pins
- An aggregator Python module if we want all 4 read in parallel
- `[load_cell_probe]` as Z probe (optional — could keep Eddy as primary)

### If failure → next options

1. **Spare PCB swap** — confirmed clean rollback to stock E5M FW=004
2. **True mainline port** — write Cortex-M23 / GD32E230 startup + linker + drivers from scratch in mainline Klipper master. Days of work.
3. **Stop** — accept Eddy-only setup, bed MCU dormant. The chip is currently inert (in bootloader limbo) and doesn't impact any other function.

## Files in this repo

This research log only. The built firmware bin is **not committed** to the repo — it's a single binary file that lives in `Downloads/`. If/when this approach validates and we want to make it reproducible, we'd document the exact build pipeline (Codespace, gh CLI command, etc.) and possibly add a build workflow to the public chelper builder repo.
