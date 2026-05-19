# Factory reset — operations guide

The printer can return to a clean state at any time, by **two redundant methods**. This is the safety contract that makes the rest of the E5M-CK toolkit safe to experiment with.

## TL;DR

| You want to… | Run this |
|---|---|
| Soft reset (keep SSH/WiFi, wipe mods) | `ssh root@printer /etc/init.d/S58factoryreset reset` |
| Hard reset (cold-boot trigger, no SSH needed) | Put empty file `factory_reset` on FAT32 USB → power cycle |
| Just remove E5M-CK mods (no full reset) | `bash scripts/factory-reset.sh --confirm-i-mean-it` |

## What gets wiped vs preserved

The custom `S58factoryreset` (deployed by `installs/install_factory_reset.sh`) is based on the well-tested Guilouz Helper-Script logic, with English-only comments.

### Wiped
- `/overlay/upper/` — every file overlaid on the squashfs base. This includes:
  - `/opt` (Entware tree)
  - Every modified `/etc/*` file
  - Every script we added to `/etc/init.d/`
- `/usr/data/*` — everything under the user data partition

### Preserved
- `/overlay/upper/etc/dropbear` — SSH host keys (so SSH still works after reset)
- `/overlay/upper/etc/localtime` — timezone
- `/overlay/upper/etc/init.d/S58factoryreset` — this script itself
- `/usr/data/creality/` — Creality stack state (except its `userdata/`)
- `/usr/data/wpa_supplicant.conf` — WiFi credentials (so network reconnects)
- `/usr/data/machine_production_info` — per-printer serial/MAC info
- `/usr/data/creality/userdata/config/system_config.json` — Creality system settings
- `/usr/data/creality/userdata/user_agree_root` — license agreement state

After a reset, the printer reboots, comes back on WiFi, accepts your SSH key, but every E5M-CK mod is gone. **To recover:**

```bash
# From your local machine, in the E5M-CK repo:
bash scripts/verify.sh   # confirms stock state
ssh root@printer 'sh' < installs/install_entware.sh
# ...then re-run the rest of the install pipeline.
```

## The three methods, in detail

### 1. USB method (recommended for emergencies)

Use this when SSH is broken or you don't trust the running system anymore.

1. Format a USB stick as **FAT32**.
2. Create an **empty file named exactly `factory_reset`** at the root of the stick (no extension, no content).
3. Plug the stick into the printer.
4. Power-cycle the printer.

At boot, the stock-or-custom `S58factoryreset` script will:
- Detect the file under `/tmp/udisk/sdaX/factory_reset`
- Rename it to `factory_reset.old` (so it doesn't trigger again)
- Wipe everything (per the rules above) and reboot

This works whether the *custom* or *stock* S58 is in place — both versions implement the USB trigger logic.

### 2. SSH method — `S58factoryreset reset`

Use this when you just want a clean slate and SSH still works.

```bash
ssh root@printer '/etc/init.d/S58factoryreset reset'
```

Same wipe as the USB method. The printer reboots automatically.

### 3. Soft method — `scripts/factory-reset.sh`

Use this when you want to remove **only** the E5M-CK mods without going all the way back to factory. This is faster (no reboot, no WiFi reset) and useful when iterating during development.

```bash
bash scripts/factory-reset.sh                       # dry-run
bash scripts/factory-reset.sh --confirm-i-mean-it   # actually do it
```

This script:
- Stops our init scripts (`S55klipper_e5m`, `S56moonraker_service`, `S97e5m_nginx`, `S98guppyscreen`, `S99telegraf`)
- Removes `/opt` (Entware), `/usr/data/e5m-ck`, `/usr/data/guppyscreen`, `/usr/data/venvs`
- Restores the stock `S58factoryreset` from `/usr/data/backup/S58factoryreset.orig`

It does **not** reboot or touch Creality's state. The stock Creality stack resumes serving on next boot.

## Installing the custom S58factoryreset

This happens once, during Phase 2 of the install pipeline:

```bash
# Local: stream the script over SSH to the printer's installer.
expected_md5=$(md5sum system/etc/init.d/S58factoryreset | awk '{print $1}')
expected_size=$(wc -c < system/etc/init.d/S58factoryreset)
cat installs/install_factory_reset.sh | \
    ssh root@printer "cat | sh -s -- '$expected_md5' '$expected_size'" \
    < system/etc/init.d/S58factoryreset
```

Or, more simply, after Phase 1: run the orchestrator (TBD in Phase 3+) that knows this dance.

Verify it's in place:

```bash
bash scripts/verify.sh
# In section "6. Drift detection", S58factoryreset should show: OK
```

## What the custom S58 changes vs stock

| Capability | Stock | E5M-CK custom |
|---|---|---|
| USB trigger (boot)            | ✅ | ✅ (unchanged) |
| Wipe `/overlay/upper`         | ✅ | ✅ |
| Wipe `/usr/data` (incl. mods) | ✅ | ✅ |
| Manual trigger over SSH (`reset`) | ❌ | ✅ |
| Preserve dropbear/SSH         | ❌ stock wipes them | ✅ |
| Preserve WiFi config          | ❌ stock wipes it | ✅ |
| Preserve timezone             | ❌ | ✅ |

So the custom version is strictly **more useful** than stock for our workflow — it preserves the bits that let us reconnect after a reset.

## What does NOT come back

After a reset, none of these survive:
- Klipper mainline build (the stock Creality fork resumes from squashfs)
- Moonraker, nginx, Fluidd, GuppyScreen
- Telegraf and metrics history
- Any tweak to Klipper config in `/usr/data/printer_data/config/`
- Any patch we applied via `sync.sh`

To get back to "everything working": follow the install pipeline in [`PLAN.md`](../../PLAN.md), or eventually run `scripts/bootstrap.sh` (TBD) which automates phases 2-7.
