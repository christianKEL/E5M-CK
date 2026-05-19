#!/usr/bin/env bash
# E5M-CK backup.sh — snapshot printer state to a local timestamped tarball.
#
# What gets backed up (from the printer):
#   /usr/data/printer_data/         Klipper config + logs + gcodes
#   /etc/init.d/                    Init scripts (so we can revert them)
#   /usr/data/creality/userdata/    Creality JSON state
#   /opt/                           Entware (if present, for future use)
#   /usr/data/e5m-ck/               Our staging dir (if present)
#
# Output: $BACKUP_DIR/E5M-CK-backup-YYYYMMDD-HHMMSS.tar.gz (gitignored).
#
# Usage:
#   bash scripts/backup.sh             # full backup
#   bash scripts/backup.sh --quick     # config only (no logs, smaller)

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/_common.sh
. "${SCRIPT_DIR}/lib/_common.sh"

load_config

QUICK=0
for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=1 ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

ssh_ping || die "SSH unreachable to ${SSH_USER}@${PRINTER_HOST}"

mkdir -p "$BACKUP_DIR"
stamp=$(date +'%Y%m%d-%H%M%S')
out="${BACKUP_DIR}/E5M-CK-backup-${stamp}.tar.gz"

# Build the include list, with --quick stripping logs.
section "Backup target: $out"

# Use tar on the remote, stream the .tar.gz over stdout, save locally.
# `tar -C /` produces relative paths inside the archive, easy to inspect.
includes='
  usr/data/printer_data
  etc/init.d
  usr/data/creality/userdata
'
[ -d "${REPO_ROOT}/scripts" ] && true  # silence linter

# Optional dirs added only if they exist on the printer.
optional_includes='
  opt
  usr/data/e5m-ck
'

# Build the remote command. Use sh -s to avoid quoting hell.
tar_excludes=''
if [ "$QUICK" = "1" ]; then
  tar_excludes='--exclude=usr/data/printer_data/logs --exclude=usr/data/printer_data/gcodes'
  info "Quick mode: excluding logs/ and gcodes/"
fi

remote_script() {
  cat <<REMOTE
set -e
cd /
includes_present=""
for d in $(echo "$includes" | tr '\n' ' '); do
  [ -e "/\$d" ] && includes_present="\$includes_present \$d"
done
for d in $(echo "$optional_includes" | tr '\n' ' '); do
  [ -e "/\$d" ] && includes_present="\$includes_present \$d"
done
# Print manifest to stderr for visibility.
echo "Backing up: \$includes_present" >&2
# Pipe through gzip on the remote (the host is small but gzip is cheap).
tar c $tar_excludes \$includes_present 2>/dev/null | gzip -1
REMOTE
}

# backup.sh always actually backs up — that's its job. No dry-run mode.
info "Streaming backup from printer..."
remote_script | ssh_script > "$out"

# Validate the archive.
if ! tar -tzf "$out" >/dev/null 2>&1; then
  rm -f "$out"
  die "Backup tarball is corrupted (deleted)."
fi

size=$(wc -c < "$out")
size_kb=$(( size / 1024 ))
ok "Backup written: $out (${size_kb} KB)"
info "List first 10 entries: tar -tzf '$out' | head"
