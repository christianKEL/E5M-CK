# TECHNICAL MEMO — Building `btteddy.uf2`

## Klipper mainline firmware for the BTT Eddy USB (RP2040)

**Author:** Christian KELHETTER
**Project:** E5M-CK — https://github.com/christianKEL/E5M-CK
**Date:** April 2026

---

## 1. Context and problem statement

### 1.1 What is `btteddy.uf2`?

`btteddy.uf2` is the **Klipper firmware** that runs on the RP2040 microcontroller embedded in the BTT Eddy USB. This firmware:

- Drives the LDC1612 chip (eddy-current sensor) over I2C.
- Sends frequency measurements to the host over USB.
- Reads the Eddy's onboard thermistor (on GPIO26).
- Applies temperature corrections to the LDC signal.

### 1.2 Why build it yourself?

BTT does provide pre-built firmware on its GitHub repository. However:

1. **Klipper version:** the pre-built BTT firmware is often tied to a Klipper version that does not match the one installed on the Nebula. When versions diverge, Klipper will log at startup:

   ```
   MCU 'eddy' protocol error: command format mismatch
   ```

2. **Binary format:** BTT sometimes distributes the firmware as a `.bin` (intended for flashing via `rp2040load` or similar). On the Nebula Pad we have neither `rp2040load` nor `openocd` — the only viable flashing method is the UF2 method (copying a file onto the USB disk that the RP2040 exposes in BOOT mode).

3. **Mainline consistency:** the Eddy's firmware must be built from **the same commit** as the Klipper installed on the Nebula. Otherwise the message layouts between host and MCU may be incompatible.

Building it yourself solves all three problems.

### 1.3 The RP2040

The **Raspberry Pi RP2040** embedded in the BTT Eddy is a dual-core ARM Cortex-M0+ microcontroller with:
- 264 KB of SRAM.
- No internal flash — the firmware lives on an external SPI flash chip.
- **BOOTSEL** mode activated by the BOOT button: the RP2040 then exposes itself as a FAT16 USB disk that accepts a `.uf2` file.

The **UF2 (USB Flashing Format)** was designed by Microsoft to make flashing dead simple: drop a `.uf2` onto the USB disk exposed by the bootloader, the firmware is automatically written to flash, and the RP2040 reboots.

---

## 2. Build environment

### 2.1 Required architecture

Building Klipper's RP2040 firmware requires:
- An ARM cross-compiler (`arm-none-eabi-gcc`).
- The `make` + `kconfig` build system.
- An x86_64 or ARM64 Linux host (both work for this target).

Unlike `c_helper.so` which absolutely requires an x86_64 host to run the Ingenic toolchain, building the RP2040 firmware can technically be done on any Linux host (the `arm-none-eabi-gcc` toolchain exists for both x86_64 and ARM64).

### 2.2 Recommended environment

For **consistency with the `c_helper.so` workflow** and to avoid setting up a local build environment, we use the **same GitHub Codespace** as the one used to build `c_helper.so` (see the `MEMO_c_helper.md` memo).

Benefits:
- Same environment for `c_helper.so` and `btteddy.uf2` — same Klipper commit.
- No local installation to maintain.
- Excellent build performance (~30 seconds).

### 2.3 Installing prerequisites

In the codespace:

```bash
# The ARM toolchain is usually pre-installed on Ubuntu Codespaces.
# If missing:
sudo apt update
sudo apt install -y gcc-arm-none-eabi build-essential

# Verify
arm-none-eabi-gcc --version
# Expected: arm-none-eabi-gcc (15:...) 10.3.1 or newer
```

Klipper recommends GCC 9 or newer for the RP2040. GCC 10+ works without issue.

### 2.4 Klipper source

If a codespace was already used for `c_helper.so`, Klipper is already cloned at `/workspaces/klipper`. Otherwise:

```bash
git clone https://github.com/Klipper3d/klipper.git /workspaces/klipper
cd /workspaces/klipper
```

**Important:** to ensure compatibility with the Nebula host, use **the same commit** as the one installed on the Nebula. The commit can be obtained from:

```bash
# On the Nebula
cd /usr/data/klipper
git rev-parse HEAD
# Example: 373f200ca5a8c5e0...
```

Then in the Codespace, before building:

```bash
cd /workspaces/klipper
git checkout 373f200ca   # same hash as on the Nebula
```

---

## 3. `make menuconfig` configuration

### 3.1 Launch

```bash
cd /workspaces/klipper
make clean
make menuconfig
```

An ncurses menu appears in the codespace terminal.

### 3.2 Settings for the BTT Eddy USB

Settings to apply in `menuconfig`:

| Option | Value | Comment |
|---|---|---|
| Micro-controller Architecture | **Raspberry Pi RP2040** | The BTT Eddy USB core |
| Processor model | **rp2040** | Only option available in this branch |
| Bootloader offset | **No bootloader** | The RP2040 has a ROM bootloader; no second bootloader needed |
| Flash chip | **GENERIC_03H with CLKDIV 4** | Matches the SPI flash soldered on the BTT Eddy |
| Communication interface | **USB (on GPIO 19/20)** | The Eddy talks to the host over USB only (no UART, no CAN) |
| USB ids | Keep defaults | Klipper uses its own VID/PID by default |
| CanBoot options | **(not applicable)** | No CAN on the USB Eddy |

**Note on Flash chip:** `GENERIC_03H with CLKDIV 4` matches BTT's Eddy products. `GENERIC_03H` refers to SPI read command `0x03` (Read Data), supported by the vast majority of flash chips. `CLKDIV 4` sets the SPI bus frequency to one quarter of the system clock, matching the nominal rate of the chip in use.

If firmware built with `GENERIC_03H` does not boot on your Eddy, try `W25Q080 with CLKDIV 2` (RP2040 standard factory value).

### 3.3 Saving and exit

In the `menuconfig` menu:
- **Y/N** keys to toggle an option.
- **Enter** to enter a submenu.
- **Escape** to go up.
- **Q** to quit. If changes were made, answer **Yes** to "Save configuration?".

The `.config` file at the project root now holds the configuration.

### 3.4 Alternative — direct `.config`

Rather than running `menuconfig`, the `.config` file can be created directly:

```bash
cat > /workspaces/klipper/.config << 'EOF'
# Micro-controller Architecture
CONFIG_MACH_RP2040=y
CONFIG_MCU="rp2040"

# Bootloader
CONFIG_RP2040_HAVE_BOOTLOADER=n

# Flash chip
CONFIG_RP2040_FLASH_GENERIC_03H=y
CONFIG_RP2040_FLASH_CLKDIV=4

# Communication
CONFIG_USBSERIAL=y

CONFIG_CLOCK_FREQ=12000000
CONFIG_USB_VENDOR_ID=0x1d50
CONFIG_USB_DEVICE_ID=0x614e
EOF
```

This is faster for an automated build.

---

## 4. Build

### 4.1 Compile

```bash
cd /workspaces/klipper
make
```

Typical output:

```
  Building out/autoconf.h
  Compiling out/src/sched.o
  Compiling out/src/command.o
  ...
  Compiling out/src/rp2040/main.o
  Compiling out/src/rp2040/usbserial.o
  ...
  Linking out/klipper.elf
  Creating hex file out/klipper.elf.hex
  Creating bin file out/klipper.bin
  Converting to uf2 file out/klipper.uf2
```

Duration: ~20 to 40 seconds on a standard codespace.

### 4.2 Output files

In the `out/` folder:

| File | Typical size | Use |
|---|---|---|
| `klipper.elf` | ~400 KB | ELF binary with symbols (debug) |
| `klipper.bin` | ~70 KB | Raw binary (for direct flashing via rp2040load) |
| `klipper.hex` | ~200 KB | Intel HEX (other flashing tools) |
| **`klipper.uf2`** | **~140 KB** | **UF2 format for USB-copy flashing** |

**The file we care about:** `out/klipper.uf2`.

We rename it to `btteddy.uf2` for clarity in our workflow:

```bash
cp out/klipper.uf2 ~/btteddy.uf2
ls -lh ~/btteddy.uf2
# -rw-r--r-- 1 user user 140K Apr 22 10:43 /home/user/btteddy.uf2
```

### 4.3 UF2 file validation

A valid UF2 always starts with the `UF2\n` magic number (bytes `55 46 32 0A`).

```bash
od -t x1 ~/btteddy.uf2 | head -1
```

Expected output:

```
0000000  55 46 32 0a 57 51 5d 9e 00 20 00 00 00 00 00 00
```

The first 4 bytes `55 46 32 0a` confirm a genuine UF2.

The header can also be inspected to verify the target family:

```bash
python3 << 'EOF'
with open('/home/user/btteddy.uf2', 'rb') as f:
    header = f.read(32)
magic0 = int.from_bytes(header[0:4], 'little')
magic1 = int.from_bytes(header[4:8], 'little')
family_id = int.from_bytes(header[28:32], 'little')
print(f"Magic0: {hex(magic0)}")       # Expected: 0x0a324655 (UF2\n little-endian)
print(f"Magic1: {hex(magic1)}")       # Expected: 0x9e5d5157
print(f"Family: {hex(family_id)}")    # Expected: 0xe48bff56 (RP2040)
EOF
```

The `family_id = 0xe48bff56` is the official RP2040 marker in the UF2 spec. If the value differs, the firmware will not target the right microcontroller.

---

## 5. Flashing the Eddy on the Nebula

### 5.1 Transferring to the Nebula

As with `c_helper.so`, the codespace cannot reach the local network directly. Two methods:

**Method A — Download then SCP:**

1. In VS Code's codespace file explorer: right-click on `btteddy.uf2` → **Download**.
2. From Windows PowerShell:
   ```powershell
   scp C:\Users\<user>\Downloads\btteddy.uf2 `
       root@<NEBULA_IP>:/usr/data/E5M_CK/btteddy.uf2
   ```

**Method B — GitHub Raw (used by `install.sh`):**

1. Upload `btteddy.uf2` to the `christianKEL/E5M-CK` GitHub repository.
2. From the Nebula:
   ```bash
   wget --no-check-certificate \
     https://raw.githubusercontent.com/christianKEL/E5M-CK/main/btteddy.uf2 \
     -O /usr/data/E5M_CK/btteddy.uf2
   ```

### 5.2 Putting the Eddy into BOOT mode

To flash the RP2040, it must be put into BOOTSEL mode:

1. **Unplug** the Eddy from the Nebula's USB port.
2. **Hold down** the BOOT button (small tactile button next to the USB port on the Eddy).
3. **Plug** the Eddy into the Nebula while still holding BOOT.
4. **Wait 3 seconds** before releasing BOOT.

### 5.3 Verifying BOOT mode

On the Nebula:

```bash
lsusb | grep "2e8a:0003"
```

If you see:

```
Bus 001 Device 005: ID 2e8a:0003 Raspberry Pi RP2 Boot
```

The RP2040 is in BOOT mode. VID `2e8a` is Raspberry Pi, PID `0003` is the RP2040 bootloader.

You can also verify the mount:

```bash
mount | grep sda
```

Expected:

```
/dev/sda1 on /tmp/udisk/sda1 type vfat (rw,relatime,fmask=0022,...)
```

In BOOT mode, the RP2040 exposes a FAT16 disk containing:
- `INDEX.HTM` — link to Raspberry Pi docs.
- `INFO_UF2.TXT` — bootloader info.

### 5.4 Flashing

Copy the firmware onto the USB disk:

```bash
cp /usr/data/E5M_CK/btteddy.uf2 /tmp/udisk/sda1/
sync
```

**What happens:**

1. The file is written to the RP2040's FAT16 disk.
2. The RP2040 bootloader detects the `.uf2`, verifies the magic number and family_id.
3. It copies the firmware into the external SPI flash.
4. It **reboots** the RP2040 automatically in application mode.

Result: the USB disk disappears and the RP2040 re-enumerates as a CDC-ACM device (USB serial).

### 5.5 Flash validation

After ~5 seconds:

```bash
ls /dev/serial/by-id/
```

Expected:

```
usb-Klipper_rp2040_50445059303E9B1C-if00
```

The `Klipper_rp2040_` prefix confirms the Klipper firmware is running. The suffix (`50445059303E9B1C` in the example) is the unique RP2040 serial number — it **varies per Eddy unit**.

### 5.6 Common errors

**The Eddy does not enter BOOT mode:**
- Make sure you hold the BOOT button **before** plugging in, and release after.
- Try a different USB cable (some cables are "charge only" without data).
- Try another USB port on the Nebula.

**The Eddy is in BOOT mode but flashing fails:**
```
cp: write error: No space left on device
```
- The RP2040 bootloader only accepts `.uf2` files. Make sure you're copying `btteddy.uf2`, not `klipper.bin` or `.elf`.

**After flashing, no `/dev/serial/by-id/usb-Klipper_rp2040_...`:**
- The firmware was flashed but does not boot. Try flashing again.
- If it persists, try another Flash chip configuration (`W25Q080 with CLKDIV 2`).
- Check kernel messages: `dmesg | tail -30`.

**After flashing, a serial port appears but Klipper can't talk to it:**
- The firmware is flashed but incompatible with the host. Rebuild making sure **the Klipper commit in the codespace matches** the one on the Nebula.

---

## 6. Klipper host-side configuration

Once the firmware is flashed and the serial port is detected, Klipper must be configured to talk to the Eddy.

Create `/usr/data/printer_data/config/eddy.cfg`:

```ini
[mcu eddy]
serial: /dev/serial/by-id/usb-Klipper_rp2040_50445059303E9B1C-if00

[temperature_sensor btt_eddy_mcu]
sensor_type: temperature_mcu
sensor_mcu: eddy
min_temp: 10
max_temp: 100

[probe_eddy_current btt_eddy]
sensor_type: ldc1612
descend_z: 3.0
i2c_mcu: eddy
i2c_bus: i2c0f
x_offset: 38
y_offset: 6

[temperature_probe btt_eddy]
sensor_type: Generic 3950
sensor_pin: eddy:gpio26
horizontal_move_z: 2
```

**Replace** the `serial:` value with the one shown by `ls /dev/serial/by-id/` — the serial number is **unique** per Eddy.

**Important notes:**

- `i2c_bus: i2c0f` → RP2040 I2C bus used by the LDC1612 chip. Default value of the BTT Eddy firmware.
- `sensor_pin: eddy:gpio26` → RP2040 pin wired to the Eddy's onboard thermistor.
- `x_offset` / `y_offset` → physical offset between nozzle and Eddy sensor center. Measure on your machine.
- `descend_z: 3.0` → initial descent height used during calibration. Replaces the deprecated `z_offset` parameter in recent Klipper.

### 6.1 Include in `printer.cfg`

Add near the top of `printer.cfg`:

```
[include eddy.cfg]
```

And modify `[stepper_z]` to use the Eddy as a virtual endstop:

```
[stepper_z]
# ... other parameters ...
endstop_pin: probe:z_virtual_endstop
homing_retract_dist: 0
# Comment out the old line:
# position_endstop: 0
```

### 6.2 Restart and calibration

```bash
/etc/init.d/S55klipper_service restart
sleep 20
curl http://localhost:7125/printer/info | python3 -m json.tool | grep state
```

Once Klipper is `ready`, perform the Eddy calibrations in order:

1. `CAL_EDDY_DRIVE_CURRENT` → `LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy` → `SAVE_CONFIG`.
2. `CAL_EDDY_MAPPING` → `PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy` + TESTZ + ACCEPT → `SAVE_CONFIG`.
3. `CAL_BED_MESH` → `BED_MESH_CALIBRATE METHOD=rapid_scan` → `SAVE_CONFIG`.

---

## 7. Maintenance and updates

### 7.1 When should `btteddy.uf2` be rebuilt?

Rebuild and re-flash is required:

- After a major Klipper update on the Nebula (if protocol mismatches appear).
- If BTT ships a hardware revision of the Eddy that requires a different flash chip.
- To test a specific commit or a Klipper fork.

### 7.2 Full update procedure

In the codespace:

```bash
cd /workspaces/klipper
git pull
# or: git checkout <commit>

make clean
make menuconfig
# (ensure no option has changed — save)

make
cp out/klipper.uf2 ~/btteddy.uf2
```

Then flash as per Section 5.

### 7.3 Rollback

If the new version causes problems, revert to the previous `btteddy.uf2` and re-flash via the BOOT button.

Always keep a known-good copy of `btteddy.uf2` in `/usr/data/E5M_CK/` on the Nebula and in another safe location.

---

## 8. Recap — minimal commands

On a blank Ubuntu GitHub codespace:

```bash
# Prerequisites
sudo apt update
sudo apt install -y gcc-arm-none-eabi build-essential

# Klipper source (if not already there)
git clone https://github.com/Klipper3d/klipper.git /workspaces/klipper
cd /workspaces/klipper

# Configuration
cat > .config << 'EOF'
CONFIG_MACH_RP2040=y
CONFIG_MCU="rp2040"
CONFIG_RP2040_HAVE_BOOTLOADER=n
CONFIG_RP2040_FLASH_GENERIC_03H=y
CONFIG_RP2040_FLASH_CLKDIV=4
CONFIG_USBSERIAL=y
CONFIG_CLOCK_FREQ=12000000
CONFIG_USB_VENDOR_ID=0x1d50
CONFIG_USB_DEVICE_ID=0x614e
EOF

# Build
make clean
make

# The firmware is at out/klipper.uf2
cp out/klipper.uf2 ~/btteddy.uf2
ls -lh ~/btteddy.uf2
```

Then download `~/btteddy.uf2` via the VS Code file explorer, flash as per Section 5.

---

## 9. Additional notes

### 9.1 Difference vs. the official BTT firmware

The official `bigtreetech/Eddy` repository ships pre-built `.uf2` files in a `firmware/` folder. These files are identical to what we build here, **up to the Klipper version**.

If the official BTT firmware happens to match the exact Klipper version installed on the Nebula, it can be used as-is without rebuilding. But this is rare in practice: Klipper upstream moves fast, and BTT publishes firmware less frequently.

### 9.2 USB serial vs. CAN

Some newer Eddy products (Eddy Coil, Eddy NG) support CAN Bus. Our configuration is strictly **USB**. Don't mix up `menuconfig` options:

- **Eddy USB** → `CONFIG_USBSERIAL=y`.
- **Eddy Coil** (connected to a toolhead board via CAN) → `CONFIG_CAN=y` with a CAN-specific configuration.

For the BTT Eddy USB, **always** choose USB.

### 9.3 Flash chip — how to find the right one?

The flash chip is marked on the Eddy's PCB — a small SOIC-8 package near the RP2040. Common markings:

| Marking | menuconfig option |
|---|---|
| `W25Q080` or `25Q08xxx` | `W25Q080 with CLKDIV 2` |
| `W25Q16JV` | `W25Q080 with CLKDIV 2` (compatible) |
| Unclear marking | `GENERIC_03H with CLKDIV 4` (slower but universal) |

On current BTT Eddy USB units (2024–2026), `GENERIC_03H with CLKDIV 4` works in 100% of cases.

### 9.4 UF2 vs. BIN — why UF2?

The `.bin` format is a raw binary flashed via a tool like `rp2040load`, `openocd`, or `picotool`. It requires:
- Either access to the RP2040's SWD pins (on the BTT Eddy these pins exist but are not exposed on a header).
- Or a software tool that speaks the RP2040 bootloader protocol.

The `.uf2` format is designed for **copy-based flashing**: no tool required, just a `cp`. This is the ideal method on the Nebula, which has no `rp2040load` installed and can't easily install one (limited toolchain).

**`.uf2` = copy-based flashing. It is our only viable method on the Nebula.**

---

*Document written in April 2026 as part of the E5M-CK project.*
