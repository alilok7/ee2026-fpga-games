# KeyLight: a piano rhythm game on the Basys3

EE2026 I-FDP, AY2026/27 Sem 1. Flip a switch to play a note, and follow the guide light above each switch. The OLED shows falling notes, menus and an on-screen piano.

- The full spec is in `KeyLight_Engineer_Prompt.md`.
- Ownership and the roadmap are in `KeyLight_Roadmap_and_Work_Split.md`.
- Every signal between parts is described in `docs/INTERFACES.md`.

## Hardware

| Needed | Where | Notes |
|---|---|---|
| Basys3 + micro-USB cable | — | Same board as the labs. |
| Pmod OLED (96×64 RGB) | **JC** | Same header and orientation as the labs and GPTs. |
| *(optional)* Pmod AMP2 + headphones or a powered speaker | **JA**, top row (pins 1–6) | Check the model at the lab counter. The game is fully playable without it. |

The on-board QSPI flash is used for saves from Phase 4 on, and needs nothing extra. No mouse, keyboard or VGA is used.

## Folder layout

```
rtl/top/        top module, keylight_defs.vh (the contract), timebase, pixel_xy, muxes
rtl/provided/   Oled_Display.v (course file, unchanged)
rtl/a_sound/    Student A    rtl/b_input_freeplay_storage/  Student B
rtl/c_game/     Student C    rtl/d_ui_learn/                Student D
songs/*.txt     songs as text  ->  tools/song_to_mem.py   -> data/songs.mem
text/*.txt      font + strings ->  tools/font_to_mem.py, strings_to_mem.py
sim/<a|b|c|d|top>/tb_*.v   self-checking testbenches
constraints/    Basys3_Master.xdc
docs/           interfaces, design notes, references and AI use
```

## Build

1. **Regenerate data** (only after editing `songs/` or `text/`): `python tools/make_data.py`
2. **Run the testbenches** (Git Bash): `bash sim/run_sim.sh all`. Every line should start with `PASS`.
3. **Build the bitstream**, either way:
   - **Batch:** `vivado -mode batch -source tools/build.tcl`. This writes `build/keylight.bit` plus the utilisation and timing reports.
   - **GUI:** in Vivado, Tools → Run Tcl Script → `tools/create_project.tcl`. Then use Generate Bitstream as usual (project in `vivado/`).

## Program the board

1. Plug the OLED into **JC** (and the AMP2 into the **top row of JA** if you have one). Connect USB, then switch the board on.
2. In Vivado, Open Hardware Manager → Open Target → Auto Connect.
3. Program Device and choose `build/keylight.bit` (or the GUI project's bitstream).

## On-board test checklist (vertical slice)

| # | Do this | You should see |
|---|---|---|
| 1 | Power on / program | The title screen: falling coloured notes and a "KEYLIGHT" logo with a light sweep. "PRESS C" blinks. The LEDs above the switches chase left to right. The 7-seg shows `HEL0`. |
| 2 | On the title, **hold btnD for 1 s** | Colour-bar self test: 8 bars in the note colours (red, orange, yellow, green, cyan, blue, violet, pink). The 7-seg shows `tESt`. Press C to go back. |
| 3 | btnC | Main menu. U/D moves the highlight bar, which slides. The 7-seg names the item (`PLAY`, `LErn`, `FrEE`, `HI`, `SEt`). The bottom bar shows the hint "^v:MOVE C:OK". |
| 4 | C on PLAY | Song select. U/D picks a song, R cycles EASY / NORMAL / HARD (shown on the 7-seg too), and the BPM appears top right. |
| 5 | C on TWINKLE | Count-in: "FLIP LIT SWITCH", then 3 · 2 · 1 · GO! Notes fall in 8 coloured lanes, and the letters at the bottom match the switches. |
| 6 | Flip the switch under the glowing LED as each note reaches the white line | PERFECT / GOOD / MISS pop-ups, a lane flash and a star burst on Perfect. The score and combo appear top left and right. The 7-seg shows the multiplier and the combo. `led[7:3]` fill up every 10 combo. With the AMP2, each hit plays its note. |
| 7 | Flip `sw[0]` up mid-song | "PAUSED" banner, everything freezes, and `led[0]` lights. Flip it back down to resume. |
| 8 | Finish the song | The Results screen shows the score, grade (S/A/B/C/D), Perfect/Good/Miss counts, accuracy and max combo. The 7-seg shows the grade and accuracy. R retries, C goes to song select, L goes to the menu. |
| 9 | Menu → FREE PLAY | Flip any switch. The on-screen key lights in its colour, the LED above it glows, and the note plays (`sw[2]` = octave up). |
| 10 | `sw[1]` up | Mute: `led[1]` lights and no sound plays. |
| 11 | Hold btnL for 1 s anywhere | Back to the main menu. |
| 12 | Hold btnU + btnD for 2 s | Soft reset to the title screen. |

Not built yet (they show "COMING SOON"): Learn, High scores and Settings screens, the recorder and MY SONG, flash saves, 4-voice polyphony and instruments. See the roadmap, Phase 3.
