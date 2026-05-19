#!/usr/bin/env bash
# E5M-CK verify.sh — read-only health check over SSH.
#
# Reports the live state of the printer and any drift between the repo
# and the deployed files. Makes ZERO changes.
#
# Usage:
#   bash scripts/verify.sh           # full report
#   bash scripts/verify.sh --quick   # skip drift detection (faster)

set -eu

# -- Source helpers --
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/_common.sh
. "${SCRIPT_DIR}/lib/_common.sh"

load_config

QUICK=0
for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=1 ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

# -- 1. Reachability --
section "1. Reachability"
info "host: ${SSH_USER}@${PRINTER_HOST}:${SSH_PORT}"
if ssh_ping; then
  ok "SSH reachable, key auth works"
else
  ko "SSH unreachable. Check VPN/LAN and key deployment."
  exit 1
fi

# -- 2. System overview --
section "2. System overview"
ssh_script <<'REMOTE' | sed 's/^/  /' >&2
:
echo "hostname     : $(cat /etc/hostname 2>/dev/null || echo unknown)"
echo "uptime       : $(uptime | sed 's/^ *//')"
echo "kernel       : $(uname -r)"
echo "arch         : $(uname -m)"
echo "memory       : $(awk '/MemAvailable/{a=$2} /MemTotal/{t=$2} END{printf "%d MB free / %d MB total", a/1024, t/1024}' /proc/meminfo)"
echo "load         : $(awk '{print $1, $2, $3}' /proc/loadavg)"
echo "disk /usr/data: $(df -h /usr/data | awk 'NR==2 {print $4 " free / " $2 " total (" $5 " used)"}')"
echo "disk overlay : $(df -h /overlay | awk 'NR==2 {print $4 " free / " $2 " total (" $5 " used)"}')"
REMOTE

# -- 3. Service status --
section "3. Services"
# Fetch the full process listing once, then grep locally to avoid SSH per service.
# (busybox pgrep -f matches its own ssh wrapper cmdline → unreliable, so we ps + grep.)
ps_dump=$(ssh_run "ps w" | grep -v ' \[' | grep -v 'PID   USER')

svc_report() {
  local name pattern
  name="$1"; pattern="$2"
  local pids
  pids=$( { echo "$ps_dump" | grep -E "$pattern" | grep -v grep | awk '{print $1}' | head -3 | tr '\n' ' '; } || true)
  if [ -n "$pids" ]; then
    ok "$name running (pids: ${pids% })"
  else
    info "$name not running"
  fi
}
svc_report "Klipper        " "klippy\.py"
svc_report "klipper_mcu    " "klipper_mcu"
svc_report "Moonraker      " "moonraker"
svc_report "nginx          " "/nginx( |$)"
svc_report "Fluidd (static)" "fluidd"
svc_report "GuppyScreen    " "guppyscreen"
svc_report "Telegraf       " "telegraf"
svc_report "Creality app   " "/app-server"
svc_report "Creality web   " "/web-server"
svc_report "Creality disp  " "/display-server"
svc_report "Creality AI    " "cx_ai_middleware"
svc_report "Creality webrtc" "/webrtc "

# -- 4. Listening ports --
section "4. Listening ports"
ssh_run "netstat -ln 2>/dev/null | awk 'NR>2 && /^tcp/{print \"  TCP \" \$4} NR>2 && /^udp/{print \"  UDP \" \$4}' | sort -u" >&2

# -- 5. Klipper health --
section "5. Klipper health"
ssh_script <<'REMOTE' | sed 's/^/  /' >&2
:
log=/usr/data/printer_data/logs/klippy.log
if [ ! -f "$log" ]; then
  echo "klippy.log not found at $log"
  exit 0
fi
echo "log size     : $(wc -c < "$log") bytes"
echo "last stats line (key metrics):"
tail -1 "$log" | awk '
  match($0, /Stats [0-9.]+/) { ts=substr($0,RSTART+6,RLENGTH-6); printf "  print_time     : %s s\n", ts }
  match($0, /memavail=[0-9]+/) { v=substr($0,RSTART+9,RLENGTH-9); printf "  memavail       : %d MB\n", v/1024 }
  match($0, /sysload=[0-9.]+/) { v=substr($0,RSTART+8,RLENGTH-8); printf "  sysload        : %s\n", v }
  match($0, /heater_bed: target=[0-9]+ temp=[0-9.]+/) { printf "  %s\n", substr($0,RSTART,RLENGTH) }
  match($0, /extruder: target=[0-9]+ temp=[0-9.]+/) { printf "  %s\n", substr($0,RSTART,RLENGTH) }
'
echo
echo "MCU health (cumulative):"
# The last stats line concatenates per-MCU sections like:
#   mcu: ... bytes_retransmit=0 ... nozzle_mcu: ... bytes_retransmit=0 ... leveling_mcu: ... bytes_retransmit=9 ...
# Walk the tokens and remember the most recent <name>: each time bytes_retransmit shows up.
tail -1 "$log" | tr ' ' '\n' | awk '
  /:$/                            { name=$0; sub(/:$/, "", name); next }
  /^bytes_retransmit=/            { sub("bytes_retransmit=",""); printf "  %-14s retransmit=%s\n", name, $0 }
'
echo
echo "recent warnings/errors (last 200 lines):"
tail -200 "$log" | grep -Ei 'warn|error|flush_handler|timer too close|shutdown' | tail -5 || true
[ -z "$(tail -200 "$log" | grep -Ei 'warn|error|flush_handler|timer too close|shutdown')" ] && echo "  (none)"
REMOTE

# -- 6. Drift detection (file md5 repo vs live) --
if [ "$QUICK" = "0" ]; then
  section "6. Drift detection (repo vs live)"
  # Map: <repo_relative_path> <remote_absolute_path>
  drift_map() {
    # Each line: REPO_PATH|LIVE_PATH
    cat <<'MAP'
system/etc/init.d/S58factoryreset|/etc/init.d/S58factoryreset
klipper/config/printer.cfg|/usr/data/printer_data/config/printer.cfg
moonraker/moonraker.conf|/usr/data/printer_data/config/moonraker.conf
nginx/nginx.conf|/opt/etc/nginx/nginx.conf
guppyscreen/guppyconfig.json|/usr/data/guppyscreen/guppyconfig.json
MAP
  }

  while IFS='|' read -r local_rel remote_path; do
    [ -z "$local_rel" ] && continue
    local_path="${REPO_ROOT}/${local_rel}"
    status=$(check_drift "$local_path" "$remote_path")
    case "$status" in
      OK)             ok   "$local_rel  =  $remote_path" ;;
      DRIFT)          ko   "$local_rel  ≠  $remote_path  (md5 differs)" ;;
      MISSING_LOCAL)  info "$local_rel  (not in repo yet)" ;;
      MISSING_REMOTE) info "$remote_path (not yet deployed on printer)" ;;
    esac
  done < <(drift_map)
else
  section "6. Drift detection: skipped (--quick)"
fi

section "Done."
