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

## v3: slip-based hook, steer window, VGA 3-D view
**Why it changed.** The v2 hook was a constant sideways force for a fixed time (256 + 96·|spin| ticks) starting exactly at the oil line, with `vx -= floor(spin·gain/16)`. The floor made negative spins hook ~1 LSB/tick² harder than positive ones (left and right hooks were not mirror images), spins +1..+3 gave no hook at all in the oil, and only 7 spin levels existed.

**Ball and floor (slip model).** At release the spin becomes a store of side slip `REV = |spin| · rev_k` (`ball_params.mem`, per ball weight: lighter balls rev up easier). Each tick the lane can take at most `mu` out of it:
```
a = min(mu(x, y), REV);   REV -= a;   vx -= a (spin > 0 hooks left);   vy -= dec + a/2
```
`mu` comes from `oil_pattern.mem` (1024 × 8 bit, address {long oil, y/16 in, |x−30|/4 in}): ~1 in the oil, a 72 in smooth-step transition, 44 on the dry back end and the deck; the oil is 18 in shorter per 4 in toward the edges (a "house shot"). Phase = SKID while `mu` is oily, HOOK while slip is left on dry wood, ROLL once `REV = 0`. Consequences that fall out of the physics: the breakpoint moves with speed (a faster ball spends fewer ticks in the oil, so it hooks later and less: checked), a big-rev ball can still be hooking on the deck, and +spin / −spin are exact mirror images (only magnitudes are used; checked to 1/64 in).

**Steer window ("body English").** For `STEER_TICKS` = 512 ticks (0.5 s) after release, A passes every mouse packet's sideways motion (`steer_valid`, `steer_dx`); B adds `clamp(dx, ±64) · 8` LSB to vx, with a total budget of ±1536 LSB (about 3.5 boards by the pins). Checked: 1-5 boards, never more.

**Ball → pin (v3).** kp / kb from the masses only (the v2 `kb_eff` "drive" broke momentum and is gone); a tangential friction kick `|spin| · 6/4096` of the normal impulse along t = (−ny, nx); a lying pin gets an impulse every tick the ball still drives into it (an upright pin once per contact, as before); the speed floor is 1 mph on the deck (3 mph on the lane); the 10 pins are scanned 0→9 and 9→0 on alternate ticks; every final shift rounds toward zero (`sra0`).

**Camera (v3).** The 3-D camera follows the ball to 80 in short of the head pin (640 in) and watches the pin action from there; the low-pass filter makes the move glide. The lead is divided by 4 in slow motion (v2 ran ~27 in ahead of a slow-motion ball).

**Zoom (v3.1, right button held).** A dolly zoom of the first-person camera, replacing v3's PIN VIEW (which flew the camera to 660 in and had to be left before a throw). `camera.v` glides a zoom level `zl` 0..255 by 12 per frame. Row r of the view is at distance K / r, and one inch across the lane is r / 51 px there, whatever K is. So zooming only changes K: K = 3060 + 84·zl (×1..×8), sent to `persp_proj` as `k_fp` (it divides K by the distance instead of the constant). `lane_render` scales the row distance from `persp_v.mem` by (256 + 7·zl) / 256, the same ratio, with one multiply. At the same time the camera backs off zl inches (`cam_fp = cam_base − zl`). The ball is then 40 + zl in ahead, which is always beyond K / 89 (the bottom row), so it stays at rows 106..113 while the head pin grows from about 1 px to about 7 px tall. `zl`, `k_fp` and `cam_fp` are registered from the same `zl` in the same clock, so the projector, the lane and the guide never disagree. The projector now also culls an object whose row would be below the screen (`r > 90`), which a long lens can produce more than 35 in away.

Q: *Why a dolly zoom and not just a longer lens?* A longer lens alone pushes the bottom of the screen further away (K / 89 in): at ×8 that is 275 in, so the ball would leave the screen. Backing the camera off by the same amount keeps the ball, the whole dotted line and the pins in one picture, like a TV camera behind the bowler.

**VGA 3-D view.** Same camera maths at twice the resolution: horizon on row 30 of 160 × 120, lane centre column 56, `dist = 3060/(y−30)`, `inv = 51·256/(y−30)` (`persp_v.mem`, 128 × 27 bit). `persp_proj` now projects every pin on the deck (standing pins as silhouettes in 16 sizes; falling / lying pins as bars along their fall direction), and `ball_render` draws a shaded sphere with a shadow and finger holes scaled to its radius. The lane renderer adds the masking unit, range finders, and the dotted aim guide (stance → wheel-chosen target at 16 ft → pins).

### v3 tuning log (`tb_physics`, `tb_carry`, 16 lb unless noted)
| Measure | v2 | v3 |
|---|---|---|
| medium hook after the oil line | spin 4: 8.7 boards | spin 16 of 31: 13 boards |
| hook for spin 4 / 16 / 31 (from 42 in) | 7 levels only | 5.4 / 14.8 / 21.8 in |
| 20 mph vs 16 mph, spin 16 | same hook | 10.4 in vs 14.8 in |
| long oil, spin 16 | < 8 boards | 9.7 boards (short oil 13.5) |
| carry map strikes: pocket / nose / Brooklyn / light | 5/9, 0/4, 1/3, 0/12 | 6/8, 0/7, 1/9, 2/4 |
| `rev_k` 12 / 14 / 16 lb | - | 1250 / 1150 / 1080 (first try 1400 / 1300 / 1220 hooked 14.6 boards) |
| tangential kick per spin level | - | 6/4096 (24/4096 pushed the 3 pin away from the 6: pocket 2/8) |

Light hits (entry 34.5-36 in, just outside the pocket window) now carry 2 of 4, so that target was relaxed from ≤ 30 % to ≤ 50 %; the team may want to retune it with real players.

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

### v3 questions
16. **Why a slip store instead of a hook timer?** Real balls hook until their side rotation matches the lane ("roll out"). REV is that rotation; friction converts it into sideways speed at most `mu` per tick. The breakpoint, the speed dependence and the hook on the deck all follow from that one rule.
17. **Why are left and right hooks now identical?** All hook arithmetic uses magnitudes and the sign is applied last; v2 used an arithmetic shift of a signed product, which rounds toward −∞.
18. **What is the oil pattern ROM?** 2 × 48 × 8 friction values (oil length, 16 in rows, 4 in columns from the centre), made by `gen_tables.py` with a smooth-step from oil to dry.
19. **How is the steer window bounded?** It lasts 512 ticks, each packet is clamped to ±64 counts, and the total added vx is clamped to ±1536 LSB.
20. **How do pins appear in front of or behind the ball in 3-D?** Both renderers output the screen row of what they draw (`depth`); the compositor draws the pin when its row is larger (nearer the camera).
