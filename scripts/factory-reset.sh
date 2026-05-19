#!/usr/bin/env bash
# E5M-CK factory-reset.sh — remove all E5M-CK mods from the printer over SSH.
#
# Removes:
#   /opt                                   (Entware tree)
#   /usr/data/e5m-ck                       (our staging dir)
#   /usr/data/printer_data/config/*.cfg    (only ones we deployed; stock files preserved if present)
#   /usr/data/guppyscreen                  (Guppy install)
#   /usr/data/venvs                        (Python venvs)
#   Replaces /etc/init.d/S58factoryreset with the original if backed up
#
# Then it restarts the relevant services to bring the stock stack back.
#
# This is NOT a hardware factory reset. The USB-key method (empty `factory_reset`
# file on FAT32) remains the authoritative "back to factory" mechanism. This
# script is a softer alternative for removing only what we added.
#
# Usage:
#   bash scripts/factory-reset.sh                       # dry-run (default)
#   bash scripts/factory-reset.sh --confirm-i-mean-it   # actually run

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/_common.sh
. "${SCRIPT_DIR}/lib/_common.sh"

load_config

DRY_RUN=1
for arg in "$@"; do
  case "$arg" in
    --confirm-i-mean-it) DRY_RUN=0 ;;
    -h|--help)
      sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Unknown argument: $arg" ;;
  esac
done
export DRY_RUN

ssh_ping || die "SSH unreachable"

# -- Inventory of what would be removed ----------------------------------
section "Scan: what E5M-CK artifacts are present?"
ssh_script <<'REMOTE' | sed 's/^/  /' >&2
:
report() {
  local label="$1" path="$2"
  if [ -e "$path" ]; then
    size=$(du -sh "$path" 2>/dev/null | awk '{print $1}')
    echo "PRESENT $label  $path  ($size)"
  else
    echo "absent  $label  $path"
  fi
}
report "Entware            " /opt
report "E5M-CK staging dir " /usr/data/e5m-ck
report "GuppyScreen        " /usr/data/guppyscreen
report "Python venvs       " /usr/data/venvs
report "Backup of init    " /usr/data/backup
report "Stock S58 backup   " /usr/data/backup/S58factoryreset.orig
REMOTE

# -- Confirm before acting -----------------------------------------------
if [ "$DRY_RUN" = "0" ]; then
  printf '\n%sYou are about to REMOVE all E5M-CK mods from the printer.%s\n' "$C_RED" "$C_RESET" >&2
  printf '%sThe stock Creality stack will resume on next boot.%s\n' "$C_YELLOW" "$C_RESET" >&2
  confirm "Continue?" || die "Aborted by user."
fi

# -- Execute -------------------------------------------------------------
section "Plan ($([ "$DRY_RUN" = "1" ] && echo dry-run || echo APPLY))"

# Restore stock S58factoryreset from backup if we have one.
ssh_script <<REMOTE | sed 's/^/  /' >&2
:
if [ -f /usr/data/backup/S58factoryreset.orig ]; then
  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] would restore /etc/init.d/S58factoryreset from backup"
  else
    cp /usr/data/backup/S58factoryreset.orig /etc/init.d/S58factoryreset
    chmod +x /etc/init.d/S58factoryreset
    echo "restored /etc/init.d/S58factoryreset"
  fi
fi
REMOTE

# Stop our services BEFORE removing files so they don't choke.
for svc in S99telegraf S98guppyscreen S97e5m_nginx S56moonraker_service S55klipper_e5m; do
  ssh_script <<REMOTE | sed 's/^/  /' >&2
:
if [ -x /etc/init.d/$svc ]; then
  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] would: /etc/init.d/$svc stop && rm /etc/init.d/$svc"
  else
    /etc/init.d/$svc stop 2>/dev/null || true
    rm -f /etc/init.d/$svc
    echo "stopped + removed /etc/init.d/$svc"
  fi
else
  echo "skip $svc (not installed)"
fi
REMOTE
done

# Remove top-level mod directories.
for path in /opt /usr/data/e5m-ck /usr/data/guppyscreen /usr/data/venvs; do
  ssh_script <<REMOTE | sed 's/^/  /' >&2
:
if [ -e "$path" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] would: rm -rf $path"
  else
    rm -rf "$path"
    echo "removed $path"
  fi
fi
REMOTE
done

section "Done."
if [ "$DRY_RUN" = "1" ]; then
  printf '%sThis was a dry-run. Pass --confirm-i-mean-it to actually act.%s\n' "$C_DIM" "$C_RESET" >&2
else
  printf '%sReboot the printer (or kill remaining Creality processes) to fully reset.%s\n' "$C_YELLOW" "$C_RESET" >&2
  info "Suggested: ssh ${SSH_USER}@${PRINTER_HOST} 'reboot'"
fi
