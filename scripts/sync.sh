#!/usr/bin/env bash
# E5M-CK sync.sh — apply repo → live printer over SSH.
#
# Idempotent: re-running converges to the target state.
# Refuses --apply without a fresh backup (< 60 min old).
#
# Sources of truth (repo) → destinations (live):
#
#   klipper/config/*           →  /usr/data/printer_data/config/
#   system/etc/init.d/*        →  /etc/init.d/
#   moonraker/moonraker.conf   →  /usr/data/printer_data/config/moonraker.conf
#   nginx/nginx.conf           →  /opt/etc/nginx/nginx.conf
#   guppyscreen/guppyconfig.json → /usr/data/guppyscreen/guppyconfig.json
#
# Transport: rsync if available locally, tar-pipe over ssh as fallback.
#
# Usage:
#   bash scripts/sync.sh                   # dry-run (default)
#   bash scripts/sync.sh --apply           # really push, after backup check
#   bash scripts/sync.sh --apply --force   # skip backup freshness check

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/_common.sh
. "${SCRIPT_DIR}/lib/_common.sh"

load_config

DRY_RUN=1
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --apply) DRY_RUN=0 ;;
    --force) FORCE=1 ;;
    -h|--help)
      sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Unknown argument: $arg" ;;
  esac
done
export DRY_RUN

# -- Map of repo source → live destination -------------------------------
# Format: TYPE|SOURCE|DEST
#   TYPE=file → one file
#   TYPE=dir  → directory contents (recursive)
sync_map() {
  cat <<'MAP'
dir|klipper/config|/usr/data/printer_data/config
dir|system/etc/init.d|/etc/init.d
file|moonraker/moonraker.conf|/usr/data/printer_data/config/moonraker.conf
file|nginx/nginx.conf|/opt/etc/nginx/nginx.conf
file|guppyscreen/guppyconfig.json|/usr/data/guppyscreen/guppyconfig.json
MAP
}

# -- Preflight -----------------------------------------------------------
section "Preflight"

ssh_ping || die "SSH unreachable"
ok "SSH reachable"

if [ "$DRY_RUN" = "0" ] && [ "$FORCE" = "0" ]; then
  if ! recent_backup_exists 60; then
    ko "No backup younger than 60 min in $BACKUP_DIR"
    info "Run: bash scripts/backup.sh"
    info "Or pass --force to bypass (NOT recommended)."
    exit 1
  fi
  ok "Recent backup present (< 60 min old)"
fi

if command -v rsync >/dev/null 2>&1; then
  TRANSPORT="rsync"
  ok "Transport: rsync"
else
  TRANSPORT="tar"
  info "Transport: tar-pipe (rsync not installed locally)"
fi

# -- Helpers -------------------------------------------------------------

# Build ssh argv as a single string for rsync's -e flag.
ssh_e_arg() {
  local s="ssh -p $SSH_PORT -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
  [ -n "$SSH_KEY" ] && s="$s -i $SSH_KEY"
  echo "$s"
}

push_file_rsync() {
  local src="$1" dst="$2"
  local opts=(-az --checksum)
  [ "$DRY_RUN" = "1" ] && opts+=(--dry-run --itemize-changes)
  rsync "${opts[@]}" -e "$(ssh_e_arg)" "$src" "${SSH_USER}@${PRINTER_HOST}:${dst}"
}

push_dir_rsync() {
  local src="$1" dst="$2"
  local opts=(-az --checksum --delete)
  [ "$DRY_RUN" = "1" ] && opts+=(--dry-run --itemize-changes)
  # Trailing slash on src means "contents of", not "the dir itself".
  rsync "${opts[@]}" -e "$(ssh_e_arg)" "${src}/" "${SSH_USER}@${PRINTER_HOST}:${dst}/"
}

push_file_tar() {
  local src="$1" dst="$2"
  if [ "$DRY_RUN" = "1" ]; then
    local status
    status=$(check_drift "$src" "$dst")
    info "  $src → $dst : $status"
    return 0
  fi
  local dst_dir
  dst_dir=$(dirname "$dst")
  ssh_run "mkdir -p '$dst_dir'"
  # Stream a single file via tar to preserve mode.
  tar -C "$(dirname "$src")" -cf - "$(basename "$src")" | \
    ssh_run "tar -C '$dst_dir' -xf - && mv '$dst_dir/$(basename "$src")' '$dst' 2>/dev/null || true"
  info "  pushed $src → $dst"
}

push_dir_tar() {
  local src="$1" dst="$2"
  if [ "$DRY_RUN" = "1" ]; then
    # Compare each file in src against the live dest.
    while IFS= read -r -d '' f; do
      local rel="${f#"$src"/}"
      local status
      status=$(check_drift "$f" "$dst/$rel")
      info "  $rel : $status"
    done < <(find "$src" -type f ! -name '.gitkeep' -print0)
    return 0
  fi
  ssh_run "mkdir -p '$dst'"
  # Tar-pipe the whole directory contents.
  tar -C "$src" --exclude='.gitkeep' -cf - . | ssh_run "tar -C '$dst' -xf -"
  info "  pushed contents of $src/ → $dst/"
}

# -- Execute -------------------------------------------------------------
section "Plan ($([ "$DRY_RUN" = "1" ] && echo dry-run || echo APPLY))"

while IFS='|' read -r kind src dst; do
  [ -z "$kind" ] && continue
  src_abs="${REPO_ROOT}/${src}"
  if [ ! -e "$src_abs" ]; then
    info "skip $src (not present in repo)"
    continue
  fi
  case "$kind" in
    file)
      if [ "$TRANSPORT" = "rsync" ]; then push_file_rsync "$src_abs" "$dst"
      else push_file_tar "$src_abs" "$dst"
      fi
      ;;
    dir)
      if [ "$TRANSPORT" = "rsync" ]; then push_dir_rsync "$src_abs" "$dst"
      else push_dir_tar "$src_abs" "$dst"
      fi
      ;;
    *)
      warn "unknown map type: $kind"
      ;;
  esac
done < <(sync_map)

section "Done."
if [ "$DRY_RUN" = "1" ]; then
  info "This was a dry-run. Pass --apply to push for real."
fi
