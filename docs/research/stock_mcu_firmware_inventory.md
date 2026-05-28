# Stock Creality MCU firmware inventory

Captured 2026-05-28 from live printer to anchor the rollback path before any
mainline-Klipper MCU flashing.

## Files on the printer

Location: `/usr/share/klipper/fw/F004/` (squashfs read-only stock)

| File | Size | MD5 | Target |
|---|---|---|---|
| `mcu0_001_G32-mcu0_005_000.bin` | 31,436 | `586ade186aed9a9c272b1187bf543913` | main MCU (GD32F303xE, 120 MHz, /dev/ttyS1) |
| `noz0_001_G30-noz0_005_000.bin` | 31,428 | `e92803cb2b4f158092f6b75d3801bf63` | nozzle MCU (GD32F303xB, 120 MHz, /dev/ttyS7) |

## Local copies in this repo

Both .bin files are archived in `klipper/firmwares/` for offline rollback :

- `klipper/firmwares/F004_mcu0_001_G32-mcu0_005_000.bin` (31,436 b, MD5 above)
- `klipper/firmwares/F004_noz0_001_G30-noz0_005_000.bin` (31,428 b, MD5 above)

Use case : if Creality publishes an OTA that drops these .bin (already done
once with the `bed0` firmware) or modifies them, the repo copy stays the
known-good 2023 version. To redeploy on the printer :

```bash
scp -O klipper/firmwares/F004_mcu0_001_G32-mcu0_005_000.bin \
    root@192.168.1.94:/usr/share/klipper/fw/F004/mcu0_001_G32-mcu0_005_000.bin
scp -O klipper/firmwares/F004_noz0_001_G30-noz0_005_000.bin \
    root@192.168.1.94:/usr/share/klipper/fw/F004/noz0_001_G30-noz0_005_000.bin
ssh root@192.168.1.94 'md5sum /usr/share/klipper/fw/F004/*.bin'
# Verify MD5 matches values above
```
Then power-cycle the printer ; `S13mcu_update` will detect the (potentially
re-introduced) mismatch and flash stock automatically.

Both built by Creality, embed timestamp `Jul 17 2023 15:29:57` (main) and
`Jul 14 2023 13:57:19` (nozzle) — visible via `cat /proc/asound/cards`-style
strings in the binary, or via the `build_machine_uid` constant Klipper logs:

```
MCU 'mcu' config: ... build_machine_uid=Jul 17 202315:29:57
MCU 'nozzle_mcu' config: ... build_machine_uid=Jul 14 202313:57:19
```

## Rollback mechanism

`/etc/init.d/S13mcu_update` runs at every boot. It enumerates `/usr/share/klipper/fw/F004/`,
extracts the target version from each filename (`*_NNN_000.bin` part), queries
the live MCU for its current version via `mcu_util -g`, and reflashes if mismatch.

So : if we flash mainline Klipper firmware (which will report a different
version label like `v0.13.0-686-g...` or whatever `make` produces), the next
boot `S13mcu_update` sees the mismatch and restores the stock .bin
automatically.

**Validation that this works** : `S13mcu_update` has been observed correctly
flashing `mcu0` and `noz0` on every boot since first install of the unit.
(Confirmed in `/tmp/mcu_update.log` between V1.2.0.09 → V1.2.0.21 OTA upgrades.)

## Precautions before flashing mainline

1. Verify both .bin files exist AND match the MD5 above. Run:
   ```bash
   ssh root@192.168.1.94 'md5sum /usr/share/klipper/fw/F004/*.bin'
   ```
   Compare against this file.

2. Capture the active MCU firmware version BEFORE flashing :
   ```bash
   ssh root@192.168.1.94 'cat /tmp/.mcu_version 2>/dev/null'
   ```
   Save for comparison after rollback.

3. Backup the current `S13mcu_update` script (we have patches to it for
   `bed0_serial`) :
   ```bash
   ssh root@192.168.1.94 'cp -p /etc/init.d/S13mcu_update /usr/data/backup/S13mcu_update.before-mainline-test'
   ```

## After the flash test

To roll back to stock :

1. Remove the mainline `.bin` from `/usr/share/klipper/fw/F004/`
2. (Optional) Power-cycle to trigger `S13mcu_update`
3. (OR) Run `S13mcu_update` manually : `/etc/init.d/S13mcu_update`
4. Verify : `cat /tmp/.mcu_version` should match the original (pre-flash)
   reading from step 2 above.

## Why this matters

The host Klipper master `4bc56464` (2026) speaks to MCU firmware compiled in
July 2023 (Creality fork at SHA `341a2c18-dirty`). All previous attempts to
diagnose `Invalid sequence` host-side crashes have eliminated :

- gcc 5.2.0 vs 14.2.0 (no diff)
- LTO ON vs OFF (no diff)
- Toolchain Ingenic vs crosstool-NG (no diff)
- Klipper commit `7c0ee84` revert (no diff)
- Patch `serialize gen_steps` (no diff)

The remaining hypotheses include : the MCU firmware mismatch perturbing
multi-MCU clocksync or feature-set negotiation in subtle ways. Flashing
mainline MCU firmware on both `mcu` and `nozzle_mcu` would isolate this
variable. The stock binaries inventory documented here is the safety net
that makes this experiment reasonable to run.
