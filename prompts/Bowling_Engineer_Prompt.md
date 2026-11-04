# StrikeLine (Bowling): engineering brief

*Paste everything below this line to the engineer. "StrikeLine" is a working title, so rename it freely.*

---

You are the senior engineer on a 4-person university FPGA project. Your job is to design and build **StrikeLine**, a mouse-controlled ten-pin bowling game with real-time physics, in Verilog on a Digilent **Basys3** board. The code is split into four parts, one per student (A, B, C, D). Each student is marked on their own part, the team is marked on how well the four parts work as one product, and each student is questioned on their own code. Read the whole brief before writing any code. The marking rules decide many of the design choices below.

## 1. The course and how this project is marked

The course is NUS EE2026 Digital Design, AY2026/27 Semester 1. The project is worth 30% of the course grade:

| Item | Weight | Notes |
|---|---|---|
| Student A / B / C / D component | 9% each, individual | Each part needs a "reasonable amount of Verilog" and "should not have much overlap" with the others |
| Integration of A+B+C+D in ONE bitstream | 9%, group | "How well the different components … are integrated together into one bitstream to create a more complete project" |
| Execution, Q&A, understanding, report and word limits | 9%, individual | A student who can't explain basic things about their own code can get **zero** for Q&A |
| Proposal + peer feedback | 2% + 1% | Not your concern |

**There are exactly four judging criteria:** **Functionality**, **Robustness & reliability**, **User Interface**, **User Experience**. The teaching assistant (TA) added these points:
- Only **integration complexity** counts as complexity: every part must depend on and feed into the others.
- UX weighs heavily. **Warning specific to this project:** a past *pool* game (mouse plus ball physics) was "highly rated but not A" because **its mouse controls and physics weren't intuitive**. StrikeLine must beat that. The throw must feel natural, give instant visual feedback, and the physics must look believable. This is the top design priority.
- Graders want to see that the students "can program in Verilog quite well".
- **FPGA resources are the real limit.** Optimise and share hardware, and integrate early, because parts that each fit often overflow together.
- Graders have seen almost every past project. Cite all external or generated code.

**Official rules** (from the Project Manual):
- Everything must run in **one bitstream**.
- **Compulsory hardware:** Basys3 plus the Pmod OLED (96×64, RGB565). The UI must use the **switches, LEDs and OLED**. The **mouse** is an allowed optional device (one per team, through the provided `MouseCtl.vhd`). Unnecessary devices are discouraged. Two OLEDs must **never** go on the same side of the board.
- Report: ≤ 500 words for group plus 4 students. Anything not described gets no marks, and anything claimed that doesn't work is penalised.
- The demo lasts 2–5 minutes, and the assessor skips anything slow to reach. **A full 10-frame game is too long to demo**, so the design must include short modes (see §2).

**Design consequences:**
1. Every module must be explainable line by line by its owner. Use clear FSMs, counters, fixed-point datapaths with one shared multiplier, and ROM tables. Comment the *why*.
2. Each part must have visible output of its own and be needed by the others.
3. The core experience (grab, swipe, watch it hook, pins scatter, score) must be reachable in ≤ 3 clicks from power-on.

## 2. The product

The player stands at the foul line on a top-down, scrolling bowling lane. They **press and hold the left mouse button on the ball, swipe forward and release**:
- **Swipe speed** sets the ball speed.
- **Swipe direction** sets the aim.
- **Curving the swipe** adds spin, which makes the ball **hook** late, as real balls do once they leave the oiled part of the lane.

The camera follows the ball down 60 ft of lane. The ball hits the pins, pins knock over other pins, wobblers may stay up, and the frame is scored under real ten-pin rules. Scores and in-progress games are **saved to flash**, so a game can be resumed even after the FPGA is reprogrammed.

Modes, all in one bitstream:
1. **Quick Game (3 frames)**, the demo default; **Full Game (10 frames)**; **2-Player hot-seat**.
2. **Practice:** *Swipe Lab* shows live gesture measurements. *Spare Challenge* sets up a classic leave (e.g. 7-10, 3-6-10) to convert.
3. **High scores and stats:** top 5 games with initials, plus lifetime strikes, spares and best game, persisted in flash.
4. **Settings:** oil pattern (short / long), ball weight (12 / 14 / 16 lb), handedness (mirror), mouse sensitivity, display theme and brightness, erase saves.
5. **Instant replay** of the last throw in slow motion. This is a stretch goal (see Part D).

### 2.1 Hardware map (Basys3, XC7A35T)

Resource budget: 20,800 LUTs · 41,600 FFs · 50 BRAM36 · 90 DSP48. Target **≤ 75% LUT**.

| Hardware | Use |
|---|---|
| `clk` W5, 100 MHz | Single system clock with clock enables. `clk6p25m` (divide-by-16) drives only `Oled_Display`. |
| Mouse, PS/2 `ps2_clk` C17 / `ps2_data` B17 (PULLUP), `MouseCtl.vhd` | Aim, throw gesture, menu pointer, scorecard toggle (right click) |
| `led[9:0]` | **Live pin deck:** one LED per pin (pin 1–10), on = standing |
| `led[15:10]` | Throw power meter while swiping; spin direction after release |
| `sw[0]` | Pause |
| `sw[1]` | Minimap on/off |
| `sw[2]` | **Physics debug overlay** (velocity vectors, contact points); great for Q&A |
| `sw[3]` | Slow motion (physics tick ÷ 4) |
| `sw[15]` | Left-handed mode |
| `btnC` / `btnU` / `btnD` / `btnL` / `btnR` | Confirm / menu up / menu down / back / show scorecard |
| `btnU`+`btnD` held 2 s | Soft reset; saved data is kept |
| 7-segment | Ball speed after release (e.g. "16.5" mph), then the frame score |
| **JC** | Pmod OLED |
| QSPI flash (`QspiCSn` K19, `QspiDB[0..3]` D18/D19/G18/F18, CCLK via `STARTUPE2`) | Save data (Part D) |

Optional stretch: a second OLED as a permanent scorecard, on a different side of the board. No audio, no VGA.

### 2.2 World model (real bowling dimensions, so the physics looks right)
- **Units:** inches. **Positions** use unsigned Q10.6 (1/64 inch, range 0–1023.98 in). **Velocities** are signed 16-bit in 1/64 inch per physics tick.
- **Physics tick:** 1024 Hz, so `dt` is a shift, not a multiply. Each tick has ~97,000 clock cycles, so all physics runs **sequentially** through one shared multiplier FSM per part, not as parallel hardware.
- **Lane:**
  - 41.5 in wide (39 boards) with 9 in gutters each side.
  - Foul line at y = 0, head pin at y = 720 (60 ft).
  - Targeting arrows at y = 180 (15 ft).
  - Pin rows spaced 10.39 in, pins 12 in apart centre to centre.
- **Bodies:** ball radius 4.3 in. Pin contact radius 2.4 in. Masses for ball 12/14/16 lb vs pin 3.5 lb come from a ROM per setting.
- **Screen scale:** 1 px = 1 in. The lane plus gutters is 60 px wide. The 36 px side panel holds a minimap (1 px = 12 in), meters and the HUD. The camera scrolls along the lane.
- **Oil pattern:** oiled from the foul line to 40 ft (short) or 45 ft (long), dry after that. This is what makes hooks happen late, as in real bowling.

## 3. Architecture

### 3.1 Clocking and timing
- One 100 MHz domain. Shared enables are generated once in `timebase.v`: `tick_phys` (1024 Hz, or ÷4 in slow motion), `tick_sample` (200 Hz, mouse sampling), `tick_frame` (60 Hz), `tick_1ms`.
- `px_x`/`px_y` are computed once from `pixel_index` in the top module. Renderers are combinational and read registered state, which updates on `tick_frame` or `tick_phys`.
- Read `Oled_Display.v` for the exact sampling latency of `pixel_data` before any renderer reads BRAM.
- Reset is synchronous and active-high: power-on OR soft reset.

### 3.2 Data flow and render layers

```
Mouse -> [A: gesture]  --throw{speed, angle, spin, start_x}--> [B: ball physics] --impulse{pin_id, vx, vy}--> [C: pin physics]
            |                                                       |  ^  ball pos/vel                              |
            | cursor/trail/meters                                   |  |  pin positions (for contact)               | standing mask, settle
            v                                                       v  |                                           v
                                        [D: game FSM, scoring display, menus, save, compositor]
Render layers (back to front): lane + camera (B) < pins (C) < ball (B) < aim, trail, meters (A) < HUD, popups, menus (D) < brightness/fade (D) -> Oled_Display
```

### 3.3 Shared interface contract: `rtl/top/strike_defs.vh` (freeze before coding)

| Signal | Producer → consumer | Meaning |
|---|---|---|
| `game_state` | D → all | `TITLE, MENU, AIM, THROW, ROLL, PINACTION, SETTLE, RESULT, SWEEP, GAMEOVER, NAME, PRACTICE_SWIPE, PRACTICE_SPARE, SCORES, SETTINGS, REPLAY` |
| `settings` | D → A, B, C | `oil_len`, `ball_lb[1:0]`, `left_handed`, `sensitivity[1:0]`, `theme`, `brightness[1:0]` |
| `throw_valid, throw_vy, throw_vx, throw_spin, throw_x0` | A → B, D | Release event: forward and lateral velocity, signed spin (−7…+7), start board |
| `cursor_x, cursor_y, mouse_left/right/middle` (edges + levels) | A → D | Pointer for menus and aiming |
| `ball_x, ball_y, ball_vx, ball_vy, ball_phase` | B → C, D, A | `phase` = `SKID / HOOK / ROLL / GUTTER / PIT` |
| `cam_y` | B → C, D | Camera position. Every world renderer subtracts it. |
| `pin_x[10], pin_y[10]` (read port) | C → B | B detects ball–pin contact against these |
| `impulse_valid, impulse_pin, impulse_vx, impulse_vy` | B → C | Momentum given to a pin on ball contact |
| `pins_standing[9:0]`, `settle_done`, `pins_down_this_ball[3:0]`, `split_flag` | C → D | End-of-ball result |
| `rack_cmd` (`FULL_RACK / SWEEP_FALLEN / SET_LEAVE + mask`) | D → C | Pin-setter control |
| Video | `px_color` 16 per layer + `px_en` | B, C, A, D → D's compositor |

### 3.4 Repository layout
`rtl/top/`, `rtl/provided/` (`Oled_Display.v`, `MouseCtl.vhd`, `Ps2Interface.vhd`, unchanged), `rtl/a_gesture/`, `rtl/b_ball/`, `rtl/c_pins/`, `rtl/d_game_ui/`, `sim/<a|b|c|d>/`, `data/*.mem`, `tools/*.py` (sprite, font, trig and split-table generators), `constraints/`, `docs/` (`INTERFACES.md`, `<X>_DESIGN.md`, `REFERENCES_AND_AI_USE.md`, `DEMO_SCRIPT.md`).

## 4. The four parts

### Part A: Mouse input and gesture recognition (Student A)

1. **Mouse setup FSM.** At reset, use MouseCtl's `value/setmax_x/setmax_y/setx/sety` to set a 4× virtual range (384 × 256). The cursor is `xpos>>2`, `ypos>>2`, which gives sub-pixel precision. Read the `MouseCtl.vhd` source for the exact set-signal timing and axis direction.
2. **Gesture capture:**
   - While the left button is held on the ball, sample at 200 Hz into a 64-entry ring buffer (BRAM or a shift register).
   - Positions are smoothed by a 4-tap moving average (shift-add, no divider).
3. **Feature extraction on release:**
   - **Speed:** forward displacement over the last 8 samples (40 ms) maps through a ROM curve to 10–22 mph, then to `throw_vy`.
   - **Aim:** the lateral/forward ratio of the whole swipe gives `throw_vx`. Use a small shift-subtract divider, or a ratio ROM on the top bits.
   - **Spin:** the **signed sum of cross products** of successive velocity vectors measures curvature. Its sign is the hook direction, and its magnitude is quantised to 0–7.
   - Handedness mirrors the result.
4. **Validation and UX:**
   - A swipe that is too short or too slow is rejected with "SWIPE FASTER". A sideways swipe gives "SWIPE FORWARD".
   - Pressing the right mouse button during the swipe cancels it.
   - Before grabbing the ball, moving the mouse left or right sets the **stance board** (`throw_x0`).
5. **Visuals (A's render layer):**
   - A fading gesture trail of the last 32 samples.
   - Live **power** and **spin** meters in the side panel and on `led[15:10]`.
   - After release, a label such as "HOOK R3 · 17 mph".
   - Throw speed is sent to the 7-seg.
6. **Swipe Lab (practice):** shows raw and filtered paths with the measured speed, aim and spin for each swipe. It demonstrates the algorithm directly.

**Q&A focus:** PS/2 mouse data and MouseCtl configuration, sampling rate choice, moving-average filter, the cross-product curvature maths, why there are so few dividers.

### Part B: Ball physics, lane and camera (Student B)

1. **Ball state machine:** `SKID` (oiled: low friction, spin barely acts) → `HOOK` (dry: spin converts into lateral acceleration) → `ROLL` (spin used up, rolls in its final direction) → `PIT`. `GUTTER` applies if |x| goes past the lane edge; the ball then rolls straight in the channel and can't touch the pins. Every phase update is a small fixed-point step per `tick_phys`.
2. **Friction model:** forward deceleration μ(zone)·g is a per-tick constant. Lateral hook acceleration = `spin × hook_gain(zone, ball_lb)`, taken from a ROM. The phase boundaries come from `oil_len`. Tune the parameters so a medium hook moves 8–12 boards, as in real bowling.
3. **Ball–pin collision:**
   - Every tick, check the 10 pins one after another: |d|² < (Rb+Rp)², with squared distances so there is **no square root**.
   - The contact normal is d / (Rb+Rp), using a constant reciprocal.
   - The impulse uses the ball/pin mass ratio. The ball deflects slightly and the pin gets velocity, which goes to C as an `impulse`.
   - One collision per pin per contact: debounce with a per-pin "in contact" flag.
4. **Camera:** `cam_y` follows the ball with lerp smoothing (`cam += (target − cam) >> 3`), clamped to the lane ends. It holds on the pin deck during pin action.
5. **Lane renderer (B's layer):**
   - Wood boards (alternating tones), oil sheen in the oiled zone, targeting arrows, foul line, gutters, pin deck and pit edge.
   - **Minimap** strip showing the ball dot and its path trace (a 64-point path buffer).
6. **Ball renderer:** a circle drawn by range check (x² + y² < r²) with a **rotating finger-hole marker** whose angle advances with spin and speed. The angle uses a small sin/cos ROM.
7. **Debug overlay** (`sw[2]`): velocity vector line and contact normal.

**Q&A focus:** fixed-point formats and overflow, the phase FSM, why the hook starts at the oil line, the collision maths without sqrt or division, the camera smoothing filter.

### Part C: Pin physics, pin-setter and scoring logic (Student C)

1. **Pin state per pin:** position, velocity, and a state `STANDING / WOBBLING / FALLING / DOWN / OFF_DECK`. Fall direction is quantised to 8 directions.
2. **Impulse handling:** an impulse above `topple_threshold` sets FALLING. Below it, WOBBLING for ~0.4 s, then STANDING again, which gives real "wobblers". Fallen pins keep sliding with friction and **can knock other pins** ("messengers").
3. **Pin–pin collisions:**
   - A **pair-iterator FSM** walks all 45 pairs from a pair ROM every tick and checks overlap with squared distances.
   - The collision is equal-mass and elastic along the normal: the normal velocity components are swapped and scaled by restitution e ≈ 0.6, done as shift-add.
   - Side kickback walls reflect pins with damping, and pins past the deck edge become OFF_DECK.
4. **Settle detector:** every pin's speed is below ε for 0.5 s, or a 4 s timeout. It then outputs `pins_standing`, `pins_down_this_ball` and `split_flag`.
5. **Split detection:** the head pin is down and the standing pins form 2 or more groups that aren't adjacent. Check this with an adjacency ROM over the 10 pins, or a ROM of named splits that also drives the "7-10 SPLIT!" label.
6. **Pin-setter:** obeys `rack_cmd`: full rack; sweep the fallen pins after ball 1 (a rake animation lowers and clears them); set a specific leave for Spare Challenge.
7. **Pin renderer (C's layer):**
   - Standing pin: a white disc with a red neck ring, seen from above.
   - Wobbling pin: jitters.
   - Falling or down pin: an elongated sprite in its fall direction, from an 8-direction sprite ROM.
   - All drawn relative to `cam_y`.
8. **Pin LEDs:** `led[9:0]` mirror `pins_standing` live, so the board shows the leave.

**Q&A focus:** the pair-iterator FSM schedule and its cycle budget, the elastic collision maths, the topple threshold choice, the settle logic, the split algorithm.

### Part D: Game controller, scoring, UI and save system (Student D)

1. **Game FSM**, a modular FSM (one top FSM plus sub-FSMs per mode):
   - Covers every state in §3.3, plus frame and ball counters and the turn order for 2 players.
   - Quick, Full and Practice flows.
   - "STRIKE!", "SPARE!", "GUTTER", "SPLIT!" and "TURKEY!" popups.
2. **Ten-pin scoring engine:** strike and spare bonuses, 10th-frame bonus balls, running totals (max 300). Marks are stored per ball (X, /, −, digit). It is fully testable in simulation against a list of known games.
3. **Scorecard renderer:** two rows of 5 frames with a 3×5 mini-font, in standard notation. Toggle with `btnR` or right-click. It appears automatically at frame end.
4. **Shared text engine:** 5×7 and 3×5 fonts generated from text files by `tools/`, string ROMs, and 2× titles.
5. **Menus driven by the mouse pointer and buttons:** title (animated rolling ball and pins), main menu, mode select, settings, high scores and stats. Hover highlight and click.
6. **On-board guidance:** a hint bar on every screen, e.g. "Hold L-click on ball, swipe forward". The first throw of a game shows a ghost animation of a swipe.
7. **Compositor and post-processing:** layer priority, theme, brightness, and 200 ms fades.
8. **Persistent save (QSPI flash), "save game":**
   - Single-bit SPI through `STARTUPE2.USRCCLKO` (the first few USRCCLKO cycles after configuration are swallowed; handle that). RDID 0x9F at boot to confirm the part, then READ 0x03, WREN 0x06, sector erase, page program 0x02, and RDSR 0x05 to poll.
   - **Two slots in the last 64 KB block with a sequence number and CRC-16**, loaded into a BRAM mirror at boot, so a power loss mid-write can't corrupt the last good save.
   - The image holds the top-5 table with initials, lifetime stats, settings, and the **in-progress game** (frame marks, current frame and ball, rack state).
   - **Auto-saves after every frame** and shows "SAVING…". "Resume game" appears in the menu when a saved game exists, including after reprogramming.
9. **Initials entry** for a new high score: the mouse wheel cycles letters, a click confirms.
10. **7-seg driver:** speed after release, then the frame score, and the menu word in menus.
11. **Instant replay (stretch, only if resources allow):** during the throw, record ball state and the 10 pin states at 60 Hz for 4 s into BRAM (~3 BRAM36). Replay in slow motion by feeding the stored states to B's and C's renderers through a state-source mux.

**Q&A focus:** the modular FSM diagram (lectures L3/L4), bonus scoring logic, the SPI flash sequence, double-buffering and CRC, compositor priority.

## 5. Why this counts as integration
- **One physics chain:** A's gesture becomes B's ball, then B's impulses become C's pins, then C's result becomes D's score. Each stage consumes the previous stage's output, with no standalone parts.
- **Settings change every part:** oil length (B), ball weight (B, C), handedness and sensitivity (A), theme (D).
- **Persistence:** a game saved after every frame, resumable after reprogramming, with scores and stats from C and D stored by D.
- **One visual scene:** four render layers from four owners combine into a single scrolling world.

## 6. Engineering standards

- **Build on what the course taught.** Read the course material provided with this brief before designing each part: lectures L1 Sequential Circuits, L2 Counters, L3 Intro to FSM, L4 Modular FSMs, and the Lab 1, 2 and 4 manuals, all as Markdown. Diagrams were lost in conversion, so the PDFs are the reference for figures. Use the course's counter and clock-divider patterns, its FSM style (state register plus next-state and output logic, L3) and its modular FSM structure (L4), and the labs' 7-segment multiplexing approach. Only go beyond the course material where a feature needs it (fixed-point physics, SPI flash, dividers). In that case, add a "how this relates to what we learned" note to that part's design doc.
- Verilog-2001 (the VHDL mouse files from the template stay as they are). Non-blocking assignments in sequential logic, blocking in combinational logic, defaults in every combinational block, **zero latches**.
- One clock with enables. Parameters instead of magic numbers. A header on every module naming its owner. Comments explain *why*. Modules ≤ ~300 lines.
- **Each part's physics uses one shared multiplier** (DSP48) driven by its own FSM. Write down the cycle budget per tick.
- **Self-checking testbenches:**
  - gesture features against recorded synthetic swipes
  - the ball phase FSM
  - ball–pin and pin–pin collisions (momentum conserved within tolerance)
  - the settle detector
  - the split detector
  - ten-pin scoring against ≥ 10 known games (all strikes = 300, all spares, a gutter game, mixed)
  - the flash FSM against a simple flash model
- **Resource log** after every integration build (LUT, FF, BRAM, DSP, WNS) in `docs/INTERFACES.md`.
- **Robustness tests:**
  - very fast, very slow and zero-length swipes
  - clicking during pin action
  - unplugging and re-plugging the mouse
  - pausing mid-roll
  - gutter ball on both sides
  - balls that touch no pins
  - pins stuck overlapping (must separate, never lock up)
  - 4 s settle timeout
  - power loss during a save
  - mode changes mid-game
- Log every external source and any generated code in `docs/REFERENCES_AND_AI_USE.md`, because undocumented use is penalised.
- Each `docs/<X>_DESIGN.md` covers a block diagram, the FSMs, fixed-point formats, resources, and 15 likely assessor questions with answers.

## 7. Build order and acceptance criteria

1. **Base:** top module, constraints, `timebase`, `pixel_xy`, OLED test pattern, the MouseCtl cursor drawn on the OLED, `strike_defs.vh`, stubs.
   - *Accept:* the cursor follows the mouse smoothly.
2. **Vertical slice:** swipe produces a straight ball, which rolls down the scrolling lane and knocks over pins with simple contact; the count is shown.
   - *Accept:* a straight-ball strike is possible.
3. **Feature-complete parts:** spin and hook, pin–pin collisions, wobblers, scoring, scorecard, menus. Integrate daily.
4. **Integration loops:** settings affect physics; save, then reprogram, then resume; practice modes; 2-player.
5. **Feel tuning, the top priority:** tune the speed curve, hook strength, friction and restitution until **5 people who have never seen the game** can throw a strike, and say the hook "feels right", within 5 tries. Record the parameter changes.
6. **Hardening:** the robustness tests, a resource squeeze (≤ 75% LUT), and timing met at 100 MHz.

**Final acceptance:** one bitstream; every feature in §2 and §4 works on hardware; tests pass; docs complete.

## 8. Demo script (2–5 minutes)
1. Title → Quick Game, in 2 clicks.
2. Straight throw: pins scatter, pin LEDs update, frame scored.
3. Hook throw: show the late curve after the oil line; strike celebration.
4. Turn on the debug overlay (`sw[2]`) and slow motion (`sw[3]`), then throw: velocity vectors and contacts are visible.
5. Spare Challenge: 7-10 split.
6. Reprogram the FPGA, then Resume game: the score and frame are restored.

## 9. Do not
- Add devices beyond the mouse and one OLED (a second OLED only as the stretch, on a different side).
- Use floating point, square roots, or parallel collision hardware for all pairs.
- Hardcode sprites, fonts, trig tables or splits in logic. They are `.mem` files produced by scripts.
- Make a separate bitstream, or claim anything that doesn't work in the final one.
- Copy code without citing it, or build anything the owner can't explain.

Start with `strike_defs.vh`, `docs/INTERFACES.md` and the base build (step 1). Then the vertical slice. Report resource usage at every milestone.
