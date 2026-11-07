Original team-allocation reference. Line counts and implementation descriptions may differ after the EE2026 rewrite; see README.md and docs/EE2026_DESIGN.md.

# StrikeLine v3.5: the four-way team split

Base: `main` at `664ef51` (StrikeLine v3.5: 19,661 LUT = 94.5 %, 86 DSP, 40 BRAM, WNS +0.203 ns, all 8 testbenches pass, programmed on a Basys3).
Split agreed by the team on 2026-11-06 and written up by the AI assistant (Claude); see `REFERENCES_AND_AI_USE.md`.

## How it was split

The project manual marks each student's component (9 %, individual) on the same four criteria as the whole project: **Functionality, Robustness and reliability, User Interface, User Experience**, and requires "a reasonable amount of Verilog" per member with little overlap. The other individual 9 % is execution, Q&A and understanding. So each part was built to have:

1. something to show under **all four criteria**
2. **one hard core** (the "not straightforward" enhancement an assessor will probe)
3. a clear **demo moment**
4. about the **same amount of Verilog**

| Part | Theme | Lines | Files | Hard core |
|---|---|---|---|---|
| **A** | Controls and feedback | 1,928 | 18 | Spin from the midpoint offset from the swipe chord (`gesture_features`, with the `div_seq` divider) |
| **B** | Ball and the 3-D VGA world | 1,811 | 13 | Fixed-point ball physics on an oil pattern + first-person perspective projection + the VGA frame buffer |
| **C** | Pins, turns and scoring | 1,883 | 9 | 10-pin collisions with body footprints and push-out (`pin_physics`, 672 lines, the largest file) |
| **D** | Game flow, menus and saves | 1,910 | 9 | Flash saves over SPI through `STARTUPE2`, double slot + CRC-16 |

Spread: 1,811 to 1,928 lines (average 1,883, every part within ±4 %). B has the fewest lines but the densest maths; C has the single largest and hardest file.

**Shared by all four** (the integration marks, 9 % group): `rtl/top/My_Top_Module.v` and the frozen contract `rtl/top/strike_defs.vh`. Change them only when all four agree.
**Not assigned:** the course-provided files in `rtl/provided/` (used unchanged) and `rtl/d_game_ui/bin2bcd.v` (dead code: nothing instantiates it; delete it).

## The four criteria, part by part

| | A: Controls and feedback | B: Ball and 3-D VGA world | C: Pins, turns and scoring | D: Game flow, menus and saves |
|---|---|---|---|---|
| **Functionality** | Swipe → speed, aim and 31-level spin; steer window after release | Skid → hook → roll on an oil-pattern ROM; ball weights; momentum-true ball-pin hits | 10-pin physics; frame rules incl. the 10th frame; 1-2 players; ten-pin scoring | Quick / Full / Resume games; high scores with initials; settings |
| **Robustness** | Synchronised + debounced inputs; release-packet capture and tremor trim; refused swipes say why; soft reset | Every ball reaches the pit; gutter handling; tear-free frame buffer | Settle detection with timeout; overlapping pins pushed apart; split detection | CRC-16 double-slot saves that survive a power cut; pause-to-quit saves the game |
| **User interface** | Cursor, trail, power/spin bars, `led[15:10]`, 7-segment (speed, then points), the shared text engine | VGA 640 × 480 output; 320 × 240 first-person 3-D view | OLED scoreboard; STRIKE! / SPARE! / SPLIT! popups, FRAME banners, pin diagram | Title, menus, settings, help; the VGA info panel (speed, power, spin, revs, entry board); layer compositing |
| **User experience** | Wheel-driven aim target; half-speed replay and the automatic replay after every ball | Dolly zoom; depth haze, wood grain, ball reflection; the far end of the alley and neighbouring lanes | Bowling call-outs (TURKEY!, DOUBLE!); hint row; first-throw ghost dot | Resume after reprogramming; spin / mouse / brightness settings; lifetime stats |
| **Demo moment** | Curve a flick: the spin bar, the LEDs and the hook all follow it | Hold right-click: zoom down the lane in 3-D | Pins scatter, "SPLIT!", the OLED scorecard updates | Reprogram the board, choose RESUME GAME, the game is still there |
| **Testbenches** | `tb_gesture` | `tb_physics`, `tb_carry` | `tb_scoring`, `tb_carry` | `tb_flash`, `tb_resume` |

Whole team: `tb_top`, `tb_screens` (full bitstream).

## Files

**A (18):** `a_gesture/` div_seq, gesture_features, gesture_render, mouse_setup, swipe_capture · `d_game_ui/` input_conditioner, debounce, button_events, seg7_ctrl, seg7_driver, replay_buffer, text_engine, string_rom, strings_map.vh (generated from `text/strings.txt`), txt_helpers.vh, bcd_fns.vh · `top/` timebase, reset_gen

**B (13):** `b_ball/` ball_physics, ball_render, ball_trace, camera, lane_render, persp_proj, backdrop_render, color_dim · `top/` render_scan, vga_out, view_map, pixel_xy, mul_s25x18

**C (9):** `c_pins/` pin_physics, pin_render, pin_settle, split_detect · `top/` rom2p · `d_game_ui/` turn_fsm, score_engine, scorecard_render, hud_render

**D (9):** `d_game_ui/` game_fsm, menu_render, vga_hud, compositor, persist_ctrl, save_image, flash_ctrl, spi_byte, crc16

Files keep their folders, because the build and simulation scripts find them there. The folder name is no longer the owner; the `Owner:` line at the top of each file is.

## Rules for changing your quarter

1. **Keep every port of your modules as it is** (names, widths, meaning) and don't edit `strike_defs.vh` or `My_Top_Module.v` alone. Then your files drop straight back in, and the four quarters combine without conflicts.
2. **Only edit your own files.** Work on your own git branch (`git checkout -b partA-yourname`); because no two parts share a file, merging the four branches is automatic.
3. **The chip is nearly full.** 1,139 LUT, 4 DSP and 10 BRAM tiles are left in total, and timing passes by 0.2 ns. Budget about **250 LUT, 1 DSP and 2 BRAM tiles each**, and register any new arithmetic. Anything bigger needs the team's agreement first.
4. **Run your testbenches after every change** (`bash sim/run_sim.sh tb_gesture`, etc.) and the full set before merging (`bash sim/lint.sh`, `bash sim/run_sim.sh all`, then `vivado -mode batch -source tools/build.tcl`). Check WNS ≥ 0, WHS ≥ 0 and 0 failing endpoints.
5. **Log what you change** in `docs/REFERENCES_AND_AI_USE.md`: your own work as yours, and any AI help as AI help. The course penalises undocumented AI use fully, and the honest log protects everyone.
6. **The report may only claim what works in the final bitstream.** If you change or drop a feature, update your report section.
