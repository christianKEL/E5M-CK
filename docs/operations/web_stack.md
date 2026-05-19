# Web stack — operations guide

After Phase 4, the printer serves a real Klipper-native web UI at `http://<printer-ip>/`. The pieces:

```
Browser  ── HTTP ─→  nginx (port 80, /opt/sbin/nginx)
                       │
                       ├─ static files: /usr/data/e5m-ck/fluidd/   ← Fluidd SPA
                       │
                       └─ proxy: /(server|access|api|machine|printer|websocket)/
                                  └─ http://127.0.0.1:7125 (Moonraker)
                                          │
                                          └─ Unix socket: /tmp/klippy_uds  ← Klipper (klippy)
```

## Versions pinned

| Component  | Pinned       | Rebuild artifact                                            |
|------------|--------------|-------------------------------------------------------------|
| Moonraker  | `v0.10.0`    | source + lean venv from `moonraker/binaries/mipsel-3.4/`    |
| Fluidd     | `v1.37.0`    | release zip from GitHub                                     |

## Why nginx is on port 80 (and what we kill to get there)

The Creality `web-server` binary holds port 80 by default. We need that port for nginx. Approach:

- Our init script `/etc/init.d/S99znginx` runs **after** `S99start_app` (lexicographic order) and unconditionally kills any `/usr/bin/web-server` process before binding port 80 itself.
- The Creality `app-server` on port 9999 keeps running. Their touch screen UI still talks to it. So GuppyScreen (Phase 5) and Fluidd both work — the touch screen ignores port 80.

## Capabilities the lean Moonraker venv misses

The bundled `moonraker-env.tar.gz` is built without these C-extension packages:

| Missing dep            | Affected feature                                              |
|------------------------|----------------------------------------------------------------|
| `pillow`               | Thumbnail generation from slicer-embedded PNGs → Fluidd shows blank job icons |
| `streaming-form-data`  | Fast streaming upload of large gcode files → falls back to slow path |
| `dbus-fast`            | systemd/D-Bus integration → no effect on this SoC (no systemd) |

These are all acceptable for v2 MVP. If we ever ship gcc on the printer (or set up cross-compile of the wheels), we can drop them in.

## Install procedure

```bash
# (1) Local: backup, prepare artifacts
bash scripts/backup.sh

# (2) Push the Moonraker venv tarball (~17 MB) to /tmp on the printer
scp -O moonraker/binaries/mipsel-3.4/moonraker-env.tar.gz \
    root@192.168.1.94:/tmp/moonraker-env.tar.gz

# (3) Run installers in order (each is idempotent)
cat installs/install_moonraker.sh | ssh root@192.168.1.94 'sh -s'
cat installs/install_fluidd.sh    | ssh root@192.168.1.94 'sh -s'

# (4) Push configs + init scripts via sync.sh
bash scripts/sync.sh --apply

# (5) Start the new services
ssh root@192.168.1.94 '/etc/init.d/S56moonraker_service start'
ssh root@192.168.1.94 '/etc/init.d/S99znginx start'

# (6) Verify
bash scripts/verify.sh
curl -s http://192.168.1.94/server/info | jq .
# Expected: klippy_state: ready, software_version starting with v0.13
```

## Verify checklist

- `bash scripts/verify.sh` in section "3. Services":
  - ✓ Klipper
  - ✓ Moonraker
  - ✓ nginx
  - · Creality web (gone — that's intended)
- `curl http://printer/` returns Fluidd HTML.
- `curl http://printer/server/info` returns JSON with `klippy_state: ready`.
- Open `http://printer/` in a browser:
  - Connection indicator says "Klippy: Ready"
  - Temperatures (bed + extruder) live-update via WebSocket
  - Can send `G28` from the gcode console (printer should home)

## Troubleshooting

| Symptom                                       | Likely cause                                                  |
|-----------------------------------------------|---------------------------------------------------------------|
| `curl /server/info` returns "connection refused" | Moonraker not running — check `/usr/data/printer_data/logs/moonraker.log` |
| `curl /` returns Creality JSON, not Fluidd HTML  | nginx didn't bind port 80; Creality web-server still up — `pgrep -f /usr/bin/web-server` and restart S99znginx |
| `klippy_state: shutdown` in `/server/info`     | Klipper itself errored — check `/usr/data/printer_data/logs/klippy.log` |
| Fluidd loads but no live data                  | WebSocket proxy broken — check nginx config `/websocket` block, check Moonraker logs |
| File upload fails on big files                 | Expected — `streaming-form-data` missing. Use the slower fallback or upload via gcode console |
| Job thumbnails are blank                       | Expected — `pillow` missing from venv                         |

## Rollback

To turn the web stack off without removing files:

```bash
ssh root@192.168.1.94 '/etc/init.d/S99znginx stop && /etc/init.d/S56moonraker_service stop'
# Creality web-server stays gone until reboot or manual restart.
# To bring back the stock UI on port 80:
ssh root@192.168.1.94 '/usr/bin/web-server &'
```

Hard removal: `bash scripts/factory-reset.sh --confirm-i-mean-it` (removes everything under `/usr/data/e5m-ck/` and `/usr/data/venvs/`).
