#!/usr/bin/env python3
"""gen_sprites.py - top-down sprites of a falling / fallen bowling pin.

Owner: Student C.   Output: data/pin_sprites.mem (2048 x 2 bit) and a text preview.

A real pin is 15 in long; at 1 px = 1 in a pin lying on the deck is 15 px.
Only TWO directions are stored, N (head up) and NE (head up-right), each in 3
fall stages (tilting = 7 px, half down = 11 px, flat = 15 px). The renderer
makes the other six directions by mirroring / swapping the coordinates, so
the ROM is 4x smaller than storing all 8 (see pin_render.v).

address = {base (0 = N, 1 = NE), stage[1:0], v+8 [3:0], u+8 [3:0]}
  u = across (right), v = down the screen, offsets -8..7, pin centre at (0, 0)
pixel  : 0 transparent, 1 white, 2 red neck stripe, 3 grey outline
"""
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LENGTHS = [7, 11, 15]


def radius(t):
    """pin radius (in) at fraction t of its length, 0 = base, 1 = top."""
    prof = [(0.0, 1.0), (0.12, 1.9), (0.30, 2.4), (0.50, 1.9), (0.67, 0.9),
            (0.80, 1.2), (0.90, 1.25), (1.0, 0.0)]
    for (t0, r0), (t1, r1) in zip(prof, prof[1:]):
        if t0 <= t <= t1:
            return r0 + (r1 - r0) * (t - t0) / (t1 - t0)
    return 0.0


def inside(u, v, base, length):
    if base == 0:                     # axis straight up the screen
        along, across = -v, u
    else:                             # axis up-right (45 degrees)
        along, across = (u - v) / math.sqrt(2), (u + v) / math.sqrt(2)
    t = (along + length / 2.0) / length
    if not 0.0 <= t <= 1.0:
        return 0, t
    return (1 if abs(across) <= radius(t) + 0.15 else 0), t


def sprite(base, stage):
    L = LENGTHS[stage]
    px = {}
    for v in range(-8, 8):
        for u in range(-8, 8):
            ins, t = inside(u, v, base, L)
            if not ins:
                px[(u, v)] = 0
            elif 0.62 <= t <= 0.74:
                px[(u, v)] = 2
            else:
                px[(u, v)] = 1
    # outline: inside pixels with an empty 4-neighbour become grey (shape reads
    # clearly against the white-ish deck)
    out = dict(px)
    for (u, v), c in px.items():
        if c == 1 and any(px.get((u + du, v + dv), 0) == 0
                          for du, dv in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            out[(u, v)] = 3
    return out


def main():
    words = [0] * 2048
    preview = []
    for base in (0, 1):
        for stage in range(3):
            sp = sprite(base, stage)
            preview.append("base %d stage %d" % (base, stage))
            for v in range(-8, 8):
                row = ""
                for u in range(-8, 8):
                    c = sp[(u, v)]
                    words[(base << 10) | (stage << 8) | ((v + 8) << 4) | (u + 8)] = c
                    row += ".WR#"[c]
                preview.append(row)
    with open(os.path.join(ROOT, "data", "pin_sprites.mem"), "w") as fh:
        fh.write("\n".join("%X" % w for w in words) + "\n")
    with open(os.path.join(ROOT, "data", "pin_sprites_preview.txt"), "w") as fh:
        fh.write("\n".join(preview) + "\n")
    print("pin_sprites.mem  2048 x 2 bit (6 sprites)")


if __name__ == "__main__":
    main()
