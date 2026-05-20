#!/usr/share/klippy-env/bin/python3
"""Wrapper around Klipper mainline calibrate_shaper.py that forces a
specific matplotlib figure size.

Mainline calibrate_shaper.py dropped GuppyScreen's -w / -l flags, but
it sets figsize in two places inside the script:

  - `matplotlib.pyplot.subplots(figsize=(8, 5))` at line ~106
  - `fig.set_size_inches(8, 6)` later in the script

Setting rcParams['figure.figsize'] is insufficient because those two
explicit calls override it. We monkey-patch both functions to force
our target (w, l) before exec'ing the upstream script.

Why we need this: GuppyScreen displays PNGs at native resolution with
no scaling (no lv_img_set_zoom symbol in its binary). The Nebula Pad
is 480x272 px, so the on-screen PNG must come out at exactly
4.8 x 2.72 inches (at 100 DPI). Mainline matplotlib defaults would
give a much larger image, cropped to the top-left ~480x272 — unusable.

Usage:
  _shaper_with_figsize.py <w_inches> <l_inches> <csv> [calibrate_shaper.py args]

This wrapper is invoked by /usr/data/e5m-ck/bin/gen_shaper_for_guppy.sh
for both GuppyScreen and Fluidd shaper-PNG generation. The Fluidd-side
large PNG uses 8 x 4.8 in (readable in Fluidd's File Manager);
GuppyScreen uses 4.8 x 2.72 in.
"""

import sys

if len(sys.argv) < 5:
    sys.stderr.write("Usage: %s <w_inches> <l_inches> <csv> [args...]\n"
                     % sys.argv[0])
    sys.exit(1)

W = float(sys.argv[1])
L = float(sys.argv[2])

import matplotlib
matplotlib.use('Agg')

# Patch 1: plt.subplots — inject our figsize, dropping any caller's.
import matplotlib.pyplot as _plt
_orig_subplots = _plt.subplots


def _patched_subplots(*args, **kwargs):
    kwargs['figsize'] = (W, L)
    return _orig_subplots(*args, **kwargs)


_plt.subplots = _patched_subplots

# Patch 2: Figure.set_size_inches — ignore caller args, force ours.
from matplotlib.figure import Figure as _Figure
_orig_set_size = _Figure.set_size_inches


def _patched_set_size(self, *_args, **_kwargs):
    return _orig_set_size(self, W, L)


_Figure.set_size_inches = _patched_set_size

# Hand off to mainline calibrate_shaper.py.
sys.argv = ['calibrate_shaper.py'] + sys.argv[3:]
SCRIPT = '/usr/data/e5m-ck/klipper/scripts/calibrate_shaper.py'
with open(SCRIPT) as f:
    exec(compile(f.read(), SCRIPT, 'exec'))
