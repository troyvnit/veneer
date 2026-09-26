#!/usr/bin/env python3
"""Measure native-glass sync lag from simulator screenshots.

Run the example app's Sync page in measure mode (ruler button) with
auto-scroll on, then:

    python3 tool/measure_sync.py <simulator-udid> [shots] [out_dir]

Each screenshot is scanned for Flutter-painted red rings and the
green-tinted native glass pill inside each one. The vertical offset between
ring centre and glass centre is the sync error for that frame; dividing by
the per-frame scroll distance gives lag in frames.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

SCROLL_VELOCITY = 1200.0  # pt/s, matches SyncTestPage.scrollVelocity


def is_red(p):
    r, g, b = p[:3]
    return r > 200 and g < 70 and b < 70


def is_green(p):
    r, g, b = p[:3]
    return g > 140 and g - r > 60 and g - b > 60


def runs(values, gap):
    """Group sorted ints into runs separated by more than `gap`."""
    out, start, prev = [], None, None
    for v in values:
        if start is None:
            start = prev = v
        elif v - prev > gap:
            out.append((start, prev))
            start = v
        prev = v
    if start is not None:
        out.append((start, prev))
    return out


def measure(path, scale):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    # Column band through the rings' left/right caps, away from the label.
    x0, x1 = int(w * 0.25), int(w * 0.30)
    red_rows = [y for y in range(h) if any(is_red(px[x, y]) for x in range(x0, x1))]
    results = []
    for top, bottom in runs(red_rows, gap=int(12 * scale)):
        if bottom - top < 40 * scale or top < 2 or bottom > h - 3:
            continue  # partial ring at screen edge
        ring_c = (top + bottom) / 2
        # Skip rings passing under the floating top buttons or the tab bar:
        # their glass merges with the pill, so the pill's extent is unknowable.
        if ring_c / scale < 170 or ring_c / scale > h / scale - 140:
            continue
        search = range(max(0, top - int(40 * scale)), min(h, bottom + int(40 * scale)))
        green_rows = [y for y in search if any(is_green(px[x, y]) for x in range(int(w * 0.35), int(w * 0.40)))]
        if not green_rows:
            continue
        glass_c = (green_rows[0] + green_rows[-1]) / 2
        results.append(((glass_c - ring_c) / scale, ring_c / scale))
    return results


def main():
    udid = sys.argv[1]
    shots = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    out = Path(sys.argv[3]) if len(sys.argv) > 3 else Path(tempfile.mkdtemp())
    out.mkdir(parents=True, exist_ok=True)
    paths = []
    for i in range(shots):
        p = out / f"shot{i:02d}.png"
        subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", str(p)], capture_output=True, check=True)
        paths.append(p)

    scale = 3.0  # iPhone 17 @3x
    per_frame = SCROLL_VELOCITY / 60.0
    offsets = []
    for p in paths:
        for off, y in measure(p, scale):
            offsets.append(off)
            print(f"{p.name}: ring@{y:6.1f}pt  glass-ring offset {off:+6.2f}pt  ({off / per_frame:+.2f} frames @60Hz)")
    if not offsets:
        print("no rings found — is measure mode on?")
        return
    mags = sorted(abs(o) for o in offsets)
    print(f"\n{len(offsets)} samples over {shots} shots")
    print(f"|offset| median {mags[len(mags) // 2]:.2f}pt, max {mags[-1]:.2f}pt; one frame = {per_frame:.1f}pt")


if __name__ == "__main__":
    main()
