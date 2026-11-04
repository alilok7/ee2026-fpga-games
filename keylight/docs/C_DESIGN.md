# Part C: rhythm game engine (Student C)

*Status: vertical slice complete. Count-in, falling notes, judgement, score, combo, multiplier, pause, LED guides, progress bar, accuracy divider and grade all work and are tested. Phase 3 adds polish and MY SONG through the chart port.*

## Block diagram
```
chart_reader (ROM / MY SONG) --> note_loader: header, last event, then each event
                                   hit_ms = start*step_ms + lead (one shared multiplier)
song_clock: song_ms, song_step (tick_1ms, frozen by pause)
note_table (24 slots, one controller FSM):
   FRAME  per frame: y position of every note + per-lane time-to-next-note
   JUDGE  lane struck: earliest pending note within the Good window
   MISS   every ms: notes past the window become Miss
   LOAD   copy the next event into a free slot 4 s before it is due
judgements --> scorer (combo, multiplier, score; divider at the end) --> results
           --> game_top: flashes, pop-ups, burst, note events to A, SFX
note_table snapshot --> play_renderer (24 range checks per pixel)
lane_dt --> led_guides (time-shared 8x8 multiplier, PWM)
```

## Flow FSM (`game_top`)
`IDLE → LOAD (header) → RUN (count-in + song) → END (1 s) → SCORE (divider) → DONE`. Leaving Play mode clears every sub-module.

## Key decisions
- **One writer for the note table.** All four jobs run in one FSM, one slot per clock, so two jobs can never fight over a slot. A scan takes 24 clocks (0.24 µs).
- **Earliest pending note in the lane** is the target of a strike, so fast repeated notes in one lane are judged in order.
- **Shifts, not division,** for note position: `y = 54 − (Δms >>> speed_shift)`.
- **No divider per pixel:** the 24 y-positions are computed once per frame, between frames, so the renderer only compares.
- **The sequential divider** computes accuracy once per song (17 clocks).
- **Progress bar** uses a Bresenham accumulator: add 96 every ms, and each time the sum passes `total_ms` the bar grows one pixel. No divider.
- **Bug found by `tb_game`:** the loader drops `evt_valid` one clock after the table's take pulse, so every note was loaded twice. The fix is to not load in the cycle after a take.

## How this relates to what we learned
`song_clock` is two L2 counters, and `ms_in_step` rolls over like the lab's counters. `game_top` and `note_table` are L3 FSMs. The scorer's 0–9 counter is a modulo-10 counter (L2), used instead of a `%` operator.

## Tests
- `sim/c/tb_game.v` uses a model player that reads `songs.mem` itself: perfect play (all Perfect, score 8800 for Twinkle, 100 %, S), zero hits (all Miss, D), pause and abort, stray strikes, and the ±70 / 35 / 130 ms judgement windows.
- `sim/c/tb_divider_seq.v` runs 2000 random divisions.

## Likely assessor questions (to complete: 15)
1. *How is a Perfect decided?* |strike time − hit time| ≤ 40 ms (60 on Easy, 30 on Hard), with the 5 ms debounce delay removed first.
2. *What if two notes in one lane are close together?* The earliest pending one inside the window is judged first.
3. *What limits the table?* 24 notes within the 4 s look-ahead. If it is full, the loader waits.
4. *Why compute positions per frame?* That way the renderer only compares, with no subtract or shift per pixel. Updating between frames also stops tearing.
5. …
