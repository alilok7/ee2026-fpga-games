#!/usr/bin/env python3
"""song_to_mem.py - turn the readable song files in songs/ into chart ROMs.

Owner: Student C (chart format), used by C and D.

Song file format (one song per file, '//' starts a comment, '#' is sharp):
    TITLE TWINKLE
    BPM 100
    C4 1, C4 1, G4 1, G4 1, A4 1, A4 1, G4 2
    R 1                      <- a rest of one beat
Each item is NOTE BEATS, where BEATS may be a fraction (0.5 = an eighth).
One beat = 4 steps (16th notes), so every duration must be a multiple of
0.25 beats.

Chart words (24 bits, see rtl/top/keylight_defs.vh):
    word 0   {step_ms[23:14], event_count[13:5], 5'b0}
    word i   {note[23:17], start_step[16:6], len_steps[5:0]}
    end      note = 0
step_ms = round(15000 / BPM) so the hardware never divides.

Outputs:
    data/songs.mem      4 songs x 512 words, address = {song_id[1:0], addr[8:0]}
    data/song_info.mem  8 x 12-bit BPM written as 3 BCD digits (e.g. 096), so
                        the song-select screen can print it without a converter
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SONG_FILES = ["twinkle.txt", "mary.txt", "ode_to_joy.txt", "jingle_bells.txt"]
WORDS_PER_SONG = 512
NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def note_to_midi(tok):
    m = re.fullmatch(r"([A-G])(#?)(\d)", tok)
    if not m:
        raise ValueError("bad note '%s'" % tok)
    midi = 12 * (int(m.group(3)) + 1) + NAMES[m.group(1)] + (1 if m.group(2) else 0)
    if not 60 <= midi <= 72:
        raise ValueError("note %s outside C4..C5" % tok)
    return midi


def parse(path):
    title, bpm, items = None, None, []
    with open(path) as fh:
        for raw in fh:
            line = raw.split("//")[0].strip()   # '#' means sharp, so comments use //
            if not line:
                continue
            if line.upper().startswith("TITLE"):
                title = line[5:].strip().upper()
            elif line.upper().startswith("BPM"):
                bpm = int(line[3:])
            else:
                for item in line.split(","):
                    item = item.strip()
                    if item:
                        tok, beats = item.split()
                        steps = float(beats) * 4
                        if abs(steps - round(steps)) > 1e-6:
                            raise ValueError("%s: duration %s is not a 16th multiple" % (path, beats))
                        items.append((tok.upper(), int(round(steps))))
    if title is None or bpm is None:
        raise ValueError("%s needs TITLE and BPM" % path)
    return title, bpm, items


def build_chart(bpm, items):
    step_ms = round(15000 / bpm)
    events, step = [], 0
    for tok, steps in items:
        if tok != "R":
            events.append((note_to_midi(tok), step, min(steps, 63)))
        step += steps
    if len(events) > WORDS_PER_SONG - 2:
        raise ValueError("too many events")
    if step >= 2048:
        raise ValueError("song longer than 2047 steps")
    words = [(step_ms << 14) | (len(events) << 5)]
    for note, start, length in events:
        words.append((note << 17) | (start << 6) | length)
    words.append(0)                       # end marker
    words += [0] * (WORDS_PER_SONG - len(words))
    return words, step_ms, len(events), step


def main():
    all_words, bpms, titles = [], [], []
    for name in SONG_FILES:
        title, bpm, items = parse(os.path.join(ROOT, "songs", name))
        words, step_ms, count, steps = build_chart(bpm, items)
        all_words += words
        bpms.append(bpm)
        titles.append(title)
        print("%-16s BPM %3d step_ms %3d events %3d length %4d steps"
              % (title, bpm, step_ms, count, steps))
    with open(os.path.join(ROOT, "data", "songs.mem"), "w") as fh:
        fh.write("\n".join("%06X" % w for w in all_words) + "\n")
    bpms += [0] * (8 - len(bpms))
    with open(os.path.join(ROOT, "data", "song_info.mem"), "w") as fh:
        fh.write("\n".join("%03d" % b for b in bpms) + "\n")   # decimal text = BCD hex
    # Titles are picked up by strings_to_mem.py (one visual language).
    with open(os.path.join(ROOT, "data", "song_titles.txt"), "w") as fh:
        fh.write("\n".join(titles) + "\n")


if __name__ == "__main__":
    try:
        main()
    except ValueError as err:
        sys.exit("song_to_mem: %s" % err)
