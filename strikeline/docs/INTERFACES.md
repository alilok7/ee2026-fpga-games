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
| `settings[15:0]` | D → A, B, C, renderers | [0] long oil, [2:1] ball 12/14/16 lb, [3] left-handed (OR `sw[15]`), [5:4] sensitivity, [6] neon theme, [8:7] brightness |
| `throw_valid`, `throw_vy`, `throw_vx`, `throw_spin`, `throw_x0`, `throw_mph10` | A → B, D | Release event. Spin −7..+7; +ve hooks left. `x0` is the stance (POS). |
| `reject` + `reject_msg`, `swipe_cancel`, `too_short` | A → D | A refused swipe (SWIPE FASTER / FORWARD / CANCELLED); D returns to AIM. |
| `grabbing` | A → D | The ball is held (AIM → THROW). |
| `stance_x` | A → B | Where the ball waits while aiming (POS). |
| `cursor_x/y`, `l_press`, `r_press`, `m_press`, `wheel`, `delta_valid` | A → D | Pointer and buttons for the menus. |
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

## Pixel timing (unchanged from KeyLight, proved by its tb_top)

1. `pixel_xy` captures `pixel_index` and computes x/y (2 registers).
2. All renderers are combinational.
3. `compositor` captures the colour 6 clocks after x/y stopped changing.

The XDC gives every path into `u_comp/oled_data_reg` 6 clocks. The OLED latches 16 clocks after the index changes. Renderers that read block RAM (the Swipe Lab bitmap) present the address from `px_x/px_y`, and the 1-clock read fits inside the window.

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
| **5 (final)** | **15 727 (75.6 %)** | **7 766 (18.7 %)** | **3 (6 %)** | **10 (11 %)** | **+0.089 ns setup, +0.017 ns hold, 0 failing** | Swipe Lab extent in 2 stages; all timing constraints met at 100 MHz |

The 3 BRAM tiles are the replay buffer (2 × RAMB36), plus one tile holding two RAMB18s: the Swipe Lab bitmap and A's speed-curve ROM. The 10 DSP48 slices are the three shared multipliers (A, B, C) and constant/small multiplies that synthesis chose to map to DSPs. The per-module numbers come from `tools/synth_util.tcl` → `build/hier_utilization.rpt`.

## How the timing was met (for the Q&A)
- **Reset fan-out:** one synchronous `rst` register drove about 7 000 flip-flops. `(* max_fanout = 40 *)` makes synthesis copy it.
- **Register file read → maths → write in one clock** (C): the read index, the read data and the write data are now each registered. The FSM waits the extra clocks; the tick has about 97 000 to spare.
- **Long comparison chains** (A's plot and features, B's near test and camera): one register in the middle, plus one extra loop iteration where needed.
