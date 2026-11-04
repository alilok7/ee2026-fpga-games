#!/usr/bin/env python3
"""gen_note_table.py - DDS phase-increment ROM for Part A (sound engine).

Owner: Student A.
For every MIDI note 36..96 (C2..C7) we precompute the 24-bit phase increment

    inc = round(f * 2^24 / Fs),   f = 440 * 2^((n - 69) / 12),
    Fs  = 100 MHz / 2048 = 48 828.125 Hz   (tick_sample in timebase.v)

so the hardware only adds, never multiplies or divides.
Output: data/note_inc.mem, 64 lines of 6 hex digits, address = note - 36
(addresses 61..63 are padding and hold 0 = silence).
"""
import os

FS = 100e6 / 2048
LOW, HIGH = 36, 96
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def inc_for(note):
    f = 440.0 * 2 ** ((note - 69) / 12)
    return round(f * (1 << 24) / FS)


def main():
    lines = []
    for addr in range(64):
        note = LOW + addr
        lines.append("%06X" % (inc_for(note) if note <= HIGH else 0))
    out = os.path.join(ROOT, "data", "note_inc.mem")
    with open(out, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    # Frequency resolution = Fs / 2^24, useful for the design note / Q&A.
    print("note_inc.mem: %d notes, resolution %.5f Hz, C4 inc=%d"
          % (HIGH - LOW + 1, FS / (1 << 24), inc_for(60)))


if __name__ == "__main__":
    main()
