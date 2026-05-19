# GuppyScreen — operations guide

Phase 5 replaces Creality's touchscreen UI (`display-server` + `boot_display` + `cmd_jpeg_display`) with **GuppyScreen**, an open-source Klipper touch UI by ballaswag.

## Versions pinned

| Component   | Pinned          | Source                                         |
|-------------|-----------------|------------------------------------------------|
| GuppyScreen | `v0.0.26-beta`  | `ballaswag/guppyscreen` release `guppyscreen-smallscreen.tar.gz` |

Screen on the Ender 5 Max is 480×272 → we use the `smallscreen` build (the `normal` build targets ≥ 800px wide screens).

## How the display handoff works

The Creality touchscreen stack consists of three init scripts that all need to stand down for GuppyScreen to own `/dev/fb0`:

| Stock script          | What it does                                  | Phase 5 action                           |
|-----------------------|-----------------------------------------------|------------------------------------------|
| `S12boot_display`     | Splash screen at boot                         | **Moved out** of `/etc/init.d/` (filesystem rename to `/usr/data/backup/guppyscreen-stock/`) |
| `S50dropbear`         | Starts SSH server                             | **Replaced** with GuppyScreen's variant — starts SSH *before* the display layer so you can recover if Guppy hangs |
| `S99start_app`        | Master script spawning 9 Creality services    | **Disabled** by `installs/creality_kill.sh --permanent` (moved to `/usr/data/backup/creality-init/S99start_app.disabled`). Reversible via `--restore`. |
| `S99guppyscreen`      | (new)                                         | **Installed** from the GuppyScreen tarball's `k1_mods/` directory |

The "kept alive" Creality services (intentionally not killed):
- WiFi: `wpa_supplicant`, `ifplugd`, `wifi-server`
- SSH: `dropbear`
- mDNS: `mdns` (so `http://printer.local/` keeps working)

## Install procedure

```bash
# (1) Local: fresh backup
bash scripts/backup.sh

# (2) PREREQ — disable Creality's display-server (and the 9 other
#     obsolete services). If skipped, install_guppyscreen.sh fails fast
#     because display-server still owns /dev/fb0.
cat installs/creality_kill.sh | ssh root@192.168.1.94 'sh -s -- --list'
cat installs/creality_kill.sh | ssh root@192.168.1.94 'sh -s -- --permanent'

# (3) Push the install script + run it
cat installs/install_guppyscreen.sh | ssh root@192.168.1.94 'sh -s'
# This:
#   - downloads guppyscreen-smallscreen.tar.gz from GitHub releases
#   - extracts to /usr/data/guppyscreen/
#   - moves /etc/init.d/S12boot_display out (kills the boot splash)
#   - replaces /etc/init.d/S50dropbear with Guppy's variant (SSH early)
#   - installs /etc/init.d/S99guppyscreen from k1_mods/
#   - creates the librc.so.1 / libeinfo.so.1 symlinks supervise-daemon needs
#   - aborts cleanly if display-server is somehow still up

# (4) Push our guppyconfig.json (pin layout matches Phase 3 printer.cfg)
bash scripts/sync.sh --apply

# (5) Start GuppyScreen
ssh root@192.168.1.94 '/etc/init.d/S99guppyscreen start'

# (6) Look at the printer screen
# You should see the GuppyScreen dashboard. Tap around.

# (7) Verify
bash scripts/verify.sh
# In section "3. Services":
#   ✓ GuppyScreen running (pids: ...)
#   · Creality disp not running
```

## Configuration (`guppyscreen/guppyconfig.json`)

Key entries tailored for E5M-CK:

| Field                                  | Why                                                  |
|----------------------------------------|------------------------------------------------------|
| `default_printer: "e5m-ck"`            | Profile name (was `k1` in v1 — renamed for clarity)  |
| `printers.e5m-ck.moonraker_host: 127.0.0.1`  | Local Moonraker, port 7125                     |
| `fans: [{id: "fan_generic fan0"}, ...]` | Matches our `[fan_generic fan0]` + `[fan_generic fan1]` Klipper sections |
| `leds: [{id: "output_pin light_pin"}]` | Matches our `[output_pin light_pin]` |
| `monitored_sensors: extruder + heater_bed` | The two heaters on this printer            |
| `default_macros.load_filament`         | Inline M83/G1/M82 (no Klipper-side macro needed)     |
| `display_rotate: 0`                    | Screen orientation — change to 180 if mounted upside |
| `theme: "dark"`                        |                                                      |
| `wifi_interface: "wlan0"`              | Matches our Broadcom WiFi (no ethernet on this SoC)  |

## Verify checklist

After `S99guppyscreen start`:

- Touchscreen lights up and shows the GuppyScreen UI within ~10 s.
- Tap a heater button → temperature target sends to Klipper → bed/extruder starts heating.
- `bash scripts/verify.sh` shows GuppyScreen process running, no Creality `display-server` / `master-server` / `cx_ai_middleware`.
- `tail -50 /usr/data/printer_data/logs/guppyscreen.log` — no Python tracebacks or `connection refused`.

## Rollback

To restore the stock Creality UI:

```bash
ssh root@192.168.1.94 '
  /etc/init.d/S99guppyscreen stop
  cp /usr/data/backup/guppyscreen-stock/S50dropbear.orig /etc/init.d/S50dropbear
  cp /usr/data/backup/guppyscreen-stock/S12boot_display.disabled /etc/init.d/S12boot_display
  rm -f /etc/init.d/S99guppyscreen
  reboot
'
```

Or, more aggressively: `bash scripts/factory-reset.sh --confirm-i-mean-it` (removes `/usr/data/guppyscreen/` and restores stock init scripts via the standard rollback path).

## Known issues

- **Black screen for 5–10 s at startup**: normal. GuppyScreen takes over the framebuffer from the kernel splash. If it stays black > 30 s, something's wrong — `ssh in` and check `guppyscreen.log`.
- **Touch coordinates inverted/wrong**: change `display_rotate` in `guppyconfig.json` (0/90/180/270).
- **Fans / heaters not controllable from UI**: pin IDs in `guppyconfig.json` must match the Klipper section names (`fan_generic fan0` vs `output_pin fan0` — case-sensitive, space-sensitive).
- **GuppyScreen restarts in a loop**: usually a Moonraker connection issue (Moonraker not running, or wrong port). Check `curl http://127.0.0.1:7125/server/info` first.
