# Build history: how the project was prompted and built

This is the full story of how both games were produced, so that a person or an AI agent can pick up the project with all of the context. Dates are 2026 (AY2026/27 Semester 1).

## 1. The method

1. **The team wrote the briefs.** For each game candidate the team wrote two documents, now in `prompts/`:
   - an **Engineer Prompt** (the spec: game design, hardware, every feature, fixed-point formats, the four-student split, Q&A expectations, course rules), and
   - a **Roadmap and Work Split** (phases 0-5, who owns what, interface contracts, what each student must be able to explain).
2. **The briefs were given to an AI coding assistant** (Claude, in Claude Code / VS Code) with the instruction to build both games completely so the team could pick the better one: *"build both completely following the prompt, later I will decide which comes out better"*. StrikeLine was then prioritised (*"complete StrikeLine perfectly ASAP"*).
3. **The assistant worked in phases**, with one self-checking testbench per part, a full-bitstream testbench, and real Vivado builds (timing and utilisation checked every build). It reported progress in short status lines.
4. **Improvements went through a plan first.** For v2 the team asked to discuss before coding (*"first give me a plan and wait for approval"*). The assistant proposed phases A-D, the team approved them, and the v1 bitstream was kept as a backup (*"keep the old bit intact so that I have a working backup"*).
5. **Everything is declared** in each game's `docs/REFERENCES_AND_AI_USE.md`, as the course requires. Each student must still study and defend their own part; `docs/A..D_DESIGN.md` hold 15 likely assessor questions with answers each.

## 2. Hardware and course rules that shaped the design

- Basys3 (Artix-7 XC7A35T, 20,800 LUTs, 90 DSPs, 50 BRAM tiles), one 100 MHz clock; everything else runs on **tick enables**, no derived clocks.
- Output: Pmod OLED 96×64 RGB565 on JC, driven by the course `Oled_Display.v` (pixel_index → pixel_data, about 6 clocks to answer each pixel, solved with a multicycle capture).
- Inputs: 16 switches, 5 buttons, the course PS/2 `MouseCtl` (VHDL) for StrikeLine. External monitor (VGA) **not used**: the course project is OLED-based.
- Saves: on-board QSPI flash via `STARTUPE2`, top two 64 KB sectors (0x3E0000, 0x3F0000), so the bitstream area is never touched.
- Each student is marked on their part, the team on integration: four folders, one frozen contract header, one top module that only wires.

## 3. StrikeLine v1 (tag `strikeline-v1.0`, 2026-11-03)

Order of work (roadmap phases):

| Phase | What was built |
|---|---|
| 0 | Contract `strike_defs.vh` (fixed-point formats: ball Q10.20 / 2^-20, interfaces POS Q10.6 and VEL Q3.12), timebase, pixel_xy, shared 25×18 multiplier, constraints, data generators (`tools/gen_tables.py`, `gen_sprites.py`, fonts, strings) |
| 1 | A: mouse → swipe capture at 200 Hz, ring buffer, 4-tap filter, peak speed, aim with a dead zone, spin from the summed cross product. B: skid / hook / roll ball FSM with oil, gutters. C: 10 pins, 45-pair iterator, impulse collisions with a 1/\|d\| ROM, wobble / topple, settle detector. D: game FSM + turn FSM, ten-pin scoring |
| 2 | Lane / ball / pin renderers, camera, compositor, shared text engine, menus, HUD, scorecard, 7-seg, LEDs |
| 3 | Splits (flood fill), pin-setter + rake animation, instant replay, Spare Challenge, Swipe Lab, 2 players, Quick Game |
| 4 | Flash save / resume: double slot + CRC-16, single writer (`persist_ctrl`), top-5 table, best game |
| 5 | Full-bitstream tests, timing closure, resource cuts, carry tuning |

Bugs found and fixed while building v1 (all by testbenches or builds, before any hardware):

- **Spin bias**: zero-velocity samples in the cross product added false spin → cross product against the last non-zero velocity.
- **Lost pulses**: throw / rack / force-settle pulses dropped while an FSM was busy → latched pending flags.
- **Pins never stopped**: friction `v >> 8` rounded to 0 below 256 → stop threshold `STOP_V ≥ 2^FRIC_SH` (found by `tb_top`).
- Verilog reserved words (`cell`, `edge`) used as names; a compositor function reading module globals → passed as arguments.
- 2× text overflow (`f + 3'd6` in 3 bits); garbage on help / practice row 10.
- Rescore race (persist busy must include incoming commands); flash-defaults race; resume and score-table read alignment (registered address); flash RX index alignment; a bug in the flash model itself.
- **Resources**: first full build at 90.6 % LUT → two-port pin register file, shift-register replay buffer, LUTRAM for score / page / trace → 75.6 %.
- **Timing**: reset fan-out (`max_fanout`), pipelining in pins, plot, features, ball, camera, 7-seg → WNS +0.089 ns.

Tool issues met on the way (useful for anyone continuing): bash heredoc quoting (write scripts to files), xsim delay literal overflow (`#3_000_000_000`), Vivado locking `.Xil` (each build uses its own `$TEMP` folder), the project path has spaces and lives in OneDrive (sims copy sources to `$TEMP`), a cp1252 vs UTF-8 file encoding issue.

v1 result: **15,727 LUT (75.6 %), WNS +0.089 ns**, all testbenches PASS.

## 4. StrikeLine v2 (tag `strikeline-v2.0`, 2026-11-04)

The team's request (paraphrased from the prompt): make it **first person**, **re-check the spin physics and pin collisions**, make the **7-seg show the points of the current game**, and *"the buttons and switches are basically doing the same thing"* → give them distinct roles. Approved plan:

| Phase | Change |
|---|---|
| **A: 7-seg** | `score_engine` gained a provisional score (pins knocked so far, a strike counts 10 at once) per player; 7-seg shows ball speed for 3 s, then points; player digit in 2P; made.tries in Spare Challenge; P1 / P2 alternate at game over. Build: 75.7 %, WNS +0.140 (bit kept as `strikeline_v2_phaseA.bit`) |
| **B: physics re-check** | Found a **critical sign bug**: the ball's lateral velocity was part-selected unsigned, so a ball moving left (left hook) could pass through pins; present in v1 too → `$signed(vx[23:8])`. Re-tuned pin friction / topple / damping (`R_DOWN=224`, `TOPPLE_P=2200`, `FRIC_SH=8`, `DL_S1=3`, `DL_S2=4`) so not every hit is a strike. Debug arrow direction fixed (screen y points down) |
| **C: distinct inputs** | Switches = settings (sw11/12 ball weight, sw13 theme, sw14 oil, sw15 hand, sw4 view); buttons = actions (btnL / btnR one-board stance nudges while aiming, btnU replay, btnD scorecard). Settings menu shows switch-owned items dimmed with "S" |
| **D: first person** | Hybrid view: first person while aiming and rolling, top-down for the pin deck results. Row ROM `persp.mem` (distance = 1530/(y-12), inverse = 51·256/(y-12)), per-frame projector `persp_proj`, pin silhouette ROM `pin_fp`; sw4 restores the classic view. Timing: DSP use limited to `lane_render` and `persp_proj` (a global `use_dsp` overshot to 87 DSPs) |

Carry tuning (strikes / attempts per pocket test), v1 → v2: pocket 1/3 → 5/9, nose 3/3 → 0/4, brooklyn 2/4 → 1/3, light 4/6 → 0/12. That is: v1 struck on almost anything; v2 strikes mostly from the pocket.

v2 result: **15,785 LUT (75.89 %), 3 BRAM, 51 DSP, WNS +0.251 ns, WHS +0.032 ns, 0 failing endpoints**; `tb_gesture`, `tb_physics`, `tb_carry`, `tb_scoring`, `tb_flash`, `tb_top`, `tb_resume` all PASS; screenshots in `strikeline/docs/screens/` come from `tb_screens`.

## 5. KeyLight (folder `keylight/`)

Built first, as a **vertical slice**: sound engine (A), switch keys + Free Play (B), rhythm game engine with chart reader, judgement, combo and scoring (C), menus, results and 7-seg (D). Last build: **3,815 LUT (18.3 %), WNS +0.309 ns**. Still to do (roadmap phases 3-4): Learn mode, high scores, settings, the recorder / MY SONG, flash saves, 4-voice polyphony and instruments. Work then moved to StrikeLine.

## 6. Status and next steps

- **Nothing has been run on real hardware yet.** First step: follow the on-board checklist in `strikeline/README.md`.
- Feel tuning with real players (speed curve and hook gains in `strikeline/tools/gen_tables.py`, aim dead zone in `gesture_features.v`).
- Pick the game (StrikeLine is far more complete); if KeyLight is chosen, finish its phases 3-4.
- Before submission: each student re-reads their `docs/X_DESIGN.md` Q&A and their RTL.
