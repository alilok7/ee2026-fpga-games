#!/usr/bin/env python3
"""screens_to_png.py - turn tb_screens' frame-buffer captures into PNG images.

Usage: python tools/screens_to_png.py <folder with screen_*.txt> [out folder]
Each capture is hex values, x fastest:
  76800 values = the VGA picture (v3.2: 320 x 240, RGB 3:3:3 as stored in
                 vga_out), saved x2 = 640 x 480 like the monitor shows it
                 (each 3-bit colour becomes the DAC's 4 bits, c c[2])
  19200 values = a v3 VGA capture (160 x 120 RGB565), saved x4
   6144 values = the OLED picture (96 x 64 RGB565), saved x4
Uses Pillow when it is installed, otherwise a small PNG writer (zlib only).
"""
import glob
import os
import struct
import sys
import zlib


def write_png(path, w, h, rows):
    """rows: list of h lists of w (r, g, b) tuples."""
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in rows)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        fh.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        fh.write(chunk(b"IEND", b""))


def dac3(c):
    """3-bit colour -> the 4-bit DAC value {c, c[2]} -> 0..255."""
    return ((c << 1) | (c >> 2)) * 17


def convert(path, out_dir):
    # an unknown value ("xxxx") is drawn black
    vals = [int(l, 16) if "x" not in l.lower() else 0 for l in open(path) if l.strip()]
    pix = []
    if len(vals) >= 76800:
        w, h, scale = 320, 240, 2
        for v in vals[:w * h]:
            pix.append((dac3((v >> 6) & 7), dac3((v >> 3) & 7), dac3(v & 7)))
    else:
        if len(vals) >= 19200:
            w, h, vga = 160, 120, True
        else:
            w, h, vga = 96, 64, False
        scale = 4
        for v in vals[:w * h]:
            r, g, b = (v >> 11) & 31, (v >> 5) & 63, v & 31
            if vga:                              # what the 4-bit VGA DAC can show
                r, g, b = (r >> 1) * 17, (g >> 2) * 17, (b >> 1) * 17
            else:
                r, g, b = r * 255 // 31, g * 255 // 63, b * 255 // 31
            pix.append((r, g, b))
    out = os.path.join(out_dir, os.path.basename(path).replace(".txt", ".png"))
    try:
        from PIL import Image
        img = Image.new("RGB", (w, h))
        img.putdata(pix)
        img.resize((w * scale, h * scale), Image.NEAREST).save(out)
    except ImportError:
        rows = []
        for y in range(h):
            row = [pix[y * w + x] for x in range(w) for _ in range(scale)]
            rows.extend([row] * scale)
        write_png(out, w * scale, h * scale, rows)
    return out


if __name__ == "__main__":
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else src
    os.makedirs(dst, exist_ok=True)
    for p in sorted(glob.glob(os.path.join(src, "screen_*.txt"))):
        print(convert(p, dst))
