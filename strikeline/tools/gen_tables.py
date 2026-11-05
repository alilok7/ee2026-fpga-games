#!/usr/bin/env python3
"""gen_tables.py - every lookup table of StrikeLine, generated (never hand-typed in RTL).

Owners: the part that reads each table (named below). Run: python tools/gen_tables.py

  speed_curve.mem  (A) 64 x 24 bit  {vy Q3.12 in/tick, mph*10}
  ball_params.mem  (B)  8 x 64 bit  per (oil, weight): decel, rev per spin level, impulse ratios
  oil_pattern.mem  (B) 1024 x 8 bit friction mu by (oil length, distance, board) - v3 slip hook
  ball_marker.mem  (B) 64 x 6 bit   finger-hole offset {dx[2:0], dy[2:0]} at radius 2 px
  pin_spots.mem    (C) 10 x 32 bit  {x POS, y POS} of each pin spot
  pin_pairs.mem    (C) 45 x 8 bit   {i, j} for the pair iterator, i < j
  pin_adj.mem      (C) 10 x 10 bit  adjacency (pins 12 in apart) for split detection
  leaves.mem       (D) 8 x 10 bit   Spare Challenge leaves (bit k = pin k+1)
  inv_len.mem      (B, C) 128 x 9 bit  2^14 / |d| for the collision normal, indexed by d^2 >> 12
  persp.mem        (B) 64 x 26 bit {dist[10:0], inv[14:0]} first-person view, per screen row
  persp_v.mem      (B) 128 x 27 bit {dist[11:0], inv[14:0]} v3 VGA first-person view
  pin_fp.mem       (C) 512 x 4 bit {red, half-width[2:0]} standing pin seen from behind,
                   address {size class[3:0], row above the base[4:0]} (v3: 16 sizes)
"""
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")

TICK_HZ = 1024.0
IN_PER_S_PER_MPH = 17.6           # 1 mph = 17.6 in/s


def write(name, words, width_bits):
    digits = (width_bits + 3) // 4
    with open(os.path.join(DATA, name), "w") as fh:
        for w in words:
            fh.write("%0*X\n" % (digits, w & ((1 << width_bits) - 1)))
    print("%-16s %3d x %d bit" % (name, len(words), width_bits))


def q312(in_per_tick):
    return int(round(in_per_tick * 4096))


# ---------------------------------------------------------------- A: speed curve
# index = peak forward mouse motion over 80 ms >> 3.  Below 4 = rejected.
# Concave curve: a gentle swipe still rolls 12-14 mph, a hard flick tops out
# at 22 mph (real bowling: 14-20 mph). mph = 10 + 12 * sqrt((i-4)/59)
def speed_curve():
    out = []
    for i in range(64):
        mph = 10.0 + 12.0 * math.sqrt(max(i - 4, 0) / 59.0)
        vy = mph * IN_PER_S_PER_MPH / TICK_HZ
        out.append((q312(vy) << 8) | int(round(mph * 10)))
    write("speed_curve.mem", out, 24)


# ---------------------------------------------------------------- B: ball params
# address = {oil_long, weight[1:0]}  (weight 0/1/2 = 12/14/16 lb, 3 = copy of 16)
# fields:
#   [63:56] dec_oil   forward deceleration in the oil        (2^-20 in/tick^2)
#   [55:48] dec_dry   forward deceleration on the dry lane   (2^-20 in/tick^2)
#   [47:32] rev_k     side slip per spin level (v3)          (2^-20 in/tick)
#                     the total sideways speed a spin level can turn into
#   [31:16] kp Q2.12  pin velocity change  = (1+e) mb/(mb+mp) * v_rel_n
#   [15:0]  kb Q2.12  ball velocity change = (1+e) mp/(mb+mp) * v_rel_n
# Tuning target (v3): spin 16 (a medium curve) hooks ~8-14 boards on short
# oil, spin 31 ~15 boards, < 2 boards inside the oil. Measured in
# sim/b/tb_physics.v (see docs/B_DESIGN.md, tuning log).
E_BALL_PIN = 0.70
PIN_LB = 3.5


def ball_params():
    out = []
    for oil_long in (0, 1):
        for w in range(4):
            lb = (12, 14, 16, 16)[w]
            rev_k = (1250, 1150, 1080, 1080)[w]   # lighter balls rev up easier
            dec_oil, dec_dry = 8, 24
            kp = (1 + E_BALL_PIN) * lb / (lb + PIN_LB)
            kb = (1 + E_BALL_PIN) * PIN_LB / (lb + PIN_LB)
            word = (dec_oil << 56) | (dec_dry << 48) | (rev_k << 32) \
                | (int(round(kp * 4096)) << 16) | int(round(kb * 4096))
            out.append(word)
    write("ball_params.mem", out, 64)


# ---------------------------------------------------------------- B: oil pattern (v3)
# mu = the most sideways acceleration the lane can give the ball this tick
# (2^-20 in/tick^2). address = {long[0], y band[5:0] (16 in), x band[2:0]
# (|x - 30 in| / 4 in)}. The oil is a "house shot": longest in the middle,
# 18 in shorter per 4 in toward the edges, then a 72 in transition (smooth
# step) to the dry back end and the wooden pin deck.
MU_OIL, MU_DRY = 1, 44
OIL_TAPER, OIL_RAMP = 18.0, 72.0


def oil_pattern():
    out = []
    for long in (0, 1):
        length = 540.0 if long else 480.0
        for yb in range(64):
            y = yb * 16 + 8
            for xb in range(8):
                if xb >= 6:                       # gutter: never used
                    out.append(0)
                    continue
                end = length - OIL_TAPER * xb
                s = min(1.0, max(0.0, (y - end) / OIL_RAMP))
                s = s * s * (3 - 2 * s)
                out.append(int(round(MU_OIL + (MU_DRY - MU_OIL) * s)))
    write("oil_pattern.mem", out, 8)


def ball_marker():
    out = []
    for a in range(64):
        t = 2 * math.pi * a / 64
        dx = int(round(2.0 * math.cos(t)))
        dy = int(round(-2.0 * math.sin(t)))     # screen y grows downward
        out.append(((dx & 7) << 3) | (dy & 7))
    write("ball_marker.mem", out, 6)


# ---------------------------------------------------------------- C: pins
ROW = 12 * math.sqrt(3) / 2      # 10.392 in between pin rows
SPOTS = [(30, 720), (24, 720 + ROW), (36, 720 + ROW),
         (18, 720 + 2 * ROW), (30, 720 + 2 * ROW), (42, 720 + 2 * ROW),
         (12, 720 + 3 * ROW), (24, 720 + 3 * ROW), (36, 720 + 3 * ROW), (48, 720 + 3 * ROW)]


def pins():
    write("pin_spots.mem",
          [(int(round(x * 64)) << 16) | int(round(y * 64)) for x, y in SPOTS], 32)
    pairs = [(i, j) for i in range(10) for j in range(i + 1, 10)]
    write("pin_pairs.mem", [(i << 4) | j for i, j in pairs], 8)
    adj = []
    for i, (xi, yi) in enumerate(SPOTS):
        m = 0
        for j, (xj, yj) in enumerate(SPOTS):
            if i != j and abs(math.hypot(xi - xj, yi - yj) - 12) < 0.1:
                m |= 1 << j
        adj.append(m)
    write("pin_adj.mem", adj, 10)


# ---------------------------------------------------------------- D: leaves
LEAVES = [[10], [7, 10], [4, 6], [3, 6, 10], [2, 4, 5, 8], [5, 7], [6, 7, 10], [1, 2, 4, 7]]


def leaves():
    write("leaves.mem", [sum(1 << (p - 1) for p in lv) for lv in LEAVES], 10)


# ---------------------------------------------------------------- B, C: 1/|d|
# n = d * inv_len[d^2 >> 12] >> 0 gives the unit normal in Q1.14 without a
# square root or divider: bin i covers d^2 in [i*4096, (i+1)*4096) (1/64-in
# units), |d| is taken at the bin centre. Error < 1.6 % for |d| > 2 in.
def inv_len():
    out = []
    for i in range(128):
        d = math.sqrt((i + 0.5) * 4096.0)
        out.append(min(511, int(round(16384.0 / d))))
    write("inv_len.mem", out, 9)


# ---------------------------------------------------------------- B: first person
# Camera at a fixed height and tilt: screen row y (horizon at y = 12) always
# looks at the same distance ahead of the camera,  dist = 1530 / (y - 12) in,
# and one inch across the lane covers (y - 12) / 51 px there. So a lane pixel
# is at  world y = camera + dist[y],  world x = 30 + (px - 30) * inv[y] / 256
# with inv[y] = 51 * 256 / (y - 12): a ROM and one multiply, no 3-D maths.
HORIZON, K = 12, 1530


def persp():
    out = []
    for y in range(64):
        r = y - HORIZON
        if r <= 0:
            out.append(0)
            continue
        dist = min(2047, int(round(K / r)))
        inv = min(32767, int(round(51 * 256 / r)))
        out.append((dist << 15) | inv)
    write("persp.mem", out, 26)


# v3: the same camera for the VGA 3-D view. v3.2: the 320 x 240 picture,
# horizon on row 60, lane centre on column 112.  r = y - 60 (1..179),
# dist = 6120 / r in,  inv = 51 * 256 / r  (one inch covers r / 51 px).
# 256 x 27 bit {dist[11:0], inv[14:0]}
V_HORIZON, V_K = 60, 6120


def persp_v():
    out = []
    for y in range(256):
        r = y - V_HORIZON
        if r <= 0:
            out.append(0)
            continue
        dist = min(4095, int(round(V_K / r)))
        inv = min(32767, int(round(51 * 256 / r)))
        out.append((dist << 15) | inv)
    write("persp_v.mem", out, 27)


# a standing pin seen from behind, 32 sizes (height in px, v3.2 VGA view at
# 320 x 240), drawn upward from its base row. persp_proj.v picks the class
# from the projected height with the same list.
PIN_H = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 18, 20,
         22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 53]


def pin_fp():
    prof = [(0.0, 1.0), (0.12, 1.9), (0.30, 2.4), (0.50, 1.9), (0.67, 0.9),
            (0.80, 1.2), (0.90, 1.25), (1.0, 0.0)]       # radius (in) along the height

    def radius(t):
        for (t0, r0), (t1, r1) in zip(prof, prof[1:]):
            if t0 <= t <= t1:
                return r0 + (r1 - r0) * (t - t0) / (t1 - t0)
        return 0.0
    out = []
    for c, h in enumerate(PIN_H):
        scale = h / 15.0                                 # px per inch
        for v in range(64):                              # rows above the base
            if v >= h:
                out.append(0x1F)                         # 0x1F = empty row
                continue
            t = (v + 0.5) / h
            hw = min(14, int(radius(t) * scale + 0.35))
            # two red neck stripes on big pins, one on small ones
            if h >= 24:
                red = 1 if (0.60 <= t <= 0.65) or (0.69 <= t <= 0.74) else 0
            else:
                red = 1 if 0.62 <= t <= 0.74 and h >= 6 else 0
            out.append((red << 4) | hw)
    write("pin_fp.mem", out, 5)                          # 2048 x 5: {class[4:0], row[5:0]}


if __name__ == "__main__":
    os.makedirs(DATA, exist_ok=True)
    speed_curve()
    ball_params()
    oil_pattern()
    ball_marker()
    pins()
    leaves()
    inv_len()
    persp()
    persp_v()
    pin_fp()
