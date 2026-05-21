#!/bin/sh
# restart_guppyscreen.sh — schedule a detached restart of GuppyScreen.
#
# Installed at: /usr/data/e5m-ck/bin/restart_guppyscreen.sh
# Invoked by:
#   - [gcode_shell_command restart_guppyscreen] in klipper/config/tmc.cfg
#     - manually via the RESTART_GUPPYSCREEN macro (Fluidd console, etc.)
#     - automatically when guppy_module_loader receives
#       _GUPPY_UNLOAD_MODULE SECTION=tmcstatus from GuppyScreen
#
# Why detach with a delay:
# The restart kills the GuppyScreen process that is currently waiting
# for the gcode response to _GUPPY_UNLOAD_MODULE. If we restart
# synchronously, Guppy never receives the "ok" and logs a phantom
# "command timed out". The 300 ms delay gives Klipper enough time to
# flush the response back through Moonraker to Guppy before Guppy is
# terminated. The detached subshell also ensures the gcode_shell_command
# wrapper returns immediately, instead of holding the gcode pipeline
# for the full ~3 s restart.

( sleep 0.3 ; /etc/init.d/S99guppyscreen restart ) </dev/null >/dev/null 2>&1 &
echo "GuppyScreen restart scheduled (300 ms delay)."
