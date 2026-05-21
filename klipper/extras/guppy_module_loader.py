# guppy_module_loader.py — vendored from GuppyScreen k1_mods/ with an
# auto-restart hook on tmcstatus unload.
#
# Upstream behavior (k1_mods/guppy_module_loader.py):
#   _GUPPY_LOAD_MODULE   SECTION=<name>  →  printer.load_object(config, name)
#   _GUPPY_UNLOAD_MODULE SECTION=<name>  →  printer.objects.pop(name)
#
# The added hook: when SECTION=tmcstatus is unloaded (which happens
# when the user toggles "TMC Metrics" off in GuppyScreen's Settings),
# immediately fire `RUN_SHELL_COMMAND CMD=restart_guppyscreen`. This
# is needed because Guppy's panel does not redraw on empty-payload
# status updates, so after a plain pop() the LVGL panel keeps showing
# the last live frame indefinitely — the only way to get the screen
# back to its pre-ON layout is to restart the Guppy process itself.
# Other unload sections fall through with no side effect.
#
# The shell command is defined in klipper/config/tmc.cfg and points at
# /usr/data/e5m-ck/bin/restart_guppyscreen.sh, which detaches a 300 ms
# sleep + /etc/init.d/S99guppyscreen restart so the gcode response can
# return to Guppy before the process is killed.

import logging


class GuppyModuleLoader:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.config = config

        gcode = self.printer.lookup_object('gcode')
        gcode.register_command("_GUPPY_LOAD_MODULE", self.cmd_guppy_load_module)
        gcode.register_command("_GUPPY_UNLOAD_MODULE", self.cmd_guppy_unload_module)

    def cmd_guppy_load_module(self, gcmd):
        section = gcmd.get('SECTION', None)
        if section and section not in self.printer.objects:
            self.printer.load_object(self.config, section)

    def cmd_guppy_unload_module(self, gcmd):
        section = gcmd.get('SECTION', None)
        if not section or section not in self.printer.objects:
            return
        self.printer.objects.pop(section)
        if section == 'tmcstatus':
            gcode = self.printer.lookup_object('gcode')
            try:
                gcode.run_script_from_command(
                    'RUN_SHELL_COMMAND CMD=restart_guppyscreen')
            except Exception as e:
                logging.warning(
                    "guppy_module_loader: tmcstatus unload restart dispatch failed: %s", e)


def load_config(config):
    return GuppyModuleLoader(config)
