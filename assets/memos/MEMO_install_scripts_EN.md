# MEMO — E5M-CK install scripts (architecture, generation, usage)

> **Scope** — This memo documents every install script in `installs/` of the E5M-CK repository: how each one was designed, what problem it solves, when to run it, what it modifies, and how to debug it. Audience: developers maintaining or forking the project, including the original author six months from now.

---

## Table of contents

1. [Project context](#1-project-context)
2. [Shared conventions](#2-shared-conventions)
3. [Hosted binaries](#3-hosted-binaries)
4. [Script-by-script reference](#4-script-by-script-reference)
5. [Recommended install order](#5-recommended-install-order)
6. [Update workflow](#6-update-workflow)
7. [Debugging cheat sheet](#7-debugging-cheat-sheet)

---

## 1. Project context

E5M-CK is a stack rebuild for the **Creality Ender 5 Max** with **Nebula Pad** (touchscreen control unit). The goal is to replace the stock Creality firmware/Helper-Script setup with a fully autonomous, reproducible install of:

- **Klipper mainline** (instead of Creality's fork)
- **Moonraker** (with working Update Manager)
- **Fluidd** (web UI)
- **GuppyScreen** (touch UI by ballaswag)
- **BTT Eddy USB** (eddy current probe)

The Nebula Pad runs **Buildroot Linux** on an **Ingenic X2000 SoC** (MIPS XBurst II V2). All scripts target this platform exclusively.

### Hardware identifiers

- **SoC** — Ingenic X2000 (`uname -m` returns `mips`)
- **Mainboard MCU** — GD32F303RET6, board ID `CR4NS200323C10`
- **Nozzle MCU** — GD32F303CBT6, board ID `CR-NOZZLE_V21`
- **Touchscreen** — 480×544 px, accessed via `/sys/class/graphics/fb0`
- **Stock loader** — `/lib/ld-2.29.so` (Creality 1.3.x firmware)

### Repository layout

```
E5M-CK/
├── installs/                 # 12 install scripts (subject of this memo)
├── configs/                  # Configuration files deployed to the printer
│   ├── moonraker.conf
│   ├── guppyconfig.json
│   ├── backup-fluidd-v1.36.4-fluidd.json
│   └── cfg/                  # Klipper *.cfg files
├── files/                    # Binary blobs hosted in the repo
│   ├── c_helper.so
│   ├── btteddy.uf2
│   ├── moonraker-env.tar.gz
│   └── e5m_ck_logo.jpg
└── assets/memos/             # Technical documentation (FR + EN)
```

---

## 2. Shared conventions

Every install script follows the same conventions. Once you've read one, you've read them all.

### 2.1 Execution model

Scripts run **on the printer** over SSH. The standard one-liner is:

```sh
wget --no-check-certificate \
    https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_<name>.sh \
    -O /tmp/install_<name>.sh && sh /tmp/install_<name>.sh
```

This pattern was chosen because:

- The Nebula Pad has very limited tooling (no `git` initially, busybox-only utilities, no `bash`).
- The user can copy a single line to install or update anything.
- `wget` and `sh` are always present.

### 2.2 Visual identity

Every script begins with a banner:

```
    ███████╗███████╗███╗   ███╗       ██████╗██╗  ██╗
    ██╔════╝██╔════╝████╗ ████║      ██╔════╝██║ ██╔╝
    █████╗  ███████╗██╔████╔██║█████╗██║     █████╔╝
    ██╔══╝  ╚════██║██║╚██╔╝██║╚════╝██║     ██╔═██╗
    ███████╗███████║██║ ╚═╝ ██║      ╚██████╗██║  ██╗
    ╚══════╝╚══════╝╚═╝     ╚═╝       ╚═════╝╚═╝  ╚═╝

              install_<name>.sh
        <one-line description>

                    ▓▓ CR*ALITY S*CKS ▓▓

         github.com/christianKEL/E5M-CK
```

A red/white/black ANSI palette is applied throughout. The "CR*ALITY S*CKS" tag is intentional — it signals to the user that this is a third-party, opinionated alternative to Creality's stock setup.

### 2.3 Logging primitives

All scripts share five log helpers:

| Helper | Symbol | Purpose |
|---|---|---|
| `log_info "msg"` | `i` | Informational |
| `log_ok "msg"` | `✓` | Step succeeded |
| `log_warn "msg"` | `!` | Non-fatal anomaly |
| `log_error "msg"` | `✗` | Fatal error (caller usually `exit 1`) |
| `log_action "msg"` | `>` | Sub-step / detail |

And one section header:

| Helper | Output |
|---|---|
| `log_step "N" "Title"` | A boxed banner around the step number and title |

Every log line is prefixed with the current `HH:MM:SS` time, which is essential when debugging from a terminal scrollback.

### 2.4 Common patterns

**`die()`** — fatal-error helper that calls `log_error` then `exit 1`:

```sh
die() {
    log_error "$1"
    exit 1
}
```

**`confirm()`** — interactive y/N prompt that defaults to "no":

```sh
confirm() {
    printf "  > $1 [y/N] "
    read CONFIRM
    case "$CONFIRM" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}
```

**`find_python()`** — locate the best Python 3 interpreter available, in priority order: `/opt/bin/python3` (Entware), `/usr/bin/python3` (system), `/usr/share/klippy-env/bin/python` (Klipper venv), `/usr/data/moonraker/moonraker-env/bin/python` (Moonraker venv).

### 2.5 Idempotence

Most scripts support being re-run safely. The two main patterns are:

- **Flag files** — A marker like `/usr/data/<thing>/.e5m_ck_installed` plus a version file `/usr/data/<thing>/.e5m_ck_version`. On re-run, the script detects the existing install and switches to UPDATE mode.
- **Conditional operations** — Each step checks whether its target state is already reached (`if [ ! -f ... ]`, `if pgrep ... >/dev/null`) before acting.

When idempotence cannot be guaranteed (e.g. `install_factory_reset.sh`), the script declares its destructive nature in the disclaimer and requires `y` confirmation.

### 2.6 Backups

Every script that modifies system files creates a timestamped or named backup first:

| Path | Created by |
|---|---|
| `/usr/data/E5M_CK/<file>.bak.<date>` | Most install scripts |
| `/usr/data/guppyify-backup/` | `install_guppyscreen.sh` |
| `/usr/data/logo_originals/` | `install_personalization.sh` |
| `/usr/data/klipper/klippy/configfile.py.bak.before_e5m_ck` | `install_klipper_patches.sh` |
| `/etc/init.d/S56moonraker_service.before_E5M_CK` | `install_moonraker.sh` |
| `/etc/init.d/S50nginx.bak` | `install_nginx.sh` |

Backups are designed to allow manual rollback if the script fails partway or if the user wants to revert.

### 2.7 Hosted binaries

A few binaries cannot be reasonably regenerated on the printer (no compiler toolchain, no Python build environment for some packages). They are hosted in `files/` of the repo with documented MD5 hashes for integrity verification. See section 3.

---

## 3. Hosted binaries

The repo hosts four binary files that the install scripts download. Each is documented with its origin and integrity hash where applicable.

| File | Size | Origin | Used by |
|---|---|---|---|
| `c_helper.so` | ~150 KB | Compiled MIPS XBurst2 helper from Klipper repo (extracted from Helper-Script) | `install_klipper.sh` |
| `btteddy.uf2` | ~70 KB | BTT firmware for the Eddy USB probe | `install_eddy.sh` |
| `moonraker-env.tar.gz` | ~16 MB | Pre-built Python virtual environment for Moonraker (extracted from Helper-Script's working install, validated via `pip list`) | `install_moonraker.sh` |
| `e5m_ck_logo.jpg` | varies | Custom boot logo image | `install_personalization.sh` |

The rationale for hosting these in the repo (rather than pulling them from upstream sources) is **autonomy** — the project should not break if Helper-Script disappears, if BTT changes URLs, or if upstream venv builds become unavailable. Hosted binaries are pinned and reproducible.

See `assets/memos/MEMO_c_helper_FR.md` and `MEMO_moonraker_venv_FR.md` for the full traceability of those two binaries.

---

## 4. Script-by-script reference

### 4.1 `install_factory_reset.sh`

**Purpose** — Reset the printer's filesystem state by triggering Creality's stock factory-reset mechanism (a USB key with a specific marker file).

**Generated because** — At the start of the project, we needed a clean baseline before installing anything. Re-runnable factory resets are useful when a user wants to scrap an install and start over without re-flashing the SD card.

**Pre-conditions** — None (works on any Nebula Pad state).

**Post-conditions** — Stock Creality firmware restored. `/usr/data/` is **preserved** (this is by Creality's design — they only reset `/etc/init.d/`, `/usr/bin/`, etc.).

**Steps** —
1. Pre-checks (network, disk).
2. Deploy the factory-reset trigger script `S58factoryreset` to `/etc/init.d/`.
3. Print instructions: insert a USB key with a file named `factory_reset` (no extension) at the root, then power-cycle the printer.

**Idempotent** — Yes. Re-running just re-deploys the trigger script.

**Notes** — The factory reset itself is performed by Creality's stock loader on next boot; this script only prepares the trigger. If the trigger script is already present, it is overwritten.

---

### 4.2 `install_entware.sh`

**Purpose** — Install Entware (an OpenWrt-derived package manager) at `/opt/`. Provides `python3`, `git`, `curl`, `wget` (modern), `nano`, `htop`, and other tools missing from the Buildroot rootfs.

**Generated because** — The Nebula Pad's Buildroot is too minimal for a Klipper/Moonraker install: no `git`, no real `python3`, no `pip`. Entware solves this without modifying the read-only rootfs (it lives entirely in `/opt/`, which is on `/usr/data/`).

**Pre-conditions** —
- Network connectivity.
- `/opt/` and `/overlay/` are mounted (default on Nebula Pad).
- Architecture detected as `mips` with `nan2008` ABI flags.

**Post-conditions** — Entware fully installed. `~70 packages` available. `/etc/profile.d/entware.sh` ensures `/opt/bin` and `/opt/sbin` are in `$PATH` after a re-login.

**Steps** —
1. Pre-checks (architecture, mountpoints, network).
2. Download Entware bootstrap script (`mipselsf-k3.4` variant, NOT `armv7sf-k3.2`).
3. Run bootstrap, which extracts Entware to `/opt/` and registers `S52entware` in init.d.
4. Install baseline packages: `python3 git curl wget-ssl nano htop`.
5. Verify by running `python3 --version` and `git --version`.

**Idempotent** — Partially. If `/opt/bin/opkg` is present, the script skips the bootstrap and only verifies/upgrades packages.

**Common failure modes** —
- Network timeout downloading bootstrap — retry.
- Architecture mismatch — script aborts with explicit message; the user must verify `uname -m` returns `mips`.
- Disk full — Entware needs ~50 MB free in `/usr/data/`.

---

### 4.3 `install_klipper.sh`

**Purpose** — Install Klipper mainline at `/usr/data/klipper/`, reusing the Creality stock Python venv at `/usr/share/klippy-env/`.

**Generated because** — The Creality stock firmware ships an old Klipper fork with custom patches. We want mainline Klipper for two reasons: bug fixes, and a clean Update Manager workflow via Moonraker.

**Pre-conditions** —
- Entware installed (for `git`).
- Stock Klipper venv intact at `/usr/share/klippy-env/` (Python 3.8.2 with `venv` module).
- Network OK.

**Post-conditions** —
- Klipper cloned at `/usr/data/klipper/` (master branch).
- `/etc/init.d/S55klipper_service` patched to point at the new path (`PY_SCRIPT=/usr/data/klipper/klippy/klippy.py`).
- The original copy_config call inside S55klipper_service is **disabled** (it would otherwise overwrite our printer.cfg at every boot).
- `klippy/chelper/c_helper.so` deployed (MIPS XBurst2 binary).
- `.git/info/exclude` populated to ignore future GuppyScreen/shell-command additions.

**Steps** —
1. Pre-checks.
2. Stop running Klipper service.
3. Backup `/etc/init.d/S55klipper_service`.
4. Clone Klipper from `https://github.com/Klipper3d/klipper.git` to `/usr/data/klipper/`.
5. Download `c_helper.so` from the repo's `files/` directory and deploy it.
6. Patch `S55klipper_service`: change `PY_SCRIPT` path, comment out `copy_config`.
7. Add Klipper-related entries to `.git/info/exclude`.
8. Restart Klipper service, verify `state: ready`.

**Idempotent** — Mostly yes. If `/usr/data/klipper/` exists, the script does a `git pull` instead of clone (UPDATE mode).

**Common failure modes** —
- `c_helper.so` 404 from GitHub — check `files/c_helper.so` exists in the repo.
- Klipper config errors after restart — caused by old printer.cfg referencing config sections that don't exist in mainline. Fix the config (see `install_configs.sh`).

---

### 4.4 `install_gcode_shellcommand.sh`

**Purpose** — Install the `gcode_shell_command.py` extension to Klipper's `extras/`, enabling shell command execution from G-code (used by GuppyScreen for things like input shaper calibration).

**Generated because** — Several GuppyScreen features and macros require running shell commands from G-code. The standard module is hosted in our repo for reproducibility (it comes from Helper-Script originally, but we own a copy).

**Pre-conditions** — Klipper installed at `/usr/data/klipper/`.

**Post-conditions** — `/usr/data/klipper/klippy/extras/gcode_shell_command.py` deployed. `.git/info/exclude` updated to keep it from polluting `git status`.

**Steps** —
1. Download `gcode_shell_command.py` from the repo's `files/` directory.
2. Copy to `klippy/extras/`.
3. Update `.git/info/exclude` if not already present.
4. Restart Klipper, verify `state: ready` (the new module shouldn't break anything if printer.cfg doesn't reference it yet).

**Idempotent** — Yes. Always re-deploys the file.

---

### 4.5 `install_klipper_patches.sh`

**Purpose** — Apply surgical patches to the local Klipper clone to suppress harmless warnings that come from the Creality MCU stack.

**Generated because** — The Creality MCU firmware (frozen July 2023) lacks features added to Klipper later, notably `STEPPER_STEP_BOTH_EDGE`. Klipper warns about this on every connection, cluttering Fluidd's UI. The warning is purely informational (we compensate via `step_pulse_duration` in printer.cfg).

**Pre-conditions** — Klipper installed at `/usr/data/klipper/` with git history.

**Post-conditions** —
- `klippy/configfile.py` patched: `deprecate_mcu_code()` returns early when `feature == 'STEPPER_STEP_BOTH_EDGE'`.
- Patch committed locally to the Klipper git repo (so `git status` stays clean).
- Backup at `klippy/configfile.py.bak.before_e5m_ck`.

**Steps** —
1. Pre-checks (Klipper dir, configfile.py, python3, service).
2. Backup `configfile.py` before patching (preserved if already exists).
3. Apply patch via `python3` text replacement. Three outcomes possible:
   - `APPLIED` — first run, success.
   - `ALREADY_PATCHED` — script re-run, no-op.
   - `PATTERN_NOT_FOUND` — Klipper version diverged, abort.
4. Commit the change locally (skipped if no diff vs HEAD).
5. Restart Klipper, wait until `state: ready`.
6. Verify the `STEPPER_STEP_BOTH_EDGE` string no longer appears in `printer/info` warnings.

**Idempotent** — Yes (explicitly designed for re-run).

**Notes** —
- After this script, the Klipper version reports as `vX.Y.Z-NNN-gHASH-dirty` where the commit count `NNN` is one higher than upstream, and the hash is your local commit. This is expected and documented in `MEMO_klipper_dirty_FR.md`.
- A future `git pull` that touches `configfile.py:533` will require manual conflict resolution. The function has been stable for years; risk is low.
- See [Issue #1] on the GitHub repo for the full rationale and the proper fix (reflashing MCUs with mainline firmware) which is out of scope for now.

---

### 4.6 `install_moonraker.sh`

**Purpose** — Install Moonraker at `/usr/data/moonraker/` with a fully working Update Manager.

**Generated because** — Moonraker is required for Fluidd, GuppyScreen, and remote management. Compiling the Python venv on the Nebula Pad is impractical (no GCC, slow CPU, missing build deps). We host a pre-built venv in the repo.

**Pre-conditions** —
- Klipper running.
- Network OK.
- `~50 MB free` for the venv extraction.

**Post-conditions** —
- Moonraker cloned at `/usr/data/moonraker/` from `https://github.com/Arksine/moonraker.git` (so Update Manager can `git pull`).
- Pre-built venv extracted at `/usr/data/moonraker/moonraker-env/` from `files/moonraker-env.tar.gz`.
- pip upgrade applied for `paho-mqtt==2.1.0`, `inotify-simple==2.0.1`, `jinja2==3.1.6` (with `--no-deps` for jinja2 to keep MarkupSafe 2.1.1).
- `/etc/init.d/S56moonraker_service` deployed.
- `moonraker.conf` deployed at `/usr/data/printer_data/config/` with `provider: none` (Buildroot has no supervisord).

**Modes** —
- **FULL** — first install. Downloads the venv tarball (16 MB), extracts, clones Moonraker code, deploys conf and init script.
- **UPDATE** — subsequent runs. Just `git pull` the Moonraker code; the venv is reused.

Detected via `/usr/data/moonraker/.e5m_ck_installed` flag.

**Steps (FULL mode)** —
1. Pre-checks.
2. Stop Moonraker if running.
3. Download `moonraker-env.tar.gz` to `/usr/data/.tmp_install/`. Verify MD5 (hardcoded) and size.
4. Clone Moonraker code from Arksine/moonraker.git.
5. Extract venv tarball into `/usr/data/moonraker/`.
6. Apply pip upgrades (with the right flags to avoid breaking existing deps).
7. Deploy `moonraker.conf` from the repo.
8. Deploy `S56moonraker_service` (backup the original first).
9. Start Moonraker, wait until `klippy_connected: true`.
10. Mark `.e5m_ck_installed` flag.

**Steps (UPDATE mode)** — Same except steps 3, 5, 6, 7, 8 are skipped or replaced by `git pull origin master`.

**Idempotent** — Yes via the flag/UPDATE mode.

**Common failure modes** —
- MD5 mismatch on tarball — file corruption during download, retry. If persistent, re-host the tarball.
- pip upgrade fails (no network in venv) — verify Entware's curl/openssl are installed.
- `klippy_connected` stays false — usually a Klipper config error. Run `tail -50 /usr/data/printer_data/logs/klippy.log` to see the cause.

---

### 4.7 `install_nginx.sh`

**Purpose** — Install nginx (from Entware) and configure it as a reverse proxy in front of Fluidd (port 4408) and Mainsail (port 4409, reserved for future use).

**Generated because** — Moonraker's built-in HTTP server is enough for development but not for serving a frontend like Fluidd. Nginx provides proper static file serving, gzip compression, and websocket proxying.

**Pre-conditions** —
- Entware installed (for `nginx-ssl`).
- Moonraker running on port 7125.

**Post-conditions** —
- nginx 1.26.3 installed via `opkg install nginx-ssl`.
- `/usr/data/nginx/nginx.conf` generated with explicit IPv4-only listen directives (Buildroot has no IPv6).
- `/etc/init.d/S50nginx` deployed (custom version with proper PID handling).
- nginx running, listening on 4408 and 4409.

**Steps** —
1. Pre-checks (Entware, Moonraker).
2. Backup any pre-existing `/etc/init.d/S50nginx` to `S50nginx.bak`.
3. `opkg install nginx-ssl`.
4. Generate `/usr/data/nginx/nginx.conf` via heredoc. The conf includes:
   - `listen 4408;` and `listen 4409;` (IPv4 only)
   - Locations for `/`, `/websocket`, `/printer/`, `/api/`, `/access/`, `/server/`, etc.
   - Static file serving from `/usr/data/fluidd/` and `/usr/data/mainsail/`.
5. Generate `/etc/init.d/S50nginx` (start/stop/restart/reload/status with `start-stop-daemon`).
6. Start nginx, verify ports 4408/4409 listening.

**Idempotent** — Yes. Re-running re-installs nginx (opkg handles "already installed") and overwrites the conf and init script.

**Common failure modes** —
- Port 4408 already used — kill the process holding it before retrying.
- IPv6 binding errors — the conf is explicitly IPv4 only; if errors persist, check `cat /etc/nginx/nginx.conf` includes from elsewhere.

---

### 4.8 `install_fluidd.sh`

**Purpose** — Install Fluidd (web UI) at `/usr/data/fluidd/`.

**Generated because** — Fluidd is the recommended web UI for Klipper/Moonraker. It's a static site (Vue.js single-page app) so install is just download + extract.

**Pre-conditions** — nginx installed and configured.

**Post-conditions** — `/usr/data/fluidd/` populated with the Fluidd build. Accessible at `http://<printer-ip>:4408/`.

**Steps** —
1. Download latest Fluidd zip from `https://github.com/fluidd-core/fluidd/releases/latest/download/fluidd.zip`.
2. Extract to `/usr/data/fluidd/`.
3. Verify nginx serves the index.html.

**Idempotent** — Yes. Always replaces the directory.

**Notes** — Update Manager handles future updates from Fluidd's GitHub releases (this script is only for the initial install).

---

### 4.9 `install_configs.sh`

**Purpose** — Deploy the E5M-CK Klipper configuration files to `/usr/data/printer_data/config/`.

**Generated because** — Klipper requires `printer.cfg` and the included `*.cfg` files (`eddy.cfg`, `homing.cfg`, `macros_calibration.cfg`, `macros_E5M_CK.cfg`, `gcode_macro.cfg`, `guppy_cmd.cfg`). They are versioned in the repo's `configs/cfg/` directory.

**Pre-conditions** — Klipper running, `/usr/data/printer_data/config/` exists.

**Post-conditions** — All `*.cfg` files from `configs/cfg/` deployed.

**Steps** —
1. Auto-discover available `.cfg` files via the GitHub Contents API: `https://api.github.com/repos/christianKEL/E5M-CK/contents/configs/cfg`.
2. For each `.cfg` returned, download via the raw URL and write to `/usr/data/printer_data/config/`.
3. Restart Klipper, verify `state: ready`.

**Idempotent** — Yes. Always overwrites; no backup is created (the user explicitly requested no backup files).

**Common failure modes** —
- GitHub API rate limit (60 requests/hour unauthenticated) — wait and retry.
- Klipper fails to start after deploy — check the logs; usually a typo in a recently-edited cfg.

---

### 4.10 `install_eddy.sh`

**Purpose** — Flash the BTT Eddy USB probe with the firmware shipped in `files/btteddy.uf2`.

**Generated because** — The BTT Eddy ships in DFU mode and needs a Klipper-compatible firmware flashed before use. The firmware is hosted in the repo for reproducibility.

**Pre-conditions** —
- BTT Eddy connected via USB to the Nebula Pad.
- The user has prepared a USB key with a single FAT32 partition (no specific files; Creality auto-mounts it at `/tmp/udisk/sdaN`).

**Post-conditions** —
- Firmware flashed to the Eddy.
- After Klipper restart, `mcu eddy` shows up as connected via `/dev/serial/by-id/usb-Klipper_rp2040_*`.

**Steps** —
1. Pre-checks (network, BTT Eddy auto-mounted).
2. Detect the USB mount path via `mount | grep -oE '/tmp/udisk/sd[a-z][0-9]*'`.
3. Verify it's a real Eddy by checking for `INFO_UF2.TXT` at the mount root (BTT bootloader signature).
4. Download `btteddy.uf2` from the repo's `files/` directory (size + MD5 verified).
5. Copy `btteddy.uf2` to the USB mount root. The bootloader auto-flashes and reboots.
6. Wait for the new serial port to appear (typically 5-10s).
7. Restart Klipper, verify `mcu eddy` is connected.

**Idempotent** — Yes (re-flashing the same firmware is a no-op functionally).

**Common failure modes** —
- USB key not recognized — check the FAT32 partitioning, try a different key.
- `INFO_UF2.TXT` not found — wrong mount, or the Eddy is in normal-mode (not DFU). Reset by holding the boot button while plugging USB.
- Klipper still doesn't see the Eddy — check `printer.cfg` references `usb-Klipper_rp2040_*` matching the actual serial-by-id (may differ between Eddy units).

---

### 4.11 `install_guppyscreen.sh` (v2)

**Purpose** — Install GuppyScreen (LVGL-based touch UI by ballaswag) at `/usr/data/guppyscreen/`. Replaces Creality's stock display server.

**Generated because** — Creality's stock UI is closed-source and tightly coupled to their cloud services. GuppyScreen is open-source, reads directly from Moonraker, and provides a clean Klipper-native experience on the touchscreen.

**Pre-conditions** —
- Klipper + Moonraker running.
- Touchscreen working (any UI displayed on it).
- ld-2.29.so present (Creality 1.3.x firmware).

**Post-conditions** —
- GuppyScreen binary running, controlling `/dev/fb0`.
- Klipper extras populated (linked symlinks for guppy modules).
- `/etc/init.d/S99guppyscreen` deployed.
- `/etc/init.d/S50dropbear` replaced with GuppyScreen's modified version (starts SSH before display).
- Optionally: Creality services disabled (`master-server`, `app-server`, `display-server`, `Monitor`, `audio-server`, `upgrade-server`, `log_main`, `cx_ai_middleware`, `webrtc`).

**Modes** —
- **FULL INSTALL** — no existing install detected. Full sequence including service replacement and Creality disable prompt.
- **UPDATE** — `.e5m_ck_installed` flag found. Compares installed version vs latest GitHub release. If newer available, downloads + extracts only. Skips service install and Creality disable (already done).

**Auto-detection** — Screen size is detected via `cat /sys/class/graphics/fb0/virtual_size`. If both dimensions are <800 px (the case for the 480×544 Nebula Pad), the script downloads `guppyscreen-smallscreen.tar.gz`. Otherwise `guppyscreen.tar.gz`.

**Steps (FULL mode)** —
1. Pre-checks.
2. Detect mode + check latest version via GitHub API.
3. Stop GuppyScreen if running (Creality display still up — keeps screen alive).
4. Download tarball, validate.
5. Extract to `/usr/data/`.
6. Install system symlinks: `/lib/libeinfo.so.1` and `/lib/librc.so.1` → respawn-daemon libs.
7. Install Klipper extras (linked symlinks for `guppy_module_loader.py`, `guppy_config_helper.py`, `tmcstatus.py`; hard copy for `calibrate_shaper_config.py`).
8. Deploy GuppyScreen config files to `/usr/data/printer_data/config/GuppyScreen/`.
9. Backup originals, install `S99guppyscreen` and replace `S50dropbear`.
10. Restart Klipper to load the new extras.
11. Start GuppyScreen, verify it's running using `guppy_pid()` helper (waits up to 20s).
12. Prompt user: "Disable all Creality services?" — see below.
13. Mark `.e5m_ck_installed` and `.e5m_ck_version` flags.
14. Cleanup temp files.

**Creality disable prompt (step 12)** — Two paths:
- **YES** — Kill 9 Creality processes (`master-server`, `app-server`, `display-server`, `Monitor`, `audio-server`, `upgrade-server`, `log_main`, `cx_ai_middleware`, `webrtc`). Remove `/etc/init.d/S99start_app`. Network daemons (`wpa_supplicant`, `ifplugd`, `dropbear`, `mdns`) are NOT touched. Backup at `/usr/data/guppyify-backup/`.
- **NO** — Minimal disable: `mv /usr/bin/Monitor /usr/bin/Monitor.disable` and same for `display-server` (the only ones that conflict with GuppyScreen because they hold `/dev/fb0`).

**v2 fixes vs v1** — Critical bugs found and fixed during testing:
- `pgrep -x guppyscreen` doesn't find the process when launched via `supervise-daemon`. Fixed by `guppy_pid()` helper using `ps | grep` on the full path with exclusion of `supervise-daemon`.
- `killall ... | while read line` decoupled signal delivery in busybox sh. Fixed by `kill_processes()` helper that runs killall directly and captures output separately.
- Initial kill list was 4 processes; extended to 9 after observing surviving Creality services in `ps`.
- Added a retry pass with `pkill -9 -f` for stubborn processes plus a final survivors report.
- Increased GuppyScreen startup wait window from 5s to 20s (supervise-daemon takes time to spawn the binary).

**Idempotent** — Yes via mode detection.

**Common failure modes** —
- "GuppyScreen failed to start" — check `tail /usr/data/printer_data/logs/guppyscreen.log` (LVGL init errors usually mean a screen size mismatch — verify the right tarball was downloaded).
- Touch unresponsive after install — `guppyconfig.json` calibration is screen-specific. Set `touch_calibrated: false` (handled by `install_personalization.sh` for E5M-CK).
- Creality processes survive the kill — they're respawned by `S99start_app`. The script removes that file in FULL disable mode; minimal mode relies on binary renaming.

---

### 4.12 `install_personalization.sh`

**Purpose** — Apply E5M-CK personalizations on top of a working install: Fluidd settings, GuppyScreen config, and boot logo.

**Generated because** — The base install gives a working but generic stack. Personalization makes it visually and functionally specific to E5M-CK: dark red theme everywhere, custom macros visible in Fluidd, custom fans/leds in GuppyScreen, custom boot logo.

**Architecture** — Single script with three independent sections, each gated by a `confirm()` prompt. The user can skip any section.

**Pre-conditions** — Working stack (Klipper, Moonraker, Fluidd, GuppyScreen). Network OK. `python3` available.

**Post-conditions** —
- Section 1 (Fluidd): all keys from `backup-fluidd-v1.36.4-fluidd.json` POSTed to `http://localhost:7125/server/database/item` under namespace `fluidd`. User must reload Fluidd in browser to see the new theme.
- Section 2 (GuppyScreen): `/usr/data/guppyscreen/guppyconfig.json` replaced with the repo version, modified to set `touch_calibrated: false` and `touch_calibration_coeff: null` (forces fresh touch calibration on first boot, regardless of which physical screen).
- Section 3 (Boot logo): all `/etc/logo/*.jpg` and `*.jpeg` replaced with `e5m_ck_logo.jpg`. Originals backed up at `/usr/data/logo_originals/`.

**Steps (per section)** —

*Section 1 — Fluidd settings:*
1. Download `backup-fluidd-v1.36.4-fluidd.json` from the repo.
2. Validate the JSON has `meta.app == "Fluidd"` and `meta.type == "settings-backup"`.
3. For each top-level key in `data` (charts, console, layout, macros, uiSettings, webcams), POST to `/server/database/item` with payload `{namespace: 'fluidd', key, value}`.
4. Report total/OK/FAIL counts.

*Section 2 — GuppyScreen config:*
1. Download `guppyconfig.json` from the repo.
2. Validate JSON parses and has `printers` key.
3. Patch in-memory: set `touch_calibrated = False`, `touch_calibration_coeff = None`.
4. Backup existing config at `guppyconfig.json.bak.<timestamp>`.
5. Stop GuppyScreen.
6. Deploy new config.
7. Restart GuppyScreen.

*Section 3 — Boot logo:*
1. Download `e5m_ck_logo.jpg` from the repo.
2. Validate it's a real JPEG (magic bytes `FF D8 FF`).
3. Backup all originals to `/usr/data/logo_originals/` (idempotent: skip if already backed up).
4. Overwrite all `/etc/logo/*.jpg` and `*.jpeg` with the new logo.
5. `sync` to flush.

**Idempotent** — Yes per section.

**Common failure modes** —
- POST to Moonraker DB fails with HTTP 4xx — likely Moonraker not reachable or namespace name wrong.
- Touch screen doesn't ask for calibration after deploy — verify `touch_calibrated: false` in the deployed file (the patch may have failed silently).
- Boot logo unchanged after reboot — `/etc/logo/` is on the read-only rootfs but mounted as overlayfs; the `cp` should work but a bad logo file (corrupt JPEG, wrong dimensions) might be silently rejected by the boot loader.

---

## 5. Recommended install order

For a **fresh install** on a stock Creality system, run in this order:

```
 1. install_factory_reset.sh        # optional, only if you want to wipe state first
 2. install_entware.sh
 3. install_klipper.sh
 4. install_gcode_shellcommand.sh
 5. install_klipper_patches.sh      # optional, suppresses the Creality MCU warning
 6. install_moonraker.sh
 7. install_nginx.sh
 8. install_fluidd.sh
 9. install_configs.sh              # deploys the printer.cfg etc.
10. install_eddy.sh                 # requires USB key, manual step
11. install_guppyscreen.sh          # requires interactive confirmation for Creality disable
12. install_personalization.sh      # optional, theme + macros + boot logo
13. sync && reboot                  # required after step 11/12 to validate full boot
```

After step 13, verify:
- Touchscreen shows GuppyScreen UI directly at boot (no Creality splash blocking it).
- SSH still works.
- Fluidd accessible at `http://<printer-ip>:4408/`.
- Klipper reports `state: ready`.

---

## 6. Update workflow

For an existing install that needs to be brought up to date:

| Component | How to update |
|---|---|
| Klipper | Update Manager in Fluidd, OR `cd /usr/data/klipper && git pull` and restart |
| Moonraker | Update Manager in Fluidd, OR re-run `install_moonraker.sh` (UPDATE mode) |
| Fluidd | Update Manager in Fluidd (handles itself) |
| GuppyScreen | Re-run `install_guppyscreen.sh` (will detect newer GitHub release) |
| Klipper patches | Re-run `install_klipper_patches.sh` (idempotent) |
| Configs | Re-run `install_configs.sh` (warning: overwrites local edits) |

Update Manager in Fluidd works for the first three because each install script sets up the `[update_manager]` section in `moonraker.conf` correctly during the initial install.

---

## 7. Debugging cheat sheet

When something breaks after an install or update, check these in order:

```sh
# 1. Are core services running?
ps | grep -E "klipper|moonraker|nginx|guppyscreen" | grep -v grep

# 2. Is Klipper ready?
curl -s http://localhost:7125/printer/info | python3 -m json.tool | head -10

# 3. Are there warnings in Klipper?
curl -s http://localhost:7125/printer/info | python3 -c "
import json, sys
print(json.load(sys.stdin)['result'].get('warnings', []))
"

# 4. Klipper log tail
tail -50 /usr/data/printer_data/logs/klippy.log

# 5. Moonraker log tail
tail -50 /usr/data/printer_data/logs/moonraker.log

# 6. GuppyScreen log tail
tail -50 /usr/data/printer_data/logs/guppyscreen.log

# 7. Who holds the framebuffer?
fuser /dev/fb0

# 8. Is anything listening on the expected ports?
netstat -tln | grep -E ':4408|:4409|:7125'

# 9. Disk space
df -h /usr/data /opt

# 10. Recent kernel messages
dmesg | tail -30
```

If a script fails midway, the backups are at:
- `/usr/data/E5M_CK/` — most install scripts
- `/usr/data/guppyify-backup/` — GuppyScreen install
- `/usr/data/logo_originals/` — boot logo
- `/usr/data/klipper/klippy/configfile.py.bak.before_e5m_ck` — Klipper patches
- `/etc/init.d/S56moonraker_service.before_E5M_CK` — Moonraker init script
- `/etc/init.d/S50nginx.bak` — nginx init script

In the worst case, `install_factory_reset.sh` + USB-key trigger will restore stock Creality state without losing anything in `/usr/data/` (which Creality's reset preserves by design).

---

## References

- Project repo: https://github.com/christianKEL/E5M-CK
- Project documentation: https://e5mdocumentation.kinsta.cloud/
- Related memos:
  - `MEMO_c_helper_FR.md` — origin and traceability of `c_helper.so`
  - `MEMO_moonraker_venv_FR.md` — origin and traceability of `moonraker-env.tar.gz`
  - `MEMO_klipper_dirty_FR.md` — explanation of the various `-dirty` markers and the `STEPPER_STEP_BOTH_EDGE` warning
- GitHub issues:
  - #1 STEPPER_STEP_BOTH_EDGE missing on Creality MCUs
  - #2 Klipper HOST `-dirty` due to GuppyScreen extras (by design)
