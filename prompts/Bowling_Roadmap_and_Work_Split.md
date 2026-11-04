# StrikeLine (Bowling): Roadmap and Work Split

The full technical spec is in **Bowling_Engineer_Prompt.md**. This file covers who does what, in what order, and what "done" means.

## The product in one paragraph
A top-down ten-pin bowling game on the OLED. **Hold the left mouse button on the ball, swipe forward and release.** Swipe speed sets the ball speed, direction sets the aim, and curving the swipe adds spin. The ball skids through the oil and **hooks late**, as real bowling balls do. Pins collide with each other, wobble or fall, and the frame is scored by real ten-pin rules. The 10 LEDs show which pins are standing. Games and high scores are **saved to flash after every frame**, so you can resume even after reprogramming.

## Who owns what

| | Student A: Gesture | Student B: Ball physics | Student C: Pin physics | Student D: Game, UI, Save |
|---|---|---|---|---|
| Core | Mouse setup, 200 Hz sampling, filtering, speed, aim and spin (cross-product curvature) | Skid → hook → roll FSM, oil-zone friction, gutter, ball→pin contact | 10 pin states, pin↔pin pair-iterator FSM, wobble or topple, settle detector | Game FSM (frames, balls, 2-player), ten-pin scoring, menus |
| Showpiece | Swipe Lab practice mode, gesture trail, power and spin meters | Scrolling lane and camera, rotating ball, minimap, debug vectors | Split detection, pin-setter (rake sweep, Spare Challenge leaves), pin LEDs | Scorecard, flash save and resume, initials, compositor and fades, replay (stretch) |
| Gives others | Throw event (B), cursor (D), handedness | Ball state + camera (C, D), impulses (C) | Pin positions (B), standing mask + split (D) | Game state + settings (all), rack commands (C) |
| Lecture link | Counters, shift registers (L1–L2) | FSMs (L3) | FSMs, sequential scheduling (L3–L4) | Modular FSMs (L4), 7-seg (labs) |

Overlap note: B and C both detect collisions, but they are separate jobs. B handles one heavy ball against 10 pins and sends impulses. C handles equal-mass pin-against-pin collisions, toppling and settling. Keep the boundary at the `impulse` interface.

## Roadmap (in order; each phase ends when its check passes on the board)

### Phase 0: Agree (all)
- [ ] Read the prompt, sections 1–3.
- [ ] Get a wired mouse.
- [ ] Freeze `strike_defs.vh`: states, throw event, ball state, impulse, pin result, rack commands, render layers.
- [ ] One shared Git repo using the prompt's folder layout.
- **Check:** everyone can explain every signal that enters or leaves their part.

### Phase 1: Base build (all, together)
- [ ] Top module, XDC (with PS/2 pins), `timebase`, `pixel_xy`, OLED pattern, mouse cursor on the OLED, stubs.
- **Check:** the cursor tracks the mouse smoothly. Clean build, timing met.

### Phase 2: Vertical slice (minimum version of every part)
- A: release detection gives a straight throw with speed.
- B: the ball rolls straight down a scrolling lane.
- C: pins topple on contact; standing count shown.
- D: title → menu → AIM/THROW/ROLL/SETTLE loop, plus text engine.
- **Check:** a stranger can throw a straight strike.

### Phase 3: Full parts (work in parallel; integrate at least daily)

**A: Gesture**
- [ ] 4× virtual mouse range
- [ ] Ring buffer and moving average
- [ ] Speed ROM curve
- [ ] Aim ratio
- [ ] Cross-product spin
- [ ] Stance board
- [ ] Swipe rejection messages
- [ ] Trail, meters, LEDs
- [ ] Swipe Lab
- [ ] Testbench with synthetic swipes

**B: Ball**
- [ ] Phase FSM and oil zones
- [ ] Hook gain ROM per ball weight
- [ ] Gutter
- [ ] Ball→pin contact with impulse
- [ ] Camera lerp
- [ ] Lane renderer (boards, arrows, oil sheen)
- [ ] Rotating ball
- [ ] Minimap with path trace
- [ ] Debug overlay
- [ ] Testbenches for the phase FSM and contact

**C: Pins**
- [ ] Pair-iterator FSM (45 pairs)
- [ ] Elastic exchange with restitution
- [ ] Wobble and topple threshold
- [ ] Sliding fallen pins
- [ ] Kickback walls
- [ ] Settle detector
- [ ] Split detector
- [ ] Pin-setter commands and rake animation
- [ ] Pin sprites (8 directions)
- [ ] Pin LEDs
- [ ] Testbenches for collisions, settle and split

**D: Game, UI, Save**
- [ ] Full, Quick, 2-Player and Practice flows
- [ ] Scoring engine
- [ ] Scorecard
- [ ] Popups (STRIKE, SPARE, SPLIT, TURKEY)
- [ ] Mouse-driven menus
- [ ] Hint bars and ghost swipe
- [ ] Settings
- [ ] Flash save: RDID, read, erase and program, double-buffer and CRC
- [ ] Resume game
- [ ] Initials
- [ ] 7-seg
- [ ] Compositor, theme and fades
- [ ] Testbench with ≥ 10 known games

**Check:** every box ticked in **one** bitstream; resources logged after each merge.

### Phase 4: Integration loops (all)
- [ ] Settings change the physics: oil length (B), ball weight (B, C), handedness (A).
- [ ] Play a frame → auto-save → reprogram → Resume shows the same frame and score.
- [ ] Spare Challenge: D picks a leave, C sets it, A and B throw, C and D judge the conversion.
- **Check:** the 6-step demo script (prompt §8) runs cleanly.

### Phase 5: Feel tuning (all; most important, because the pool game lost marks here)
- [ ] 5 people who have never played try it. Each should throw a strike within 5 tries and say the hook feels right.
- [ ] Record each parameter change: speed curve, hook gain, friction, restitution, topple threshold.

### Phase 6: Harden and polish (all)
- [ ] Robustness tests (prompt §6): extreme swipes, re-plugging the mouse, pins overlapping, settle timeout, power loss during save.
- [ ] Bring LUT use under 75%, keep timing met.
- [ ] Replay, only if resources allow.

### Phase 7: Report and demo (each person writes their own section)
- [ ] Sheet A ≤ 500 words total, bold under 20%, real OLED photos. Colours: team pink, A red, B blue, C yellow, D green. Mark the **mouse** in bold as an optional device.
- [ ] Sheet B: course feedback, and every reference and AI use.
- [ ] Each person rehearses their 15 Q&A answers. Run the demo in under 5 minutes. Print 2 colour copies.

## Rules for the whole team
1. **Never merge anything you can't explain line by line.**
2. **Feel beats features.** An intuitive throw is worth more than an extra mode.
3. **Integrate early and often**, and watch resource use after every merge.
4. **Interfaces are frozen** unless all four owners agree.
5. **Log every source and AI use as you go.** Only claim what works in the final bitstream.
