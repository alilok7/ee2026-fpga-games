#!/usr/bin/env python3
"""gen_tables.py - every lookup table of StrikeLine, generated (never hand-typed in RTL).

Owners: the part that reads each table (named below). Run: python tools/gen_tables.py

  speed_curve.mem  (A) 64 x 24 bit  {vy Q3.12 in/tick, mph*10}
  ball_params.mem  (B)  8 x 64 bit  per (oil, weight): decel/hook gains and impulse ratios
  ball_marker.mem  (B) 64 x 6 bit   finger-hole offset {dx[2:0], dy[2:0]} at radius 2 px
  pin_spots.mem    (C) 10 x 32 bit  {x POS, y POS} of each pin spot
  pin_pairs.mem    (C) 45 x 8 bit   {i, j} for the pair iterator, i < j
  pin_adj.mem      (C) 10 x 10 bit  adjacency (pins 12 in apart) for split detection
  leaves.mem       (D) 8 x 10 bit   Spare Challenge leaves (bit k = pin k+1)
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
#   [47:40] hook_oil  sideways accel per spin level, oil     (2^-24 in/tick^2)
#   [39:32] hook_dry  sideways accel per spin level, dry     (2^-24 in/tick^2)
#   (hook gains are 16x finer: the oil value is well below 1 LSB of velocity)
#   [31:16] kp Q2.12  pin velocity change  = (1+e) mb/(mb+mp) * v_rel_n
#   [15:0]  kb Q2.12  ball velocity change = (1+e) mp/(mb+mp) * v_rel_n
# Tuning target (prompt 4B.2): spin 4 hooks ~10 boards on short oil, < 2 boards
# inside the oil. Measured in sim/b/tb_physics.v (see docs/B_DESIGN.md, tuning log).
E_BALL_PIN = 0.70
PIN_LB = 3.5


def ball_params():
    out = []
    for oil_long in (0, 1):
        for w in range(4):
            lb = (12, 14, 16, 16)[w]
            hook_dry = (88, 80, 76, 76)[w]  # lighter balls rev up easier
            dec_oil, dec_dry, hook_oil = 8, 24, 4
            kp = (1 + E_BALL_PIN) * lb / (lb + PIN_LB)
            kb = (1 + E_BALL_PIN) * PIN_LB / (lb + PIN_LB)
            word = (dec_oil << 56) | (dec_dry << 48) | (hook_oil << 40) | (hook_dry << 32) \
                | (int(round(kp * 4096)) << 16) | int(round(kb * 4096))
            out.append(word)
    write("ball_params.mem", out, 64)


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


if __name__ == "__main__":
    os.makedirs(DATA, exist_ok=True)
    speed_curve()
    ball_params()
    ball_marker()
    pins()
    leaves()
