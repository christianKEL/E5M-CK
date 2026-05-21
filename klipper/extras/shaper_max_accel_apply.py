# shaper_max_accel_apply.py — auto-update [printer] max_accel after MEASURE_AXIS X+Y
#
# Klipper's SHAPER_CALIBRATE writes the recommended shaper type / freq to the
# autosave block, but it does NOT touch max_accel — only prints a "suggested
# max_accel <= N" line to the console. The reason is that max_accel is a
# global limit and the operator is supposed to decide whether to apply it.
#
# This module automates that step. After MEASURE_AXIS AXIS=Y has run (which
# implies AXIS=X was also run, since the canonical workflow does both), the
# MEASURE_AXIS macro calls APPLY_SHAPER_MAX_ACCEL. That command:
#
#   1. Picks the newest /tmp/calibration_data_x_*.csv and _y_*.csv
#   2. Re-runs the same shaper-fit analysis as SHAPER_CALIBRATE (via Klipper's
#      own extras/shaper_calibrate.py library — same code path, same numbers)
#   3. Reads each axis's recommended max_accel for the best-fit shaper
#   4. Takes min(x, y) — the global limit must satisfy both axes
#   5. Applies it at runtime via SET_VELOCITY_LIMIT (effective immediately)
#   6. Rewrites the `max_accel:` line in [printer] of the LIVE
#      /usr/data/printer_data/config/printer.cfg (atomic write via temp + rename;
#      autosave block at the bottom is untouched).
#
# The repo-side klipper/config/printer.cfg is NOT modified — sync.sh is
# unidirectional (repo -> printer). The operator should manually copy the
# new value back to the repo after a successful calibration (a console
# reminder is printed). See docs/operations/input_shaper.md.
#
# Why not write to a separate include? [printer] is a Klipper "unique" section
# and can only live in one file. Splitting it out would mean moving the entire
# block (kinematics, max_velocity, max_z_*, square_corner_velocity, ...) to
# a new file, for the sake of one auto-updated line. Not worth the churn.
#
# Why not save_variables + boot-time SET_VELOCITY_LIMIT? Because printer.cfg
# would then display a stale max_accel value, misleading anyone who reads
# the file. The user picked in-place rewrite over runtime-only persistence.

import glob
import os
import re
import tempfile

import numpy as np

from . import shaper_calibrate

LIVE_CFG = '/usr/data/printer_data/config/printer.cfg'
# Both naming patterns are supported. Fluidd's MEASURE_AXIS uses
# SHAPER_CALIBRATE which writes calibration_data_<axis>_<ts>.csv (PSD).
# GuppyScreen's Input Shaper button uses TEST_RESONANCES which writes
# resonances_<axis>_<axis>.csv (raw accelerometer data). The newest of
# all matches wins.
CSV_X = ['/tmp/calibration_data_x_*.csv', '/tmp/resonances_x_*.csv']
CSV_Y = ['/tmp/calibration_data_y_*.csv', '/tmp/resonances_y_*.csv']


class ShaperMaxAccelApply:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.gcode = self.printer.lookup_object('gcode')
        self.gcode.register_command(
            'APPLY_SHAPER_MAX_ACCEL', self.cmd_APPLY_SHAPER_MAX_ACCEL,
            desc='Compute max_accel from latest MEASURE_AXIS X+Y CSVs and '
                 'apply (SET_VELOCITY_LIMIT + rewrite live printer.cfg).'
        )

    def _newest(self, patterns):
        # patterns can be a str (one glob) or a list of globs (returns
        # the absolute newest match across all of them).
        if isinstance(patterns, str):
            patterns = [patterns]
        candidates = []
        for p in patterns:
            candidates.extend(glob.glob(p))
        if not candidates:
            return None
        return max(candidates, key=os.path.getmtime)

    def _scv(self):
        # find_best_shaper's smoothing calc needs square_corner_velocity; with
        # scv=None, _get_shaper_smoothing propagates a NoneType into a `+`.
        # We read the toolhead's attribute directly rather than going through
        # get_status(systime) — the latter touches clocksync.get_clock which
        # crashes if the MCU hasn't reported a sample yet (i.e. when this
        # command runs cold right after a FIRMWARE_RESTART).
        return self.printer.lookup_object('toolhead').square_corner_velocity

    def _best_for_csv(self, path):
        # Mirror calibrate_shaper.py's parse_log() — handles both raw
        # accelerometer dumps and the PSD-format CSVs that SHAPER_CALIBRATE
        # writes (header starts with "freq,psd_x,psd_y,psd_z,psd_xyz,shapers:...").
        with open(path) as f:
            for header in f:
                if not header.startswith('#'):
                    break
        # ShaperCalibrate(printer=None) matches what scripts/calibrate_shaper.py
        # uses, so find_best_shaper runs through the exact same code path
        # (synchronous, no multiprocessing fork). With printer=self.printer,
        # background_process_exec forks a child — same math in theory, but
        # we observed a ~1-2 Hz drift in the best-fit MZV frequency vs the
        # script. printer=None gives byte-identical results to the script.
        helper = shaper_calibrate.ShaperCalibrate(printer=None)
        if not header.startswith('freq,'):
            # Raw accelerometer CSV (TEST_RESONANCES OUTPUT=raw_data)
            data = np.loadtxt(path, comments='#', delimiter=',')
            cal = helper.process_accelerometer_data(path, data)
            cal.normalize_to_frequencies()
        else:
            # Pre-computed PSD CSV (SHAPER_CALIBRATE default output)
            data = np.genfromtxt(path, dtype=np.float64, skip_header=1,
                                 comments='#', delimiter=',',
                                 filling_values=0.)
            if not header.startswith('freq,psd_x,psd_y,psd_z,psd_xyz'):
                raise RuntimeError(
                    'Unexpected PSD header in %s: %r' % (path, header[:80]))
            cal = shaper_calibrate.CalibrationData(
                name=path,
                freq_bins=data[:, 0],
                psd_sum=data[:, 4],
                psd_x=data[:, 1],
                psd_y=data[:, 2],
                psd_z=data[:, 3])
            cal.set_numpy(np)
            # Match scripts/calibrate_shaper.py parse_log exactly: if the
            # CSV doesn't include pre-fitted shaper columns (',shapers:'),
            # the PSD is raw and needs normalization. SHAPER_CALIBRATE's
            # CSVs include the shapers column and are pre-normalized;
            # TEST_RESONANCES's (what GuppyScreen and our MEASURE_AXIS now
            # produce) do not, so we must normalize here. Missing this
            # step gives ~1-2 Hz drift in the fitted MZV frequency.
            if ',shapers:' not in header:
                cal.normalize_to_frequencies()
        # shapers=['mzv'] forces the recommendation to MZV always for
        # the SAVE_CONFIG / max_accel path. The PNG-generation path
        # (gen_shaper_for_guppy.sh) deliberately does NOT restrict the
        # shaper list — its plots show all 5 candidates so the user can
        # visually compare them. The restriction here only affects what
        # we stage into the [input_shaper] autosave block and what we
        # use to compute max_accel.
        best, _all = helper.find_best_shaper(
            cal, shapers=['mzv'], scv=self._scv())
        return best

    def _rewrite_max_accel(self, new_val):
        with open(LIVE_CFG, 'r') as f:
            txt = f.read()
        # Match the [printer] section: from "\n[printer]\n" up to the next
        # "\n[" (next section header) or EOF. The autosave block at the
        # bottom uses "#*# [section]" comment-prefixed lines and does not
        # contain a [printer] header, so this match is unambiguous.
        m = re.search(r'\n\[printer\]\n(.*?)(?=\n\[|\Z)', txt, re.DOTALL)
        if not m:
            raise RuntimeError('No [printer] section found in ' + LIVE_CFG)
        section_start = m.start(1)
        section_end = m.end(1)
        section_body = m.group(1)
        # Replace the max_accel value AND any trailing # comment on the
        # same line, then append our own marker comment. The marker
        # signals to humans (and to future-us) that this number is
        # auto-managed by APPLY_SHAPER_MAX_ACCEL and will be overwritten
        # by the next calibration.
        marker = '  # set automatically by APPLY_SHAPER_MAX_ACCEL'
        new_body, n = re.subn(
            r'(^|\n)(max_accel\s*:\s*)\d+[^\n]*',
            lambda mo: '%s%s%d%s' % (mo.group(1), mo.group(2),
                                     new_val, marker),
            section_body, count=1
        )
        if n != 1:
            raise RuntimeError(
                'max_accel: line not found inside [printer] section')
        new_txt = txt[:section_start] + new_body + txt[section_end:]
        # Atomic write: same directory so rename(2) is atomic on the same fs.
        d = os.path.dirname(LIVE_CFG)
        fd, tmp = tempfile.mkstemp(
            dir=d, prefix='.printer.cfg.', suffix='.tmp')
        try:
            with os.fdopen(fd, 'w') as f:
                f.write(new_txt)
            os.rename(tmp, LIVE_CFG)
        except Exception:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise

    def cmd_APPLY_SHAPER_MAX_ACCEL(self, gcmd):
        x_csv = self._newest(CSV_X)
        y_csv = self._newest(CSV_Y)
        if not x_csv:
            raise gcmd.error(
                'No X calibration CSV in /tmp/ — run MEASURE_AXIS AXIS=X first')
        if not y_csv:
            raise gcmd.error(
                'No Y calibration CSV in /tmp/ — run MEASURE_AXIS AXIS=Y first')
        x_best = self._best_for_csv(x_csv)
        y_best = self._best_for_csv(y_csv)
        x_ma = int(round(x_best.max_accel / 100.) * 100)
        y_ma = int(round(y_best.max_accel / 100.) * 100)
        new_ma = min(x_ma, y_ma)
        gcmd.respond_info(
            'Shaper limits: X %s@%.1fHz max_accel<=%d, '
            'Y %s@%.1fHz max_accel<=%d -> applying %d' % (
                x_best.name, x_best.freq, x_ma,
                y_best.name, y_best.freq, y_ma,
                new_ma))
        self.gcode.run_script_from_command(
            'SET_VELOCITY_LIMIT ACCEL=%d' % new_ma)

        # Write [input_shaper] autosave entries via configfile.set.
        # Mirrors what Klipper's SHAPER_CALIBRATE does internally, so the
        # next SAVE_CONFIG persists the calibrated shaper. Both axes are
        # always MZV (we forced shapers=['mzv'] in _best_for_csv).
        configfile = self.printer.lookup_object('configfile')
        configfile.set('input_shaper', 'shaper_type_x', x_best.name)
        configfile.set('input_shaper', 'shaper_freq_x', '%.1f' % x_best.freq)
        configfile.set('input_shaper', 'shaper_type_y', y_best.name)
        configfile.set('input_shaper', 'shaper_freq_y', '%.1f' % y_best.freq)
        gcmd.respond_info(
            'Staged [input_shaper] autosave: '
            'shaper_type_x=%s shaper_freq_x=%.1f, '
            'shaper_type_y=%s shaper_freq_y=%.1f. Run SAVE_CONFIG to persist.' % (
                x_best.name, x_best.freq, y_best.name, y_best.freq))

        try:
            self._rewrite_max_accel(new_ma)
            gcmd.respond_info(
                'Wrote max_accel=%d into [printer] of %s' % (new_ma, LIVE_CFG))
            gcmd.respond_info(
                'Reminder: copy this value into klipper/config/printer.cfg '
                '[printer] max_accel and commit, so a fresh sync reproduces '
                'the calibrated state.')
        except Exception as e:
            gcmd.respond_info(
                'WARN: SET_VELOCITY_LIMIT applied but could not rewrite '
                'printer.cfg: %s' % str(e))

        # Best-effort cleanup of the transient GuppyScreen PNGs at
        # config/resonances_<axis>.png. By the time APPLY runs the user
        # has already seen them on the Nebula Pad — LVGL holds the
        # decoded image in its in-memory cache, so deleting the on-disk
        # file does not yank the current display. The permanent record
        # lives in config/printer_calibration_graphs/resonance_<axis>_full.png.
        for axis in ('x', 'y'):
            png = ('/usr/data/printer_data/config/'
                   'resonances_%s.png' % axis)
            try:
                os.remove(png)
                gcmd.respond_info('Removed transient %s' % png)
            except OSError:
                pass  # not present (or symlink already cleaned up) — fine


def load_config(config):
    return ShaperMaxAccelApply(config)
