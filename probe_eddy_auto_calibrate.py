# Auto-calibration plugin for eddy current probes
#
# Re-runs the native PROBE_EDDY_CURRENT_CALIBRATE sequence using the
# CURRENT toolhead position as the Z=0 reference (instead of the
# interactive paper test). The new frequency/Z table is activated in
# RAM immediately (no Klipper restart required).
#
# Single responsibility: this plugin does NOT manage temperatures,
# does NOT home, does NOT move the toolhead. The caller is responsible
# for placing the toolhead at the desired Z=0 reference position before
# calling PROBE_EDDY_CALIBRATE_AUTO.
#
# Typical caller workflow (in start_gcode):
#   ; ... heat to print conditions ...
#   G28
#   G1 X200 Y200
#   SET_Z_FROM_PROBE METHOD=tap SAMPLES=5    ; find real Z=0 by impact
#   G1 Z0.05 F300                             ; descend to a small offset
#   PROBE_EDDY_CALIBRATE_AUTO                 ; rebuild table at this state
#   BED_MESH_CALIBRATE METHOD=rapid_scan      ; use the fresh table
#
# Configuration:
#   [probe_eddy_auto_calibrate]
#   chip: btt_eddy
#   probe_speed: 5.0
#   z_ref_max: 0.5
#
# Usage:
#   PROBE_EDDY_CALIBRATE_AUTO [CHIP=<name>] [PROBE_SPEED=<f>]
#                             [ACTIVATE_RAM=0|1] [Z_REF_MAX=<f>]

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

    def _lookup_eddy_calibration(self, chip):
        # Look up the [probe_eddy_current <chip>] printer object and
        # return its EddyCalibration instance.
        section_name = 'probe_eddy_current ' + chip
        try:
            eddy_obj = self.printer.lookup_object(section_name)
        except Exception:
            raise self.printer.command_error(
                "Eddy chip not found: '[%s]' section missing in config"
                % section_name)
        if not hasattr(eddy_obj, 'calibration'):
            raise self.printer.command_error(
                "Eddy object '%s' has no .calibration attribute"
                " (incompatible Klipper version?)" % section_name)
        return eddy_obj.calibration

    def cmd_PROBE_EDDY_CALIBRATE_AUTO(self, gcmd):
        chip = gcmd.get('CHIP', self.chip_name)
        probe_speed = gcmd.get_float(
            'PROBE_SPEED', self.default_probe_speed, above=0.)
        activate_ram = gcmd.get_int(
            'ACTIVATE_RAM', 1, minval=0, maxval=1)
        z_ref_max = gcmd.get_float(
            'Z_REF_MAX', self.default_z_ref_max, above=0.)

        eddy_cal = self._lookup_eddy_calibration(chip)

        # ─── Pre-flight checks ───
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

        # ─── Build fake ManualProbeResult from current position ───
        # post_manual_probe reads bed_x, bed_y, bed_z from this object.
        # With offsets=(0,0,0), create_probe_result puts test_pos
        # straight into bed_*, which is exactly what we want.
        fake_mpresult = manual_probe.create_probe_result(
            (cur_x, cur_y, cur_z))

        # ─── Set probe_speed (required by do_calibration_moves) ───
        # Native cmd_EDDY_CALIBRATE sets this attribute before invoking
        # manual_probe.ManualProbeHelper. We must do the same.
        eddy_cal.probe_speed = probe_speed

        # ─── Optional: monkey-patch _save_calibration to also load RAM ───
        # Klipper's native _save_calibration only writes the new table
        # to the pending SAVE_CONFIG block. The active in-memory table
        # (cal_freqs / cal_zpos) is NOT updated until the next restart.
        # We patch it temporarily so the new table is also active in RAM.
        original_save = None
        if activate_ram:
            original_save = eddy_cal._save_calibration

            def patched_save(z_freq_pairs):
                # Persist to config (original behavior)
                original_save(z_freq_pairs)
                # Activate in RAM immediately
                eddy_cal.load_calibration(z_freq_pairs)
                gcmd.respond_info(
                    "PROBE_EDDY_CALIBRATE_AUTO: new table active in RAM"
                    " (%d points). SAVE_CONFIG pending if you want to"
                    " persist this calibration across restarts."
                    % len(z_freq_pairs))

            eddy_cal._save_calibration = patched_save

        # ─── Run the native calibration sequence ───
        # post_manual_probe will:
        #   1. Lift toolhead by 5 mm
        #   2. Translate by (-x_offset, -y_offset) to put coil over the
        #      previous nozzle position
        #   3. Descend back to mpresult.bed_z + 0.050 mm
        #   4. Run do_calibration_moves (40 um steps up to ~4 mm)
        #   5. Validate, build z_freq_pairs, call _save_calibration
        try:
            eddy_cal.post_manual_probe(fake_mpresult)
        finally:
            # Restore the original method even if an error occurred,
            # so we don't leave the eddy_cal object in a patched state
            # for subsequent operations.
            if activate_ram and original_save is not None:
                eddy_cal._save_calibration = original_save


def load_config(config):
    return ProbeEddyAutoCalibrate(config)
