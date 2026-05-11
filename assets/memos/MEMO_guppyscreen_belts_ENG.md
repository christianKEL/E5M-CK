# TECHNICAL MEMO — GuppyScreen Belts, Input Shaper & matplotlib

## Klipper mainline + Creality K1-derived stack

**Author:** Christian KELHETTER
**Project:** E5M-CK — https://github.com/christianKEL/E5M-CK
**Date:** May 2026

---

## 1. Context and problem statement

### 1.1 The GuppyScreen Belts feature

GuppyScreen is a touch UI for Klipper, originally developed by ballaswag for Creality K1/K1 Max printers. It runs natively on the printer's display (LVGL-based, no X server needed) and provides shortcuts to common operations.

One of those shortcuts is the **Belts** button: a CoreXY-specific test that measures the resonance response of belt A (X axis path) and belt B (Y axis path) and produces a visual comparison. It's based on Frix-x's `klippain-shaketune` work — same idea, GuppyScreen-integrated.

The expected output:
- A PNG file named `belts_calibration.png`
- Containing a frequency-response chart and a difference spectrogram
- A "similarity score" line at the top (e.g. `Belts estimated similarity: 93.1%`)
- Score above 95% = belts well-balanced; 85-95% = acceptable; below 85% = retension needed.

### 1.2 The toolchain involved

When the user presses the Belts button in GuppyScreen, the following chain executes:

1. GuppyScreen calls `GUPPY_BELTS_SHAPER_CALIBRATION` (a gcode macro defined in `/usr/data/printer_data/config/GuppyScreen/guppy_cmd.cfg`).
2. The macro runs `TEST_RESONANCES AXIS=1,1 OUTPUT=raw_data` and `TEST_RESONANCES AXIS=1,-1 OUTPUT=raw_data` to excite each diagonal direction.
3. Klipper saves two raw CSV files in `/tmp` (one per excitation direction).
4. The macro then runs the **Frix-x graph_belts.py** script (located in `/usr/data/printer_data/config/GuppyScreen/scripts/graph_belts.py`).
5. `graph_belts.py` reads the CSVs, runs PSD analysis using **numpy** + **matplotlib**, and writes `belts_calibration.png` to `/usr/data/printer_data/config/`.
6. GuppyScreen polls the file system, sees the new PNG, and displays it on the touch screen.

### 1.3 The problem on the Ender 5 Max

On the E5M with Klipper mainline 2026 + ADXL345 bridge (see `MEMO_adxl345_bridge_ENG.md`), the **first 4 steps work fine** — TEST_RESONANCES generates valid CSVs. But step 5 (the Frix-x script) crashed in three different ways across iteration:

1. **`Stepper too far in past`** during the test itself — saturation of the UART link at default `adxl345_rate: 3200`. Resolved by setting `adxl345_rate: 1600` in the bridge config.

2. **`terminate called after throwing an instance of 'std::runtime_error'. what(): Couldn't close file. Aborted`** — happened the moment matplotlib tried to load fonts. This is the bug that consumed the most investigation time. See §3.

3. **`FileNotFoundError: '/tmp/raw_data_axis=1.000,-1.000_a.csv'`** — file path mismatch between what the macro expects and what Klipper mainline actually generates. See §4.

This memo documents how each of those was resolved.

---

## 2. The Klipper mainline / Klipper Creality / matplotlib version mismatch

Some context that helps everything else make sense.

### 2.1 The Klipper venv

```bash
$ ls -la /usr/share/klippy-env/
drwxr-xr-x  bin   ...
drwxr-xr-x  lib   ...

$ /usr/share/klippy-env/bin/python --version
Python 3.8.2
```

Created **November 2022** (factory default Creality firmware), Python 3.8.2 (sysrelease 2020).

### 2.2 The packages frozen in there

```
matplotlib  2.2.3   # 2017
numpy       1.16.4  # 2019
Pillow      7.0.0   # 2020
kiwisolver  1.1.0   # ~2018
```

These are **not** required by Klipper itself. The `klippy-requirements.txt` file shipped with Klipper mainline lists only `greenlet`, `cffi`, `Jinja2`, `pyserial`, `python-can`. Numpy and matplotlib are present **only because Creality pre-installed them** for the original belt test scripts.

### 2.3 The libfreetype upgrade

Meanwhile, on the same printer:

```bash
$ /opt/lib/libfreetype.so.6 -> libfreetype.so.6.20.2  (Entware, March 2026)
```

`/opt/` is Entware, an alternative package manager that the user has installed for general MIPS-compatible binaries. Entware's libfreetype is **freetype 2.13.x**.

### 2.4 The ABI conflict

matplotlib 2.2.3 ships with a precompiled C extension:

```
/usr/lib/python3.8/site-packages/matplotlib/ft2font.cpython-38-mipsel-linux-gnu.so
```

This `.so` was compiled in 2017-2018 and **statically linked against the freetype headers of that era** (FT 2.6 / 2.7 / 2.8). When loaded at runtime, it dynamically resolves against the system's `libfreetype.so.6` — but on the E5M with Entware, that's **freetype 2.13**, which has different internal struct sizes, different stream-handling logic, and different memory layout assumptions.

The result: the C++ runtime in `ft2font.so` calls into freetype with what it thinks is a valid `FT_Stream`, freetype writes outside the buffer matplotlib allocated, and on stream cleanup the stack throws:

```
terminate called after throwing an instance of 'std::runtime_error'
  what():  Couldn't close file
```

This crash happens during `matplotlib.font_manager` initialization, which iterates every `.ttf` file in `/usr/lib/python3.8/site-packages/matplotlib/mpl-data/fonts/ttf/`. Even on a single bad font, the C++ exception propagates up and aborts the Python interpreter.

---

## 3. Investigation of the matplotlib font crash

This is the section that documents all the things that **didn't work**, before we found the answer. Useful reading because the same dead-ends will tempt future contributors.

### 3.1 What we ruled out

#### Disabling individual fonts

Hypothesis: maybe one specific font file is corrupted and crashes freetype. Approach: disable fonts one by one, see which one stops the crash.

```bash
# Iteration 1: rename all STIX fonts (math fonts, often weird)
mv STIX*.ttf STIX*.ttf.disabled
# → still crashes, this time on DejaVuSerifDisplay.ttf

# Iteration 2: disable DejaVuSerifDisplay too
# → still crashes, this time on cm10.ttf (Computer Modern)

# Iteration 3: disable all Computer Modern + Display fonts
# → still crashes, this time on DejaVuSerif-Bold.ttf
```

Pattern: every iteration, the next font in the alphabetical scan crashes. This is **not a bad-font issue** — it's a **systemic ABI issue** that affects every font.

#### The "keep only DejaVuSans" approach

Hypothesis: maybe matplotlib only really needs DejaVuSans. Keep that one, disable everything else.

```bash
for f in *.ttf; do
    case "$f" in
        DejaVuSans.ttf|DejaVuSans-Bold.ttf|DejaVuSans-Oblique.ttf|DejaVuSans-BoldOblique.ttf) ;;
        *) mv "$f" "${f}.disabled" ;;
    esac
done

# Test:
/usr/share/klippy-env/bin/python -c "import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot"
# → "Couldn't close file. Aborted"
```

Even on DejaVuSans alone, freetype 2.13 + matplotlib 2.2.3's `ft2font.so` crashes. Confirmed: it's not the font, it's the ABI.

### 3.2 Backend hint: `matplotlib.use('Agg')` — does it help?

Hypothesis: maybe a non-default backend avoids loading display-related fonts.

```python
import matplotlib
matplotlib.use('Agg')          # before pyplot import — allegedly safe
import matplotlib.pyplot       # → still crashes
```

No difference. The crash is during `font_manager` initialization, which `pyplot` triggers regardless of backend.

### 3.3 Compiling matplotlib from source — paths considered

#### Path A: native build on the printer

The MIPS CPU has 2 cores. Compiling matplotlib 3.5+ takes ~30-90 minutes natively. Disk space:

```
$ df -h /
Filesystem      Size      Used Available Use%
overlayfs:/     290.5M    214.4M     61.1M  78%
```

Tight. Not impossible if `TMPDIR` is redirected to `/usr/data` (which has 4.9 GB free), but several deps need C compilation: `Cython`, `kiwisolver`, `contourpy`. Each of those wants headers we don't have (no `python3-dev` package in Entware by default for some of them).

Tried — pip install of `matplotlib<3.6` from PyPI on the printer with full env redirection. Failed at the `freetype.h` header link step (Entware ships the lib but not the dev headers). Moot anyway because of path B.

#### Path B: cross-compile in GitHub Codespaces

Already done for `c_helper.so` (see `MEMO_c_helper_ENG.md`). The toolchain is:

- Ingenic GCC 5.2 from `Dafang-Hacks/mips-gcc520-glibc222-64bit-r3.2.1`
- Target flags: `-mnan=2008 -mfp64 -mabs=2008` (MIPS XBurst2 specific)
- Output: ELF flags `0x70001407, noreorder, pic, cpic, nan2008, o32, mips32r2`

Cross-compiling matplotlib is **considerably harder** than `c_helper.so`:

- 3 C extensions to build (`ft2font`, `_image`, `_path`)
- Each must link against versions of libfreetype/libpng that **exactly match** what's on the printer (Entware: freetype 2.13.3, libpng 1.6.50)
- The Entware headers and libs would need to be downloaded into the codespace as a sysroot
- The Python target is 3.8 (for the venv) or 3.13 (for Entware Python) — different ABI, different `Py_ssize_t` etc.

Estimated effort: 2-4 hours of toolchain wrangling for an uncertain outcome. Not the path we ultimately took.

#### Path C: piwheels / prebuilt wheels

[piwheels.org](https://piwheels.org) is the standard prebuilt Python wheel repository. **It only supports armhf** (Raspberry Pi). MIPS is not supported. PyPI has zero MIPS wheels.

Result: no prebuilt option exists.

### 3.4 The actual solution — the K1 mod from GuppyScreen itself

After hours of investigation, the answer was **already on the printer**, dropped there months ago by the GuppyScreen installer:

```bash
$ ls -la /usr/data/guppyscreen/k1_mods/
-rwxr-xr-x  1 1001  root  101564 Apr 28  2024 ft2font.cpython-38-mipsel-linux-gnu.so
                                                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                                A precompiled, recent-freetype-compatible ft2font.so
```

The ballaswag GuppyScreen project specifically built and ships a `ft2font.cpython-38-mipsel-linux-gnu.so` that:

- Is statically compiled for MIPS little-endian / soft-float / mips32r2
- Targets Python 3.8 (matches the matplotlib 2.2.3 venv)
- Is **dynamically linked against a recent libfreetype** (probably 2.10+, compatible with 2.13)
- Is **101564 bytes** (vs 80828 for the original Creality one)

The guppyscreen `installer.sh` knows about this issue and handles it:

```sh
if [ ! -d "/usr/lib/python3.8/site-packages/matplotlib-2.2.3-py3.8.egg-info" ]; then
    echo "Not replacing matplotlib ft2font module. PSD graphs might not work"
else
    printf "Replacing matplotlib ft2font module for plotting PSD graphs\n"
    cp $K1_GUPPY_DIR/k1_mods/ft2font.cpython-38-mipsel-linux-gnu.so $FT2FONT_PATH
fi
```

### 3.5 Why our system was broken

The user had GuppyScreen installed but the ft2font swap **had never happened**. The most likely cause: a previous reinstall of matplotlib via Creality factory reset, or the GuppyScreen install ran but skipped the swap (maybe the egg-info dir wasn't where the installer expected it). Result: the original (broken) `ft2font.so` was still in place.

### 3.6 The fix

Three commands:

```bash
# 1. Backup the original (in case)
cp /usr/lib/python3.8/site-packages/matplotlib/ft2font.cpython-38-mipsel-linux-gnu.so \
   /usr/lib/python3.8/site-packages/matplotlib/ft2font.cpython-38-mipsel-linux-gnu.so.original

# 2. Install the K1 mod
cp /usr/data/guppyscreen/k1_mods/ft2font.cpython-38-mipsel-linux-gnu.so \
   /usr/lib/python3.8/site-packages/matplotlib/ft2font.cpython-38-mipsel-linux-gnu.so

# 3. Wipe matplotlib's font cache (forces re-scan with new lib)
rm -rf /root/.cache/matplotlib /root/.matplotlib
```

Verification:

```bash
$ md5sum /usr/lib/python3.8/site-packages/matplotlib/ft2font.cpython-38-mipsel-linux-gnu.so
7706852f09ad75472d15ff790ecc0d55
$ md5sum /usr/data/guppyscreen/k1_mods/ft2font.cpython-38-mipsel-linux-gnu.so
7706852f09ad75472d15ff790ecc0d55
# Match — swap successful.

$ /usr/share/klippy-env/bin/python -c "
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
fig, ax = plt.subplots()
ax.plot([1,2,3])
fig.savefig('/tmp/test.png')
print('OK')
"
matplotlib + savefig OK
$ ls -la /tmp/test.png
-rw-r--r--  20117 May  7 16:14 /tmp/test.png
```

PNG generated, 20 KB. matplotlib works.

---

## 4. The CSV filename mismatch

After matplotlib was fixed, a new error appeared:

```
FileNotFoundError: [Errno 2] No such file or directory:
  '/tmp/raw_data_axis=1.000,-1.000_a.csv'
```

But the actual file present in `/tmp` was:

```
/tmp/raw_data_axis=1.000,-1.000,0.000_a.csv
```

Note the extra `,0.000` — Klipper mainline 2026 includes the **Z component** in the filename even when it's zero. Older Klipper versions (and the GuppyScreen macro, written against an older Klipper) used the format without the Z component.

### 4.1 Where the wrong path lives

```bash
$ grep -n "raw_data_axis" /usr/data/printer_data/config/GuppyScreen/guppy_cmd.cfg
56:  RUN_SHELL_COMMAND CMD=guppy_belts_calibration PARAMS=\
"-w {png_width} -l {png_height} -n -o {png_out_path} -k /usr/share/klipper \
 /tmp/raw_data_axis=1.000,-1.000_a.csv \
 /tmp/raw_data_axis=1.000,1.000_b.csv"
```

Two filename references on line 56, both with the old format. **And** a third issue: `-k /usr/share/klipper` points at a path that **doesn't exist** on this system (it's `/usr/data/klipper`).

### 4.2 The fix

```bash
cd /usr/data/printer_data/config/GuppyScreen/
cp guppy_cmd.cfg guppy_cmd.cfg.bak

# Add ',0.000' to both CSV filenames
sed -i 's|raw_data_axis=1.000,-1.000_a.csv|raw_data_axis=1.000,-1.000,0.000_a.csv|g' \
    guppy_cmd.cfg
sed -i 's|raw_data_axis=1.000,1.000_b.csv|raw_data_axis=1.000,1.000,0.000_b.csv|g' \
    guppy_cmd.cfg

# Fix the klipper directory
sed -i 's|-k /usr/share/klipper|-k /usr/data/klipper|g' guppy_cmd.cfg

# Verify
grep "raw_data_axis\|-k /usr" guppy_cmd.cfg
```

Then `FIRMWARE_RESTART` (so Klipper re-reads the macro definitions).

### 4.3 Direct test (no GuppyScreen UI needed)

If the CSVs are still in `/tmp`, the script can be tested directly:

```bash
/usr/data/printer_data/config/GuppyScreen/scripts/graph_belts.py \
  -w 8 -l 4.8 -n \
  -o /usr/data/printer_data/config/belts_calibration.png \
  -k /usr/data/klipper \
  /tmp/raw_data_axis=1.000,-1.000,0.000_a.csv \
  /tmp/raw_data_axis=1.000,1.000,0.000_b.csv
```

Expected (and obtained) output:

```
Warning: CSV filenames look to be different than expected
Warning: belts doesn't seem to have the correct name A and B
Belts estimated similarity: 93.1%
```

The two warnings are **cosmetic**. The script tries to extract belt names from the filename ("a" and "b") and complains about the new format, but the calculation itself is correct. PNG is generated, score is computed.

```bash
$ ls -la /usr/data/printer_data/config/belts_calibration.png
-rw-r--r-- 1 root root 77910 May  7 16:34 belts_calibration.png
```

77 KB PNG. Visually inspectable in Fluidd's File Manager.

---

## 5. The PNG dimension issue — observed but not fixed

### 5.1 Symptom

After fixing matplotlib (§3) and the CSV filenames (§4), the belt test runs to completion and a PNG is generated. **However**, when triggered from the GuppyScreen UI Belts button, the resulting `belts_calibration.png` has visible rendering defects:

- Title text overlapping with subtitle
- Axis labels superimposed on tick numbers
- Legend box bleeding into the chart area
- No `1e5` multiplier on the Y axis
- Generally cramped, hard to read

The same script run **manually from SSH** with `-w 8 -l 4.8` produces a clean, well-laid-out PNG. So the script works, but GuppyScreen passes different dimensions.

### 5.2 Root cause

The GuppyScreen binary (`/usr/data/guppyscreen/guppyscreen`) calls the macro with hardcoded dimension parameters:

```sh
$ strings /usr/data/guppyscreen/guppyscreen | grep "PNG_WIDTH"
GUPPY_BELTS_SHAPER_CALIBRATION PNG_OUT_PATH={} PNG_WIDTH={} PNG_HEIGHT={}
```

The actual values sent (verified by injecting a `RESPOND` debug line into the macro):

```
DEBUG: png_width=4.8 png_height=2.72
```

These dimensions match the Nebula Pad's screen resolution: 480 × 272 pixels at 100 DPI = 4.8" × 2.72". GuppyScreen tries to generate a PNG that exactly fills the screen.

The problem: **matplotlib cannot fit graph_belts.py's content in 480 × 272 pixels** without overlapping text. The script wasn't designed to scale gracefully to that size — its layout assumes ~800 × 480 minimum.

### 5.3 Attempted fix — and why it was reverted

We tested forcing the macro to ignore GuppyScreen's dimensions by hardcoding `8 × 4.8`:

```bash
# Tested but REVERTED — kept here as reference
python3 << 'PYEOF'
content = content.replace(
    "{% set png_width = params.PNG_WIDTH|default(8)|float %}",
    "{% set png_width = 8 %}"
)
# ...
PYEOF
```

This produced a clean, full-quality PNG (800 × 480 px). But it introduced a new cosmetic issue:

GuppyScreen displays `belts_calibration.png` **at native size, no scaling** (confirmed by `strings` inspection — no `lv_img_set_zoom` or `LV_IMG_SIZE_MODE_VIRTUAL` symbols in the binary). So an 800 × 480 PNG is shown at 800 × 480 on a 480 × 272 screen — only the top-left corner is visible.

Two equally imperfect outcomes:

| Approach | PNG quality | GuppyScreen display |
|---|---|---|
| Default (4.8 × 2.72) | Cramped text | Fits screen but illegible |
| Forced (8 × 4.8) | Clean | Cropped, only top-left visible |

**The proper solution is to produce BOTH formats** — one optimized for GuppyScreen's display, one for desktop viewing via Fluidd. See §6 below for the implemented dual-PNG strategy. The dimension-forcing patch was reverted in favor of this approach.

---

## 6. Dual-PNG strategy — small for GuppyScreen, large for PC

Rather than fighting GuppyScreen's hardcoded dimensions, we produce two PNGs per calibration: the one GuppyScreen wants (small, fits the screen), plus a desktop-readable one (large, viewable via Fluidd). Same test data, two renderings.

### 6.1 Architecture overview

```
Belt test:
  GUPPY_BELTS_SHAPER_CALIBRATION (macro)
    ├─ TEST_RESONANCES AXIS=1,1  → /tmp/raw_data_axis=...,0.000_b.csv
    ├─ TEST_RESONANCES AXIS=1,-1 → /tmp/raw_data_axis=...,0.000_a.csv
    ├─ RUN_SHELL_COMMAND guppy_belts_calibration
    │   → graph_belts.py -w 4.8 -l 2.72 → belts_calibration.png       [GuppyScreen]
    └─ RUN_SHELL_COMMAND guppy_belts_calibration_pc
        → gen_belts_png.sh (wrapper)
            → mkdir -p printer_calibration_graphs/
            → graph_belts.py -w 8 -l 4.8 → belts_calibration_PC_SIZE_<timestamp>.png   [PC]

Input Shaper test:
  Triggered by GuppyScreen UI button (bypasses GUPPY_SHAPERS macro,
  calls TEST_RESONANCES + guppy_input_shaper directly)
    ├─ TEST_RESONANCES AXIS=X NAME=x → /tmp/resonances_x_x.csv
    ├─ RUN_SHELL_COMMAND guppy_input_shaper
    │   → gen_shaper_combo.sh (wrapper)
    │       ├─ calibrate_shaper.py CSV → resonances_x.png            [GuppyScreen]
    │       └─ calibrate_shaper.py CSV -w 8 -l 4.8
    │           → resonances_x_PC_SIZE_<timestamp>.png               [PC]
    └─ same for Y axis
```

### 6.2 Why two architectures (macro vs shell-command wrapper)

The two features have different control flow:

- **Belts**: GuppyScreen calls the macro `GUPPY_BELTS_SHAPER_CALIBRATION`. The macro is fully under our control — we add a second `RUN_SHELL_COMMAND` for the PC version.
- **Input Shaper**: GuppyScreen **bypasses** the `GUPPY_SHAPERS` macro. Its binary calls `TEST_RESONANCES AXIS=X NAME=x` directly (confirmed by `strings` inspection), then triggers the shell command `guppy_input_shaper`. We can't add lines to a code path we don't control.

The workaround for Input Shaper: redirect `guppy_input_shaper` to a wrapper script that produces both PNGs. GuppyScreen still calls one command; the wrapper internally fans out.

### 6.3 The shaper combo wrapper

`/usr/data/printer_data/config/GuppyScreen/scripts/gen_shaper_combo.sh`:

```sh
#!/bin/sh
set -e

# 1. GuppyScreen sized PNG (original behavior, pass-through args)
/usr/data/printer_data/config/GuppyScreen/scripts/calibrate_shaper.py "$@"

# 2. Detect axis from CSV path
CSV="$1"
AXIS=$(echo "$CSV" | grep -oE "resonances_[xy]" | sed 's/resonances_//')
[ -z "$AXIS" ] && AXIS="unknown"

# 3. PC sized PNG
OUT_DIR="/usr/data/printer_data/config/printer_calibration_graphs"
mkdir -p "$OUT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT_PNG="$OUT_DIR/resonances_${AXIS}_PC_SIZE_${TIMESTAMP}.png"

/usr/data/printer_data/config/GuppyScreen/scripts/calibrate_shaper.py \
    "$CSV" -o "$OUT_PNG" -w 8 -l 4.8

echo "PC-sized shaper PNG: $OUT_PNG"
```

And `gcode_shell_command guppy_input_shaper` is repointed to it:

```ini
[gcode_shell_command guppy_input_shaper]
command: /usr/data/printer_data/config/GuppyScreen/scripts/gen_shaper_combo.sh
timeout: 600.0
verbose: True
```

GuppyScreen still calls `guppy_input_shaper` exactly as before. The wrapper produces the small PNG (for GuppyScreen's display, identical to before), then transparently makes a PC-sized one.

### 6.4 The belts wrapper and macro patch

`/usr/data/printer_data/config/GuppyScreen/scripts/gen_belts_png.sh`:

```sh
#!/bin/sh
set -e

CSV_A="$1"
CSV_B="$2"

OUT_DIR="/usr/data/printer_data/config/printer_calibration_graphs"
mkdir -p "$OUT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT_PNG="$OUT_DIR/belts_calibration_PC_SIZE_${TIMESTAMP}.png"

/usr/data/printer_data/config/GuppyScreen/scripts/graph_belts.py \
    -w 8 -l 4.8 -n -o "$OUT_PNG" \
    -k /usr/data/klipper \
    "$CSV_A" "$CSV_B"

echo "PC-sized belts PNG: $OUT_PNG"
```

A new shell command in `guppy_cmd.cfg`:

```ini
[gcode_shell_command guppy_belts_calibration_pc]
command: /usr/data/printer_data/config/GuppyScreen/scripts/gen_belts_png.sh
timeout: 600.0
verbose: True
```

And the macro `GUPPY_BELTS_SHAPER_CALIBRATION` gets one extra `RUN_SHELL_COMMAND` at the end:

```ini
  RUN_SHELL_COMMAND CMD=guppy_belts_calibration PARAMS="-w {png_width} -l {png_height} -n -o {png_out_path} -k /usr/data/klipper /tmp/raw_data_axis=1.000,-1.000,0.000_a.csv /tmp/raw_data_axis=1.000,1.000,0.000_b.csv"
  RESPOND MSG="Generating Belts Plot (PC size)..."
  RUN_SHELL_COMMAND CMD=guppy_belts_calibration_pc PARAMS="/tmp/raw_data_axis=1.000,-1.000,0.000_a.csv /tmp/raw_data_axis=1.000,1.000,0.000_b.csv"
```

### 6.5 Output naming convention

PC-sized PNGs go into a dedicated subdirectory with timestamped filenames:

```
/usr/data/printer_data/config/printer_calibration_graphs/
├── belts_calibration_PC_SIZE_20260511_040339.png
├── resonances_x_PC_SIZE_20260511_041103.png
└── resonances_y_PC_SIZE_20260511_041152.png
```

Benefits:
- **History preserved** — every test produces a new file, no overwrite
- **GuppyScreen files untouched** — `resonances_x.png`, `resonances_y.png`, `belts_calibration.png` stay where GuppyScreen expects them
- **Easy cleanup** — delete the whole subdirectory to reset history; wrappers re-create it on next run

### 6.6 Side fix — calibrate_shaper.py shebang

When testing the Input Shaper path standalone (without GuppyScreen), `calibrate_shaper.py` failed with:

```
ModuleNotFoundError: No module named 'matplotlib'
```

Cause: the script's shebang `#!/usr/bin/env python3` resolves to `/opt/bin/python3` (Entware Python 3.13), which doesn't have matplotlib. Only the legacy Klipper venv at `/usr/share/klippy-env/bin/python` has the patched matplotlib 2.2.3 from §3.

Fix:

```bash
sed -i '1c#!/usr/share/klippy-env/bin/python' \
    /usr/data/printer_data/config/GuppyScreen/scripts/calibrate_shaper.py
```

`graph_belts.py` already had the correct shebang.

---

## 7. Cosmetic improvements to graph_belts.py

The Frix-x `graph_belts.py` script emits two warnings on every Klipper-native CSV input, and uses A/B belt labels that don't match the Ender 5 Max's physical labeling.

### 7.1 Warning 1 — "CSV filenames look to be different than expected"

The script tries to parse a date/time from the filename:

```python
# Lines ~521-527 of graph_belts.py
try:
    filename = lognames[0].split('/')[-1]
    dt = datetime.strptime(f"{filename.split('_')[1]} {filename.split('_')[2]}",
                          "%Y%m%d %H%M%S")
    title_line2 = dt.strftime('%x %X')
except:
    print("Warning: CSV filenames look to be different than expected ...")
    title_line2 = lognames[0].split('/')[-1] + " / " + lognames[1].split('/')[-1]
```

It expects the historic Klippain-shaketune filename format `belt_a_YYYYMMDD_HHMMSS_a.csv`. But Klipper mainline 2026 generates `raw_data_axis=1.000,-1.000,0.000_a.csv` — no date in the name. The except branch fires every time.

**Fix**: add a graceful fallback that uses the file's modification time:

```python
try:
    filename = lognames[0].split('/')[-1]
    dt = datetime.strptime(f"{filename.split('_')[1]} {filename.split('_')[2]}",
                          "%Y%m%d %H%M%S")
    title_line2 = dt.strftime('%x %X')
except:
    # Klipper-native format: use file mtime as title date
    try:
        import os
        mtime = os.path.getmtime(lognames[0])
        dt = datetime.fromtimestamp(mtime)
        title_line2 = dt.strftime('%x %X')
    except:
        title_line2 = lognames[0].split('/')[-1] + " / " + lognames[1].split('/')[-1]
```

Result: title now reads "05/11/26 04:03:39" (file creation time) instead of a long messy filename.

### 7.2 Warning 2 — "belts doesn't seem to have the correct name A and B"

The script extracts the belt letter from the filename:

```python
# Line ~297
signal1_belt = (lognames[0].split('/')[-1]).split('_')[-1][0]
# → for raw_data_axis=...,0.000_a.csv: '_a.csv'.split('_')[-1][0] = 'a' (lowercase)
```

Then compares case-sensitively:

```python
if signal1_belt == 'A' and signal2_belt == 'B':   # 'a' != 'A'  → fails
```

Klipper writes lowercase filenames; the script expects uppercase. Mismatch → warning fires every time.

**Fix**: uppercase the extracted letter:

```python
signal1_belt = (lognames[0].split('/')[-1]).split('_')[-1][0].upper()
signal2_belt = (lognames[1].split('/')[-1]).split('_')[-1][0].upper()
```

### 7.3 Belt naming — A/B vs X/Y

On the Ender 5 Max (a true CoreXY printer), the convention in the upstream `graph_belts.py` is to label belts as "A" and "B" — technically correct since neither belt drives X or Y independently. However, the user-facing convention in Creality's documentation and the E5M-CK project is **"X belt"** and **"Y belt"**, identifying them by which stepper drives them.

**Empirical verification via diagonal moves**:

```
G91 G0 X10 Y-10 F3000   → only stepper_x rotates → moves the "X belt"
G91 G0 X10 Y10  F3000   → only stepper_y rotates → moves the "Y belt"
```

(Test confirmed on the user's E5M.)

In Klipper CoreXY kinematics, `AXIS=1,-1` exercises stepper_x alone (= X belt), and `AXIS=1,1` exercises stepper_y alone (= Y belt). The macro produces:

```
TEST_RESONANCES AXIS=1,-1 NAME=a  →  /tmp/raw_data_axis=...,0.000_a.csv  →  X belt
TEST_RESONANCES AXIS=1,1  NAME=b  →  /tmp/raw_data_axis=...,0.000_b.csv  →  Y belt
```

**Fix**: remap A→"X belt", B→"Y belt" in the chart legend, and remove the redundant "Belt " prefix in the plot label:

```python
# E5M-CK: remap A/B (CoreXY convention) to X/Y (physical belts on Ender 5 Max)
#   Belt A = stepper_x rotation = X belt (verified via STEPPER_BUZZ + diagonal moves)
#   Belt B = stepper_y rotation = Y belt
if signal1_belt == 'A' and signal2_belt == 'B':
    signal1_belt = "X belt"
    signal2_belt = "Y belt"
elif signal1_belt == 'B' and signal2_belt == 'A':
    signal1_belt = "Y belt"
    signal2_belt = "X belt"
else:
    print("Warning: belts doesn't seem to have the correct name A and B ...")

# And in the plot calls:
ax.plot(signal1.freqs, signal1.psd, label=signal1_belt, ...)   # was: "Belt " + signal1_belt
ax.plot(signal2.freqs, signal2.psd, label=signal2_belt, ...)
```

The peak annotations (`A1`, `A2`, `B1`, `B2`...) are **unaffected** — they come from a separate `ALPHABET[paired_peak_count]` variable and continue to use sequential letters per detected peak pair.

### 7.4 Combined patch

All three fixes applied via one Python script that reads, replaces, and writes back. See `installs/patch_graph_belts.sh` in the E5M-CK repository for the deployable version. Backup is preserved as `graph_belts.py.bak` and `graph_belts.py.bak2`.

---

## 8. The duplicated-logs bug

After deploying the dual-PNG strategy, every macro message and every shell command appeared **twice** in the Fluidd console:

```
Belts comparative frequency profile generation (GuppyScreen)...
Belts comparative frequency profile generation (GuppyScreen)...
// Running Command {guppy_belts_calibration}...:
// Running Command {guppy_belts_calibration}...:
```

Root cause discovered via:

```bash
$ grep -rn "include.*guppy_cmd\|include.*GuppyScreen" /usr/data/printer_data/config/*.cfg
/usr/data/printer_data/config/printer-20260507_105940.cfg:12:[include GuppyScreen/*.cfg]
/usr/data/printer_data/config/printer.cfg:13:[include GuppyScreen/*.cfg]
```

A **dated backup of printer.cfg** had been left in the `config/` directory. Klipper loads every `.cfg` in that directory (since `printer.cfg` is just one entry of many), and both files contain `[include GuppyScreen/*.cfg]` — so all GuppyScreen macros got loaded twice, all shell commands got registered twice, and every G-code command got executed twice.

**Fix**: move any backup `.cfg` files **out** of `printer_data/config/`:

```bash
mkdir -p /usr/data/printer_data/backup_cfg
mv /usr/data/printer_data/config/printer-*.cfg \
   /usr/data/printer_data/backup_cfg/
```

**Lesson**: Klipper's `[include]` wildcard matching is **directory-wide**, not just for files referenced from `printer.cfg`. Renaming to `.bak` extension is enough to exclude from the include scan; moving to a different folder is safer.

---



## 9. Validation procedure — full belt test

### 9.1 Prerequisites

- ADXL345 bridge installed and working (`MEMO_adxl345_bridge_ENG.md`).
- `adxl345_rate: 1600` in `[accel_chip_proxy]` block.
- ft2font swap done (§3.6).
- guppy_cmd.cfg patched for CSV filenames (§4.2).
- Dual-PNG strategy installed (§6): wrappers in place, `guppy_input_shaper` redirected to combo, belts macro extended.
- graph_belts.py cosmetic patches applied (§7).
- No duplicate `[include]`-bearing cfg in `config/` (§8).
- Klipper restarted with FIRMWARE_RESTART so macros are reloaded.

### 9.2 Run from GuppyScreen

Touch screen → **Belts** button.

GuppyScreen calls `GUPPY_BELTS_SHAPER_CALIBRATION FREQ_START=5 FREQ_END=44.6 HZ_PER_SEC=2 PNG_WIDTH=4.8 PNG_HEIGHT=2.72`. The test runs ~3 minutes, then **two PNGs** are produced:

- `/usr/data/printer_data/config/belts_calibration.png` — small (480×272), for GuppyScreen's display
- `/usr/data/printer_data/config/printer_calibration_graphs/belts_calibration_PC_SIZE_<timestamp>.png` — large (800×480), for desktop viewing

Similarly, **Input Shaper** button produces small + PC PNGs per axis.

### 9.3 Run from Fluidd console

```
GUPPY_BELTS_SHAPER_CALIBRATION FREQ_START=5 FREQ_END=44.6 HZ_PER_SEC=2
```

`GUPPY_SHAPERS` can also be invoked from Fluidd console but **isn't** what the GuppyScreen Input Shaper button calls — the button bypasses the macro and calls `TEST_RESONANCES` + `guppy_input_shaper` directly.

### 9.4 Manual run (for debugging)

```
TEST_RESONANCES AXIS=1,1 OUTPUT=raw_data
TEST_RESONANCES AXIS=1,-1 OUTPUT=raw_data
RUN_SHELL_COMMAND CMD=guppy_belts_calibration PARAMS="-w 8 -l 4.8 -n \
  -o /usr/data/printer_data/config/belts_calibration.png \
  -k /usr/data/klipper \
  /tmp/raw_data_axis=1.000,-1.000,0.000_a.csv \
  /tmp/raw_data_axis=1.000,1.000,0.000_b.csv"
```

### 9.5 Reading the result

The PC-sized PNG (`printer_calibration_graphs/belts_calibration_PC_SIZE_*.png`) contains:

- **PSD curves**: `X belt` (purple) and `Y belt` (orange), overlaid. Peaks should overlap closely if belts are balanced.
- **Relax region**: pale green band; peaks below this threshold are ignored.
- **Annotated peaks**: black `×` markers with labels (`A1`/`A2` for first paired peak pair, `B1`/`B2` for second, etc.).
- **Score & table**: top-right, similarity percentage and per-peak frequency/amplitude deltas.

Interpretation of similarity score:

| Score | Meaning |
|---|---|
| > 95% | Excellent — belts perfectly balanced |
| 90-95% | Good — minor imbalance, prints will be fine |
| 85-90% | Acceptable — printable, but consider retensioning |
| < 85% | Imbalanced — retension before serious printing |

The user's E5M consistently scored **84.9% – 92.6%** across multiple measurements — within the "acceptable" to "good" band.

### 9.6 Reading the Input Shaper results

The PC-sized PNGs (`printer_calibration_graphs/resonances_x_PC_SIZE_*.png` and `_y_*`) show:

- **Power spectral density** of the axis frequency response
- **Shapers overlaid**: ZV, MZV, EI, 2HUMP_EI, 3HUMP_EI — each with the residual vibration percentage, smoothing factor, and `max_accel` ceiling
- **Recommended shaper**: highlighted in the legend

The recommendation appears in the Fluidd console too, as JSON:

```
{"shapers": {"zv": {...}, "mzv": {...}, ...}, "best": "mzv", ...}
```

GuppyScreen displays the small PNGs and offers a `Save` button to write the recommendation into `printer.cfg` via `SAVE_INPUT_SHAPER`.

---

## 10. Failure modes encountered (and resolved)

| Symptom | Root cause | Fix |
|---|---|---|
| `Stepper too far in past` during TEST_RESONANCES | UART link saturated at 3200 Hz | `adxl345_rate: 1600` in proxy config |
| `terminate ... Couldn't close file. Aborted` on PNG generation | matplotlib 2.2.3 ft2font.so vs freetype 2.13 ABI mismatch | Swap to `/usr/data/guppyscreen/k1_mods/ft2font.cpython-38-mipsel-linux-gnu.so` |
| `FileNotFoundError /tmp/raw_data_axis=1.000,-1.000_a.csv` | Klipper mainline filename format changed (added Z component) | sed in `guppy_cmd.cfg` to add `,0.000` |
| graph_belts.py imports fail | wrong `-k` path | Change `-k /usr/share/klipper` to `-k /usr/data/klipper` |
| PNG visually broken on PC view | GuppyScreen sends `PNG_WIDTH=4.8 PNG_HEIGHT=2.72` (480×272 px) — too small for matplotlib layout | Dual-PNG strategy (§6): small for GuppyScreen, large for PC |
| `ModuleNotFoundError: No module named 'matplotlib'` running calibrate_shaper.py | Shebang `/usr/bin/env python3` resolves to Entware (no matplotlib) | Change shebang to `/usr/share/klippy-env/bin/python` |
| Input Shaper button doesn't produce PC PNG | GuppyScreen bypasses `GUPPY_SHAPERS` macro and calls shell command directly | Wrap shell command with `gen_shaper_combo.sh` that produces both sizes |
| Every macro line/command duplicated in Fluidd console | A dated backup `.cfg` in `config/` got auto-included | Move backups to a folder outside `config/` |
| Warning "CSV filenames look to be different than expected" | graph_belts.py expects historic Klippain filename format | Add fallback to `os.path.getmtime()` for title date |
| Warning "belts doesn't seem to have the correct name A and B" | Case-sensitive comparison of lowercase filename letter | `.upper()` on extracted letter |
| Legend says "Belt A" / "Belt B" — confusing for E5M users | CoreXY convention vs Creality user-facing labeling | Remap to `X belt` / `Y belt` |

---

## 11. What we tried that didn't work — record for future reference

These are the dead-ends we walked into. Listing them here so future maintainers don't repeat them.

### 11.1 Disabling subset of fonts

Cycled through STIX → DejaVuSerif* → CM* → DejaVuSans* one by one. Each round, the next font in alphabetical order would crash. Confirmed not a font-specific bug.

### 11.2 Forcing specific matplotlib backend

Tried `matplotlib.use('Agg')` before importing pyplot. Crashes regardless. The font_manager scan happens during pyplot init, before backend selection matters for fonts.

### 11.3 Compiling matplotlib natively on the printer

Tried `pip install matplotlib<3.6` with `TMPDIR=/usr/data/pip-tmp` etc. Failed during the `ft2font` C extension build because Entware doesn't ship freetype dev headers.

### 11.4 Trying to find a prebuilt MIPS wheel on PyPI / piwheels

None exist. piwheels is armhf-only. PyPI doesn't ship MIPS wheels for matplotlib at any version.

### 11.5 Cross-compiling matplotlib in Codespaces

Theoretically possible (we have the toolchain working for `c_helper.so` already). Practically: 3 C extensions, multiple deps to ABI-match against the printer's Entware libs, 2-4 hours of work for uncertain results.

Not pursued because we found the K1 mod ft2font.so already on the printer, which solved the problem in 30 seconds.

### 11.6 Patching the GuppyScreen binary for image scaling

Tried locating LVGL image-scaling symbols (`lv_img_set_zoom`, `LV_IMG_SIZE_MODE_VIRTUAL`) in the binary:

```bash
$ strings /usr/data/guppyscreen/guppyscreen | grep -iE "lv_img|img_set|set_zoom|size_mode"
# (empty)
```

The `BeltsCalibrationPanel` C++ class hardcodes the image widget. Patching the binary would require recompiling GuppyScreen from source — out of scope. The dual-PNG strategy (§6) is the alternative.

### 11.7 Forcing 8×4.8 dimensions for everything

We tested overriding GuppyScreen's `PNG_WIDTH=4.8 PNG_HEIGHT=2.72` to always use 8×4.8 in the macro. PNG was clean, but GuppyScreen's on-screen display showed only the top-left quadrant (no auto-scaling — see §11.6). The dual-PNG strategy was preferred because it serves both audiences cleanly: GuppyScreen sees what it wants, the user sees a proper graph on the PC.

### 11.8 Modifying calibrate_shaper.py and graph_belts.py in place

Considered modifying the Python scripts directly to produce both sizes in one call. Rejected because:

- Touches third-party code that may get updated/overwritten by future GuppyScreen installs
- The wrapper-script approach is more transparent and easier to maintain
- Performance: a second call adds only ~5 seconds to a 3-minute test

The cosmetic patches in §7 are a different matter — they're small targeted edits with clear backups, and the affected code paths aren't expected to change upstream.

---

## 12. Recap — minimum commands

Full deployment, assuming the ADXL345 bridge is already in place:

```bash
# ─── §3 — Fix matplotlib ft2font ABI ───────────────────
cp /usr/data/guppyscreen/k1_mods/ft2font.cpython-38-mipsel-linux-gnu.so \
   /usr/lib/python3.8/site-packages/matplotlib/ft2font.cpython-38-mipsel-linux-gnu.so
rm -rf /root/.cache/matplotlib /root/.matplotlib

# ─── §4 — Fix CSV filename format and -k path ──────────
sed -i 's|raw_data_axis=1.000,-1.000_a.csv|raw_data_axis=1.000,-1.000,0.000_a.csv|g' \
    /usr/data/printer_data/config/GuppyScreen/guppy_cmd.cfg
sed -i 's|raw_data_axis=1.000,1.000_b.csv|raw_data_axis=1.000,1.000,0.000_b.csv|g' \
    /usr/data/printer_data/config/GuppyScreen/guppy_cmd.cfg
sed -i 's|-k /usr/share/klipper|-k /usr/data/klipper|g' \
    /usr/data/printer_data/config/GuppyScreen/guppy_cmd.cfg

# ─── §6.6 — Fix calibrate_shaper.py shebang ────────────
sed -i '1c#!/usr/share/klippy-env/bin/python' \
    /usr/data/printer_data/config/GuppyScreen/scripts/calibrate_shaper.py

# ─── §6 — Install dual-PNG wrappers ────────────────────
wget --no-check-certificate \
  https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/gen_belts_png.sh \
  -O /usr/data/printer_data/config/GuppyScreen/scripts/gen_belts_png.sh
wget --no-check-certificate \
  https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/gen_shaper_png.sh \
  -O /usr/data/printer_data/config/GuppyScreen/scripts/gen_shaper_png.sh
# Combo wrapper (intercepts guppy_input_shaper)
wget --no-check-certificate \
  https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/gen_shaper_combo.sh \
  -O /usr/data/printer_data/config/GuppyScreen/scripts/gen_shaper_combo.sh
chmod +x /usr/data/printer_data/config/GuppyScreen/scripts/gen_*.sh

# Patch guppy_cmd.cfg: add new shell commands + extend belts macro
# (see PATCH_guppy_cmd.txt in repo for the full Python script)

# ─── §7 — Apply graph_belts.py cosmetic patches ────────
# (see installs/patch_graph_belts.sh in repo)

# ─── §8 — Move any duplicate cfg backups out ───────────
mkdir -p /usr/data/printer_data/backup_cfg
mv /usr/data/printer_data/config/printer-*.cfg \
   /usr/data/printer_data/backup_cfg/ 2>/dev/null || true

# ─── Restart and validate ──────────────────────────────
/etc/init.d/S55klipper_service restart

# Test from GuppyScreen UI: Belts button + Input Shaper button.
# Verify outputs:
ls -la /usr/data/printer_data/config/belts_calibration.png
ls -la /usr/data/printer_data/config/resonances_x.png
ls -la /usr/data/printer_data/config/resonances_y.png
ls -la /usr/data/printer_data/config/printer_calibration_graphs/
```

---

## 13. Open questions / future work

### 13.1 Why didn't the GuppyScreen installer swap ft2font?

The installer logic is:

```sh
if [ ! -d "/usr/lib/python3.8/site-packages/matplotlib-2.2.3-py3.8.egg-info" ]; then
    echo "Not replacing matplotlib ft2font module."
else
    cp $K1_GUPPY_DIR/k1_mods/ft2font.cpython-38-mipsel-linux-gnu.so $FT2FONT_PATH
fi
```

It checks for the **egg-info** directory of matplotlib 2.2.3. If present → swap. If absent → skip.

On the user's system, the egg-info was either:
- Not present at install time (matplotlib was reinstalled/repaired afterwards)
- Or present but at a slightly different path

Either way, the conditional fired the wrong branch. **Fix would be**: drop the conditional and always swap. But that's a change to ballaswag's installer, not something to do unilaterally.

### 13.2 Should the bridge installer also handle the dual-PNG setup?

Plausible enhancement to `install_adxl_patch_v2.sh`: detect missing wrappers and offer to install them. This would consolidate all GuppyScreen fixes into a single install command.

Not a priority — each individual fix is well-documented and reversible.

### 13.3 Should we patch graph_belts.py for the small-display case?

Currently the GuppyScreen-sized PNG (480×272) has cramped text. A genuine fix would patch `graph_belts.py` to detect a small canvas and adapt the layout: smaller fonts, no detailed legend, tighter ratios.

Estimated effort: 30-60 minutes of Python work + iterative testing. Not done because:

- The PC-sized PNG (§6) covers the desktop use case
- Belt tests are infrequent (every few months at most)
- The cramped on-screen rendering is mostly cosmetic — the user can read the similarity score, which is what matters operationally

Future enhancement candidate.

### 13.4 Should we upstream the cosmetic patches?

The §7 fixes (warning suppression, A/B → X/Y remap, mtime fallback) are arguably useful for all CoreXY users running Klipper mainline, not just E5M-CK. They could be submitted to ballaswag's `guppyscreen` repo (or the upstream Frix-x `klippain-shaketune` if they share the same `graph_belts.py`). Out of scope for this project, but a candidate for a clean PR.

---

## 14. Repository layout

```
E5M-CK/
├── files/
│   ├── adxl345_creality.py
│   ├── accel_chip_proxy.py
│   └── ft2font.cpython-38-mipsel-linux-gnu.so   ← optional mirror of K1 mod
├── installs/
│   ├── install_adxl_patch_v2.sh
│   ├── gen_belts_png.sh                          ← dual-PNG wrapper (belts)
│   ├── gen_shaper_png.sh                         ← dual-PNG wrapper (shaper, standalone)
│   ├── gen_shaper_combo.sh                       ← combo wrapper (intercepts guppy_input_shaper)
│   ├── PATCH_guppy_cmd.txt                       ← manual patch instructions
│   └── patch_graph_belts.sh                      ← cosmetic patches (§7)
└── docs/
    ├── MEMO_c_helper_ENG.md
    ├── MEMO_adxl345_bridge_ENG.md
    └── MEMO_guppyscreen_belts_ENG.md   ← this file
```

The K1-mod `ft2font.cpython-38-mipsel-linux-gnu.so` is also retrievable directly from the GuppyScreen GitHub releases (asset `guppyscreen.tar.gz` → `k1_mods/ft2font.cpython-38-mipsel-linux-gnu.so`):

- https://github.com/ballaswag/guppyscreen/releases

MD5 of the working version: `7706852f09ad75472d15ff790ecc0d55` (101564 bytes).

---

*Document written in May 2026 as part of the E5M-CK project. Companion to `MEMO_c_helper_ENG.md` and `MEMO_adxl345_bridge_ENG.md`.*
