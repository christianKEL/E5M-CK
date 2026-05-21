#!/usr/share/klippy-env/bin/python3
"""All-in-one belts-comparison plot generator: small + full from one fit.

Companion to shaper_full.py. Optimized to avoid the double-CSV-load
penalty: belt CSVs are 21 MB of raw accelerometer data each, and a
full belts_calibration() pass spends most of its time inside
parse_log() + compute_signal_data() (FFT). Calling that twice (once
per PNG size) takes >240 s on the 256 MB MIPS Nebula Pad — long
enough to blow through the gcode_shell_command timeout.

Optimization: call graph_belts.belts_calibration() ONCE to get a
matplotlib Figure. Save it. Then mutate fig.set_size_inches + redo
tight_layout and savefig the same Figure again at the second size.
matplotlib re-lays out on each savefig from the new size — fonts and
axis positions reflow correctly. Cuts total runtime roughly in half.

graph_belts.py is the Frix-x / Klippain-shaketune ancestry script
shipped under klipper/scripts/. It does its own PSD + plot +
similarity score; we just orchestrate sizing and output paths.

Usage:
    belts_full.py <csv_A> <csv_B> --small <png> [-w 4.8] [-l 2.72]
                                  [--full <png>] [--max-freq 200.0]
                                  [--klipperdir /usr/data/e5m-ck/klipper]
"""

import optparse
import os
import sys

KLIPPER_DIR = '/usr/data/e5m-ck/klipper'
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
    p.add_option("-w", "--width", type="float", default=4.8, dest="width")
    p.add_option("-l", "--height", type="float", default=2.72, dest="height")
    p.add_option("--full", dest="full", default="",
                 help="optional second PNG (8x4.8 in by default)")
    p.add_option("--max-freq", type="float", default=200., dest="max_freq")
    p.add_option("--klipperdir", dest="klipperdir", default=KLIPPER_DIR)
    options, args = p.parse_args()
    if len(args) != 2:
        p.error("need exactly two CSV files (A belt and B belt)")
    if not options.small:
        p.error("missing --small <png>")
    return options, args


def main():
    options, csvs = parse_args()

    # ONE pass through belts_calibration → parse_log + compute_signal_data
    # + plot. We start at the small size so the layout fits the tight
    # 4.8x2.72 in canvas (font sizes / ticks chosen for that).
    fig = gb.belts_calibration(
        csvs, klipperdir=options.klipperdir, max_freq=options.max_freq,
        graph_spectogram=False,
        width=options.width, height=options.height)
    fig.savefig(options.small)

    # Re-render the same Figure at the full size — no recomputation.
    # matplotlib reflows on savefig from the new figsize, so text and
    # axes scale cleanly. tight_layout + subplots_adjust mirror what
    # belts_calibration applies at the end of its own flow.
    if options.full:
        fig.set_size_inches(8.0, 4.8)
        try:
            fig.tight_layout()
            fig.subplots_adjust(top=0.89)
        except Exception:
            pass
        fig.savefig(options.full)

    plt.close(fig)


if __name__ == '__main__':
    main()
