#!/bin/sh
# creality_kill.sh — disable Creality's printer-stack services on this Nebula Pad.
#
# Runs ON THE PRINTER (busybox sh).
#
# Why this script exists:
#   Once we deploy mainline Klipper + Moonraker + nginx + Fluidd + GuppyScreen,
#   the Creality stock services (master-server, app-server, display-server,
#   web-server, …) become dead weight. They:
#     - hold port 80 (web-server) → nginx can't bind
#     - own /dev/fb0 (display-server, cmd_jpeg_display) → GuppyScreen can't draw
#     - eat CPU/RAM with nothing useful to do
#     - spam klippy.log with shakehands callback errors (~30/sec)
#
# Before this script, the kill logic was scattered:
#     - install_guppyscreen.sh killed the 9 obsolete services at install time
#     - S99znginx killed web-server at boot
#   Two problems with that:
#     (1) services come back on every reboot (S99start_app respawns them)
#     (2) ownership unclear — each consumer killed "their" subset
#
# This script centralizes the policy in one place.
#
# Modes:
#   --list        Show which Creality services are running. Read-only.
#   --kill-now    Kill them in the current session. Does NOT survive reboot.
#   --permanent   --kill-now PLUS disable /etc/init.d/S99start_app so the
#                 services don't autostart on subsequent boots. Reversible
#                 via --restore.
#   --restore     Undo --permanent. The Creality stack starts again at next boot.
#
# Services killed (these are spawned by /etc/init.d/S99start_app):
#   master-server  app-server     web-server      display-server   Monitor
#   audio-server   upgrade-server  log_main       cx_ai_middleware webrtc
#
# Services explicitly NOT killed (printer would lose network/SSH):
#   wpa_supplicant  ifplugd  dropbear  mdns  wifi-server
#
# Usage:
#   ssh root@printer 'sh' < installs/creality_kill.sh -- --list
#   ssh root@printer 'sh' < installs/creality_kill.sh -- --permanent
#   ssh root@printer 'sh' < installs/creality_kill.sh -- --restore

set -eu

# -- Configuration --------------------------------------------------------
CREALITY_PROCS="master-server app-server web-server display-server Monitor audio-server upgrade-server log_main cx_ai_middleware webrtc"

S99_TARGET="/etc/init.d/S99start_app"
BACKUP_DIR="/usr/data/backup/creality-init"
S99_BACKUP="$BACKUP_DIR/S99start_app.disabled"

# -- Logging --------------------------------------------------------------
ts()   { date +'%H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(ts)" "$*" >&2; }
err()  { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; }
die()  { err "$*"; exit 1; }

# -- Args -----------------------------------------------------------------
MODE=""
for arg in "$@"; do
    case "$arg" in
        --list)       MODE=list ;;
        --kill-now)   MODE=kill ;;
        --permanent)  MODE=permanent ;;
        --restore)    MODE=restore ;;
        -h|--help)
            sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "Unknown argument: $arg. Use --help." ;;
    esac
done
[ -n "$MODE" ] || die "No mode given. Use --list, --kill-now, --permanent, or --restore."

# -- Helpers --------------------------------------------------------------

# Print a one-line status for each tracked Creality process.
list_state() {
    printf '%-22s %-10s %s\n' "PROCESS" "STATE" "PIDs"
    printf '%-22s %-10s %s\n' "----------------------" "----------" "----"
    for proc in $CREALITY_PROCS; do
        PIDS=$(pidof "$proc" 2>/dev/null || true)
        if [ -n "$PIDS" ]; then
            printf '%-22s %-10s %s\n' "$proc" "RUNNING" "$PIDS"
        else
            printf '%-22s %-10s %s\n' "$proc" "stopped" "-"
        fi
    done
    echo
    if [ -f "$S99_TARGET" ]; then
        echo "S99start_app autostart: ENABLED ($S99_TARGET present)"
    elif [ -f "$S99_BACKUP" ]; then
        echo "S99start_app autostart: DISABLED (moved to $S99_BACKUP)"
    else
        echo "S99start_app autostart: ??? (neither $S99_TARGET nor $S99_BACKUP found)"
    fi
}

# Kill all Creality processes in $CREALITY_PROCS. Idempotent.
kill_procs() {
    killed=0
    for proc in $CREALITY_PROCS; do
        PIDS=$(pidof "$proc" 2>/dev/null || true)
        if [ -n "$PIDS" ]; then
            kill -TERM $PIDS 2>/dev/null || true
            killed=$((killed + 1))
            info "  TERM $proc (PIDs: $PIDS)"
        fi
    done
    sleep 1
    # Retry pass for stubborn ones.
    for proc in $CREALITY_PROCS; do
        PIDS=$(pidof "$proc" 2>/dev/null || true)
        if [ -n "$PIDS" ]; then
            kill -KILL $PIDS 2>/dev/null || true
            info "  KILL $proc (still alive after TERM)"
        fi
    done
    # cmd_jpeg_display sometimes lingers — kill it too.
    PIDS=$(pidof cmd_jpeg_display 2>/dev/null || true)
    [ -n "$PIDS" ] && kill -9 $PIDS 2>/dev/null && info "  KILL cmd_jpeg_display"
    info "Done ($killed processes received TERM)."
}

# Disable S99start_app at boot by moving it out of /etc/init.d/.
disable_autostart() {
    mkdir -p "$BACKUP_DIR"
    if [ -f "$S99_TARGET" ]; then
        mv "$S99_TARGET" "$S99_BACKUP"
        info "Moved $S99_TARGET -> $S99_BACKUP (no autostart at next boot)."
    elif [ -f "$S99_BACKUP" ]; then
        info "Already disabled: $S99_BACKUP exists, $S99_TARGET absent."
    else
        warn "Neither $S99_TARGET nor $S99_BACKUP found — nothing to disable."
    fi
}

# Re-enable S99start_app at boot.
enable_autostart() {
    if [ -f "$S99_BACKUP" ]; then
        mv "$S99_BACKUP" "$S99_TARGET"
        chmod +x "$S99_TARGET"
        info "Restored $S99_TARGET. Creality services will autostart at next boot."
    elif [ -f "$S99_TARGET" ]; then
        info "Already enabled: $S99_TARGET is in place."
    else
        die "Cannot restore — neither $S99_TARGET nor $S99_BACKUP found."
    fi
}

# -- Dispatch -------------------------------------------------------------
case "$MODE" in
    list)
        info "Creality service status:"
        echo
        list_state
        ;;
    kill)
        info "Killing Creality services in this session (will resurrect on reboot)."
        kill_procs
        echo
        list_state
        ;;
    permanent)
        info "Killing Creality services AND disabling autostart..."
        kill_procs
        disable_autostart
        echo
        list_state
        ;;
    restore)
        info "Restoring Creality autostart..."
        enable_autostart
        echo
        list_state
        warn "Services will only respawn on next reboot. To start them now, run S99start_app directly."
        ;;
esac
