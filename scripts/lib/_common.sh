#!/usr/bin/env bash
# E5M-CK shared helpers. Sourced by all scripts in scripts/.
# Provides: logging, config loading, SSH wrapper, confirmation prompts, drift detection.

# Strict mode (callers may opt out with `set +u` if needed).
set -o pipefail

# -- Paths ----------------------------------------------------------------

# Resolve repo root regardless of where the calling script lives.
# BASH_SOURCE[1] = the script that sourced us; BASH_SOURCE[0] = this file.
_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${_lib_dir}/../.." && pwd)"
unset _lib_dir

# -- Logging --------------------------------------------------------------

# Use stderr for diagnostics so stdout stays clean for piping.
_ts() { date +'%Y-%m-%d %H:%M:%S'; }

log()  { printf '[%s] %s\n'           "$(_ts)" "$*" >&2; }
warn() { printf '[%s] WARN: %s\n'     "$(_ts)" "$*" >&2; }
err()  { printf '[%s] ERROR: %s\n'    "$(_ts)" "$*" >&2; }
die()  { err "$*"; exit 1; }

# Colored output only when stderr is a tty.
if [ -t 2 ]; then
  C_RESET=$'\033[0m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
else
  C_RESET=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
fi
section() { printf '\n%s== %s ==%s\n' "$C_BLUE" "$*" "$C_RESET" >&2; }
ok()      { printf '%s  ✓ %s%s\n'     "$C_GREEN" "$*" "$C_RESET" >&2; }
ko()      { printf '%s  ✗ %s%s\n'     "$C_RED" "$*" "$C_RESET" >&2; }
info()    { printf '%s  · %s%s\n'     "$C_DIM" "$*" "$C_RESET" >&2; }

# -- Config loading -------------------------------------------------------

# Load config.sh if present, otherwise rely on environment variables, otherwise fail.
load_config() {
  local cfg="${REPO_ROOT}/config.sh"
  if [ -f "$cfg" ]; then
    # shellcheck disable=SC1090
    . "$cfg"
  fi
  : "${PRINTER_HOST:?PRINTER_HOST not set. Copy config.sh.example to config.sh and edit it.}"
  : "${SSH_USER:=root}"
  : "${SSH_PORT:=22}"
  : "${SSH_KEY:=}"
  : "${BACKUP_DIR:=backups-local}"

  # Make backup dir an absolute path under REPO_ROOT if relative.
  case "$BACKUP_DIR" in
    /*) : ;;
    *)  BACKUP_DIR="${REPO_ROOT}/${BACKUP_DIR}" ;;
  esac
  export PRINTER_HOST SSH_USER SSH_PORT SSH_KEY BACKUP_DIR
}

# -- SSH wrapper ----------------------------------------------------------

# Run a command on the printer over SSH. Stdin is forwarded.
# Usage: ssh_run "command" | ssh_run "command" < input
#
# Modern OpenSSH clients print a noisy "WARNING: connection is not using a
# post-quantum key exchange algorithm" line on stderr for every connection
# to older sshd (busybox/dropbear). We filter it so verify.sh stays readable.
ssh_run() {
  local cmd="$1"
  local opts=(
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout=10
    -o ServerAliveInterval=30
    -p "$SSH_PORT"
  )
  if [ -n "$SSH_KEY" ]; then
    opts+=(-i "$SSH_KEY")
  fi
  ssh "${opts[@]}" "${SSH_USER}@${PRINTER_HOST}" "$cmd" 2> >(
    grep -vE '(WARNING: connection is not using|store now, decrypt later|may need to be upgraded|openssh.com/pq.html)' >&2
  )
}

# Run a shell script on the remote via stdin. Avoids quoting hell.
# Usage: ssh_script <<'EOF'
#   echo "hello from printer"
# EOF
ssh_script() {
  ssh_run 'sh -s'
}

# Quick check: is the printer reachable over SSH?
ssh_ping() {
  ssh_run 'echo ok' >/dev/null 2>&1
}

# -- Interactive prompts --------------------------------------------------

# confirm "Question" → exits 0 if user types y/yes, non-zero otherwise.
# Non-interactive callers must pass --yes via the calling script's args.
confirm() {
  local question="$1"
  local reply
  printf '%s%s [y/N] %s' "$C_YELLOW" "$question" "$C_RESET" >&2
  read -r reply
  case "$reply" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

# -- File-system helpers --------------------------------------------------

# md5 of a file, portable (md5sum on Linux/Git Bash, md5 on macOS).
file_md5() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$1" | awk '{print $1}'
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q "$1"
  else
    die "Need md5sum or md5 in PATH."
  fi
}

# md5 of a remote file via ssh (uses md5sum on the printer's busybox).
remote_md5() {
  local remote_path="$1"
  ssh_run "md5sum '$remote_path' 2>/dev/null | awk '{print \$1}'"
}

# -- Drift detection ------------------------------------------------------

# Compare a local file with its expected live path on the printer.
# Echoes "OK", "DRIFT", or "MISSING".
# Usage: check_drift <local_path> <remote_path>
check_drift() {
  local local_path="$1"
  local remote_path="$2"
  if [ ! -f "$local_path" ]; then
    echo "MISSING_LOCAL"
    return
  fi
  local local_hash remote_hash
  local_hash=$(file_md5 "$local_path")
  remote_hash=$(remote_md5 "$remote_path")
  if [ -z "$remote_hash" ]; then
    echo "MISSING_REMOTE"
  elif [ "$local_hash" = "$remote_hash" ]; then
    echo "OK"
  else
    echo "DRIFT"
  fi
}

# -- Backup freshness -----------------------------------------------------

# Is there a backup in BACKUP_DIR that is younger than MAX_AGE_MINUTES?
# Used by sync.sh to refuse --apply without a fresh safety backup.
recent_backup_exists() {
  local max_age_min="${1:-60}"
  [ -d "$BACKUP_DIR" ] || return 1
  # find files newer than N minutes
  local newest
  newest=$(find "$BACKUP_DIR" -maxdepth 1 -name '*.tar.gz' -type f -mmin "-${max_age_min}" 2>/dev/null | head -n 1)
  [ -n "$newest" ]
}

# -- Dry-run guard --------------------------------------------------------

# Scripts set DRY_RUN=1 by default and parse --apply to flip it.
# Use `would_do` for non-destructive printing in dry-run mode.
would_do() {
  if [ "${DRY_RUN:-1}" = "1" ]; then
    printf '%s  [dry-run] would: %s%s\n' "$C_DIM" "$*" "$C_RESET" >&2
    return 0
  fi
  return 1
}
