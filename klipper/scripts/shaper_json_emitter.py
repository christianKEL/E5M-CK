#!/usr/share/klippy-env/bin/python3
"""Emit a JSON summary of an input-shaper sweep for GuppyScreen to consume.

GuppyScreen's UI parses a line of the form
    // {"shapers": {...}, "best": "mzv", "png": "...", ...}
from the stdout of `RUN_SHELL_COMMAND CMD=guppy_input_shaper` and uses
the "png" field to locate the rendered chart for on-screen display.

Klipper master's scripts/calibrate_shaper.py prints human-readable text
only — no JSON. Rather than fork mainline, we fill that gap here by
re-using Klipper's own shaper_calibrate library so the numerics match
mainline exactly.

Project policy: the "best" field is hardcoded to "mzv", regardless of
what find_best_shaper picks. The PNG itself still shows all 5 candidate
shapers for visual comparison; only the persisted/recommended-for-save
value is forced to MZV.

Usage:
    shaper_json_emitter.py <csv> --png <png_path> [--scv 5.0]
"""

import json
import optparse
import sys

sys.path.insert(0, '/usr/data/e5m-ck/klipper/klippy')
import numpy as np  # noqa: E402
from extras import shaper_calibrate  # noqa: E402


def parse_args():
    p = optparse.OptionParser(
        usage="%prog [options] <csv>",
        description="Emit JSON describing the shaper sweep in <csv>.")
    p.add_option("--png", dest="png", default="",
                 help="PNG path to embed in the JSON 'png' field")
    p.add_option("--scv", type="float", default=5.0, dest="scv",
                 help="square_corner_velocity used in the smoothing calc")
    options, args = p.parse_args()
    if not args:
        p.error("missing CSV file argument")
    return options, args[0]


def load_calibration(csv_path):
    """Mirror calibrate_shaper.py's parse_log() for both CSV formats."""
    with open(csv_path) as f:
        for header in f:
            if not header.startswith('#'):
                break
    helper = shaper_calibrate.ShaperCalibrate(printer=None)
    if not header.startswith('freq,'):
        # Raw accelerometer dump (TEST_RESONANCES OUTPUT=raw_data).
        data = np.loadtxt(csv_path, comments='#', delimiter=',')
        cal = helper.process_accelerometer_data(csv_path, data)
        cal.normalize_to_frequencies()
        return helper, cal
    # Pre-computed PSD format (default TEST_RESONANCES output).
    data = np.genfromtxt(csv_path, dtype=np.float64, skip_header=1,
                         comments='#', delimiter=',', filling_values=0.)
    cal = shaper_calibrate.CalibrationData(
        name=csv_path,
        freq_bins=data[:, 0],
        psd_sum=data[:, 4],
        psd_x=data[:, 1],
        psd_y=data[:, 2],
        psd_z=data[:, 3])
    cal.set_numpy(np)
    # Pre-fitted CSVs already have shaper columns and are pre-normalized;
    # raw PSD CSVs (like GuppyScreen's TEST_RESONANCES output) don't.
    if ',shapers:' not in header:
        cal.normalize_to_frequencies()
    return helper, cal


def main():
    options, csv_path = parse_args()
    helper, cal = load_calibration(csv_path)
    _, all_shapers = helper.find_best_shaper(cal, scv=options.scv)
    shapers = {
        s.name: {
            "freq": s.freq,
            "vib": s.vibrs,
            "smooth": s.smoothing,
            # GuppyScreen expects "max_acel" (sic — matches the vendored
            # script's field name); rounded to 100 mm/s² like Klipper does.
            "max_acel": round(s.max_accel / 100.) * 100.,
        }
        for s in all_shapers
    }
    payload = {
        "shapers": shapers,
        "best": "mzv",
        "logfile": csv_path,
        "png": options.png,
    }
    # Single-line JSON so the gcode_shell_command response carries it
    # in one `// {...}` comment that GuppyScreen can parse easily.
    print(json.dumps(payload))


if __name__ == '__main__':
    main()
