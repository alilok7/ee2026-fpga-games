# StrikeLine: mouse-swipe ten-pin bowling on the Basys3

EE2026 I-FDP, AY2026/27 Sem 1. Hold left-click on the lane, flick the mouse forward and let go. Flick speed sets the ball speed, direction sets the aim, and curving the flick makes the ball hook late, like a real ball leaving the oil. Pins collide, wobble and fall; frames are scored by real ten-pin rules; games are saved to flash after every frame.

**v3 (this working copy):** a VGA monitor is the main screen (640 × 480: full-screen first-person 3-D lane drawn at 320 × 240 in 512 colours, a compact info panel; a full-screen top-down replay with a camera look after every ball), the OLED is the scoreboard (v3.3); spin is measured from the whole curve (31 levels, Settings → SPIN), the swipe is read exactly (release packet, tremor trimmed), a 0.5 s steer window after release, a first-person zoom (hold the right button; v3.1) with a dotted aim guide, and a slip-based hook on an oil-pattern lane with better pin action. See ../docs/BUILD_HISTORY.md section 5.

- Spec: `../prompts/Bowling_Engineer_Prompt.md`. Roadmap: `../prompts/Bowling_Roadmap_and_Work_Split.md`.
- Every signal between the parts: `docs/INTERFACES.md`. Each part: `docs/A..D_DESIGN.md` (with 15 Q&A each).
- Demo: `docs/DEMO_SCRIPT.md`. Sources and AI use: `docs/REFERENCES_AND_AI_USE.md`.

## Hardware
| Needed | Where |
|---|---|
| Basys3 + micro-USB cable | — |
| VGA monitor + cable (v3, main screen) | Basys3 VGA connector |
| Pmod OLED (96×64 RGB) (v3: second screen) | **JC** |
| **Wired USB mouse** (optional device, one per team) | Basys3 USB host port (top) |

Saves use the on-board QSPI flash (top two 64 KB sectors), nothing extra.

## Folder layout
```
rtl/top/        My_Top_Module, strike_defs.vh (the contract), timebase, pixel_xy, mul_s25x18
rtl/provided/   Oled_Display.v, Mouse_Control.vhd (MouseCtl), Ps2Interface.vhd (unchanged)
rtl/a_gesture/  Student A    rtl/b_ball/  Student B    rtl/c_pins/  Student C    rtl/d_game_ui/  Student D
text/           fonts (5x7, 3x5) and strings.txt  ->  tools/fonts_to_mem.py, strings_to_mem.py
tools/          gen_tables.py, gen_sprites.py, make_data.py, build.tcl, create_project.tcl
sim/<a|b|d|top>/tb_*.v   self-checking testbenches (sim/d/flash_model.v = SPI flash model)
```

## Build and test
1. Regenerate data (only after editing `text/` or a generator): `python tools/make_data.py`
2. Testbenches (Git Bash, from `strikeline/`): `bash sim/run_sim.sh all` (every line should be `PASS`). Quick syntax check of all RTL: `bash sim/lint.sh`.
3. Bitstream: `vivado -mode batch -source tools/build.tcl` → `build/strikeline.bit` + reports. Or GUI: Tools → Run Tcl Script → `tools/create_project.tcl`.

| Testbench | Checks |
|---|---|
| `tb_gesture` (A) | 20: straight / curved / angled / sideways / backwards / slow / zero-length / cancelled / huge swipes; v3: spin grows with the curve, mirror symmetry, tremor trimmed, spin sensitivity |
| `tb_physics` (B+C) | 26: phases, gutters, hook distance, oil length, ball–pin momentum, settle, leaves, splits, no stuck overlaps; v3: mirror-image hooks, hook grows with spin, faster ball hooks less, bounded steer |
| `tb_scoring` (D) | 23: 12 known games (300, 299, 167 …), marks, Quick Game, top-5 order, best game |
| `tb_flash` (D) | 13: blank flash, save/restore after reprogram, slot alternation, power cut in erase and in program, no flash |
| `tb_top` (all) | the whole bitstream: boot → menu → Quick Game → real throws → scorecard → auto-save → quit → reprogram → resume |
| `tb_resume` (D) | fast check of the RESUME path on the whole bitstream |
| `tb_screens` (all) | screenshots of both frame buffers, VGA and OLED (`python tools/screens_to_png.py <sim run folder> build/screens`) |

## Controls (v2)
| Input | Use |
|---|---|
| Mouse move | Point in menus; on the lane: pick the stance board |
| **Hold the right button** (v3.1) | Zoom the first-person view: ball, dotted aim guide and pins stay on screen; you can flick while zoomed, and it stays on through the roll |
| **Wheel while aiming** (v3) | Move the target mark of the aim guide |
| **Sideways move just after release** (v3) | Steer window: nudges the ball for 0.5 s |
| Hold left-click + flick up | Throw (speed = flick speed, curve = hook) |
| Right click | Scorecard after a throw (v3.1: result / sweep only), back in menus, cancels a swipe in progress |
| (automatic, v3.2) | After every ball: full-screen top-down replay at real speed; **a click skips it** |
| Middle click / **btnU** | (on a result) instant replay at half speed |
| Wheel / btnU, btnD | Letters when entering initials; menu navigation |
| **btnL / btnR** (aiming) | Move the stance exactly one board left / right |
| **btnD** (in a game) | Scorecard |
| **btnC** | Choose; skip a result |
| Hold **btnL** 1 s | Leave the game (it is saved) |
| btnU + btnD 2 s | Soft reset (saves kept) |
| **sw11 / sw12** | Ball 12 lb / 16 lb (both down = 14 lb) |
| **sw13** | Neon "cosmic bowling" theme |
| **sw14** | Long oil (45 ft): the ball hooks later and less |
| **sw15** | Left-handed (boards counted from the left) |
| **sw4** | Classic top-down view on the VGA too (default: 3-D first person during play) |
| sw0 / sw1 / sw2 / sw3 | Pause / minimap / physics debug view / slow motion |
| `led[9:0]` / `led[15:10]` | Pins standing / power while swiping, then the hook |
| 7-seg | Menu word; ball speed after a throw; then the points so far (2 players: left digit = player); Spare Challenge: made.tries |

## On-board checklist (first time on hardware)
1. Program → VGA: the STRIKELINE title around the framed menu; OLED: title "STRIKE LINE" with a rolling ball; 7-seg `bOWL`.
2. Click, then click QUICK GAME → "FRAME 8" banner, rake animation, the ball sits under the pointer.
3. Throw straight up from the centre → pins fall, LEDs update, popup, score in the panel.
4. After the frame: the scorecard shows, "SAVING" blinks.
5. Hold btnL → menu → reprogram the FPGA → click → RESUME GAME is bright → you are back in frame 9.
6. Feel tuning (roadmap phase 5) needs real players: the speed curve is `tools/gen_tables.py` (`speed_curve`), the hook gains are `ball_params`, the aim dead zone and gain are in `gesture_features.v`.
