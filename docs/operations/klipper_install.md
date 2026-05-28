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
cat installs/install_klipper.sh | ssh root@192.168.1.94 'sh -s'
```

The installer:
- Backs up the stock `S55klipper_service` to `/usr/data/backup/klipper-stock/`
- Backs up the stock `printer_data/config/` to `config.stock.tar.gz`
- Reuses the stock Creality venv at `/usr/share/klippy-env/` (ships pre-built greenlet+cffi for Python 3.8 on MIPS32r2)
- Clones Klipper upstream at the pinned tag (default `master`) to `/usr/data/e5m-ck/klipper`
- Resolves `c_helper.so` from one of three sources (see below)
- Verifies klippy can `import chelper; chelper.get_ffi()` — proves the binary is ABI-compatible with the checked-out Klipper SHA
- Does NOT touch the stock init script or the live `printer.cfg`

Override the pinned tag with `--tag=<ref>` (`master`, `v0.13.0`, a SHA…).

### `c_helper.so` — where it comes from

`klippy/chelper/c_helper.so` is a C extension that has to match (a) this printer's CPU ABI — Ingenic XBurst2 mipsel32r2, nan2008, glibc≥2.22 — AND (b) the Klipper Python code's expectations for that SHA. Klipper can auto-rebuild it on first start IF gcc is on the host, but gcc + binutils need ~150 MB unpacked and our `/overlay` partition has ~90 MB free → installing it there blows up the partition.

The installer resolves `c_helper.so` in this priority order:

**1. Pre-staged at `/tmp/c_helper.so` (offline / explicit)** — if you `scp` it there before running the script, it's used as-is. Useful when:
- The printer has no internet
- You've built a hand-modified binary you want to test
- You want to deploy the binary committed in this repo at `klipper/binaries/mipsel-3.4/c_helper.so` (an older known-good `v0.13.0+` build, kept for emergencies/factory-reset rollback)

```bash
scp -O klipper/binaries/mipsel-3.4/c_helper.so root@192.168.1.94:/tmp/
cat installs/install_klipper.sh | ssh root@192.168.1.94 'sh -s'
```

**2. Auto-downloaded from [klipper-ingenic-chelper](https://github.com/christianKEL/klipper-ingenic-chelper) (default)** — the script computes the short SHA of the Klipper commit it just checked out, then `wget`s the matching release asset:
```
https://github.com/christianKEL/klipper-ingenic-chelper/releases/download/klipper-<SHORT_SHA>/c_helper.so
```

If the release exists, you don't need to pre-stage anything. The companion repo (`klipper-ingenic-chelper`) auto-rebuilds `master` weekly and publishes any specific SHA on demand — see [its README](https://github.com/christianKEL/klipper-ingenic-chelper#readme).

**3. Hard fail** — if `/tmp/c_helper.so` is missing AND the public release for this Klipper SHA doesn't exist (or the printer can't reach GitHub), the script aborts with instructions for both options 1 and 2. Trigger a build at <https://github.com/christianKEL/klipper-ingenic-chelper/actions> with `klipper_ref=<your-sha>`, wait ~5 min, re-run the script.

### Local patches applied on top of the upstream Klipper tag

In normal operation we run vanilla upstream Klipper. A small number of
empirical fixes live under [`klipper/patches/`](../../klipper/patches/)
and are applied to the source tree before the `c_helper.so` build.
Today the list is:

| Patch                                                                 | Touches              | Why                                                                                                                |
|-----------------------------------------------------------------------|----------------------|--------------------------------------------------------------------------------------------------------------------|
| `0001-steppersync-serialize-gen-steps-per-steppersync.patch`          | `chelper/steppersync.c` | Workaround for the recurring `Internal error in stepcompress` shutdown on coreXY at low-speed direction reversals. See the patch header. |

When upstream eventually fixes one of these, drop the patch and rebuild.

To rebuild `c_helper.so` against a patched source tree, apply patches
in numeric order *after* `git clone` and *before* the build command in
the next section:

```bash
cd /tmp/klipper
for p in /path/to/E5M-CK/klipper/patches/*.patch; do
    git apply --3way "$p"
done
```

### Rebuilding `c_helper.so` for a Klipper bump (advanced)

If you bumped `KLIPPER_TAG` in the installer and want to publish a matching binary to the public repo, OR you're hacking on a Klipper fork:

**Easy path** — trigger the public builder for any Klipper ref:
```bash
gh workflow run build.yml \
    --repo christianKEL/klipper-ingenic-chelper \
    -f klipper_ref=<your-tag-or-sha>
```
Wait for the run to finish, then the install script's auto-download path picks it up automatically next time.

**Manual path** (for Klipper forks or air-gapped builds) — fork the [klipper-ingenic-chelper](https://github.com/christianKEL/klipper-ingenic-chelper) repo and change the `klipper_repo` workflow input, OR run the build steps yourself in any x86_64 Linux env (the workflow's [build.yml](https://github.com/christianKEL/klipper-ingenic-chelper/blob/main/.github/workflows/build.yml) is the canonical reference):

```bash
# In a GitHub Codespace, WSL, Docker, or any Ubuntu/Debian box:
git clone --depth 1 https://github.com/Dafang-Hacks/mips-gcc520-glibc222-64bit-r3.2.1 ~/ingenic-toolchain
git clone https://github.com/Klipper3d/klipper /tmp/klipper
cd /tmp/klipper && git checkout <your-ref>
cd klippy/chelper && rm -f c_helper.so
~/ingenic-toolchain/bin/mips-linux-gnu-gcc \
    -shared -fPIC -O2 -mnan=2008 -mfp64 -mabs=2008 \
    $(ls *.c) -o c_helper.so
~/ingenic-toolchain/bin/mips-linux-gnu-readelf -h c_helper.so | grep "Flags"
# Expected: Flags: 0x70001407, noreorder, pic, cpic, nan2008, o32, mips32r2
```

The original write-up of why these exact gcc flags matter is in [`assets/memos/MEMO_c_helper_ENG.md`](../../assets/memos/MEMO_c_helper_ENG.md) on the legacy `main` branch.

### Why not just install gcc on the printer?

Tried in v1 and again briefly in v2 (commit `2737589`). The `gcc + binutils` Entware package needs ~150 MB unpacked, and our `/overlay` partition is at ~90 MB free once Phases 4-9 are installed. It doesn't fit. Even if it did, Klipper's chelper rebuild on every klippy restart adds ~30 s of build time and risks silent failures. The pre-built + reproducible-from-Actions path is faster and more auditable.

### Custom `klippy/extras/` Python modules

Some of our needs aren't covered by upstream Klipper config options. We
keep small Python modules in `klipper/extras/` (in this repo) and have
`install_klipper.sh` copy them into the live `klippy/extras/` directory
at install time. Each module is a normal Klipper extra — load it by
referencing its section name in `printer.cfg`.

Current modules:

| File                              | Section in printer.cfg     | Purpose                                                             |
|-----------------------------------|----------------------------|---------------------------------------------------------------------|
| `mcu_deprecation_filter.py`       | `[mcu_deprecation_filter]` | Silence specific `deprecated_mcu_code` warnings (Creality MCU firmware kept for factory-reset rollback). |

**Why this is OK** vs. just patching Klipper source:
- The files live in our repo with our own commit history and rationale.
- `install_klipper.sh` reinstalls them on every Klipper upgrade, so a
  `git pull` of upstream Klipper master can't silently delete them.
- Each module documents its purpose in a top-of-file docstring and
  requires a `reason: ...` config line that gets echoed to `klippy.log`
  at startup. Removing the section in `printer.cfg` is the rollback.

**Deploy flow** when adding a new one:
1. Write the module in `klipper/extras/<name>.py`, with a header
   docstring that explains why it exists and how to roll it back.
2. Stage to the printer's `/tmp/`:
   ```bash
   for f in klipper/extras/*.py; do
     scp -O "$f" root@192.168.1.94:/tmp/klipper_extras_$(basename "$f")
   done
   ```
3. Re-run `installs/install_klipper.sh` — its `4b.` step copies anything
   matching `/tmp/klipper_extras_*.py` into `klippy/extras/`.
4. Add the `[<section>]` block to `printer.cfg` (in this repo) before
   any section it needs to wrap, and sync.

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
