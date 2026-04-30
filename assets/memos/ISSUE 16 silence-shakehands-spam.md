# Silencing Creality `master-server` `shakehands` Spam in `klippy.log`

> **E5M-CK** — Ender 5 Max + Creality + Klipper mainline configuration project.

A minimal, fully reversible fix for Creality printers running mainline
Klipper (Ender 5 Max, K1 family, and similar Creality F006-based firmware).

## The Problem

On Creality printers running mainline Klipper, `klippy.log` is flooded
with the following message about once per second:

```
webhooks: No registered callback for path 'shakehands'
```

The log fills up quickly, drowning out useful diagnostic output and
making it harder to debug real issues.

## Root Cause

The Creality stock firmware ships a proprietary userland that includes a
process called `master-server` (`/usr/bin/master-server`). It is the
orchestrator that bridges the Creality touchscreen UI, the Creality
cloud services, and the printer's motion control daemon.

`master-server` opens a Unix socket connection to Klipper at
`/tmp/klippy_uds` and periodically polls a webhook endpoint named
`shakehands` (a typo for "shake_hands"). That endpoint exists only in
Creality's forked Klipper — **mainline Klipper has no such handler**, so
it logs an error every time the request arrives.

Identifying the culprit can be done with `lsof`:

```sh
lsof /tmp/klippy_uds
```

The connection from `/usr/bin/master-server` is the offending one. Its
peer socket is registered under the unusual name `/tmp/klippy_client`,
visible in `/proc/net/unix`.

## What `master-server` Provides (and What You Lose)

Disabling `master-server` removes:

- The Creality Cloud / Creality Print mobile app integration
- Control from the **stock Creality touchscreen UI** (irrelevant if you
  use GuppyScreen, Mainsail, or Fluidd)
- Automatic cloud upload and notifications

It does **not** affect:

- Klipper, Moonraker, Fluidd, Mainsail
- GuppyScreen
- The camera stack (`webrtc`)
- Wi-Fi, SSH, NTP
- Klipper macros and configurations

If you are running a mainline-Klipper setup with a third-party UI, you
were almost certainly not using any `master-server` features anyway.

## The Fix

The approach is to leave the original Creality init scripts **untouched**
and add a second init script that kills `master-server` shortly after
boot. This is the most reversible option: removing the file restores the
system to its factory state.

### Installation

Create the script at `/etc/init.d/Z99kill_master_server`:

```sh
cat > /etc/init.d/Z99kill_master_server << 'EOF'
#!/bin/sh
case "$1" in
    start)
        ( sleep 8 && killall master-server 2>/dev/null ) &
        ;;
esac
exit 0
EOF
chmod +x /etc/init.d/Z99kill_master_server
```

Then reboot the printer.

### How It Works

- `Z99kill_master_server` runs at boot. Its name guarantees it executes
  alphabetically after `S99start_app`, the Creality script that spawns
  `master-server`.
- The 8-second `sleep` is a safety margin in case the Creality init
  scripts run in parallel rather than strictly sequentially. After
  8 seconds `master-server` is reliably running and ready to be killed.
- `killall master-server` terminates only that process. All other
  Creality services (`audio-server`, `wifi-server`, `app-server`,
  `web-server`, `upgrade-server`) keep running.
- Klipper's `Disconnected` notice for the closed socket is logged once,
  and the `shakehands` spam stops permanently.

### Verification

About 30 seconds after boot:

```sh
ps w | grep master-server | grep -v grep
```

The output should be empty. You can also check the live log:

```sh
tail -f /usr/data/printer_data/logs/klippy.log
```

There should be no further `shakehands` lines.

### Reverting

```sh
rm /etc/init.d/Z99kill_master_server
reboot
```

The system returns to its original Creality behavior. No backup of any
stock file is required, because no stock file was modified.

## Tested On

- Ender 5 Max (mainboard CR4NS200323C10) running mainline Klipper +
  Moonraker + Fluidd + GuppyScreen
- Should apply unmodified to any Creality printer using the F006
  userland that runs `master-server` from `/etc/init.d/S99start_app`,
  including K1 variants flashed to mainline Klipper.

## License

Public domain. Use, copy, modify freely.

---

*Part of the **E5M-CK** configuration project — Ender 5 Max running
mainline Klipper, BTT Eddy probe, GuppyScreen, and Fluidd on the stock
Creality F006 mainboard (CR4NS200323C10).*
