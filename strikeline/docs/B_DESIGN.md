# Part B: ball physics, lane and camera (Student B)

## Files
| File | What it does |
|---|---|
| `rtl/b_ball/ball_physics.v` | Phase FSM, oil/dry friction and hook, gutter, ball→pin collisions (impulses to C) |
| `rtl/b_ball/camera.v` | Low-pass camera with speed lead |
| `rtl/b_ball/ball_trace.v` | 64-row path memory for the minimap (LUTRAM, cleared one entry per clock on a new throw) |
| `rtl/b_ball/lane_render.v` | Lane, oil sheen, arrows, deck, pit, gutters, kickbacks, themes, minimap |
| `rtl/b_ball/ball_render.v` | The ball, rotating finger holes, debug vectors (`sw[2]`) |
| `rtl/top/timebase.v` | Every tick of the design, including `tick_phys` (1024 Hz, slow motion, pause) |
| `rtl/top/mul_s25x18.v` | The shared multiplier (one instance per part) |
| `tools/gen_tables.py` | `ball_params.mem` (per oil × weight), `ball_marker.mem` (sin/cos offsets) |
| `sim/b/tb_physics.v` | B + C together, 20 checks |

## Ball phase FSM (once per `tick_phys`)
```
IDLE --throw--> SKID --(y >= oil length)--> HOOK --(640 ticks)--> ROLL --(y >= 760 in)--> PIT
                  \___________ centre past a lane edge, before the deck ____________/--> GUTTER --> PIT
```
- **SKID:** `vy -= dec_oil` (8), `vx -= spin × hook_oil / 16`. The ball barely reads the lane.
- **HOOK:** `vy -= dec_dry` (24), `vx -= spin × hook_dry / 16`. The spin turns into sideways acceleration.
- **ROLL:** the spin is used up and the ball keeps its final direction.
- **GUTTER:** x snaps to the channel centre, vx = 0, and the ball can no longer touch pins.
- The speed never drops below 3 mph, so every ball reaches the pit and the game can never stall.

Why the hook starts at the oil line: oil makes the lane slippery, so the ball skids and the spin does almost nothing. On the dry back end the friction is high, and the spin pushes the ball sideways. That is why real balls hook late. A longer oil pattern (45 ft) gives less dry lane, so it hooks less.

## Tuning log (from `tb_physics`, 16 lb, 16 mph, start board 12 from the right)
| Version | Oil drift | Dry hook | Note |
|---|---|---|---|
| gains 1 / 7 (LSB) | 6 boards | 17 boards | far too strong: the oil gain needed finer units |
| gains 4 / 66 (1/16 LSB) | 1.5 boards | 7.6 boards | just under the 8–12 board target |
| **gains 4 / 76 (16 lb), 80 (14 lb), 88 (12 lb)** | **1.5 boards** | **8.7 boards** | spin-4 hook ball from board 42 = strike |

## v2 physics changes (Phase B)
- **Bug fixed (was in v1):** `relx <= vx[23:8] - pin_vx` - a part-select is *unsigned* in Verilog, so a ball moving left (every left hook) had a huge positive relative speed, the contact maths saw "separating" and the ball slid through pins. Now `$signed(vx[23:8])`. Found by tracing one pocket hit pin by pin (the 1 pin was never touched).
- **True normal:** `n = d * inv_len[d^2 >> 12]` (128-entry 1/|d| ROM) instead of a fixed 1/6.7 in, so impulses stay right when the ball meets a pin already overlapping.
- **Lying pins** have the same footprint for the ball as for other pins (3.5 in).
- **Hook length** grows with the revs: 256 + 96 × |spin| ticks (spin 4 = 640, as before).
- **Hooking costs forward speed:** the forward deceleration grows by the hook acceleration.
- **Drive:** a spinning ball deflects less: `kb × (1 − |spin| / 16)`.

## Ball → pin collision (per pin, sequential, one multiplier)
1. Quick reject: `|dx|` or `|dy|` > 7 in, skip (no multiply).
2. `|d|² = dx² + dy² < (Rb + Rp)² = (6.7 in)²`. Squares, so **no square root**.
3. Normal `n = d × (1 / 6.7 in)`, a constant reciprocal. At first contact |d| is within one tick of travel (about 6%) of 6.7 in, so no divider is needed.
4. `v_rel_n = (v_ball − v_pin) · n`. If ≤ 0 they are already separating, so no impulse.
5. Pin Δv = `kp · v_rel_n · n`, ball Δv = `−kb · v_rel_n · n`, with `kp = (1+e)·mb/(mb+mp)` and `kb = (1+e)·mp/(mb+mp)` from the ROM. Momentum is conserved because `mb·kb = mp·kp`. The testbench checks it to within 6%.
6. A per-pin "touching" flag gives one impulse per contact. It clears when the pin is 0.2 in further away.

Cycle budget: 4 clocks per tick for integration, 4 per near pin, about 20 per hit pin. Worst case is about 200 clocks out of 97 656.

## First-person view (v2)
- While aiming and rolling the OLED shows the lane from behind the ball; the pin action cuts to the overhead deck camera (TV-style). sw4 forces the classic top-down view.
- **No 3-D maths:** the camera has a fixed height and tilt, so screen row y always looks at the same distance ahead, `dist = 1530 / (y - 12)` inches (horizon on row 12), and one inch across is `(y - 12) / 51` px there. `persp.mem` stores `dist` and `inv = 51*256/(y-12)` per row; a lane pixel is at `world y = cam_fp + dist[y]`, `world x = 30 + (px - 30) * inv[y] >> 8` (one multiply). The existing lane "texture" (boards, oil, arrows, deck) is then evaluated at that point unchanged. Boards are only drawn where 1 in ≥ 0.5 px (no shimmer far away).
- `persp_proj.v` projects the ball and the 10 pins once per frame (row = 12 + 1530/dz, x = 30 + (wx-30)·r/51) with one sequential divider (~220 clocks per frame); `ball_render` draws a circle of the projected radius, `pin_render` (C) draws pin silhouettes from a 128-entry size-class ROM.
- The first-person camera sits 40 in behind the ball with the same low-pass filter and speed lead as the overhead camera.

## Camera
`cam += (target − cam) >> 3` once per frame is a first-order low-pass filter. On its own it would lag a ball moving at 5 in/frame by 40 px (the ball would sit at the top of the screen). So the target includes a **lead** of the same size, `vy >> 5` (8 frames × 17 ticks/frame × vy), and the ball stays near the bottom with the lane ahead in view. Targets: −12 while aiming (foul line visible), the ball while rolling, 700 during pin action (whole deck). Clamped to [−40, 700].

## Fixed point
Internal x, y are unsigned Q10.20 (30 bit); vx, vy are signed with 1 LSB = 2^-20 in/tick (24 bit). The finest step, 8 LSB of friction per tick, is 0.035 mph lost per second. VEL Q3.12 would round it to 0. Exported as POS Q10.6 = x[29:14] and VEL Q3.12 = v[23:8].

## Lane renderer
Pure combinational: world y = `cam_y + 63 − py` and world x = px. Then a chain of zone tests: approach, foul line, boards (alternating tones), oil sheen (a moving highlight pattern while y < oil length), 7 arrows in a V at 14.5–16 ft, dots at 7 ft, deck from 708 in with the 10 spots, pit from 756 in, gutters, kickback walls. The neon theme swaps the palette. The minimap is 1 px per 12 in along the lane and 6 in across (stretched so a hook is visible). It shows the path, the ball, the visible window and a schematic of the standing pins.

## How this relates to the lectures
- Counters with enables (L2): `timebase` builds every tick from the 100 MHz clock (Lab 4 clock-divider idea, used as enables).
- FSM (L3): the phase FSM, plus a micro-sequenced datapath FSM that steps the shared multiplier.
- Beyond the course: fixed-point physics, impulse-based collisions, a low-pass filter.

## 15 likely questions
1. **What is your fixed-point format and why?** Positions Q10.20 and velocities 2^-20 in/tick internally, so friction steps of 8 LSB per tick still register. Exported as Q10.6 / Q3.12.
2. **Can anything overflow?** Speeds are clamped to 3–22 mph (well inside ±8 in/tick) and positions stay below 1024 in. Products are 43-bit in the DSP and only the needed bits are kept.
3. **Walk me through the phase FSM.** SKID → HOOK at the oil line → ROLL after 640 hook ticks → PIT at 760 in, or GUTTER when the centre passes a lane edge before the deck.
4. **Why does the hook start at the oil line?** In oil the friction is tiny and the spin can't grip. On the dry back end it grips and pushes the ball sideways.
5. **How do you detect a ball–pin collision without a square root?** Compare the squared distance with the squared contact distance.
6. **And the normal without a divide?** Multiply by a constant 1/6.7 in. At first contact the distance is within 6% of 6.7 in.
7. **Why test v_rel·n > 0?** Only approaching bodies collide. It, plus the touching flag, prevents double impulses.
8. **Show that momentum is conserved.** Pin gets J/mp, ball gets −J/mb with the same J, so mb·Δvb + mp·Δvp = 0. `kp` and `kb` come from one ROM line. The test checks it to within 6%.
9. **How many multiplies per tick, and why one multiplier?** About 2 + 4 per near pin + 10 per hit. There are 97 000 clocks per tick, so one DSP used one product per clock is plenty and saves DSPs and LUTs.
10. **Why 1024 Hz?** Per-second constants become shifts, and the ball moves only 0.3 in per tick, so contacts are never skipped.
11. **What does slow motion do?** `timebase` passes 1 of every 4 physics ticks. The physics code is unchanged.
12. **Explain the camera.** A first-order filter, `cam += (target − cam) >> 3`, with a speed lead so the steady-state lag is cancelled.
13. **How is the ball drawn?** A range check `dx² + dy² ≤ 18` (|dx| ≤ 4, so the square is a 5-entry table), lit from the top left. Finger holes come from a 64-entry ROM indexed by the spin angle.
14. **How does the first-person view work without 3-D maths?** Fixed camera height and tilt → each screen row is at a fixed distance (1530/(y-12) in); a ROM gives that distance and the lateral scale per row, one multiply gives the lane x. Objects: row = 12 + 1530/dz, one divider for 11 objects per frame.
15b. **How does the oil setting change the game?** It moves the SKID→HOOK boundary from 40 to 45 ft: less dry lane, a smaller and later hook (checked in the test).
15. **What happens if a ball is in the gutter?** It snaps to the channel centre, can't touch pins, rolls into the pit and scores 0. D shows GUTTER.
