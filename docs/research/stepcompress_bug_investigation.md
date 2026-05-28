# `Internal error in stepcompress` — investigation log

## TL;DR

After 7 reproductions over 12 hours of testing on 2026-05-27 / 28, every
crash signature shares one striking property: **only steppers connected
to the main MCU are ever affected** (stepper_x oid=5, stepper_y oid=8,
stepper_z oid=9). The extruder, which is on the nozzle MCU, has never
once produced an `Invalid sequence`.

The bug has been definitively shown to be **independent** of :
gcc 5.2.0 vs 14.2.0, LTO ON/OFF, the Ingenic vs crosstool-NG toolchains,
the Klipper commit `7c0ee84` (input_shaper single-pass refactor), the
`serialize gen_steps` host-side patch we tried, having input_shaper
enabled, and having bed_mesh fade compensation enabled.

The current strongest hypothesis is that the **Creality 2023 main-MCU
firmware** (build SHA `341a2c18-dirty-20230717`) interacts incorrectly
with mainline Klipper master `4bc56464` in a way that perturbs the
host's `stepcompress` calculations for steppers on that MCU. The
nozzle MCU, despite using the SAME firmware fork from the same era,
does not exhibit the bug — possibly because its only stepper
(extruder) doesn't see the same calculation paths as XYZ.

## Bug signature

```
b'stepcompress o=<oid> i=<negative> c=1 a=0: Invalid sequence'
b"Error in syncemitter 'stepper_<name>' step generation"
Transition to shutdown state: Internal error in stepcompress
```

The `Invalid sequence` is raised in `klippy/chelper/stepcompress.c`'s
`check_line()` function when `move.interval` (a uint32_t) appears as a
negative value when interpreted signed — i.e., the host has calculated
that step N+1 should occur in MCU clock time BEFORE step N. This is a
purely host-side check, fired before any `queue_step` is sent to the MCU.

## All 7 crashes side-by-side

| # | Klipper | gcc | LTO | Misc | Stepper (oid) | `i` value | `flush_time` | Position at shutdown |
|---|---|:---:|:---:|---|---|---|---|---|
| 1 | `bd09e017` (May) | 5.2.0 | yes | + serialize patch | stepper_y (8) | -7,132 | ~55,000 s | n/a (pre-PR #7271) |
| 2 | `4bc56464` (May) | 5.2.0 | yes | + serialize patch | stepper_y (8) | -29,863 | 31,248 s | (61.6, 141.5, 56.4) |
| 3 | `4bc56464` | 5.2.0 | **no** | vanilla | stepper_y (8) | -130,580 | 4,964 s | (132.6, 236.8, 5.8) |
| 4 | `4bc56464` | 14.2.0 | yes | vanilla | stepper_x (5) | -2,080,205 | 1,495 s | (107.8, 33.6, -0.3) |
| 5 | `4bc56464` | 14.2.0 | yes | revert `7c0ee84` | stepper_x (5) | -44,449 | 507 s | (18.8, 66.1, 20.0) |
| 6 | `4bc56464` | 14.2.0 | yes | revert `7c0ee84`, NO shaper | **stepper_z (9)** | -54,638 | 1,922 s | (243.3, 335.4, 0.085) |
| 7 | `4bc56464` | 14.2.0 | yes | revert `7c0ee84`, NO shaper, NO bed_mesh | stepper_y (8) | -47,148 | 1,205 s | (33.6, 104.7, 0.23) |

All `oid` values 5, 8, 9 map to steppers on the **main MCU** (the GD32F303xE
on the mainboard). The extruder (oid 11, on nozzle_mcu) has never fired
`Invalid sequence`.

The shorter `flush_time` to crash on newer gcc / fewer host smoothing
layers is **not random variance** — the gcode is byte-identical across
all 7 runs. Each binary deterministically crashes at the earliest gcode
point where its specific FP/optim profile crosses the limit. Removing
host-side smoothing (input_shaper convolution, bed_mesh fade Z
compensation) just exposes earlier limit-points.

## Eliminated hypotheses

| Hypothesis | Outcome | Evidence |
|---|---|---|
| MIPS architecture / NaN 2008 / hard-float ABI | ✗ ELIMINATED | Creality stock host runs on same MIPS + same ABI and never crashes |
| gcc 5.2.0 (Ingenic toolchain) specifically | ✗ ELIMINATED | Crashes 4-7 use gcc 14.2.0 from crosstool-NG, still crash |
| LTO on/off | ✗ ELIMINATED | Crash 3 has no LTO and still crashes |
| Toolchain Ingenic vs crosstool-NG | ✗ ELIMINATED | Both toolchains produce binaries that crash with similar signatures |
| Patch `serialize gen_steps` (race in steppersyncmgr) — **this IS Kevin O'Connor's explicit suggestion** : *"change steppersyncmgr_gen_steps() to call se_finalize_gen_steps() immediately after se_start_gen_steps()"* | ✗ ELIMINATED | Crash 2 was reproduced WITH this patch deployed (`c_helper.so.lto-with-serialize` on printer). Crashes 3-7 also crash without it. The threading-into-sequential conversion does NOT fix the underlying bug. |
| Klipper commit `7c0ee84` (input_shaper single-pass refactor) | ✗ ELIMINATED | Crashes 5-7 have the revert applied and still crash |
| Input shaper subsystem entirely | ✗ ELIMINATED | Crashes 6-7 run with `[input_shaper]` disabled and still crash |
| Bed mesh fade compensation (Z micro-corrections per move) | ✗ ELIMINATED | Crash 7 runs with `BED_MESH_CLEAR` and still crashes |
| Random / non-deterministic variance | ✗ ELIMINATED | Same gcode file across all runs; each binary crashes at deterministic point |

## Remaining live hypotheses

1. **Main MCU firmware (Creality 2023 fork) protocol mismatch with
   mainline Klipper 2026 host.** The clocksync between host and MCU
   uses periodic `get_clock` exchanges. If the MCU firmware has any
   non-standard timing in its `get_clock` response (RTT, propagation
   delay, batching) that differs from what mainline Klipper expects,
   the host's `clock_est` model for that MCU could carry residual
   error that leaks into stepcompress's time-to-tick conversion.
   - Supports : ALL 7 crashes are on the main MCU
   - Cuts against : the nozzle MCU uses the same Creality fork but its
     stepper never crashes. (Possible explanation : extruder operates
     mostly at low-frequency stepping, where the error margins are wider.)

2. **Specific config interaction** (rotation_distance asymmetry X=63.874
   vs Y=64.024, microsteps=32, shaper_freq_y=40.2). Less likely after
   eliminating shaper and mesh, but the asymmetric rotation_distance
   in CoreXY is still an unusual setup.

3. **Klipper code path specific to multi-MCU clocksync.** The mainline
   has 3 MCUs each with separate clocksync. The host coordinates them
   to a single time-base. Subtle synchronization issues might fire on
   the busiest MCU (the main, which drives 3 steppers + bed heater +
   fans + TMC UART) but not the nozzle (just extruder + hotend +
   light fan).

## What's currently deployed on the printer

- `c_helper.so` : gcc 14.2.0 + LTO + Klipper master `4bc56464` with
  commit `7c0ee84` REVERTED. (= crash 7 build)
- `[input_shaper]` autosave block DISABLED via prepending `# DISABLED
  FOR TEST` to its lines in `/usr/data/printer_data/config/printer.cfg`
- `BED_MESH_CALIBRATE METHOD=rapid_scan` REPLACED with `BED_MESH_CLEAR`
  in `START_PRINT` macro
- Main MCU still on stock Creality firmware
  `mcu0_001_G32-mcu0_005_000.bin` (MD5 `586ade186aed9a9c272b1187bf543913`)
- Nozzle MCU still on stock Creality firmware
  `noz0_001_G30-noz0_005_000.bin` (MD5 `e92803cb2b4f158092f6b75d3801bf63`)

## Backup / rollback artifacts available

In `klipper/binaries/mipsel-3.4/` :
- `c_helper.so.creality_stock` — Creality stock host c_helper.so
- `c_helper.so.preserialize` — gcc 5.2.0 + LTO + vanilla master 4bc56464
- `c_helper.so.lto-with-serialize` — gcc 5.2.0 + LTO + master + serialize patch
- `c_helper.so.nolto.vanilla` — gcc 5.2.0 + NO-LTO + vanilla master
- `c_helper.so.gcc14` — gcc 14.2.0 + LTO + vanilla master (= crash 4 build)
- `c_helper.so.gcc14-revert7c0ee84` — gcc 14.2.0 + LTO + master MINUS 7c0ee84 (= crashes 5/6/7 build)

In `klipper/firmwares/` :
- `F004_mcu0_001_G32-mcu0_005_000.bin` — Creality stock main MCU firmware
- `F004_noz0_001_G30-noz0_005_000.bin` — Creality stock nozzle MCU firmware

On the printer at `/usr/data/e5m-ck/klipper/klippy/chelper/` :
- `c_helper.so.gcc14-vanilla` — backup of the build before revert
- Older `.preserialize`, `.lto-with-serialize` are also kept

On the printer at `/usr/data/printer_data/config/` :
- `printer.cfg.before-shaper-disable` — printer.cfg backup with shaper
- `macros/start_end.cfg.before-mesh-disable` — START_PRINT macro backup
  with BED_MESH_CALIBRATE intact

Rollback procedure : described in `docs/research/stock_mcu_firmware_inventory.md`
for MCU firmware, and trivially `mv` operations for the host-side
artifacts on the printer.

## Hardware setup

| Component | Detail |
|---|---|
| SBC | Creality Nebula Pad (Ingenic XBurst2 MIPS32r2, glibc 2.29, linux 4.4.94) |
| Main MCU | GD32F303xE, 120 MHz, on `/dev/ttyS1` @ 230400, Creality firmware `341a2c18-dirty Jul 17 2023` |
| Nozzle MCU | GD32F303xB, 120 MHz, on `/dev/ttyS7` @ 230400, Creality firmware `341a2c18-dirty Jul 14 2023` |
| Eddy MCU | RP2040 (BTT Eddy), mainline Klipper firmware `v0.13.0-658-gbd09e0170` |
| Kinematics | CoreXY (moving bed in Z), 400×400×400 print volume |
| Steppers X/Y/Z | TMC2209 with sensorless homing |
| Microsteps | 32 |
| Rotation_distance | X=63.874, Y=64.024 (asymmetric, baked in by Creality factory cal) |
| Input shaper (when active) | MZV X=51.2 Hz, Y=40.2 Hz |
| Probe | BTT Eddy (probe_eddy_current), scan-based G28, rapid_scan bed_mesh |
| Slicer | OrcaSlicer 2.3.2, ~50k SCV toggles in the gcode |
| Print test | The same multi-hour print file across all 7 runs |

## SWD access for flash

The mainboard exposes a 5-pin SWD header with silkscreen labels :
`VCC, DIO, CLK, GND, NRST`. Standard ST-Link V2 (and clones) wiring :

| SWD pad | ST-Link pin |
|---|---|
| VCC | T_VCC (1) |
| DIO | SWDIO (7) |
| CLK | SWCLK (9) |
| GND | GND (8) |
| NRST | NRST (15) |

The user has an ST-Link V2 (STM8+STM32 capable, the common $10 clone)
and a spare main MCU board as physical safety net if a flash bricks
the active one.

## Open work (planned)

The next test is to flash a **truly mainline-equivalent Klipper firmware
to the main MCU** (and only the main MCU; the nozzle stays on Creality
stock). This will isolate the Creality-fork-firmware hypothesis.

The blocker : **mainline Klipper has no support for STM32F303 / GD32F303xE**
(verified in `src/stm32/Kconfig`, no `MACH_STM32F303` entry). The
closest supported MCU is STM32F207 (Cortex-M3, 120 MHz) but the
architecture differs (M3 vs M4) and so do peripherals.

Path forward : add `MACH_STM32F303` to mainline Klipper as a new chip
variant, with PLL config supporting the GD32F303's 120 MHz operation
(PLL × 15 from HSE 8 MHz, vs STM32F303's max 72 MHz). Files needed :

1. `src/stm32/stm32f3.c` (chip-family init, mirrors `stm32f1.c`)
2. `src/stm32/Kconfig` entry for `MACH_STM32F303`
3. `src/stm32/Makefile` build rules
4. CMSIS headers for STM32F303 in `lib/`
5. Linker script adjustments

Estimated effort : 3-5 hours focused. Track progress in subsequent
research log files.

## Upstream escalation candidates

If the F303 port confirms the firmware-mismatch hypothesis, this is a
useful contribution to upstream Klipper. The community Klipper Discourse
post template should include :

- Crash signature table above
- Steppers-on-main-MCU-only pattern
- All eliminated hypotheses
- The before/after data once the F303 port runs

Authors to address : Kevin O'Connor (`@koconnor`, ANS he opened PR #7271
for diagnostics on this exact error class), Dmitry Butyugin (`@dmbutyugin`,
authored the input_shaper refactor we tested), nefelim4ag (`@nefelim4ag`,
recent stepcompress committer, observed the SCV pattern in our setup).
