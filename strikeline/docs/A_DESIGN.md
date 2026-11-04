# Part A: mouse input and gesture recognition (Student A)

## Files
| File | What it does |
|---|---|
| `rtl/a_gesture/mouse_setup.v` | MouseCtl setup FSM, movement deltas, sensitivity, cursor, button edges |
| `rtl/a_gesture/swipe_capture.v` | Stance, grab/release FSM, 200 Hz sampling, 64-entry ring buffer, 4-tap filter, live power, trail |
| `rtl/a_gesture/gesture_features.v` | Speed, aim and spin from the ring, validation. One shared multiplier and one divider. |
| `rtl/a_gesture/div_seq.v` | Restoring divider, 1 bit per clock |
| `rtl/a_gesture/swipe_lab_plot.v` | Draws the raw and filtered path into a 64×64 BRAM bitmap (Swipe Lab) |
| `rtl/a_gesture/gesture_render.v` | Trail, target line, stance marker, meters, labels, Swipe Lab screen, cursor, `led[15:10]` |
| `tools/gen_tables.py` | `speed_curve.mem` (64 entries) |
| `sim/a/tb_gesture.v` | 15 checks with synthetic swipes |

## Block diagram
```
MouseCtl --xpos/ypos/new_event--> mouse_setup --delta, buttons--> swipe_capture --ring--> gesture_features --throw--> B, D
             ^ setx/sety (re-centre)      \--cursor--> D menus, A cursor        \--trail, power--> gesture_render
                                                                               \--ring--> swipe_lab_plot --bitmap--> gesture_render
```

## Design decisions
1. **Deltas, not positions.** MouseCtl clamps its position to [0, max]. A forward flick is about 1000 counts (8 counts/mm), so a 256-count screen range would saturate halfway through the swipe and the measured speed would drop. `mouse_setup` sets the maximum to 4095 and the position to 2048. After every packet it reads `pos − 2048` and puts the position back to 2048. A packet moves at most ±255, so nothing ever clamps. MouseCtl writes the position in packet bytes 2/3, about 2 ms before `new_event`, so the read and the re-centre never collide with an update. (This replaces the brief's "4× virtual range" idea, for the reason above.)
2. **Cursor in quarter pixels** (0..383 × 0..255) for sub-pixel smoothness. Sensitivity scales the deltas by ×0.5, ×1, ×1.5 or ×2, all shifts.
3. **Sampling at 200 Hz** into a 64-entry ring (320 ms). MouseCtl reports at only 40 Hz (`SAMPLE_RATE = 0x28`), so the raw samples are a staircase. The 4-tap moving average `(s0+s1+s2+s3) >> 2` turns it into a smooth path.
4. **Speed = peak 80 ms forward motion in the last ~120 ms**, not "the last 40 ms". 40 ms is less than two mouse packets, and players often stop just before letting go. The index `motion >> 3` reads a concave ROM curve, 10–22 mph.
5. **Aim = whole-swipe ratio** `|dx| × 256 / forward` from the divider. A dead zone of about 6° counts as straight, and the gain is low (45° gives a 1.6° launch), because a 1° error already moves the ball 12 in at the pins. This is what lets a stranger throw a strike.
6. **Spin = signed sum of cross products** of successive filtered velocities. For a constant speed each term is |v|²·sin(turn), so `turn = C × N / E` (E = Σ|v|²) is the total turn in radians, independent of speed. **Zero-velocity samples are skipped**: one sample in five does not move (40 Hz packets), and a zero vector would break the chain of turns. Testing showed a constant −15 bias per packet before this fix. Quantised: under 0.125 rad is straight, then one level per 0.0625 rad, up to 7. A curve to the left gives positive spin and a left hook ("what you draw is what you get").
7. **Stance by buttons (v2):** btnL / btnR move the stance exactly one board (precise aim without mouse jitter); moving the mouse takes over again.
8. **Robustness:** right-click cancels; holding for more than 3 s cancels (covers an unplugged mouse); fewer than 4 samples means "too short"; grabs are only accepted in AIM / Swipe Lab.

## FSMs
- `mouse_setup`: MAX → CENTRE → RUN → (new_event) WAIT 4 clocks → READ (delta, re-centre) → OUT → RUN.
- `swipe_capture`: IDLE ↔ GRABBING (press on the lane / release, right-click or timeout).
- `gesture_features`: IDLE → FIRST → LAST → peak loop (PK_A/PK_B) → spin loop (SP_RD, SP_CHK, M1..M6) → CHECK → AIM (divider, multiply) → SPIN (multiply, divider) → OUT. About 600 clocks (6 µs).

## Fixed point
Ring values are mouse counts (16-bit signed). `throw_vy`/`throw_vx` are VEL Q3.12 in/tick. The aim ratio is ×256, the turn is radians ×256. Products use the 25×18 DSP (`mul_s25x18`, one instance for the whole part).

## Resources (A)
One DSP48 (shared multiplier), the ring buffer (64 × 64-bit LUTRAM), and the Swipe Lab bitmap (4096 × 2 bit, 1 BRAM18). See `INTERFACES.md`, resource log.

## How this relates to the lectures
- Counters and enables (L2): 200 Hz sampling uses `tick_sample`; the timeout and trail fade are counters.
- Shift registers (L1): the 32-point trail is a shift register, and so is the filter history.
- FSMs (L3): mouse_setup and the grab FSM are state register + next-state logic + outputs.
- Beyond the course: fixed-point arithmetic, the restoring divider, and the cross-product curvature measure.

## 15 likely questions
1. **How does the PS/2 mouse reach your code?** MouseCtl (provided, VHDL) talks PS/2 and gives an absolute position and buttons. I use it as a delta source: read `pos − 2048` after each packet, then set the position back to 2048.
2. **Why not just use xpos/ypos?** They clamp. A fast flick moves about 1000 counts, the screen is 256 counts tall, and the speed would stop increasing halfway.
3. **Why sample at 200 Hz if the mouse reports at 40 Hz?** Fine timing of the release, and the moving average turns the 40 Hz staircase into a smooth path.
4. **Explain the moving-average filter.** It keeps the last 3 raw samples. Filtered = (current + 3 old) >> 2, a shift instead of a divide by 4.
5. **How is speed measured?** The largest forward motion over any 16 samples (80 ms) during the last ~120 ms. `>> 3` gives an index into a 64-entry ROM curve (mph and VEL).
6. **Why the peak and not the last 80 ms?** People stop the mouse a moment before letting go. The last window would read nearly zero.
7. **How is aim computed without floating point?** `|dx| × 256 / forward` with a 1-bit-per-clock restoring divider, a dead zone of 26 (about 6°), then `vx = vy × (r − 26) >> 13` on the DSP.
8. **What is the cross product telling you?** v1 × v2 = |v1||v2| sin θ. Its sign says left or right turn, and its size says how much. Summed over the swipe and divided by the mean |v|², it is the total turn in radians.
9. **Why skip zero velocities?** One sample in five does not move. A zero vector breaks the chain, so the turn into the next movement is lost and the rounding bias of the filter no longer cancels. The test caught a −15 per packet bias.
10. **Why so few dividers?** A combinational divider is large and slow. One sequential divider used twice per throw (40 clocks each) is enough, because a throw happens once every few seconds.
11. **What does sensitivity do?** It scales every delta by a shift-add: ×0.5, ×1, ×1.5, ×2.
12. **What stops the game hanging if the mouse is unplugged mid-swipe?** The 3 s timeout cancels the swipe. MouseCtl re-initialises the mouse itself when it is plugged back in.
13. **What happens on a sideways swipe?** If `|dx| > forward` the throw is rejected with "SWIPE FORWARD" and D returns to AIM.
14. **How is the trail drawn without a frame buffer?** 32 stored positions are compared with the pixel position in parallel. The newest match sets the brightness.
15. **What does Swipe Lab show?** The raw (grey) and filtered (yellow) path, auto-zoomed by a power of two (no divider), plus the measured speed, aim, spin and sample count. It shows the whole algorithm at work.
