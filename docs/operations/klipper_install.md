# Klipper mainline install — operations guide

Phase 3 replaces the stock Creality klippy Python process with **upstream Klipper** running from our own venv. **MCU firmwares are kept stock** — no cross-compile, no flashing. Mainline klippy talks to the existing Creality-fork firmwares for standard operations (steppers, heaters, fans, GPIO).

## What gets installed

| Artifact                                          | Stock                                            | E5M-CK v2                                              |
|---------------------------------------------------|--------------------------------------------------|--------------------------------------------------------|
| Klipper Python entry point                        | `/usr/share/klipper/klippy/klippy.py` (squashfs) | `/usr/data/e5m-ck/klipper/klippy/klippy.py`            |
| Python venv                                       | `/usr/share/klippy-env/`                         | **same** (we reuse stock; ships pre-built greenlet+cffi) |
| init script                                       | `/etc/init.d/S55klipper_service` (stock)         | `/etc/init.d/S55klipper_service` (our replacement)     |
| `printer.cfg`                                     | Creality fork template (CR-10 SE based)          | Mainline-compatible split under `klipper/config/`      |
| MCU firmwares on the 3 GD32 chips                 | **Creality fork**                                | **Creality fork (unchanged in Phase 3)**               |

## Capabilities matrix

| Feature                  | Stock | After Phase 3 | Notes                                                 |
|--------------------------|:-----:|:-------------:|-------------------------------------------------------|
| Homing X / Y (sensorless)| ✅    | ✅            | via TMC2209 StallGuard                                 |
| Homing Z                 | ✅ (prtouch_v2)| ⚠️ sensorless | careful, no probe — head touches bed                  |
| Motion (G0/G1)           | ✅    | ✅            |                                                       |
| Heaters (bed + hotend)   | ✅    | ✅            | PID values reused from stock                          |
| Fans                     | ✅    | ✅            | hotend fan auto + 2 part-cooling fans via M106        |
| Filament runout sensor   | ✅    | ✅            | switch_pin: !PC6                                      |
| LEDs (status lights)     | ✅    | ✅            | output_pin                                            |
| Bed mesh                 | ✅ (prtouch_v2)| ❌ no probe   | section kept; `BED_MESH_CALIBRATE` fails until Phase 6 |
| Input Shaping            | ✅ (Creality ADXL)| ❌            | deferred to Phase 10 (needs ADXL patch)                |
| Creality EEPROM (bl24c16f)| ✅    | ❌ ignored     | not used in our config                                |
| HX711 strain gauges      | ✅ (prtouch backup)| ❌ ignored    | not wired into our config                             |
| Z probing                | ✅ (prtouch_v2)| ❌            | comes back with BTT Eddy in Phase 6                   |

## Install procedure

### 1. Prepare the venv on the printer

```bash
# From your local machine in the E5M-CK repo:

# (a) Pre-stage the precompiled c_helper.so on the printer.
#     This avoids klippy trying to compile it on first run (we don't ship
#     gcc on the printer — costs ~100 MB on the small overlay partition).
scp klipper/binaries/mipsel-3.4/c_helper.so root@192.168.1.94:/tmp/

# (b) Run the installer.
cat installs/install_klipper.sh | ssh root@192.168.1.94 'sh -s'
```

The installer:
- Backs up the stock `S55klipper_service` to `/usr/data/backup/klipper-stock/`
- Backs up the stock `printer_data/config/` to `config.stock.tar.gz`
- Clones Klipper upstream at the pinned tag (default `v0.13.0`) to `/usr/data/e5m-ck/klipper`
- Creates the venv at `/usr/data/venvs/klippy/` and installs `klippy-requirements.txt`
- Copies `/tmp/c_helper.so` into `klippy/chelper/` and bumps its mtime so klippy doesn't try to recompile
- Verifies klippy can `import chelper; chelper.get_ffi()` — proves the binary is ABI-compatible with this Klipper tag
- Does NOT touch the stock init script or the live `printer.cfg`

Override the pinned tag with `--tag=vX.Y.Z` if needed.

### Rebuilding `c_helper.so` for a different Klipper tag

The shipped binary at `klipper/binaries/mipsel-3.4/c_helper.so` is compiled against the **pinned tag (default `v0.13.0`)**. If you bump the Klipper tag and the chelper sources changed, you need to rebuild.

The Ingenic XBurst2 SoC requires very specific compiler flags (`-mnan=2008 -mfp64 -mabs=2008`) that the Creality stock gcc and most Debian cross-compilers don't get right. The reliable path is the Dafang-Hacks Ingenic toolchain on an x86_64 host. The full method is documented in [`assets/memos/MEMO_c_helper_ENG.md`](../../assets/memos/MEMO_c_helper_ENG.md) on the legacy `main` branch (the document this v2 rebuild is based on).

Short version, in a GitHub Codespace:

```bash
git clone --depth 1 https://github.com/Dafang-Hacks/mips-gcc520-glibc222-64bit-r3.2.1 ~/ingenic-toolchain
git -C /workspaces/klipper -c advice.detachedHead=false checkout vX.Y.Z   # your target tag
cd /workspaces/klipper/klippy/chelper && rm -f c_helper.so
~/ingenic-toolchain/bin/mips-linux-gnu-gcc -shared -fPIC -O2 -mnan=2008 -mfp64 -mabs=2008 \
    $(ls *.c) -o c_helper.so
~/ingenic-toolchain/bin/mips-linux-gnu-readelf -h c_helper.so | grep "Flags"
# Expected: Flags: 0x70001407, noreorder, pic, cpic, nan2008, o32, mips32r2
```

Then `gh codespace cp -c <name> remote:.../c_helper.so klipper/binaries/mipsel-3.4/c_helper.so` and commit.

### Fallback — install gcc on the printer

If pre-built binaries become unmanageable, install gcc + make via Entware (~100 MB on the `/overlay` partition; check `df -h /overlay` first — leaves ~37 MB free with everything we'll install in Phases 4-9). Then klippy compiles c_helper.so on first start.

```bash
ssh root@192.168.1.94 '/opt/bin/opkg install gcc make'
```

**Not recommended** unless you're actively iterating on chelper — the disk-space cost is real and you risk filling the overlay.

### 2. Deploy the new config + init script

```bash
bash scripts/backup.sh                     # safety backup
bash scripts/sync.sh                       # dry-run, review the plan
bash scripts/sync.sh --apply               # push:
                                           #   klipper/config/         → /usr/data/printer_data/config/
                                           #   system/etc/init.d/S55*  → /etc/init.d/S55klipper_service
```

`sync.sh` uses `rsync` or a `tar`-pipe fallback. It refuses `--apply` without a backup younger than 60 min.

### 3. Restart Klipper

```bash
ssh root@192.168.1.94 '/etc/init.d/S55klipper_service restart'
```

### 4. Verify

```bash
bash scripts/verify.sh
```

Watch for:
- `Klipper` running (PID changes)
- `Klipper health` section: log size growing, `print_time` advancing, no warnings
- `MCU health`: low `retransmit` values
- `Drift detection`: every `klipper/config/*` and `system/etc/init.d/S55klipper_service` should show `=` (md5 match)

### 5. First basic test

Once you confirm klippy is running cleanly:

```bash
# Smoke test via the klippy UDS socket (or via Moonraker once Phase 4 lands).
# Until then, the touch screen / web UI from Creality still works because
# we coexist with the Creality stack — but they may report errors since
# they're hard-coded for stock klippy quirks.
```

## Rollback

### Soft (preferred): revert just the klippy install

```bash
# 1. Restore stock S55 init script
ssh root@192.168.1.94 'cp /usr/data/backup/klipper-stock/S55klipper_service.orig /etc/init.d/S55klipper_service'

# 2. Restore stock config
ssh root@192.168.1.94 'cd /usr/data/printer_data/config && tar xzf /usr/data/backup/klipper-stock/config.stock.tar.gz'

# 3. Restart with stock klippy
ssh root@192.168.1.94 '/etc/init.d/S55klipper_service restart'
```

### Hard: factory reset

```bash
ssh root@192.168.1.94 '/etc/init.d/S58factoryreset reset'   # SSH method
# or USB method: FAT32 stick with empty `factory_reset` file, power-cycle
```

After a factory reset the printer is back to stock Creality (Klipper fork + Creality UI + everything), and you'd re-run the install pipeline from Phase 2 onward to get back to v2.

## Known issues during Phase 3

- **Creality web UI on port 80 still talks to stock klippy paths.** It may show errors. We replace it with Fluidd + nginx in Phase 4.
- **Touch screen (display-server) may glitch or refuse to load printer state** if it can't find the stock socket paths or APIs. It's replaced by GuppyScreen in Phase 5.
- **BED_MESH_CALIBRATE will fail** until BTT Eddy probe is installed in Phase 6.
- **SHAPER_CALIBRATE will fail** until the ADXL Creality patch lands in Phase 10.
- **The leveling_mcu is connected but idle** (no `[prtouch_v2]` / `[hx711s]` in our config). klippy will report it as `ready` but won't issue commands to it.
