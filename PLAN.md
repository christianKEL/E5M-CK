# E5M-CK v2 — Execution Plan

> Tactical companion to [`ROADMAP.md`](ROADMAP.md). The roadmap says *why* and *what*; this plan says *in what order* and *how to know we're done*.

## Conventions

- **Phase** = a self-contained unit of work that ends in a deployable, verifiable state.
- **🟢 quick** = ≤ 30 min · **🟡 medium** = 1–4 h · **🔴 big** = days · **⚪ blocked** = waiting on an answer or upstream
- Every phase declares: *goal · prerequisites · steps · acceptance criteria · rollback*.
- Anything destructive on the printer requires explicit user confirmation before running, even with the auto-mode policy.

---

## Phase 0 — Foundation ✅ DONE

**Goal:** Empty GitOps skeleton + ROADMAP committed to `main-v2`.

Done in commits `8d7a743` and `00367bc`.

---

## Phase 1 — Tooling & safety net  🟡

**Goal:** Have read-only and reversible tooling in place *before* any destructive action on the printer.

**Prereqs:** Phase 0.

**Steps:**

1. `scripts/lib/_common.sh` — shared helpers (logging, SSH wrapper, dry-run guard).
2. `scripts/verify.sh` — read-only health check over SSH. Reports:
   - hostname, uptime, free RAM, free disk
   - Klipper / Moonraker / nginx / GuppyScreen presence + version + status
   - Listening ports
   - md5 diff between repo files and live files (drift detection)
3. `scripts/backup.sh` — snapshot `/usr/data/printer_data/`, `/etc/init.d/`, `/usr/data/creality/userdata/` into a timestamped tarball at `backups-local/` (gitignored).
4. `scripts/sync.sh` — apply repo → live via `rsync` over SSH. Idempotent. Modes: `--dry-run` (default), `--apply`. Refuses to apply without a fresh backup.
5. `scripts/factory-reset.sh` — SSH-triggered reset (parallel to the USB method). Confirms twice before acting.
6. `docs/operations/gitops_sync.md` — how to use the four scripts above.

**Acceptance criteria:**

- `bash scripts/verify.sh` runs without error against the live printer and produces a readable report.
- `bash scripts/sync.sh --dry-run` shows what *would* change, changes nothing.
- `bash scripts/backup.sh` produces a timestamped `.tar.gz` that can be untarred locally.
- `bash scripts/factory-reset.sh` shows what it *would* do under `--dry-run`, refuses to run for real without `--confirm-i-mean-it`.

**Rollback:** N/A (Phase 1 is non-destructive on the printer).

---

## Phase 2 — Entware + persistence  🟡

**Goal:** Install the package manager and the custom factory-reset hook so subsequent installs can survive resets.

**Prereqs:** Phase 1.

**Steps:**

1. `installs/install_entware.sh` — install Entware in `/opt`, persist the mount, add `/opt/bin` to PATH for our scripts.
2. `system/etc/init.d/S58factoryreset` — replacement that preserves `/usr/data/e5m-ck/` across resets (or re-applies from repo on reboot).
3. `installs/install_factory_reset.sh` — drops the custom init script in place, makes a backup of the original.
4. `docs/operations/factory_reset.md` — both methods (USB + SSH) documented, with the contract: the printer can always return to stock.

**Acceptance criteria:**

- `opkg list-installed | wc -l` ≥ 100 after install.
- `/etc/init.d/S58factoryreset` md5 matches `system/etc/init.d/S58factoryreset` in repo.
- Simulated reset (test mode in the script) restores expected state.

**Rollback:** USB factory reset always works; original `S58factoryreset` backed up at `/usr/data/backup/S58factoryreset.orig`.

---

## Phase 3 — Klipper mainline rebuild  🔴

**Goal:** Replace stock Creality Klipper with upstream Klipper, applying *at most one* minimal patch for the Creality ADXL345.

**Prereqs:** Phase 2.

**Steps:**

1. `klipper/patches/adxl345_creality.patch` — minimal, well-commented patch against upstream `master`. Goal: target ≤ 100 lines.
2. `installs/install_klipper.sh` :
   - Clones upstream Klipper at a pinned tag (recorded in the script).
   - Applies the patch.
   - Builds firmware for the 3 GD32 MCUs (main `CR4NS200323C10`, nozzle `CR-NOZZLE_V21`, leveling `CR-K1-MAX-LEVELING-V1.0.0`).
   - Installs Python venv at `/usr/data/venvs/klippy/`.
   - Replaces `/etc/init.d/S55klipper_service` to use the new install.
   - Stages firmwares; flashing is a separate explicit step.
3. `installs/flash_klipper_mcus.sh` — interactive flasher, one MCU at a time, with verification after each.
4. `klipper/config/` — modular printer.cfg split (printer, mcu, steppers, extruder, bed, sensorless, macros/*).
5. `docs/operations/klipper_rebuild.md` — what changed, how to rollback to stock if needed.

**Acceptance criteria:**

- `klippy.log` shows mainline Klipper version banner.
- All 4 MCUs come up `ready` within 30 s.
- 30-minute idle observation: `bytes_retransmit` < 100 per MCU, no `flush_handler` warnings.
- `STATUS` over Klipper UDS returns sane values.

**Rollback:** Reflash stock Klipper firmwares (kept in `/usr/data/backup/firmwares/` by `install_klipper.sh`); restore stock `S55klipper_service` from `/usr/data/backup/`.

---

## Phase 4 — Moonraker + nginx + Fluidd  🟡

**Goal:** Open-source API + web UI working end-to-end.

**Prereqs:** Phase 3.

**Steps:**

1. `installs/install_moonraker.sh` — clone Moonraker at pinned tag, venv at `/usr/data/venvs/moonraker/`, init script at `S56moonraker_service`.
2. `moonraker/moonraker.conf` — committed config, edited locally only for secrets (.env, gitignored).
3. `installs/install_nginx.sh` — install nginx from Entware, deploy `nginx/nginx.conf`. nginx listens on port 80, proxies `/server/*` and `/websocket` to Moonraker:7125, serves Fluidd statics for everything else.
4. `installs/install_fluidd.sh` — download Fluidd release tarball at pinned version, extract to `/usr/data/fluidd/`, point nginx at it.
5. Handle port 80 conflict with Creality `web-server`: either kill it from boot (in `system/etc/init.d/S99e5m_ck`) or move nginx to another port. **Open question.**
6. `docs/operations/web_stack.md` — how the stack fits together.

**Acceptance criteria:**

- `curl http://printer:7125/server/info` returns `klippy_state: ready`.
- `curl http://printer/` returns Fluidd HTML.
- Fluidd dashboard loads in a browser, shows all temperatures + MCUs, can issue G-code (`G28` test).
- WebSocket-driven updates work (Fluidd shows live temp changes).

**Rollback:** Stop our nginx + Moonraker init scripts. Stock `web-server` resumes serving port 80 next boot.

---

## Phase 5 — GuppyScreen  🔴

**Goal:** Replace Creality `display-server` with GuppyScreen on the local touchscreen.

**Prereqs:** Phase 4.

**Steps:**

1. `installs/install_guppyscreen.sh` — fetch GuppyScreen MIPS prebuilt binary, install to `/usr/data/guppyscreen/`, init script `S98guppyscreen` (after `S97`, before display services).
2. Display handoff: stop Creality `display-server` + `cmd_jpeg_display` + `boot_display` from boot (in `system/etc/init.d/` overrides). Guppy takes `/dev/fb0` + touch evdev.
3. `guppyscreen/guppyconfig.json` — committed config (themes, macros to show, etc.).
4. `docs/operations/guppyscreen.md` — install, troubleshooting (black screen, touch miscalibration).

**Acceptance criteria:**

- GuppyScreen UI visible on the touchscreen within 30 s of boot.
- Touch input registered correctly across the full screen area.
- Stock `display-server` confirmed not running (`ps | grep display-server` empty).
- No display flicker / artifacts during a 10-minute idle test.

**Rollback:** Re-enable stock display init scripts; Creality UI returns on next reboot.

---

## Phase 6 — BTT Eddy probe  🔴

**Goal:** Recompile Eddy firmware from scratch, install, calibrate.

**Prereqs:** Phase 3 (Klipper mainline must be running for Eddy support).

**Steps:**

1. `klipper/firmwares/build_eddy.sh` — script that compiles `btteddy_v2.uf2` from upstream Klipper using the official Eddy build target. Pinned Klipper tag.
2. `installs/install_eddy.sh` — flash procedure (manual step: BOOT button + USB plug), copy `klipper/config/probe_eddy.cfg` into the live config.
3. `klipper/config/probe_eddy.cfg` — `[probe_eddy_current]` section + macros for calibration.
4. Calibration sequence documented in `docs/calibration/eddy.md`:
   - `EDDY_CALIBRATE_DRIVE_CURRENT`
   - `EDDY_CALIBRATE` (frequency/height mapping)
   - Test probe accuracy (≤ 0.010 mm σ)

**Acceptance criteria:**

- `STATUS` shows `probe_eddy_current` ready.
- 10 consecutive probes at the same point: σ ≤ 0.010 mm.
- `BED_MESH_CALIBRATE` runs to completion without error.

**Rollback:** Stock probe wiring is preserved; revert `printer.cfg` to use it.

---

## Phase 7 — Initial calibrations  🟡

**Goal:** Bring the printer to printable state.

**Prereqs:** Phases 3, 4, 6.

**Steps:**

1. `klipper/config/macros/calibration.cfg` — macros for each calibration.
2. Run order (one at a time, verify each):
   1. `PID_CALIBRATE HEATER=heater_bed TARGET=60`
   2. `PID_CALIBRATE HEATER=extruder TARGET=220`
   3. `BED_TILT_CALIBRATE` (if hardware supports it; otherwise document why skipped)
   4. `BED_MESH_CALIBRATE` (Eddy from Phase 6)
   5. `SHAPER_CALIBRATE` (Input Shaping via patched ADXL345 from Phase 3)
   6. Pressure Advance — sample tower print
   7. Flow rate — sample cube print
3. Save results to `klipper/config/printer_params.cfg` (committed) — the runtime calibration values.
4. `docs/calibration/full_calibrate.md` — the full sequence with expected values and red flags.

**Acceptance criteria:**

- First test print (calibration cube, 20 mm) completes successfully.
- Layer adhesion + dimensional accuracy within 0.1 mm.

**Rollback:** None — calibrations are pure configuration changes, reversible by editing `printer_params.cfg`.

---

## Phase 8 — Observability  🟡

**Goal:** Real-time metrics pushed to a remote Grafana so we can detect regressions early (especially the v1 `flush_handler` killer).

**Prereqs:** Phase 4 (need Moonraker to expose metrics).

**Steps:**

1. Decide push target: user's local PC running Grafana, or Grafana Cloud free tier. **Open question.**
2. `observability/telegraf.conf` — collectors:
   - System: CPU, RAM, swap, sysload (≤ 5 s interval)
   - Klipper: `bytes_retransmit`, `print_stall`, `mcu_awake`, temps (via Moonraker API)
   - Network: WiFi RSSI (Broadcom)
3. `installs/install_telegraf.sh` — install telegraf from Entware, deploy config, init script `S99telegraf`.
4. `observability/dashboards/` — Grafana JSON dashboards (system overview, Klipper health, MCU health, alert thresholds).
5. Memory budget enforced: telegraf RSS ≤ 15 MB. Add alert if exceeded.
6. `docs/operations/observability.md` — how to add a metric, how to read the dashboards, how to interpret alerts.

**Acceptance criteria:**

- Live metrics visible in remote Grafana within 30 s of telegraf start.
- 24-hour stability test: no metric gap > 60 s, no telegraf restart, RSS budget respected.
- Alert fires correctly when synthetic load drives sysload > 1.0.

**Rollback:** Disable `S99telegraf`; no impact on print stack.

---

## Phase 9 — Slicer integration  🟢

**Goal:** Smooth print workflow from Orca → printer.

**Prereqs:** Phase 4 (Moonraker upload endpoint).

**Steps:**

1. `slicer/orca/E5M-CK.orca_printer` — printer profile.
2. `slicer/orca/filaments/` — one JSON per validated filament (PLA, PETG, PLA-CF, PA-CF as a starting set).
3. Custom start/end G-code referencing macros from `klipper/config/macros/start_end.cfg`.
4. Moonraker upload URL: `http://printer/server/files/upload`.
5. `docs/operations/slicer.md` — setup walkthrough.

**Acceptance criteria:**

- Orca → upload → print works without manual intervention for at least 3 distinct filaments.

**Rollback:** N/A.

---

## Phase 10 — Hardening + v2 release  🟡

**Goal:** Promote `main-v2` to `main` as the new stable.

**Prereqs:** Phases 1–9.

**Steps:**

1. Documentation pass: every script has a header block, every `docs/` page is current, every open question in ROADMAP either resolved or explicitly deferred.
2. CI: `lint.yml` workflow (shellcheck + klipper-cfg-lint + yamllint). Requires `workflow` OAuth scope — re-auth `gh` then.
3. End-to-end test: factory-reset the printer → run all installs in order → printer prints in < 2 h.
4. Tag the current `main` as `v1-final`. Optionally branch `legacy/v1` from the same commit for posterity.
5. Merge `main-v2` → `main`. Tag `v2.0.0`.
6. Update README on `main` to reflect v2.

**Acceptance criteria:**

- Fresh stock printer → fully operational v2 in one continuous run, no manual fixes.
- `git log main` shows the v1-final tag preserved.
- v2.0.0 release notes published.

**Rollback:** `git revert` the merge commit; users can pin `v1-final` to stay on v1.

---

## Phase ordering & critical path

```
Phase 0 (done)
   │
   ▼
Phase 1 (tooling) ────────────────┐
   │                              │
   ▼                              │
Phase 2 (entware + persistence)   │
   │                              │
   ▼                              │
Phase 3 (klipper rebuild) ────────┤── critical path
   │                              │
   ├──► Phase 6 (eddy)            │
   │       │                      │
   │       └──┐                   │
   │          ▼                   │
   └──► Phase 4 (moonraker+nginx+fluidd)
              │       │
              │       ├──► Phase 5 (guppyscreen)
              │       │
              │       ├──► Phase 8 (observability)
              │       │
              │       └──► Phase 9 (slicer)
              ▼
           Phase 7 (calibrations) ── needs 3, 4, 6
              │
              ▼
           Phase 10 (release)
```

**Critical path:** 0 → 1 → 2 → 3 → 4 → 7 → 10. Phases 5, 6, 8, 9 can run in parallel once their prereqs are met.

---

## Open questions tracker (mirrors ROADMAP §9)

| # | Question | Blocks | Owner |
|---|---|---|---|
| OQ1 | Telegraf push target (local Grafana? Cloud?) | Phase 8 | user |
| OQ2 | Cohabitation strategy (parallel vs aggressive shutdown of Creality services) | Phase 4 (port 80 conflict) | user |
| OQ3 | Runout sensor wiring (input pin + Klipper config) | minor — can land any time | user |
| OQ4 | LEDs wiring (neopixel? GPIO?) | minor — can land any time | user |
| OQ5 | License (probably GPL-3 to match Klipper) | Phase 10 | user |

---

*Last updated: 2026-05-19. Phase status updated as phases complete.*
