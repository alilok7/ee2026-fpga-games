#!/usr/bin/env python3
"""font_to_mem.py - build the 5x7 font ROM for D's text engine.

Owner: Student D.
Input : text/font5x7.txt (64 glyphs, ASCII 0x20..0x5F, '#' = pixel on)
Output: data/font.mem, 512 lines of 2 hex digits.
        address = {glyph_code[5:0], row[2:0]}, data bit 4 = leftmost column.
        Row 7 is always 0 (the gap between text lines).
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(path):
    glyphs, cur, rows = {}, None, []
    with open(path) as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if line.startswith("//") or not line.strip():
                continue
            if line.startswith("char "):
                name = line[5:]
                cur = " " if name == "space" else name
                rows = []
                glyphs[cur] = rows
            else:
                if len(line) != 5 or set(line) - set("#."):
                    raise ValueError("glyph '%s': bad row '%s'" % (cur, line))
                rows.append(int(line.replace("#", "1").replace(".", "0"), 2))
    for ch, rows in glyphs.items():
        if len(rows) != 7:
            raise ValueError("glyph '%s' has %d rows" % (ch, len(rows)))
    return glyphs


def main():
    glyphs = load(os.path.join(ROOT, "text", "font5x7.txt"))
    missing = [chr(c) for c in range(0x20, 0x60) if chr(c) not in glyphs]
    if missing:
        raise ValueError("missing glyphs: %s" % "".join(missing))
    out = []
    for code in range(64):
        rows = glyphs[chr(0x20 + code)] + [0]
        out += ["%02X" % r for r in rows]
    with open(os.path.join(ROOT, "data", "font.mem"), "w") as fh:
        fh.write("\n".join(out) + "\n")
    print("font.mem: 64 glyphs")


if __name__ == "__main__":
    try:
        main()
    except ValueError as err:
        sys.exit("font_to_mem: %s" % err)
