# StrikeLine interfaces (the frozen contract)

All constants live in `rtl/top/strike_defs.vh`. A change needs all four owners to agree.

## Units

| Name | Format | Meaning |
|---|---|---|
| POS | unsigned Q10.6, 16 bit | inches, 1/64 in resolution. World x: 0 = outer edge of the left gutter, lane centre = 30 in. World y: 0 = foul line, head pin = 720 in. |
| VEL | signed Q3.12, 16 bit | inches per physics tick (1/1024 s). 17 mph = 1196. |
| tick | 1024 Hz | `tick_phys`. Slow motion (`sw[3]`) passes 1 in 4; pause (`sw[0]`) blocks it. |

Internal formats are finer. B uses Q10.20 positions and 2^-20 velocities; C uses Q10.12 and Q3.16. Each part converts to POS/VEL at its edge.

## Signals between the parts

| Signal | From → to | Meaning |
|---|---|---|
| `game_state[4:0]` | D → all | `GS_*`: TITLE, MENU, AIM, THROW, ROLL, PINACTION, SETTLE, RESULT, SWEEP, GAMEOVER, NAME, PRACTICE_SWIPE, PRACTICE_SPARE, SCORES, SETTINGS, REPLAY, HELP |
| `settings[15:0]` | D → A, B, C, renderers | [0] long oil, [2:1] ball 12/14/16 lb, [3] left-handed (= `sw[15]`), [5:4] sensitivity, [6] neon theme, [8:7] brightness, [10:9] spin sensitivity (v3: normal / high / max / soft) |
| `throw_valid`, `throw_vy`, `throw_vx`, `throw_spin`, `throw_x0`, `throw_mph10` | A → B, D | Release event. Spin −31..+31 (v3, `SPIN_W` = 6; v2 −7..+7); +ve hooks left. `x0` is the stance (POS). |
| `steer_valid`, `steer_dx` (v3) | A → B | A mouse packet while the ball rolls and its sideways motion; B uses it for `STEER_TICKS` (0.5 s) after release, bounded |
| `target_in` (v3) | A → B, D | Aim-guide target (inches at the arrows), moved by the wheel while aiming |
| `aim_zoom` (v3, v3.1) | D → B, D | Zoom held: right button down from aiming to the pin action (v3: PIN VIEW toggle) |
| `replay_fast` (v3.2) | D turn → D replay | The replay just started is the automatic one (real speed); a click in REPLAY stops it |
| `k_fp[15:0]`, `zoom_lvl[7:0]` (v3.1) | B camera → B projector, lane | First-person lens constant K = 3060 + 84·zl and the zoom level 0..255; `cam_fp` already includes the zl-inch back-off |
| `ball_rev` (v3) | B → D | Side slip left in the ball, 0..255 (REVS bar) |
| `reject` + `reject_msg`, `swipe_cancel`, `too_short` | A → D | A refused swipe (SWIPE FASTER / FORWARD / CANCELLED); D returns to AIM. |
| `grabbing` | A → D | The ball is held (AIM → THROW). |
| `stance_x` | A → B | Where the ball waits while aiming (POS). |
| `cursor_x/y`, `ucur_x/y`, `l_press`, `r_press`, `m_press`, `wheel`, `delta_valid` | A → D | Pointer (v3: VGA pixels 160 × 120; `ucur` = the same point in the 96 × 64 UI window, for the menus) and buttons. |
| `ball_x`, `ball_y`, `ball_vx`, `ball_vy`, `ball_phase` | B → C, D, renderers | Phase: IDLE, SKID, HOOK, ROLL, GUTTER, PIT. |
| `cam_y` (signed, inches) | B → all world renderers | World y of the bottom screen row. A pixel row is at `cam_y + 63 − py`. |
| `pin_rd_idx` → `pin_rd_x/y/vx/vy`, `pin_rd_solid` | B ↔ C | Combinational read port into C's pin register file. |
| `impulse_valid`, `impulse_pin`, `impulse_vx/vy` | B → C | Velocity change for one pin from a ball hit (VEL). |
| `scan_done` | B → C | B finished its pin scan this tick. C runs its own update only now. |
| `standing[9:0]`, `settle_done`, `pins_down_this_ball`, `split_flag`, `standing_before` | C → D | The result of a ball. |
| `rack_go`, `rack_cmd` (FULL / SWEEP / LEAVE), `rack_mask`, `rack_busy` | D ↔ C | Pin-setter. Every command runs the rake first. |
| `pin_vis[239:0]` | C → renderers (replay) | 10 × {x, y, state, dir, stage} |
| text request `TX_*` (53 bit) | A, D layers → D text engine | One string ROM and one copy of each font for the whole design. |

## One physics tick (fixed order)

1. `tick_phys` → B integrates the ball (hook multiply, ~4 clocks).
2. B scans pins 0–9 through the read port, at most ~20 clocks per hit pin. Impulses go to C, which applies them at once because it is idle.
3. `scan_done` → C updates the 10 pins (10 clocks), then the 45-pair iterator (4–17 clocks per pair).
4. Worst case is about 1000 clocks out of 97 656 per tick. Everything finishes long before the next tick, so the order never changes.

## Pixel timing (v3: render engine + frame buffers)

1. `render_scan` walks the VGA picture (160 × 120, `scr` = 0) and then the OLED picture (96 × 64, `scr` = 1) once per frame, holding each pixel 8 clocks. `view_map` turns the pixel into the coordinates each renderer uses (VGA pixel for the 3-D layout, UI-space `ux/uy` for the 96 × 64 picture).
2. All renderers are combinational.
3. `compositor` captures the colour on clock 8 (`cap`); it is written into `vga_out`'s buffers (VGA double buffer, OLED buffer). `done` is `tick_frame`.
4. `vga_out` shows the front VGA buffer at 640 × 480 @ 60 Hz (4 × 4 per logical pixel, dithered to 4 bits per colour) and swaps at the vertical blank; `Oled_Display` reads the OLED buffer through `pixel_index`.

The XDC gives every path into `u_comp/pix_reg` 7 clocks. The Swipe Lab bitmap (block RAM) gets 3 clocks for its address and 3 from its output.

v3.2 / v3.3: the VGA pass is 320 × 240 into one 9-bit buffer (RGB 3:3:3, dithered by `wpar`); the 3-D lane, ball and pins get that position (`hx`, `hy`), every other layer gets it halved (`sx`, `sy` = 160 × 120). `view_map` also outputs `rp_full` (full-screen top-down replay).

### 3-D projection bus (v3.2, B → C's renderer, 320 × 240 units)
`pins_fp[359:0]` = 10 × {vis, bar, x[9:0], row[7:0], class or half-width[4:0], half-height[4:0], neck[4:0], 1'b0}; ball {vis, x[9:0], floor row[7:0], radius[3:0]}. Ball and pin renderers also output `depth` (screen row) for the compositor's occlusion test.

## Save image (128 bytes, `IM_*`)

| Bytes | Content |
|---|---|
| 0–4 | "S", "L", version 1, sequence number (lo, hi) |
| 5–6 | settings |
| 8–15 | strikes, spares, games, best game (16 bit each) |
| 16–40 / 41–65 | top 5 Full / top 5 Quick: {score lo, valid + score bit 8, 3 initials} |
| 66–69 | game in progress: valid, kind, player, frame |
| 70–111 | rolls of player 1 / player 2 (21 each, 15 = not thrown) |
| 112–113 | number of rolls per player |
| 126–127 | CRC-16-CCITT of bytes 0..125 (in flash only) |

Flash slots: A = 0x3E0000, B = 0x3F0000 (each in its own 64 KB sector). The newest valid slot wins.

## Resource log

| Build | LUT | FF | BRAM tiles | DSP | WNS | Notes |
|---|---|---|---|---|---|---|
| 1 (first full design) | 18 843 (90.6 %, post-synth) | — | 1 | 10 | not run | over budget: pin register file written from ~8 places, replay and score registers indexed by variables |
| 2 (resource squeeze) | 16 020 (77.0 %) | 6 792 | 3 | 10 | −5.71 ns, 3 417 paths | pins: 2 write ports; replay: shift registers; scores, flash page, trace: LUTRAM |
| 3 (pipelining) | 15 802 (76.0 %) | 7 519 | 3 | 10 | −2.52 ns, 234 paths | reset replicated (max_fanout); pin reads and writes registered; ball / camera / 7-seg registers |
| 4 | 15 804 (76.0 %) | 7 716 | 3 | 10 | −0.66 ns, 17 paths | hit decision registered, Swipe Lab plot 2 stages, features totals registered |
| **5 (v1 release)** | **15 727 (75.6 %)** | **7 766 (18.7 %)** | **3 (6 %)** | **10 (11 %)** | **+0.089 ns setup, +0.017 ns hold, 0 failing** | Swipe Lab extent in 2 stages; all timing constraints met at 100 MHz |
| 6 (v2 Phase A) | 15 750 (75.7 %) | — | 3 | 10 | +0.140 ns, 0 failing | provisional score, 7-seg rework |
| 7 (v2 first try) | 16 689 (80.2 %) | 8 312 | 3 | 10 | −0.35 ns, 59 paths | first-person view + physics changes: over budget |
| 8 | 15 735 (75.7 %) | — | 3 | 87 | −2.50 ns, 145 paths | `use_dsp` on all renderers: too many DSPs, registers pulled into DSPs |
| **9 (v2 release)** | **15 785 (75.9 %)** | — | **3** | **51 (57 %)** | **+0.251 ns setup, +0.032 ns hold, 0 failing** | debug arrow without multipliers; `use_dsp` only for the lane perspective and projector; projector, pin impulse and scoring paths registered |
| 10 (v3 first try) | 19 778 (95.1 %) | 9 150 | 39.5 | 85 | −3.99 ns, 519 paths | VGA + OLED render engine, frame buffers, 3-D pins, vga_hud, slip physics: congested |
| 11 | 18 972 (91.2 %) | — | 45 | 85 | −6.65 ns, 179 paths | C's pin tables in block RAM (rom2p, −800 LUT); missing ROM→pixel multicycle |
| 12 | 18 753 (90.2 %) | 9 486 | 45 | 82 | +0.288 ns, 0 failing | projector, ball, pin update, gesture trim, camera and HUD paths registered; ROM data gets 5 of the 8 pixel clocks |
| 13 | 18 786 (90.3 %) | 9 499 | 45 | 82 | −0.199 ns, 12 paths | closer PIN VIEW camera: the extra clamp lengthened the camera target path |
| **14 (v3)** | **18 749 (90.1 %)** | **9 536 (22.9 %)** | **45 (90 %)** | **82 (91 %)** | **+0.435 ns setup, +0.022 ns hold, 0 failing** | camera lead and rolling targets registered; projector far-limit bug fixed (`tb_screens`) |
| **15 (v3.1)** | **18 933 (91.0 %)** | **9 577 (23.0 %)** | **45 (90 %)** | **88 (98 %)** | **+0.344 ns setup, +0.033 ns hold, 0 failing** | first-person zoom: lens K into the projector, zoomed row distance in `lane_render` (+6 DSP). DSPs are now nearly full: new multiplies must share |
| 16 (v3.2) | 19 313 (92.9 %) | 9 609 | 40.5 | 87 | +0.313 ns, 0 failing | 320 × 240 VGA in ONE 9-bit buffer (−4.5 tiles vs two 160 × 120 × 16), 3-D renderers at full resolution, auto replay |
| **17 (v3.3)** | **19 390 (93.2 %)** | **9 639 (23.2 %)** | **40.5 (81 %)** | **87 (97 %)** | **+0.399 ns setup, +0.017 ns hold, 0 failing** | full-width 3-D view, half-size panel, full-screen replay with camera overlay, tall OLED scorecard. LUTs at 93 %: the next feature must free logic first |
| 18 (v3.4 try) | — | — | — | 91 of 90 | not placed | haze / grain subtractions inside `lane_render` (use_dsp) became DSPs |
| **19 (v3.4)** | **20 238 (97.3 %)** | **9 706 (23.3 %)** | **40.5 (81 %)** | **86 (96 %)** | **+0.102 ns setup, +0.034 ns hold, 0 failing** | two-circle pin footprint + push-out, pause-quit, initials back, haze / grain moved to `color_dim` (no DSP), ball reflection. Biggest users (synthesis): pin_physics 4 858, all pixel renderers together 4 364, ball_physics 1 419, replay 1 399, flash saves ~1 700 |
| **20 (v3.5)** | **19 661 (94.5 %)** | **9 405 (22.6 %)** | **40 (80 %)** | **86 (96 %)** | **+0.203 ns setup, +0.025 ns hold, 0 failing** | practice section removed (−954 LUT at synthesis), then `backdrop_render` (masking unit, curtain, ceiling at their real distance), neighbouring lanes, new ball reflection, BEST per tab |

The 3 BRAM tiles of v2 are the replay buffer (2 × RAMB36), plus one tile holding two RAMB18s: the Swipe Lab bitmap and A's speed-curve ROM. v3 adds the frame buffers (2 × 160 × 120 × 16 VGA + 96 × 64 × 16 OLED, about 33 tiles), B's oil-pattern ROM and C's 10 pin-table ROMs (rom2p) for 45 tiles in all. The 10 DSP48 slices are the three shared multipliers (A, B, C) and constant/small multiplies that synthesis chose to map to DSPs. The per-module numbers come from `tools/synth_util.tcl` → `build/hier_utilization.rpt`.

## How the timing was met (for the Q&A)
- **Reset fan-out:** one synchronous `rst` register drove about 7 000 flip-flops. `(* max_fanout = 40 *)` makes synthesis copy it.
- **Register file read → maths → write in one clock** (C): the read index, the read data and the write data are now each registered. The FSM waits the extra clocks; the tick has about 97 000 to spare.
- **Long comparison chains** (A's plot and features, B's near test and camera): one register in the middle, plus one extra loop iteration where needed.
