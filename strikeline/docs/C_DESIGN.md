# Part C: pin physics, pin-setter, the ball result and screen 2 (Student C)

## Files
| File | What it does |
|---|---|
| `rtl/c_pins/pin_physics.v` | 10-pin register file, impulses, wobble/topple, sliding, walls, pit, 45-pair iterator, rack + rake |
| `rtl/c_pins/pin_settle.v` | When is the pin action over? Pins down this ball |
| `rtl/c_pins/split_detect.v` | Flood fill over the adjacency ROM |
| `rtl/c_pins/pin_render.v` | 10 parallel pin renderers, sprite symmetry, rake, debug tint |
| `rtl/c_pins/screen2.v` | v3: the second OLED. Picks the page, mixes the layers, own text engine, brightness, output register |
| `rtl/c_pins/deck_panel.v` | v3: screen 2 live pin diagram, DOWN / STANDING counts, SPLIT!, Spare Challenge header |
| `rtl/c_pins/switch_panel.v` | v3: screen 2 help page: every switch, green when up, and the buttons |
| `text/screen2_strings.txt` | v3: screen 2's words → `data/screen2_strings.mem`, `rtl/c_pins/screen2_map.vh` |
| `tools/gen_tables.py` | `pin_spots.mem`, `pin_pairs.mem` (45 pairs), `pin_adj.mem` |
| `tools/gen_sprites.py` | `pin_sprites.mem` (N and NE, 3 fall stages) and a text preview |

## Pin state
Each pin has x, y (Q10.12), vx, vy (Q3.16), a state, a fall direction (8-way) and a timer.
```
STANDING --weak hit--> WOBBLING --0.4 s--> STANDING            (a "wobbler")
STANDING / WOBBLING --hit > TOPPLE--> FALLING --0.15 s--> DOWN  (slides with friction)
FALLING / DOWN --past the deck end--> OFF (in the pit)
```
- **Topple threshold:** 1300 in Q3.16, about 0.02 in/tick (1.2 mph) of velocity change. The same value is used for ball hits and pin hits, measured with the "octagonal norm" `max + min/2` (within 12% of the true length, no multiplier).
- **Fall direction:** the octant of the push (compare |vx| with 2|vy|).

## Per tick (after B's `scan_done`)
1. **UPDATE** (1 pin per clock): wobble/fall timers; sliding pins move `x += v`; friction `v −= v >> 8` (time constant 0.25 s); |v| below a small threshold becomes 0; kickback walls reflect with half speed; pins can't slide back past 700 in; past 756 in they go OFF.
2. **PAIR ITERATOR:** pairs 0..44 from the pair ROM, one at a time:
   - skip if either pin is OFF, both are upright, or a 9 in box test fails
   - `|d|² <` contact distance². An upright pin is a 2.4 in circle; a falling/fallen pin collides as a **4.0 in circle** because it is 15 in long and sweeps much more of the deck. Without this, a head-on ball knocked only 4 pins; with it, a head-on ball gives realistic pin action and the pocket strikes.
   - normal from a constant reciprocal (as in B)
   - `v_rel_n = (v_i − v_j)·n`; if > 0, an equal-mass collision along the normal: `Δ = (1+e)/2 · v_rel_n = 0.8125 · v_rel_n` (e = 0.625), computed as `x − x/8 − x/16` (shift-add); `v_i −= Δn`, `v_j += Δn`
   - an upright pin that receives Δ: topple test as above
   - overlapping but not approaching: push apart 1/64 in per tick, so pins can never lock together (the test checks that no overlap lasts 2 s)
3. **Cycle budget:** 10 + 45 × 4 (all far) up to 45 × 17 (all touching), at most about 800 clocks of 97 656.

## Register file structure (resource squeeze)
The 10 pin records (99 bits each: x, y, vx, vy, state, direction, timer) are written through **exactly two write ports**, A and B, because at most two pins change in one clock (one pin in UPDATE or for a ball impulse, both pins of a pair in the pair iterator). There are also three whole-rack operations: rake, placement, and the settle timeout. Each record bit therefore has a 4-input multiplexer. The first version wrote the arrays from about 8 places, with the hit logic inlined three times, and used 5 714 LUTs. The same behaviour now passes the same 21 checks in far fewer LUTs (see the resource log in INTERFACES.md).

## Tuning log (v2, measured by `sim/b/tb_carry.v`)
The carry test throws a grid of start boards × spin × speed and classifies each ball by where it enters the head-pin row: pocket (hooking into 1-3), nose (dead centre), Brooklyn (wrong side), light (outside the pocket). Real bowling: pocket hits usually strike, the others usually do not.

| Version | Pocket | Nose | Brooklyn | Light | Note |
|---|---|---|---|---|---|
| v1 (lying pin 4.0 in, topple 1300) | 1/3 | 3/3 | 2/4 | 4/6 | everything strikes: unrealistic, plus the unsigned bug |
| bug fixed, 4.0 in / 1300 | 1/4 | 0/3 | 2/3 | 0/6 | |
| 3.0 in / 2200 | 2/4 | 0/3 | 1/3 | 0/6 | |
| pocket-focused, 3.5 in / 2200 | 4/5 | 0/1 | — | 0/12 | chosen |
| **final (3.5 in, topple 2200 ≈ 2 mph), full test** | **5/9** | **0/4** | **1/3** | **0/12** | test limits: ≥ 50 %, ≤ 40 %, ≤ 50 %, ≤ 30 % |

The knobs are module parameters of `pin_physics` (`R_DOWN`, `TOPPLE_P`, `FRIC_SH`, `DL_S1/DL_S2`) and `ball_physics` (`R_DOWN`), so a tuning experiment needs no code change. Pin-pin momentum is now checked on every collision in `tb_physics` (46 collisions, 0 errors).

## Settle detector (`pin_settle`)
After the throw: wait until the ball is in the pit, then until **every pin is quiet** (no wobbling, no falling, all stopped) for 0.5 s. A **4 s timeout** after the ball reaches the deck forces wobblers upright and fallen pins still. Then it reports `pins_down = popcount(standing_before & ~standing)` and starts the split detector.

## Split detection
Rule: the head pin is down and the standing pins form 2 or more groups that don't touch (neighbours are 12 in apart). It's a flood fill from the lowest standing pin, `reach |= neighbours(reach) & standing`, one step per clock, at most 4 steps. Any standing pin not reached means a split. The test confirms 4-6 is a split and 4-5 isn't. 7-10, 5-7 and 3-10 (baby split) are splits; the bucket and 3-6-10 are not.

## Pin-setter
Every rack command first runs the **rake**: a bar moves from 700 to 770 in (1/8 in per tick, 0.55 s) and pushes every pin that isn't standing into the pit. Then:
- FULL: all 10 pins on their spots
- SWEEP: only the standing pins stay
- LEAVE: exactly `rack_mask` (Spare Challenge)

Commands are latched, so a `rack_go` that arrives during the pair iterator can't be lost.

## Renderer
10 identical per-pin renderers (generate loop) run in parallel and are then priority-picked: upright pins first (they stand taller), lowest number first.
- Upright pin: a 5×5 pattern (white disc, red neck ring). Wobblers are drawn 1 px to the side every other 4 frames.
- Fallen pin: a 16×16 sprite. **Only N and NE are stored.** The other directions are mirrors and x↔y swaps of the pixel offset: E = N(oy, −ox), S = N(ox, −oy), W = N(oy, ox), SE = NE(ox, −oy), SW = NE(−ox, −oy), NW = NE(−ox, oy). The ROM is 4× smaller, so 10 parallel copies fit, and there are no overlap artefacts.
- `led[9:0]` show `standing`.

## Screen 2 (v3): the scoreboard OLED
Before v3 the scorecard was drawn **over** the lane on the only OLED. In v3 a second Pmod OLED (on **JXADC**, the left-edge header; the manual forbids two OLEDs on the same side of the board) works like the monitor above a real bowling lane:

| Page | When | Top (y 0-35) | Bottom (y 36-63) |
|---|---|---|---|
| SCORE | in a game, game over, initials | D's scorecard (`scorecard_render`, unchanged), or the Spare Challenge header | live pin diagram + counts (`deck_panel`) |
| SWITCHES | menus; in a game while btnD / right-click is toggled on | whole screen: `switch_panel` | |

How it works, step by step:
1. **Same pixel on both screens.** Both `Oled_Display` instances use the same 6.25 MHz clock and the same reset. Their state machines are identical, so at every moment they ask for the same `pixel_index`. Screen 2 therefore reuses screen 1's `px_x`, `px_y` (no second `pixel_xy`). `tb_screens` checks this on every sampled pixel.
2. **Layers.** Each panel answers "do I draw this pixel (en), in which colour, and do I want a character here (text request)". `screen2` picks the page, then the layer for the pixel's region.
3. **Own text engine.** Screen 2 instantiates D's `text_engine` a second time with its own 512-entry string ROM (`STR_FILE`, `STR_AW` parameters), so the two screens never wait for each other. The scorecard's digits are literal glyphs, so they work with either ROM.
4. **Brightness.** The same 4 levels as screen 1, from the Settings menu.
5. **Output register.** Exactly like D's compositor: the colour is stored 6 clocks after `px_x/px_y` stop changing; the XDC gives `u_scr2/oled_data_reg` a 6-clock multicycle.

Pin diagram colours: white = standing, red = knocked down by this ball (`standing_before & ~standing`), grey = already down before this ball. DOWN counts up live while pins are falling. Text grid (3x5 font): column = (x − x0) >> 2; row = (y − 2) / 6 computed as `(n * 43) >> 8` (exact for n < 128), no divider.

## How this relates to the lectures
- FSMs and sequential scheduling (L3/L4): the pin FSM is an iterator walking a ROM schedule; settle is a small FSM with two timers; split detection is an iterative FSM.
- Counters (L2): wobble and fall timers, quiet and timeout counters, the rake position.

## 15 likely questions
1. **How many cycles does your pair iterator need?** 4 clocks per far pair, about 17 per touching pair, so at most about 800 per tick of 97 656.
2. **Why not check all 45 pairs in parallel?** 45 multiplier pairs would not fit (90 DSPs, all the LUTs), and one pair per few clocks is fast enough.
3. **Explain the pin–pin collision maths.** Equal masses: only the velocity component along the normal changes. Each pin gets (1+e)/2 of the relative normal velocity, in opposite directions.
4. **Why 0.8125?** e ≈ 0.6 (pins are lively), so (1+e)/2 ≈ 0.8. 0.8125 = 1 − 1/8 − 1/16 is two shifts and two subtracts.
5. **How did you choose the topple threshold?** A pin tips when its base is pushed at roughly 1 mph. Lower made every pin topple from a breeze; higher made "solid 10s" too common.
6. **What is a wobbler?** A pin hit softly. It rocks for 0.4 s and stays standing; its velocity is discarded (the base friction absorbs it).
7. **Why do fallen pins have a bigger collision radius?** They are 15 in long and sweep the deck as they tumble. With only 2.4 in, a head-on ball knocked only 4 pins.
8. **How do you stop pins sticking together?** Overlapping, non-approaching pairs are pushed apart by 1/64 in per tick. The test checks that no overlap lasts 2 s.
9. **How do you know the pins have stopped?** Every pin must be quiet for 0.5 s after the ball is in the pit, or a 4 s timeout fires after the ball reaches the deck.
10. **How is "pins down this ball" counted?** It's a popcount of standing at the throw AND NOT standing now.
11. **Explain the split algorithm.** Flood fill from the lowest standing pin through the adjacency ROM. Any standing pin not reached is a second group, and with the head pin down that is a split.
12. **What does the rake do?** It pushes every non-standing pin in front of it into the pit, then the rack command places the pins.
13. **How do you draw 8 fall directions from 2 sprites?** Mirror and swap the pixel offset before the ROM lookup. It's just wiring, no extra logic.
14. **Why are the pins drawn in parallel and not one after another?** The colour must be ready within 6 clocks of the pixel position, so all 10 tests run at once and a priority encoder picks one.
15. **How do your LEDs work?** `led[9:0] = standing`, one per pin, updated live as pins fall.

Screen 2 (v3):

16. **How do two OLEDs show different pictures with one `pixel_xy`?** Both drivers get the same clock and reset, so they request the same pixel index at the same time. One x/y, two colour pipelines: D's compositor for JC, my `screen2` for JXADC.
17. **Why JXADC and not JA or JB?** The manual says two OLEDs on the same side of the board physically interfere and lose marks. On the Basys3, JA and JB are on the same side as JC; JXADC is on the opposite edge. Its pins are normally the analog (XADC) inputs, but they are ordinary FPGA I/O pins too, so used as LVCMOS33 outputs they drive the OLED exactly like JC.
18. **Why a second text engine instead of sharing D's?** Both screens need a character for the same pixel in the same clock. Sharing would mean time-multiplexing inside the 6-clock window. A second copy with a 512-entry ROM is small (about 150 LUTs) and simple.
19. **How do you count pins down live?** `knocked = standing_before & ~standing`, then a 10-step adder loop (popcount). It is combinational, so it changes the moment a pin falls.
20. **How do you divide by 6 for the text rows?** `n / 6 == (n * 43) >> 8` for every n < 128; 43 is a constant, so it is a few adders, not a divider.
21. **How does the switch page know a switch is up?** It reads the debounced `sw_level` directly; row k of the left column is `sw_level[k]`, of the right column `sw_level[11 + k]`.
