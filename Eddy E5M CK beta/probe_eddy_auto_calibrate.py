# Auto-calibration plugin for eddy current probes
#
# Provides three commands:
#
#   1. PROBE_EDDY_CALIBRATE_AUTO
#      Re-runs the native PROBE_EDDY_CURRENT_CALIBRATE sequence using
#      the CURRENT toolhead position as the Z=0 reference (instead of
#      the interactive paper test). The new frequency/Z table is
#      activated in RAM immediately (no Klipper restart required).
#
#   2. EDDY_APPLY_TAP_THRESHOLD
#      Activate a tap_threshold value in RAM after
#      PROBE_EDDY_CURRENT_TAP_CALIBRATE TAP=verify, since native
#      Klipper only writes the new threshold to the pending
#      SAVE_CONFIG block (no RAM update until restart).
#
#   3. EDDY_RESET_TO_CONFIG
#      Reset RAM state of the Eddy probe to the values persisted in
#      printer.cfg (calibrate table + tap_threshold). Use this at the
#      start of every print to ensure a deterministic, reproducible
#      starting state regardless of session history.
#
# Single responsibility: this plugin does NOT manage temperatures,
# does NOT home, does NOT move the toolhead.
#
# Configuration:
#   [probe_eddy_auto_calibrate]
#   chip: btt_eddy
#   probe_speed: 5.0
#   z_ref_max: 0.5
#
# Commands:
#   PROBE_EDDY_CALIBRATE_AUTO [CHIP=<name>] [PROBE_SPEED=<f>]
#                             [ACTIVATE_RAM=0|1] [Z_REF_MAX=<f>]
#   EDDY_APPLY_TAP_THRESHOLD [CHIP=<name>] [VALUE=<f>]
#   EDDY_RESET_TO_CONFIG [CHIP=<name>]

import logging
from . import manual_probe


class ProbeEddyAutoCalibrate:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.chip_name = config.get('chip', 'btt_eddy')
        self.default_probe_speed = config.getfloat(
            'probe_speed', 5.0, above=0.)
        self.default_z_ref_max = config.getfloat(
            'z_ref_max', 0.5, above=0.)
        gcode = self.printer.lookup_object('gcode')
        gcode.register_command(
            'PROBE_EDDY_CALIBRATE_AUTO',
            self.cmd_PROBE_EDDY_CALIBRATE_AUTO,
            desc=("Auto-calibrate eddy probe table from current toolhead"
                  " position. The current Z is used as the Z=0 reference."))
        gcode.register_command(
            'EDDY_APPLY_TAP_THRESHOLD',
            self.cmd_EDDY_APPLY_TAP_THRESHOLD,
            desc=("Apply a tap_threshold value to the runtime EddyTap"
                  " object (workaround for native code only updating"
                  " pending SAVE_CONFIG, not RAM)."))
        gcode.register_command(
            'EDDY_RESET_TO_CONFIG',
            self.cmd_EDDY_RESET_TO_CONFIG,
            desc=("Reset RAM state of the Eddy probe to the values"
                  " persisted in printer.cfg. Use at the start of"
                  " every print to ensure deterministic state."))

    def _lookup_eddy_obj(self, chip):
        section_name = 'probe_eddy_current ' + chip
        try:
            return self.printer.lookup_object(section_name)
        except Exception:
            raise self.printer.command_error(
                "Eddy chip not found: '[%s]' section missing in config"
                % section_name)

    def _lookup_eddy_calibration(self, chip):
        eddy_obj = self._lookup_eddy_obj(chip)
        if not hasattr(eddy_obj, 'calibration'):
            raise self.printer.command_error(
                "Eddy object '%s' has no .calibration attribute"
                " (incompatible Klipper version?)" % chip)
        return eddy_obj.calibration

    def _lookup_eddy_tap(self, chip):
        eddy_obj = self._lookup_eddy_obj(chip)
        if not hasattr(eddy_obj, 'eddy_tap'):
            raise self.printer.command_error(
                "Eddy object '%s' has no .eddy_tap attribute"
                " (incompatible Klipper version?)" % chip)
        return eddy_obj.eddy_tap

    def _get_section_settings(self, section_name):
        # Read settings as parsed by Klipper at boot (includes autosave block)
        configfile = self.printer.lookup_object('configfile')
        reactor = self.printer.get_reactor()
        eventtime = reactor.monotonic()
        cf_status = configfile.get_status(eventtime)
        return cf_status.get('settings', {}).get(section_name, {})

    def _get_pending_settings(self, section_name):
        # Read pending SAVE_CONFIG values (changes made in current session)
        configfile = self.printer.lookup_object('configfile')
        reactor = self.printer.get_reactor()
        eventtime = reactor.monotonic()
        cf_status = configfile.get_status(eventtime)
        pending = cf_status.get('save_config_pending_items', {})
        return pending.get(section_name, {}) or {}

    # ─────────────────────────────────────────────────────────
    # PROBE_EDDY_CALIBRATE_AUTO
    # ─────────────────────────────────────────────────────────

    def cmd_PROBE_EDDY_CALIBRATE_AUTO(self, gcmd):
        chip = gcmd.get('CHIP', self.chip_name)
        probe_speed = gcmd.get_float(
            'PROBE_SPEED', self.default_probe_speed, above=0.)
        activate_ram = gcmd.get_int(
            'ACTIVATE_RAM', 1, minval=0, maxval=1)
        z_ref_max = gcmd.get_float(
            'Z_REF_MAX', self.default_z_ref_max, above=0.)

        eddy_cal = self._lookup_eddy_calibration(chip)

        toolhead = self.printer.lookup_object('toolhead')
        reactor = self.printer.get_reactor()
        eventtime = reactor.monotonic()
        homed = toolhead.get_status(eventtime).get('homed_axes', '')
        if 'x' not in homed or 'y' not in homed or 'z' not in homed:
            raise gcmd.error(
                "Printer must be fully homed (XYZ) before"
                " auto-calibration. Currently homed: '%s'" % homed)

        cur_pos = toolhead.get_position()
        cur_x, cur_y, cur_z = cur_pos[0], cur_pos[1], cur_pos[2]

        if cur_z < 0. or cur_z > z_ref_max:
            raise gcmd.error(
                "Current Z=%.4f is outside valid reference range"
                " [0, %.3f]. Position the nozzle near the bed (typically"
                " 0.05 mm) before calling this command. To override,"
                " pass Z_REF_MAX=<larger_value>." % (cur_z, z_ref_max))

        gcmd.respond_info(
            "PROBE_EDDY_CALIBRATE_AUTO: chip=%s probe_speed=%.1f"
            " ref_pos=(X=%.3f Y=%.3f Z=%.4f) activate_ram=%d"
            % (chip, probe_speed, cur_x, cur_y, cur_z, activate_ram))

        fake_mpresult = manual_probe.create_probe_result(
            (cur_x, cur_y, cur_z))

        eddy_cal.probe_speed = probe_speed

        original_save = None
        if activate_ram:
            original_save = eddy_cal._save_calibration

            def patched_save(z_freq_pairs):
                original_save(z_freq_pairs)
                eddy_cal.load_calibration(z_freq_pairs)
                gcmd.respond_info(
                    "PROBE_EDDY_CALIBRATE_AUTO: new table active in RAM"
                    " (%d points). SAVE_CONFIG pending if you want to"
                    " persist this calibration across restarts."
                    % len(z_freq_pairs))

            eddy_cal._save_calibration = patched_save

        try:
            eddy_cal.post_manual_probe(fake_mpresult)
        finally:
            if activate_ram and original_save is not None:
                eddy_cal._save_calibration = original_save

    # ─────────────────────────────────────────────────────────
    # EDDY_APPLY_TAP_THRESHOLD
    # ─────────────────────────────────────────────────────────

    def cmd_EDDY_APPLY_TAP_THRESHOLD(self, gcmd):
        chip = gcmd.get('CHIP', self.chip_name)
        explicit_value = gcmd.get_float('VALUE', None, above=0.)

        eddy_tap = self._lookup_eddy_tap(chip)

        if explicit_value is None:
            section_name = 'probe_eddy_current ' + chip
            section_pending = self._get_pending_settings(section_name)
            new_value = section_pending.get('tap_threshold', None)
            if new_value is None:
                raise gcmd.error(
                    "No pending tap_threshold for '%s'. Run"
                    " PROBE_EDDY_CURRENT_TAP_CALIBRATE TAP=verify"
                    " first, or pass VALUE=<f> explicitly."
                    % section_name)
            try:
                new_value = float(new_value)
            except Exception:
                raise gcmd.error(
                    "Invalid pending tap_threshold value: %r"
                    % (new_value,))
        else:
            new_value = explicit_value

        if new_value <= 0.:
            raise gcmd.error(
                "tap_threshold must be > 0 (got %.3f)" % new_value)

        old_value = getattr(eddy_tap, '_tap_threshold', None)
        eddy_tap._tap_threshold = new_value
        gcmd.respond_info(
            "EDDY_APPLY_TAP_THRESHOLD: chip=%s tap_threshold %s -> %.3f"
            " (active in RAM, persisted only on SAVE_CONFIG)"
            % (chip,
               ("%.3f" % old_value) if old_value is not None else "<unset>",
               new_value))

    # ─────────────────────────────────────────────────────────
    # EDDY_RESET_TO_CONFIG
    # ─────────────────────────────────────────────────────────
    #
    # Resets RAM state to the values that were parsed at Klipper boot
    # from printer.cfg (including the autosave block at the bottom).
    # This is equivalent to a FIRMWARE_RESTART for the Eddy probe state,
    # without the actual restart (which would break the print).
    #
    # Resets:
    #   - eddy_cal.cal_freqs / cal_zpos    (the frequency/Z table)
    #   - eddy_tap._tap_threshold          (the tap detection threshold)
    #
    # Does NOT reset:
    #   - tap_z_offset                     (immutable from config)
    #   - calibration_temp                 (read-only, drift compensation)
    #   - reg_drive_current                (set on hardware at boot)

    def cmd_EDDY_RESET_TO_CONFIG(self, gcmd):
        chip = gcmd.get('CHIP', self.chip_name)
        section_name = 'probe_eddy_current ' + chip

        eddy_cal = self._lookup_eddy_calibration(chip)
        eddy_tap = self._lookup_eddy_tap(chip)

        settings = self._get_section_settings(section_name)
        if not settings:
            raise gcmd.error(
                "No settings found for section '%s'" % section_name)

        # ─── Restore frequency/Z table ────────────────────────
        cal_str = settings.get('calibrate', None)
        if cal_str is None:
            gcmd.respond_info(
                "EDDY_RESET_TO_CONFIG: no 'calibrate' field in config"
                " — skipping table reset")
            cal_count = 0
        else:
            try:
                # Klipper stores 'calibrate' as a multiline string with format:
                #   z1:freq1, z2:freq2, ...
                # (whitespace and newlines included)
                cal_pairs = []
                for entry in cal_str.split(','):
                    entry = entry.strip()
                    if not entry:
                        continue
                    z_str, freq_str = entry.split(':', 1)
                    cal_pairs.append([float(z_str), float(freq_str)])
                if len(cal_pairs) < 2:
                    raise ValueError("less than 2 calibration points")
                eddy_cal.load_calibration(cal_pairs)
                cal_count = len(cal_pairs)
            except Exception as e:
                raise gcmd.error(
                    "EDDY_RESET_TO_CONFIG: failed to parse 'calibrate'"
                    " field: %s" % e)

        # ─── Restore tap_threshold ────────────────────────────
        threshold_value = settings.get('tap_threshold', None)
        old_threshold = getattr(eddy_tap, '_tap_threshold', None)
        if threshold_value is None:
            new_threshold_msg = "no value in config (left as %s)" % (
                ("%.3f" % old_threshold) if old_threshold is not None
                else "<unset>")
        else:
            try:
                threshold_value = float(threshold_value)
                if threshold_value <= 0.:
                    raise ValueError("tap_threshold must be > 0")
                eddy_tap._tap_threshold = threshold_value
                new_threshold_msg = "%s -> %.3f" % (
                    ("%.3f" % old_threshold) if old_threshold is not None
                    else "<unset>",
                    threshold_value)
            except Exception as e:
                raise gcmd.error(
                    "EDDY_RESET_TO_CONFIG: failed to parse"
                    " 'tap_threshold' field: %s" % e)

        gcmd.respond_info(
            "EDDY_RESET_TO_CONFIG: chip=%s table=%d points, tap_threshold %s"
            % (chip, cal_count, new_threshold_msg))


def load_config(config):
    return ProbeEddyAutoCalibrate(config)
