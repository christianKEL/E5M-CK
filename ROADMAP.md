# E5M-CK v2 — Roadmap

> **Refactor of [main branch](../tree/main) into a clean, GitOps-managed mainline Klipper stack.**

## 1. Vision

Convert a stock Creality Ender 5 Max into a fully open-source, observable, maintainable 3D printer running:

- **Mainline Klipper** (no fork, no dirty patches — ideally zero, at most one surgical patch for the Creality ADXL345)
- **Moonraker** as the printer API
- **Fluidd** as the web UI
- **GuppyScreen** as the local touchscreen UI
- **BTT Eddy** as the bed probe (firmware recompiled in-tree)
- **nginx** as the reverse proxy
- **Entware** as the package manager
- **Telegraf** (or equivalent lightweight) pushing metrics to a remote Grafana

Deployed via **GitOps**: this repo is the source of truth, a `sync.sh` script applies it to the printer over SSH. Recovery back to the stock Creality firmware is always possible (USB factory reset + SSH `factory-reset.sh`).

## 2. Non-goals

- Not a port to other printers (Ender 5 Max only — different printers welcome to fork).
- Not a camera/AI failure-detection stack (we explicitly drop the Creality `webrtc` and `cx_ai_middleware`).
- Not bilingual docs — **English only**.
- Not a heavy observability stack — no Prometheus local, no Grafana local. Push metrics to a remote host.

## 3. Lessons learned from v1 (what v2 must fix)

| v1 pain | v2 fix |
|---|---|
| Klipper became "dirty" — multiple forks, switch.sh between mainline/Creality fork, `flush_handler` errors at the end of the project | Stay **strictly mainline**. Any modification lives in `klipper/patches/` as a single isolated patch, applied at build time only. No runtime forks. |
| Install scripts were fragile / non-idempotent — could half-fail and leave broken state | **GitOps + idempotent `sync.sh`**. Re-running it always converges to the target state. |
| Loss of config on factory reset | Custom `S58factoryreset` preserves the overlay, and `sync.sh` can re-apply everything from the repo. |
| Mixed FR/EN docs confused the community | **English only** across code, docs, commits, memos. |
| Input Shaping required painful `switch.sh` | **Minimal Klipper patch for the Creality ADXL345** lives in `klipper/patches/`. No more runtime fork-switching. |

## 4. Install order (with dependencies)

Each step has its own script in [`installs/`](installs/). Steps must be run in order; each depends on the previous.

| # | Step | Depends on | Script | Notes |
|---|---|---|---|---|
| 1 | **SSH key + persistence prep** | Stock firmware reachable | (manual) | Already done in setup |
| 2 | **Entware** | SSH | `install_entware.sh` | Package manager for embedded — base for everything else |
| 3 | **Custom factory_reset** | Entware | `install_factory_reset.sh` | Ensures our mods survive any future reset OR can be cleanly removed |
| 4 | **Klipper mainline (compiled)** | Entware | `install_klipper.sh` | Pulls upstream Klipper, applies `klipper/patches/adxl345_creality.patch`, compiles firmwares for the 3 MCUs |
| 5 | **Moonraker** | Klipper | `install_moonraker.sh` | Python venv in `/usr/data/venvs/moonraker` |
| 6 | **nginx** | (independent) | `install_nginx.sh` | Reverse proxy for Fluidd + Moonraker on port 80 |
| 7 | **Fluidd** | Moonraker + nginx | `install_fluidd.sh` | Static files served by nginx |
| 8 | **GuppyScreen** | Moonraker | `install_guppyscreen.sh` | Replaces Creality `display-server`. Talks directly to framebuffer + evdev. |
| 9 | **Eddy probe firmware + config** | Klipper | `install_eddy.sh` | Flash `btteddy_v2.uf2` (in `klipper/firmwares/`), add `[probe_eddy_current]` block |
| 10 | **Initial calibrations** | All above | manual macros | Bed PID, nozzle PID, Eddy auto-calibration, bed mesh, input shaping, pressure advance, flow |
| 11 | **Observability** | All above | `install_telegraf.sh` (TBD) | Push metrics to remote Grafana |

After install: ongoing changes go through `scripts/sync.sh` (GitOps).

## 5. Acceptance criteria per step

A step is "done" when:

| Step | Acceptance criteria |
|---|---|
| 2 Entware | `opkg list-installed | wc -l` returns > 100; `python3` (Entware) in PATH |
| 3 Factory reset | A test run of `factory-reset.sh --dry-run` reports what *would* be removed; USB method still works |
| 4 Klipper | Klipper restarts cleanly with our compiled firmwares, all 4 MCUs ready, no `flush_handler` warnings for 30 min |
| 5 Moonraker | `curl http://printer:7125/server/info` returns 200 with `klippy_state: ready` |
| 6 nginx | `curl http://printer/` returns Fluidd HTML; `/server/info` proxies correctly |
| 7 Fluidd | Fluidd dashboard loads, shows all temperatures and MCUs, can issue G-code |
| 8 GuppyScreen | Touchscreen shows Guppy UI, touch input works, no display flicker, Creality `display-server` confirmed stopped |
| 9 Eddy | `[probe_eddy_current]` shows in `STATUS`, probe responds to `EDDY_CALIBRATE` |
| 10 Calibrations | Bed PID converged, IS measured, first successful test print (calibration cube) |
| 11 Observability | Remote Grafana shows live `mcu_temp`, `sysload`, `memavail`, `klipper_retransmit_seq` |

## 6. Known failure modes & mitigations

| Failure | Cause | Mitigation |
|---|---|---|
| `flush_handler` errors (the v1 killer) | MCU saturated, host CPU overloaded, or non-idempotent patches | Stay mainline, monitor `bytes_retransmit` and `sysload`, alert if rising. Avoid extra Python deps in Klipper venv. |
| RAM exhaustion (200 MB host) | Too many heavyweight services (esp. KlipperScreen-style) | Hard rule: total RSS budget = 150 MB for our stack. Telegraf must be < 15 MB. GuppyScreen ~50 MB. Moonraker ~80 MB. Klipper ~50 MB. Margins are tight. |
| Lost mods after factory reset | Creality wipes overlay partition | Custom `S58factoryreset` + `sync.sh` re-applies from repo in < 5 min |
| Eddy probe drift | Temperature sensitivity | Document recalibration procedure in `docs/calibration/eddy.md` |
| MCU firmware mismatch after Klipper update | Host updated, firmwares not reflashed | `install_klipper.sh` always recompiles + reflashes all 3 GD32 MCUs |
| Fluidd cannot connect to Moonraker | nginx misconfig, Moonraker not running | `verify.sh` checks both ports and proxy chain |

## 7. Quick wins vs big chunks

**Quick wins** (≤ 30 min each, low risk):
- SSH key deployment ✅ (done)
- Initial repo structure ✅ (done)
- `verify.sh` for read-only inspection
- Memos translation FR → EN
- shellcheck CI in `.github/workflows/lint.yml`

**Medium effort** (1–4 h):
- Entware install + verify
- Custom `S58factoryreset` script + tests
- nginx reverse proxy config
- Fluidd static install
- `scripts/sync.sh` skeleton (rsync over SSH + post-hooks)

**Big chunks** (days):
- Klipper mainline build pipeline on this MIPS toolchain + minimal ADXL345 patch
- GuppyScreen build/install + display handoff from Creality `display-server`
- BTT Eddy firmware recompile + bed calibration tuning
- Input shaping calibration with ADXL345
- Observability pipeline (telegraf collectors + remote Grafana dashboards)

## 8. Branching & release model

- **`main-v2`** = active development (this branch)
- **`main`** = stable release (currently still holds v1 — to be replaced once v2 is stable)
- **Tags:** semver (`v2.0.0`, `v2.1.0`, …) on `main` after merge from `main-v2`
- **Legacy:** before the first v2 release on `main`, tag the current `main` as `v1-final` and optionally archive as `legacy/v1` branch

## 9. Open questions (to settle as we go)

- Exact telegraf config — collectors + push target (user's local PC? Free Grafana Cloud?)
- Cohabitation strategy with Creality stack — fully parallel (drop only what conflicts) vs aggressive (kill `app-server`, `web-server`, `display-server`, `cx_ai_middleware`, `webrtc` from boot)
- Runout sensor wiring — which input pin on the main MCU? Klipper config in `klipper/config/runout.cfg`
- LEDs — neopixel? Where wired? Which macros (`LEDS_PRINT_DONE`, etc.)?
- Slicer integration — beyond Orca profiles in `slicer/orca/`, do we want a custom uploader?

---

*Last updated: 2026-05-19. Owner: christianKEL.*
