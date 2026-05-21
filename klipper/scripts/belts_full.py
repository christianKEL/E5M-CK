#!/usr/share/klippy-env/bin/python3
"""All-in-one belts-comparison plot generator: small + full in one process.

Companion to shaper_full.py. Same rationale: the 256 MB Nebula Pad
goes OOM if matplotlib is imported twice in quick succession. graph_belts.py
+ raw 21 MB belt CSVs are the heaviest combo in this stack, so calling
the script twice (once per PNG size) is the worst case.

Imports the vendored graph_belts.py as a module and calls its
belts_calibration() function twice. Single matplotlib import.

graph_belts.py is the Frix-x / Klippain-shaketune ancestry script
shipped under klipper/scripts/. It does its own PSD computation + plot
+ similarity score in one call. We just orchestrate the figure-size
overrides.

Usage:
    belts_full.py <csv_A> <csv_B> --small <png> [-w 4.8] [-l 2.72]
                                  [--full <png>] [--max-freq 200.0]
                                  [--klipperdir /usr/data/e5m-ck/klipper]
"""

import optparse
import os
import sys

KLIPPER_DIR = '/usr/data/e5m-ck/klipper'
# graph_belts does `import shaper_calibrate` at module top (no relative
# import), so klippy/extras must be on sys.path before we import it.
# klippy/ also needed for the 'extras' package itself.
sys.path.insert(0, os.path.join(KLIPPER_DIR, 'klippy', 'extras'))
sys.path.insert(0, os.path.join(KLIPPER_DIR, 'klippy'))
sys.path.insert(0, os.path.join(KLIPPER_DIR, 'scripts'))

import matplotlib  # noqa: E402
matplotlib.use('Agg')
import matplotlib.pyplot as plt  # noqa: E402

import graph_belts as gb  # noqa: E402


def parse_args():
    p = optparse.OptionParser(usage="%prog <csv_A> <csv_B> [options]")
    p.add_option("--small", dest="small",
                 help="small PNG path (typically GuppyScreen-requested one)")
    p.add_option("-w", "--width", type="float", default=4.8, dest="width",
                 help="small PNG width in inches")
    p.add_option("-l", "--height", type="float", default=2.72, dest="height",
                 help="small PNG height in inches")
    p.add_option("--full", dest="full", default="",
                 help="optional second PNG for desktop preview (8x4.8 in)")
    p.add_option("--max-freq", type="float", default=200., dest="max_freq")
    p.add_option("--klipperdir", dest="klipperdir", default=KLIPPER_DIR,
                 help="klipper checkout root (graph_belts uses this for "
                      "shaper_calibrate import resolution; we already put it "
                      "on sys.path, so this is mostly cosmetic)")
    options, args = p.parse_args()
    if len(args) != 2:
        p.error("need exactly two CSV files (A belt and B belt)")
    if not options.small:
        p.error("missing --small <png>")
    return options, args


def make_one_png(csvs, klipperdir, max_freq, width, height, out_path):
    """Call graph_belts.belts_calibration with our figsize, save, close."""
    # graph_spectogram=False (the `-n` flag in the shell wrapper): the
    # difference spectrogram panel needs scipy, which isn't in klippy-env.
    fig = gb.belts_calibration(
        csvs, klipperdir=klipperdir, max_freq=max_freq,
        graph_spectogram=False, width=width, height=height)
    fig.savefig(out_path)
    plt.close(fig)


def main():
    options, csvs = parse_args()
    # Small PNG (GuppyScreen on-screen display).
    make_one_png(csvs, options.klipperdir, options.max_freq,
                 options.width, options.height, options.small)
    # Optional full-size PNG (Fluidd desktop preview).
    if options.full:
        make_one_png(csvs, options.klipperdir, options.max_freq,
                     8.0, 4.8, options.full)


if __name__ == '__main__':
    main()
