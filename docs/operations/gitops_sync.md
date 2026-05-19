# GitOps sync — operations guide

The four scripts in [`scripts/`](../../scripts/) are the only way you should be touching the printer's filesystem after Phase 1. They enforce the contract that **the repo is the source of truth** and that nothing destructive happens without a fresh backup.

## Prerequisites

On your local machine:

| Tool       | Required? | Where to get it (Windows)              |
|------------|-----------|----------------------------------------|
| `bash` 4+  | yes       | Bundled with Git for Windows (Git Bash) |
| `ssh`      | yes       | Bundled with Git for Windows / Windows 10+ |
| `tar`      | yes       | Bundled with Git for Windows           |
| `md5sum`   | yes       | Bundled with Git for Windows           |
| `rsync`    | optional  | `pacman -S rsync` in MSYS2, or fallback to tar-pipe |

On Linux/macOS everything except `rsync` is preinstalled; install rsync with your package manager if you don't already have it.

## One-time setup

```bash
cp config.sh.example config.sh
# Edit config.sh: at minimum set PRINTER_HOST to your printer's IP.
```

`config.sh` is gitignored.

## The four scripts

### `verify.sh` — read-only health check

Run this anytime to see the live state of the printer:

```bash
bash scripts/verify.sh           # full report (~5 s)
bash scripts/verify.sh --quick   # skip drift detection (~2 s)
```

Reports:

1. SSH reachability
2. System overview (uptime, RAM, disk)
3. Which services are running (Klipper, Moonraker, nginx, GuppyScreen, telegraf, Creality stack)
4. Listening TCP/UDP ports
5. Klipper health (log size, last stats line, recent warnings/errors)
6. Drift between repo files and live files (md5 comparison)

**Makes zero changes. Safe to run at any time, even mid-print.**

### `backup.sh` — local snapshot

Always run this before any `sync.sh --apply`:

```bash
bash scripts/backup.sh             # full backup including logs
bash scripts/backup.sh --quick     # config-only (no logs, no gcodes)
```

Produces `backups-local/E5M-CK-backup-YYYYMMDD-HHMMSS.tar.gz`. The `backups-local/` directory is gitignored — backups never leave your machine.

Backup contents:

- `/usr/data/printer_data/` — Klipper config + logs + gcodes
- `/etc/init.d/` — init scripts (for reverting service changes)
- `/usr/data/creality/userdata/` — Creality state JSONs
- `/opt/` — Entware tree (if present)
- `/usr/data/e5m-ck/` — our staging dir (if present)

### `sync.sh` — apply repo → live

Two modes:

```bash
bash scripts/sync.sh             # dry-run: shows what WOULD change, changes nothing (default)
bash scripts/sync.sh --apply     # actually push, after backup-freshness check
bash scripts/sync.sh --apply --force   # skip backup check (NOT recommended)
```

`--apply` refuses to run if there's no backup younger than 60 minutes in `backups-local/`. This is by design.

The sync map (what goes where) is defined inside `sync.sh`. As the project grows we extend it:

| Repo path                              | Live path                                           |
|----------------------------------------|-----------------------------------------------------|
| `klipper/config/`                      | `/usr/data/printer_data/config/` (dir, --delete)    |
| `system/etc/init.d/`                   | `/etc/init.d/` (dir, --delete)                      |
| `moonraker/moonraker.conf`             | `/usr/data/printer_data/config/moonraker.conf`      |
| `nginx/nginx.conf`                     | `/opt/etc/nginx/nginx.conf`                         |
| `guppyscreen/guppyconfig.json`         | `/usr/data/guppyscreen/guppyconfig.json`            |

Transport is `rsync` if installed locally, otherwise a `tar | ssh tar` pipe fallback.

### `factory-reset.sh` — undo all E5M-CK mods

```bash
bash scripts/factory-reset.sh                       # dry-run, shows what would be removed
bash scripts/factory-reset.sh --confirm-i-mean-it   # actually does it
```

This is the **SSH alternative** to the USB factory-reset method. It removes only what *we* installed (Entware, our venvs, GuppyScreen, our init scripts) and restores the original Creality `S58factoryreset` from its backup if present. It does not touch the squashfs base system.

If something is so broken that SSH no longer works, fall back to the USB method: format a USB key as FAT32, create an empty file named exactly `factory_reset` (no extension), plug it in, power-cycle.

## Recommended workflow

For a routine config change:

```bash
# 1. Edit files in the repo (e.g. klipper/config/printer.cfg)
$EDITOR klipper/config/printer.cfg

# 2. Validate that the change is what you expect
bash scripts/sync.sh                  # dry-run
bash scripts/verify.sh                # see live drift before the change

# 3. Take a backup
bash scripts/backup.sh

# 4. Apply
bash scripts/sync.sh --apply

# 5. Verify the result
bash scripts/verify.sh

# 6. Commit if happy
git add klipper/config/printer.cfg
git commit -m "Bump bed PID after re-tuning"
git push
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `SSH unreachable` | Wrong IP, printer off, key not deployed | Check `config.sh`, ping the printer, re-deploy `id_rsa.pub` |
| `No backup younger than 60 min` | Forgot to run `backup.sh` | `bash scripts/backup.sh && bash scripts/sync.sh --apply` |
| `md5sum: command not found` (local) | Git Bash isn't on PATH | Ensure Git for Windows is installed and `bash` resolves to it |
| Drift reported on a file you didn't touch | Live runtime auto-edited the file (e.g. Klipper writes back calibration) | Pull the live version into the repo, commit, then re-sync |
| `rsync: command not found` | Optional dep missing | The tar-pipe fallback kicks in automatically; install rsync for speed if you want |
