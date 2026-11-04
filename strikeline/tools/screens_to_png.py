#!/usr/bin/env python3
"""screens_to_png.py - turn tb_screens' OLED captures into PNG images (x4 scale).

Usage: python tools/screens_to_png.py <folder with screen_*.txt> [out folder]
Each capture is 6144 RGB565 hex values in OLED order (x fastest, 96 x 64).
"""
import glob
import os
import sys

from PIL import Image


def convert(path, out_dir, scale=4):
    # an unknown value ("xxxx", e.g. the last pixel the capture misses) is drawn black
    vals = [int(l, 16) if "x" not in l else 0 for l in open(path) if l.strip()]
    img = Image.new("RGB", (96, 64))
    for i, v in enumerate(vals[:6144]):
        r, g, b = (v >> 11) & 31, (v >> 5) & 63, v & 31
        img.putpixel((i % 96, i // 96), (r * 255 // 31, g * 255 // 63, b * 255 // 31))
    img = img.resize((96 * scale, 64 * scale), Image.NEAREST)
    out = os.path.join(out_dir, os.path.basename(path).replace(".txt", ".png"))
    img.save(out)
    return out


if __name__ == "__main__":
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else src
    os.makedirs(dst, exist_ok=True)
    for p in sorted(glob.glob(os.path.join(src, "screen_*.txt"))):
        print(convert(p, dst))
