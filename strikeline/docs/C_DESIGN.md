# Part C: pin physics, pin-setter and the ball result (Student C)

## Files
| File | What it does |
|---|---|
| `rtl/c_pins/pin_physics.v` | 10-pin register file, impulses, wobble/topple, sliding, walls, pit, 45-pair iterator, rack + rake |
| `rtl/c_pins/pin_settle.v` | When is the pin action over? Pins down this ball |
| `rtl/c_pins/split_detect.v` | Flood fill over the adjacency ROM |
| `rtl/c_pins/pin_render.v` | 10 parallel pin renderers, sprite symmetry, rake, debug tint |
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

## v3: pin action
- **Collision shape of a lying pin.** A fallen pin is 15 in long but collided as a 3.5 in circle at its *base*, so the ball and other pins hit it in the wrong place. `ccx/ccy` now place its collision circle 5 in along its fall direction (2.5 in while it is still falling) - for B's read port and for the pair iterator (one extra pipeline state).
- **Fall time from the push.** `fall_time = 150 − min((|dv| − TOPPLE) >> 8, 90)` ticks: a pin hit hard goes down fast, a nudged one topples slowly.
- **Gutter pins.** A slow pin (< 0.01 in/tick sideways) that slides off the lane edge drops into the gutter channel and stays there; a fast one reaches the kickback, which now returns it with e = 0.75 (was 0.5): livelier "messenger" pins.
- **No left/right bias.** The 45 pairs are walked 0→44 and 44→0 on alternate ticks (B does the same with its pin scan).
- **Spin.** B adds a small tangential kick along the contact tangent, signed by the ball's spin.
- **3-D renderer.** `pin_render` draws the pins for the VGA view: 16 silhouette sizes (`pin_fp.mem`, 512 × 4 bit) for standing pins, rounded bars with a red neck for falling and lying ones, nearest pin in front; the top-down sprites are unchanged for the OLED.

Carry map after v3 (`tb_carry`): pocket 6/8 strikes, nose 0/7, Brooklyn 1/9, light 2/4 (see B_DESIGN.md).

### v3 questions
16. **Where does a lying pin collide now, and why?** 5 in along its body, close to its centre of mass, because that is where the ball and the other pins actually meet it.
17. **Why alternate the pair order?** Each pair is resolved with the velocities left by the previous pairs; a fixed order always favours the same side of the rack.
18. **What happens to a pin in the gutter?** Slow: it drops into the channel (x = gutter centre, no sideways speed) and can no longer reach the deck. Fast: it bounces off the kickback.

## v3.4: footprint and no overlap
- **Two circles per lying pin (pin vs pin).** Belly: 3.5 in radius, 5 in from the base (v3's tuned messenger circle). Head: 2.4 in, 11.5 in from the base. Both at half the offset while the pin is still falling. A standing pin: one 2.4 in circle. `pcc(r, axis, sub)` gives circle `sub` of a record, as a **signed** 17-bit position. The pair iterator walks the circle pairs that exist (sp = {circle of i, circle of j}): 1 for standing + standing (skipped), 2 for standing + lying, 4 for lying + lying. Pins whose bases are more than 30 in apart are rejected after one look.
- **Push-out.** For an overlapping circle pair: |d| = d² · (2^14 / |d|) >> 14 (the normal's reciprocal ROM, one multiply), overlap p = (rA + rB) − |d|, then each lying pin moves p/2 + 1/64 in along the normal (p + 1/64 when the other one stands; a standing pin never slides). This is written together with the impulse, so pins can no longer sit inside each other.
- **Head hits.** A standing pin hit by a lying pin's head circle is struck high up; it topples at a quarter of TOPPLE.
- **One position for the views.** `pin_vis` reports a lying pin at the centre of its body (7.5 in from the base, half while falling), so the top-down sprite and the 3-D bar are drawn where the physics has it.
- **Measured.** `tb_physics` now checks every circle against every other: deepest overlap 3/64 in, never more than 1/4 in (outside the rake sweep, where the pin-setter drags pins together on purpose). `tb_carry`: pocket 4/8, nose 0/7, Brooklyn 3/9, light 0/4.

### v3.4 questions
19. **Why not make the lying pin true size (2.4 in all along)?** Measured: `tb_carry` dropped to 0 strikes from 8 pocket hits. In a flat 2-D model a lying pin cannot bounce or roll over its neighbours, so its belly circle stays at v3's 3.5 in to carry the action; the head circle is true size.
20. **How do you know pins never overlap?** The testbench recomputes every pin's circles each 4 ticks and records the deepest overlap and how long one lasts. It also found the unsigned-centre bug: a pin lying toward the gutter had a circle at x < 0 that wrapped to x = 1023 in.
