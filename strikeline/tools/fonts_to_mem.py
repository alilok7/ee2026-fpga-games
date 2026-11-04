#!/usr/bin/env python3
"""fonts_to_mem.py - build both font ROMs of D's shared text engine.

Owner: Student D.
Inputs : text/font5x7.txt (5 x 7), text/font3x5.txt (3 x 5); 64 glyphs, ASCII 0x20..0x5F
Outputs: data/font5x7.mem  512 lines: address {glyph[5:0], row[2:0]}, bit 4 = leftmost
         data/font3x5.mem  512 lines: address {glyph[5:0], row[2:0]}, bit 2 = leftmost
Rows past the glyph height are 0 (the gap between text lines).
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(path, w, h):
    glyphs, cur = {}, None
    with open(path) as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if line.startswith("//") or not line.strip():
                continue
            if line.startswith("char "):
                name = line[5:]
                cur = " " if name == "space" else name
                glyphs[cur] = []
            else:
                if len(line) != w or set(line) - set("#."):
                    raise ValueError("%s glyph '%s': bad row '%s'" % (path, cur, line))
                glyphs[cur].append(int(line.replace("#", "1").replace(".", "0"), 2))
    for ch, rows in glyphs.items():
        if len(rows) != h:
            raise ValueError("%s glyph '%s' has %d rows" % (path, ch, len(rows)))
    missing = [chr(c) for c in range(0x20, 0x60) if chr(c) not in glyphs]
    if missing:
        raise ValueError("%s: missing glyphs %s" % (path, "".join(missing)))
    return glyphs


def build(src, dst, w, h):
    g = load(os.path.join(ROOT, "text", src), w, h)
    out = []
    for code in range(64):
        rows = g[chr(0x20 + code)] + [0] * (8 - h)
        out += ["%02X" % r for r in rows]
    with open(os.path.join(ROOT, "data", dst), "w") as fh:
        fh.write("\n".join(out) + "\n")
    print("%-14s 64 glyphs %dx%d" % (dst, w, h))


if __name__ == "__main__":
    try:
        build("font5x7.txt", "font5x7.mem", 5, 7)
        build("font3x5.txt", "font3x5.mem", 3, 5)
    except ValueError as err:
        sys.exit("fonts_to_mem: %s" % err)
