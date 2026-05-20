# Input shaper — Ender 5 Max v2

## Why a proxy?

The ADXL345 accelerometer on the Ender 5 Max's print head is wired into
the SPI bus of the stock Creality 2023 nozzle-MCU firmware. Mainline
Klipper's `[adxl345]` driver does NOT speak the same on-wire protocol:

- `query_adxl345` takes 3 args in the stock firmware (with a `clock`
  parameter), 2 in mainline.
- Samples are packed in 5 bytes with the Z high-bits masked `0x60`, not
  the 6 bytes / `0xe0` mask mainline expects.
- The serial callback registration migrated from the MCU object to the
  serial layer between the two versions.

We cannot reflash the nozzle MCU because the stock firmware is a
precondition for our `factory_reset` rollback path (see
`docs/operations/factory_reset.md` and `installs/creality_kill.sh`).

So we bridge on the host side:

- `klipper/extras/adxl345_creality.py` ports the Creality ADXL class
  while reusing mainline's `AccelCommandHelper` and `BatchBulkHelper`.
- `klipper/extras/accel_chip_proxy.py` registers a synthetic chip named
  `accel_chip_proxy` that `[resonance_tester]` targets.
- `klipper/extras/gcode_shell_command.py` (vendored from the Eric
  Callahan / kiauh community module) lets macros launch shell scripts.

All three .py files are staged into `klippy/extras/` by
`install_klipper.sh` via the `/tmp/klipper_extras_*.py` pipeline.

## The matplotlib `ft2font` ABI fix (mandatory before any PNG works)

`calibrate_shaper.py` and `graph_belts.py` both use matplotlib to render
the PNGs. The Creality-pre-installed matplotlib 2.2.3 in
`/usr/share/klippy-env/` ships an `ft2font.cpython-38-mipsel-linux-gnu.so`
that was statically compiled against freetype 2.6–2.8 headers (2017).
On this printer `libfreetype.so.6` is freetype 2.13 (Entware), and the
struct layouts have changed. Result: any `matplotlib.pyplot` import
walks into `font_manager` which calls into freetype with a mis-sized
`FT_Stream`, and on cleanup the C++ runtime aborts:

```
terminate called after throwing an instance of 'std::runtime_error'
  what():  Couldn't close file
Aborted
```

This kills every PNG generation, instantly, with no recovery.

**Fix (already automated in `install_input_shaper.sh`):** swap matplotlib's
broken `ft2font.so` for the ABI-fixed version that ballaswag's GuppyScreen
project ships at `/usr/data/guppyscreen/k1_mods/ft2font.cpython-38-mipsel-linux-gnu.so`.
That binary is dynamically linked against a modern freetype and works
against 2.13 cleanly. md5 `7706852f09ad75472d15ff790ecc0d55`, 101564 bytes.

The installer keeps a backup at `${ORIG}.original` and verifies the swap
with md5 before continuing. It's idempotent: if the K1-mod is already in
place, it's a no-op.

**Why this depends on GuppyScreen:** the K1-mod binary only exists on the
filesystem because `install_guppyscreen.sh` placed it under
`/usr/data/guppyscreen/k1_mods/`. So the installation order is
`install_guppyscreen.sh` → `install_klipper.sh` → `install_input_shaper.sh`.
If you `creality_kill`'d GuppyScreen but kept its k1_mods dir, that's
fine — we only need the .so file, not GuppyScreen as a service.

What we tried first that did NOT work (recorded for future readers):

- Disabling fonts one-by-one — every iteration the next font crashes,
  because it's an ABI bug not a corrupt-font bug.
- `matplotlib.use('Agg')` — crash happens during font_manager init,
  before the backend matters.
- Native pip install of newer matplotlib — Entware ships libfreetype
  but not the dev headers, so the C extension build fails.
- Cross-compiling matplotlib in Codespaces — 2–4 h of toolchain
  wrangling for an uncertain outcome, abandoned in favor of the K1 mod.

(See [`assets/memos/MEMO_guppyscreen_belts_ENG.md`](https://github.com/christianKEL/E5M-CK/blob/main/assets/memos/MEMO_guppyscreen_belts_ENG.md)
on the v1 branch for the full investigation history.)

## v1 → v2 changes

| Concern | v1 | v2 |
|---|---|---|
| `.py` modules | curl-downloaded at install time | versioned in repo, deployed by `install_klipper.sh` |
| `configfile.py` source patch (to silence `spi_set_sw_bus`) | in-place string replacement, breaks on `git pull` | `[mcu_deprecation_filter] features:` adds `spi_set_sw_bus` to the existing allowlist — no source modification |
| Config injection | sed markers in live `printer.cfg` | versioned `klipper/config/input_shaper.cfg` + repo `printer.cfg` `[include]` |
| `calibrate_shaper.py` source | GuppyScreen-vendored copy | Klipper's own `/usr/data/e5m-ck/klipper/scripts/calibrate_shaper.py` |
| `graph_belts.py` source | GuppyScreen-vendored copy | vendored to `klipper/scripts/graph_belts.py` (from the K1 fork; Klippain's modern shaketune package is no longer a standalone script) |
| User-facing macros | none — user called raw `TEST_RESONANCES` | `MEASURE_AXIS`, `MEASURE_BELTS`, `SHAPER_PNG` with light-on + auto-G28 + auto-positioning |
| Primary workflow | `TEST_RESONANCES` → CSV → manual `calibrate_shaper.py` → PNG → manual edit | `SHAPER_CALIBRATE` (auto-suggest + auto-write to autosave) → optional PNG |
| Rollback | uninstall script that restores `.bak.*` files | comment out `[include input_shaper.cfg]` and `[include macros/input_shaper.cfg]`, restart |

## One-time installation

After `install_klipper.sh` has run and deployed the three `.py` extras:

```bash
# From the repo on the host laptop:
scp -O klipper/scripts/gen_shaper_png.sh root@192.168.1.94:/tmp/
scp -O klipper/scripts/gen_belts_png.sh  root@192.168.1.94:/tmp/
scp -O klipper/scripts/graph_belts.py    root@192.168.1.94:/tmp/
cat installs/install_input_shaper.sh | ssh root@192.168.1.94 'sh -s'

# Push the config (sync.sh preserves the autosave block in printer.cfg):
bash scripts/sync.sh --apply

# Restart Klipper:
ssh root@192.168.1.94 '/etc/init.d/S55klipper_service restart'
```

Verify in Fluidd's console:

```
HELP
```

You should see `MEASURE_AXIS`, `MEASURE_BELTS`, `SHAPER_PNG`,
`TEST_RESONANCES`, `SHAPER_CALIBRATE` in the listing.

## First calibration

`[input_shaper]` is a Klipper unique section. Convention: it lives ONLY
in the autosave block at the bottom of the LIVE `printer.cfg`. Our
included `input_shaper.cfg` deliberately does NOT define it, so
`SAVE_CONFIG` can write it cleanly.

1. Run:
   ```
   MEASURE_AXIS AXIS=X
   ```
   - Light comes on automatically.
   - If not homed, the macro runs `G28` first.
   - Toolhead goes to (X=200, Y=200, Z=10) — center of bed.
   - `SHAPER_CALIBRATE AXIS=X` runs (~45 s sweep + analysis).
   - Klipper prints the recommendation:
     ```
     // Recommended shaper_type_x = mzv, shaper_freq_x = 50.0 Hz
     ```

2. Repeat for Y:
   ```
   MEASURE_AXIS AXIS=Y
   ```

3. Optional — visualize:
   ```
   SHAPER_PNG AXIS=x
   SHAPER_PNG AXIS=y
   ```
   PNGs land in
   `/usr/data/printer_data/config/printer_calibration_graphs/`.

4. Persist:
   ```
   SAVE_CONFIG
   ```
   Klipper writes `[input_shaper]` to the autosave block at the bottom
   of the LIVE `printer.cfg`, then restarts. Done.

## Re-sync to the repo (optional)

The autosave block is on the live printer only. To make a fresh
`sync.sh` from this repo reproduce a calibrated state, you have two
options:

- **Re-run the cal**. Calibration takes 90 seconds and is deterministic
  for a given mechanical state — usually fastest.
- **Vendor the values as a comment block** at the bottom of
  `klipper/config/input_shaper.cfg` (only a record; the actual values
  must be in the autosave for SAVE_CONFIG to keep working). Pull from
  the live with:
  ```bash
  ssh root@192.168.1.94 'awk "/#\*# \[input_shaper\]/,/^[^#]/" /usr/data/printer_data/config/printer.cfg'
  ```

## Belt-tension comparison (CoreXY health check)

```
MEASURE_BELTS
```

Sweeps along the A belt (1,1,0) then the B belt (1,-1,0), then
overlays the two FFT spectra. Healthy belts: curves overlap
closely. Bad belt: one curve is shifted or has different peaks —
tighten the slack belt and re-run.

Output PNG: `printer_calibration_graphs/belts_<timestamp>.png`.

## Periodic re-cal

Re-run `MEASURE_AXIS X / Y`:

- After any belt change or significant bed/gantry maintenance.
- If you observe ghosting or ringing on prints that wasn't there.
- Every 3–6 months as a routine.

## Recovery from a bad shaper result

| Symptom | Likely cause | Fix |
|---|---|---|
| Recommended freq < 25 Hz | Bed clamp loose or accel cable not secured | Reseat both, re-run |
| Recommended freq > 100 Hz | Bed too high (Z=10 too aggressive); accel saturated | Edit `input_shaper.cfg` `[resonance_tester] probe_points` to Z=50, push, re-run |
| Noisy spectrum, no peak | Heaters / fans running at 100% during sweep | `TURN_OFF_HEATERS`, wait 5 min, re-run |
| Per-belt curves don't overlap | One CoreXY belt slacker than the other | Tighten the loose belt, re-run `MEASURE_BELTS` |
| `'accel_chip_proxy' not found` | Module didn't install | Re-run `install_klipper.sh` with the three .py files staged via `/tmp/klipper_extras_*` |
| `Option 'spi_set_sw_bus' is deprecated` warning still showing | `mcu_deprecation_filter` features list missing `spi_set_sw_bus` | Add it to the `features:` line in `printer.cfg`, restart |

## Rollback to no-input-shaper

In `klipper/config/printer.cfg`, comment out:

```
# [include input_shaper.cfg]
# [include macros/input_shaper.cfg]
```

`bash scripts/sync.sh --apply`, restart Klipper. The `.py` modules
stay on disk in `klippy/extras/` but become dormant — Klipper only
loads modules referenced by an active config section. To fully
purge, also delete the four `.py` files from
`/usr/data/e5m-ck/klipper/klippy/extras/` (note that
`gcode_shell_command.py` may be in use by other macros — check
before deleting).

## Known limitations

1. **Raw acceleration magnitudes are wrong** (~3.66 g at rest instead
   of 1.0 g) due to sign-extension in the Creality unpacking. Does
   not affect shaper results because the FFT is dynamics-based, not
   magnitude-based.
2. **`adxl345_rate` is capped at 1600 Hz.** Higher rates (3200 Hz)
   drop samples on the nozzle-MCU UART. 1600 Hz still covers
   >600 Hz, well past anything mechanical on this machine.
3. **Bridge is tied to specific firmware versions.** If you ever
   update the stock firmware (don't — factory_reset depends on it)
   OR if Klipper-master refactors `AccelCommandHelper`, the bridge
   may need re-porting. The header in `accel_chip_proxy.py`
   documents the last-known-good baseline.
4. **`graph_belts.py` is a 2024-era standalone script** — Klippain
   has since refactored it into the shaketune package. We carry
   the K1-fork standalone version. If you need newer belt
   analytics, install Klippain Shake&Tune as a separate add-on.
