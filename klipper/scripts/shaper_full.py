#!/usr/share/klippy-env/bin/python3
"""All-in-one shaper analysis: fit + plot small + plot full + JSON.

Replaces the previous three-script chain (_shaper_with_figsize.py
called twice + shaper_json_emitter.py) with a single Python process.
Rationale: the Creality Nebula Pad has only ~200 MB RAM and matplotlib
adds ~50 MB per import. Three matplotlib processes back-to-back per
axis hit OOM and got SIGKILL'd, which surfaced as "Command timed out"
on the Klipper side and a blank/stale image on the GuppyScreen panel.

Single-process design keeps matplotlib loaded once, generates both
PNG sizes from the same fit by calling Klipper master's own
plot_freq_response (zero divergence with mainline rendering), emits
the JSON line GuppyScreen parses, then exits.

Compatible with the path/format conventions GuppyScreen's binary
expects (verified by reading inputshaper_panel.cpp):
  - logfile path in JSON must match /tmp/resonances_<axis>_<axis>.csv
    byte-for-byte (it's the discriminator GuppyScreen uses to route
    the response to the X or Y panel).
  - png field in JSON is a non-null sentinel; the actual path used
    for display is rebuilt by GuppyScreen from <config_root>/<XPNG>
    where XPNG is "resonances_x.png" / "resonances_y.png". So our
    -o argument MUST land at that path or the panel stays blank.
  - best field must be one of {zv, mzv, ei, 2hump_ei, 3hump_ei};
    GuppyScreen uses shapers[best]["freq"] to pre-populate the
    Save-button sliders. We hardcode "mzv" (project policy).

Usage:
  shaper_full.py <csv> -o <small_png> [-w 4.8] [-l 2.72]
                       [--full <large_png_path>]
                       [--scv 5.0] [--max-freq 200.0]
"""

import json
import optparse
import os
import sys

KLIPPER_DIR = '/usr/data/e5m-ck/klipper'
sys.path.insert(0, os.path.join(KLIPPER_DIR, 'klippy'))
sys.path.insert(0, os.path.join(KLIPPER_DIR, 'scripts'))

import numpy as np  # noqa: E402
import matplotlib  # noqa: E402
matplotlib.use('Agg')
import matplotlib.pyplot as plt  # noqa: E402

# Import Klipper master's own calibrate_shaper.py — we re-use its
# parse_log() and plot_freq_response() so the rendered PNG is
# byte-identical to what the upstream script would produce.
import calibrate_shaper as cs  # noqa: E402
from extras import shaper_calibrate  # noqa: E402


def parse_args():
    p = optparse.OptionParser(usage="%prog [options] <csv>")
    p.add_option("-o", "--output", dest="output",
                 help="small PNG path (GuppyScreen-requested one)")
    p.add_option("-w", "--width", type="float", default=4.8, dest="width",
                 help="small PNG width (inches); matches screen / 100")
    p.add_option("-l", "--height", type="float", default=2.72, dest="height",
                 help="small PNG height (inches)")
    p.add_option("--full", dest="full", default="",
                 help="optional second PNG for desktop preview (8x4.8 in)")
    p.add_option("--scv", type="float", default=5.0, dest="scv")
    p.add_option("--max-freq", type="float", default=200., dest="max_freq")
    options, args = p.parse_args()
    if not args:
        p.error("missing CSV file argument")
    if not options.output:
        p.error("missing -o <png>")
    return options, args[0]


def save_plot_at_size(cal, shapers, selected, max_freq,
                      figsize, png_path):
    """Call mainline plot_freq_response and force the figure size after."""
    fig = cs.plot_freq_response(cal, shapers, selected, max_freq)
    # plot_freq_response hardcodes figsize=(8, 5) in its own subplots call,
    # so we override after creation. tight_layout reduces empty margins
    # which matters at the 4.8x2.72 in size.
    fig.set_size_inches(figsize[0], figsize[1])
    try:
        fig.tight_layout()
    except Exception:
        pass  # tight_layout can fail on very small figures
    fig.savefig(png_path)
    plt.close(fig)


def main():
    options, csv_path = parse_args()

    # Mirror calibrate_shaper.py main flow.
    cal = cs.parse_log(csv_path)
    helper = shaper_calibrate.ShaperCalibrate(printer=None)
    _, all_shapers = helper.find_best_shaper(
        cal, scv=options.scv, max_freq=options.max_freq)

    # Highlight MZV in the plot regardless of find_best_shaper's pick —
    # MZV is the project's policy shaper.
    selected = "mzv"
    # Sanity: if MZV isn't in the candidate set for some reason, fall
    # back to whatever find_best_shaper actually picked (defensive).
    if not any(s.name == selected for s in all_shapers):
        selected = all_shapers[0].name

    # Small PNG (GuppyScreen / -o path).
    save_plot_at_size(cal, all_shapers, selected, options.max_freq,
                      (options.width, options.height), options.output)

    # Optional full-size PNG (Fluidd preview).
    if options.full:
        save_plot_at_size(cal, all_shapers, selected, options.max_freq,
                          (8.0, 4.8), options.full)

    # JSON for GuppyScreen.
    shapers_dict = {
        s.name: {
            "freq": s.freq,
            "vib": s.vibrs,
            "smooth": s.smoothing,
            "max_acel": round(s.max_accel / 100.) * 100.,
        }
        for s in all_shapers
    }
    print(json.dumps({
        "shapers": shapers_dict,
        "best": "mzv",       # project policy — always MZV
        "logfile": csv_path,  # MUST match the GuppyScreen X/Y discriminator
        "png": options.output,
    }))


if __name__ == '__main__':
    main()
