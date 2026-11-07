# 03. What Part D takes and gives (through My_Top_Module, v3.5)

All of this comes from `rtl/top/My_Top_Module.v`. Constants such as `GS_*`, `SET_*`, `IM_*`, `PK_*` and `TX_*` come from `strike_defs.vh` (the frozen contract; don't change it alone).

## 1. What I TAKE (my inputs)

### From Student A (controls, timebase, text engine)

| Signal (top-level name) | Width | Goes into | Meaning |
|---|---|---|---|
| `clk`, `rst` | 1 | all my modules | 100 MHz clock; reset from A's `reset_gen` |
| `tick_game` | 1 | game_fsm | 1 ms game tick (A's `timebase`; stops while paused) |
| `tick_frame` | 1 | menu_render, vga_hud, compositor | one pulse per drawn frame (~60 Hz), for blinking and the fade |
| `ucur_x`, `ucur_y` | 7, 6 | game_fsm (`cursor_x/y`) | mouse pointer in UI space (96 x 64), for hover |
| `delta_valid` | 1 | game_fsm (`mouse_move`) | a mouse packet arrived |
| `l_press`, `r_press`, `m_press` | 1 | game_fsm | one-clock click pulses |
| `r_level` | 1 | game_fsm | right button held (zoom) |
| `wheel` | 4 signed | game_fsm | wheel movement |
| `btn_press`, `btn_repeat`, `btn_long` | 5 each | game_fsm | button events `{U, D, L, R, C}` (A's input_conditioner) |
| `sw_level[0]` (`paused`) | 1 | game_fsm, vga_hud | pause switch |
| `sw_level[14:11]` (`sw_play`) | 4 | game_fsm | {long oil, neon, 16 lb, 12 lb} switches |
| `sw_level[15]` (`lefty_sw`) | 1 | game_fsm | left-handed switch |
| `grabbing`, `live_power`, `throw_valid`, `throw_spin`, `throw_mph10`, `reject`, `reject_msg`, `swipe_cancel \| too_short`, `stance_x[12:6]`, `target_in` | various | vga_hud | swipe state for the info panel and messages |
| `cur_en`/`cur_c`, `a_en`/`a_c`/`a_t` | layer | compositor | A's cursor layer and trail/meter layer |
| `text_engine`, `string_rom`, `strings_map.vh`, `txt_helpers.vh`, `bcd_fns.vh` | files | compositor, menu_render, vga_hud | shared text and digit helpers (A's code, used unchanged) |

### From Student B (video pipeline, ball)

| Signal | Width | Goes into | Meaning |
|---|---|---|---|
| `cap`, `scr` | 1 | compositor | `render_scan`: capture this pixel now; 0 = VGA pass, 1 = OLED pass |
| `ux`, `uy` | 7, 6 | menu_render (`px_x/y`) | the pixel in UI space (from `view_map`) |
| `sx`, `sy`, `hx`, `hy` | 8, 7, 9, 8 | vga_hud | the pixel at 160 x 120 and 320 x 240 |
| `v3d`, `u_in`, `rp_full` | 1 | vga_hud, compositor | which layout this pixel uses: 3-D game, inside the UI window, full-screen replay |
| `sign_row`, `sign_ok` | 7, 1 | vga_hud | where the STRIKELINE sign goes on the masking unit |
| `ball_rev`, `ball_vy`, `ball_x`, `ball_y`, `ball_phase` | various | vga_hud | live speed, revs and the entry board in the panel |
| `ball_*`, `lane_*`, `bd_*` layers | layer | compositor | B's ball (with depth), lane and backdrop |

### From Student C (turns, scoring, pins)

| Signal | Width | Goes into | Meaning |
|---|---|---|---|
| `tstate` | 5 | game_fsm | turn_fsm's state; this becomes `game_state` while a game runs |
| `t_active`, `t_game_over`, `t_kind` | 1, 1, 3 | game_fsm | game running / finished / kind (Full, 2P, Spare) |
| `game0`, `game1` | 9 each | game_fsm, menu_render | official totals (top-5 check, game-over screen) |
| `prov0`, `prov1` | 9 each | vga_hud (`score0/1`) | live (provisional) points |
| `card_word` | 28 | vga_hud | a scorecard word; vga_hud sends `card_addr` back |
| `player`, `frame`, `ball_no`, `popup_id`, `popup_n`, `banner`, `spare_made`, `spare_tries` | various | vga_hud | panel contents and popups |
| `standing` | 10 | vga_hud (`pins_standing`) | pin diagram |
| `c_roll`, `roll_p`, `roll_idx`, `roll_val`, `c_hdr`, `hdr_valid`, `hdr_player`, `hdr_frame`, `c_clear`, `c_strike`, `c_spare` (+ `t_kind` as `hdr_kind`) | various | persist_ctrl | save every roll and the game header into the save image |
| `save_req_t` | 1 | flash_ctrl (ORed with mine) | save to flash after a frame |
| `sc_*`, `hud_*`, `pin_*` layers | layer | compositor | C's scorecard, HUD and pins |

## 2. What I GIVE (my outputs)

| Signal | From | To | Meaning |
|---|---|---|---|
| **`game_state`** | game_fsm | **everyone** | the current screen or game state (`GS_*`) |
| **`settings`** | game_fsm | A (sensitivity, spin), B (oil, ball weight, theme), all renderers (theme, brightness) | the 16-bit settings word (`SET_*`) |
| `settings_raw` | game_fsm | persist_ctrl | the menu's settings, as saved |
| `go_new`, `go_resume`, `kind_out`, `leave_mask`, `abort` | game_fsm | C turn_fsm | start, resume or stop a game |
| `want_replay`, `skip` | game_fsm | C turn_fsm, A replay_buffer | replay request / click to skip |
| `card_show` | game_fsm | C scorecard (`show`) | show the scorecard |
| `aim_zoom` | game_fsm | B camera and lane, my vga_hud | zoom while the right button is held |
| `nudge_l`, `nudge_r` | game_fsm | A swipe_capture | move one board left/right while aiming |
| `hover` | game_fsm | menu_render, A seg7_ctrl | highlighted menu row |
| `persist_busy` | persist_ctrl | C turn_fsm, game_fsm, flash_ctrl | the save image is being updated: wait |
| `saving` | flash_ctrl | C hud_render, my vga_hud | "SAVING" indicator |
| `flash_ok`, `load_done` | flash_ctrl | menu_render, game_fsm, `led[9:0]` | flash present; boot load finished |
| save image read ports 2 and 6 | save_image | C score_engine (`ra_score`/`rd_score`), C turn_fsm (`ra_turn`/`rd_turn`) | C reads the rolls back |
| `vh_card_addr` | vga_hud | C score_engine (muxed with C's own in the top) | which scorecard word the panel wants |
| **`pix`** | compositor | B vga_out (frame buffers → VGA + OLED) | the final colour of every pixel |
| `QspiCSn`, `QspiDB[3:0]`, `spi_sck` → `STARTUPE2` | flash_ctrl | board pins | the flash |

## 3. Save image read ports (save_image has 7)

| Port | Used by | Owner |
|---|---|---|
| 0 | flash_ctrl (snapshot for saving) | D |
| 1 | persist_ctrl (read-modify-write) | D |
| 2 | score_engine (rolls) | C |
| 3 | game_fsm (settings at boot, top-5 check) | D |
| 4, 5 | menu_render (low and high byte of a value) | D |
| 6 | turn_fsm (resume) | C |

## 4. Rules I must not break (or integration fails)

1. **Same module names, port names, widths and meanings** as v3.5. Same instance names in the top (`u_game`, `u_menu`, `u_vhud`, `u_comp`, `u_persist`, `u_img`, `u_flash`).
2. **Keep the compositor's output register named `pix`.** The XDC gives paths into `u_comp/pix_reg[*]` 7 clocks (`set_multicycle_path -setup 7` / `-hold 6`). If I rename it, timing fails.
3. **Renderers are combinational in the pixel position** (menu_render, vga_hud): the colour must be ready within the 7-clock window. Registered helpers that update once per frame are fine.
4. **The layer contract:** each layer gives `en` (I draw this pixel), `color` (RGB565, 16 bits) and `txt` (a 53-bit `TX_*` text request, or 0). The compositor gives the first valid text request to the one text engine.
5. **Save image layout** is `IM_*` (128 bytes, CRC over bytes 0..125 at 126/127). C's code reads it too.
6. **`persist_ctrl` is the only game writer**, and `flash_ctrl` writes only at boot. `persist_busy` must be high whenever a command is pending, or a save can capture a half-updated image.
7. **Flash slots** at 0x3E0000 and 0x3F0000 (top two 64 KB sectors), so the bitstream area is never touched.
8. **Budget:** about 250 LUTs over what the v3.5 Part D modules use now. Measure the v3.5 numbers first (doc 05).

## 5. What I assume about my teammates' modules

**I take signals (wires), not modules.** A's, B's and C's modules make the signals in section 1; `My_Top_Module.v` wires them into my modules. I never instantiate their modules myself, with one exception: A's `text_engine` (+ `string_rom`, fonts), which sits inside my compositor.

| From | Their modules that make what I take |
|---|---|
| **A** | `timebase`, `reset_gen`, `input_conditioner` (buttons, switches), `mouse_setup`, `swipe_capture`, `gesture_features`, `gesture_render` (cursor, trail), `text_engine` + `string_rom` + fonts |
| **B** | `render_scan` + `view_map` (which pixel), `ball_physics`, `lane_render`, `ball_render`, `backdrop_render`, `vga_out` (takes my `pix`) |
| **C** | `turn_fsm` (game states, save commands), `score_engine` (scores, reads the save image), `pin_physics` + `pin_render`, `hud_render`, `scorecard_render` |

**My assumption:** these modules exist and work as in v3.5, with the **same names, ports, widths and meanings**. This is the team rule: nobody changes a module's ports, `strike_defs.vh` or `My_Top_Module.v` without all four agreeing. If a teammate rewrites a module and keeps its ports, my modules don't notice any difference.

**To check at integration:**
1. Each teammate confirms their port lists still match v3.5.
2. The meanings are unchanged, for example `tstate` still uses the `GS_*` codes, and the save commands (`c_roll`, `c_hdr`, ...) are still 1-clock pulses. A wire with the right name but a new meaning would break things silently.
3. Run the whole-design testbenches after the merge (`tb_resume`, `tb_screens`, `tb_top`) and the build (WNS ≥ 0, WHS ≥ 0).

**Until integration I don't need them:** my testbenches and the board test top use stand-ins (a stub turn_fsm, the buttons instead of A's mouse, the course `Oled_Display` instead of B's frame buffers).
