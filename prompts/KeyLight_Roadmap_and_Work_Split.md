# KeyLight: Roadmap and Work Split

The full technical spec (signals, formats, every feature) is in **KeyLight_Engineer_Prompt.md**. This file covers who does what, in what order, and what "done" means.

## The product in one paragraph
KeyLight turns the Basys3 into a piano rhythm game. **Flipping** any of the 8 left switches plays a note (either direction counts). The LED above each switch glows as its next note falls toward the hit line on the OLED. There are four modes. **Play** judges each note Perfect, Good or Miss, with score, combo and grade. **Learn** waits for the right key. **Free Play** is a 13-key piano with a recorder. Your recording becomes **MY SONG**, playable in Play and Learn. High scores and MY SONG are **saved to the board's flash**, so they survive reprogramming.

## Who owns what

| | Student A: Sound | Student B: Input, Free Play, Storage | Student C: Game engine | Student D: UI, Learn, Control |
|---|---|---|---|---|
| Core | 4-voice DDS synth, ADSR, 4 instruments, mixer, audio Pmod adapter | Debounce, switch-flip strikes, button events (long-press, repeat) | Song clock, note scheduler, Perfect/Good/Miss judgement, score, combo, grade | Mode FSM, text engine and font, all menus, 7-seg driver |
| Showpiece | Time-shared multiplier, SFX ROM, metronome, scope feed | Recorder with count-in and 16th-note quantising; **flash save** (double-buffered and CRC) | Falling-note renderer, LED guide lights (PWM), accuracy divider | Learn mode, initials entry, hint bars, fade and brightness post-processing |
| Gives others | Sound for every mode; scope samples (B) | `key_strike`/buttons (all), MY SONG chart (C, D), saved scores (D) | `chart_reader` (D), results (D, B), note events (A) | `mode`, `settings`, song and difficulty (all), text engine (B, C) |
| Lecture link | Counters, clock dividers (L1–L2) | Sequential circuits, synchronisers (L1) | Counters and FSMs (L2–L3) | FSMs and modular FSMs (L3–L4) |

Each owner also presents the shared files they explain in Q&A: A `timebase`, B the IO mux, D `pixel_xy` and the video mux.

## Roadmap (in order; each phase ends when its check passes on the board)

### Phase 0: Agree (all)
- [ ] Read the engineer prompt, sections 1–3.
- [ ] Confirm the audio Pmod model at the lab counter (AMP2 or I2S2).
- [ ] Freeze `keylight_defs.vh`: mode codes, event bus, chart format, results, storage, video, LED and 7-seg buses.
- [ ] Set up one shared Git repo with the folder layout from §3.4 of the prompt.
- **Check:** everyone can explain every signal that crosses into or out of their part.

### Phase 1: Base build (all, together)
- [ ] Top module, XDC, `timebase`, `pixel_xy`, OLED colour bars, stub modules A–D.
- **Check:** clean build, no latches, timing met, OLED shows bars.

### Phase 2: Vertical slice (each person builds the minimum version of their part)
- A: one square-wave voice that plays an `ev_note`.
- B: `input_conditioner` producing `key_strike` and button pulses.
- C: one ROM song falls, gets judged and scored.
- D: title → menu → Play → Results FSM, plus text engine.
- **Check:** a stranger can play Twinkle start to finish and see a score.

### Phase 3: Full parts (work in parallel; integrate into the shared top at least daily)

**A: Sound**
- [ ] DDS + generated note ROM
- [ ] 4 voices + allocator
- [ ] ADSR with shared multiplier
- [ ] 4 instruments
- [ ] Mixer with saturation and volume
- [ ] SFX ROM
- [ ] Metronome
- [ ] Scope output
- [ ] Testbenches for DDS and allocator

**B: Input, Free Play, Storage**
- [ ] On-screen piano with fade
- [ ] Note name display
- [ ] Scope view
- [ ] Recorder (BPM, count-in, quantise)
- [ ] Playback
- [ ] MY SONG chart port
- [ ] Flash: RDID, then read, then erase and program, then double-buffered save image with CRC
- [ ] Testbenches for debounce and the flash FSM

**C: Game engine**
- [ ] `chart_reader` covering ROM and MY SONG
- [ ] 24-slot active-note table
- [ ] Difficulty windows
- [ ] Combo multiplier
- [ ] Pause
- [ ] Count-in
- [ ] Hit flashes and judgement pop-ups
- [ ] Progress bar
- [ ] LED guide PWM
- [ ] Accuracy divider + grade
- [ ] Testbenches for judgement and divider

**D: UI, Learn, Control**
- [ ] Song select with best scores
- [ ] Settings
- [ ] High-score table
- [ ] Results animation
- [ ] Initials entry
- [ ] Hint bars
- [ ] Overlay (pause, SAVING, toasts)
- [ ] Theme, brightness and fades
- [ ] Learn mode with Listen-first
- [ ] 7-seg content per mode
- [ ] Testbench for the mode FSM

**Check:** every box ticked in **one** bitstream; resources logged after each merge.

### Phase 4: Integration loops (all)
- [ ] Record in Free Play → save MY SONG → play it in Play → learn it in Learn.
- [ ] Finish a song → NEW RECORD → initials → SAVING → reprogram the FPGA → score still shown.
- [ ] Settings change the instrument and volume (A), the note speed (C), and the theme and brightness (D) everywhere.
- **Check:** the 6-step demo script (prompt §8) runs with no hiccups.

### Phase 5: Harden and polish (all)
- [ ] Robustness tests (prompt §6): mash switches, long holds, mode change mid-song, 255+ note recording, power-off during save, no audio Pmod.
- [ ] Bring LUT use under 75% and keep timing met.
- [ ] Fresh-user test: someone new finishes a song unaided; fix every place they got stuck.

### Phase 6: Report and demo (each person writes their own section)
- [ ] Sheet A: group section plus 4 student sections, **≤ 500 words total** (about 80–90 each). Bold under 20%. Real OLED photos. Colours: team pink, A red, B blue, C yellow, D green.
- [ ] Sheet B: course feedback, and every reference and AI use (from `docs/REFERENCES_AND_AI_USE.md`).
- [ ] Each person rehearses their 15 Q&A answers (in their `docs/<X>_DESIGN.md`).
- [ ] Rehearse the demo end to end in under 5 minutes, and print 2 colour copies of the report.

## Rules for the whole team
1. **Never merge anything you can't explain line by line.** Q&A can score zero otherwise.
2. **Integrate early and often.** Four parts that each fit can still overflow the FPGA when combined.
3. **Interfaces are frozen.** Change `keylight_defs.vh` only with all four owners agreeing.
4. **Log every source and every AI use as you go**, not at the end.
5. **Only claim what works in the final bitstream.**
