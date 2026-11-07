# Part D integration notes (Student D: game flow, menus and saves)

Branch: `partD-aliasgar`, made from `main` at `4781934` (v3.5 + Part B and Part C rewrites).

## What this branch changes

| Where | What |
|---|---|
| `rtl/d_game_ui/` | The 9 Part D modules rewritten: `crc16`, `spi_byte`, `save_image`, `persist_ctrl`, `flash_ctrl`, `game_fsm`, `menu_render`, `compositor`, `vga_hud` |
| `sim/d/` | 4 new self-checking testbenches: `tb_persist`, `tb_game_fsm`, `tb_spi_byte`, `tb_save_image` (picked up by `run_sim.sh all`) |
| `docs/partD/` | These notes, the feature list, module notes, interfaces, and block / state diagrams |

**Not changed:** `My_Top_Module.v`, `strike_defs.vh`, the XDC, and every A / B / C file.

## Drop-in rules kept

- Same module names, port names, widths and meanings as v3.5, and the same instance names in the top (`u_game`, `u_menu`, `u_vhud`, `u_comp`, `u_persist`, `u_img`, `u_flash`).
- The compositor's capture register is still `pix` (the XDC multicycle rule targets `u_comp/pix_reg[*]`).
- Internal names that the testbenches use are kept: `u_game.mode` (title = 0), `u_game.row_at`, `u_game.act`, `u_game.card_show`, `u_comp.fade`, `u_img.mem`.
- Three small helper modules live inside existing files (no new files to add to a project): `crc_step` in `crc16.v`, `text_layer` in `compositor.v`, `vh_board` in `vga_hud.v`. No name clashes with the rest of the design.

## Behaviour changes (everything else behaves exactly as v3.5)

1. **game_fsm, bug fix:** in SETTINGS, a change followed by a click on a greyed-out (switch) row was never saved in v3.5. It is saved now.
2. **persist_ctrl:** a command arriving on the exact clock its own job finishes is no longer lost.
3. **spi_byte:** SCK always returns low the clock after a byte. flash_ctrl never starts a byte in that clock, so the flash sees the same signals.
4. **vga_hud:** the leftover Spare Challenge panel code is removed (that mode was removed in v3.5; nothing can switch it on).

## What Part D takes from A, B, C (please keep these as they are)

| From | Signals | Modules |
|---|---|---|
| A | clk, rst, tick_frame; mouse pointer (UI space), clicks, wheel; btn_press / repeat / long; switches; swipe info (power, speed, spin, rejects, stance, target); cursor + trail layers; text_engine + string_rom + fonts | timebase, reset_gen, input_conditioner, mouse_setup, swipe_capture, gesture_features, gesture_render, text_engine |
| B | pixel position (ux, uy, hx, hy), cap, scr, v3d, u_in, rp_full; ball speed / position / revs / phase; lane, ball, backdrop layers | render_scan, view_map, ball_physics, lane_render, ball_render, backdrop_render, vga_out |
| C | tstate (GS_* codes), t_game_over, t_kind, game0/1, prov0/1; frame, pins, pop-ups, banner; save commands c_roll / c_hdr / c_clear / c_strike / c_spare as **1-clock pulses**, save_req_t | turn_fsm, score_engine, pin_physics, pin_render, hud_render, scorecard_render |

**Part D gives:** `game_state` and `settings` to everyone; `go_new`, `go_resume`, `kind_out`, `abort`, `persist_busy`, save-image read ports 2 and 6, `want_replay`, `skip`, `card_show` to C; `nudge_l/r`, `hover` to A; `aim_zoom` and `pix` to B; the flash pins.

If a rewrite of yours changes the meaning of one of these (for example new tstate codes, or a save command held longer than one clock), tell me: the name would still match but the behaviour would break.

## How it was checked

- Against the v3.5 originals, same inputs, every output compared: 2,000,000 random clocks (game_fsm), 400,000 (persist_ctrl), 40 saves with 9 power cuts identical on every flash pin (flash_ctrl), every pixel of every menu screen (4.2 M) and of the VGA panel / overlays (2.8 M).
- The team's `tb_flash`: 13 / 13.
- `bash sim/lint.sh`: no errors.
- `bash sim/run_sim.sh all` on this branch: see the result in the pull request / commit message.
- Size: the 9 modules synthesise to **4,588 LUTs vs 4,547 for v3.5 (+41)**, inside the ~250 per-part budget.

## To do at merge time (integrator)

1. Merge the part branches into `main`.
2. `bash sim/lint.sh`, then `bash sim/run_sim.sh all`.
3. `vivado -mode batch -source tools/build.tcl`: check WNS ≥ 0, WHS ≥ 0, 0 failing endpoints, total LUTs.
4. Program the board and run the Part D demo: play a frame → leave (pause + click, it saves) → reprogram → RESUME → same frame and scorecard.

## Before the final archive (everyone)

Part D's comments will be trimmed to short, practical ones before the archive. Please do the same in your own files so the four parts read alike.

## More detail

- [FEATURES_AND_CONTROLS.md](FEATURES_AND_CONTROLS.md): every Part D feature, its controls, why it is built that way, and where the code is
- [MODULE_NOTES.md](MODULE_NOTES.md): each module's inputs / outputs, how it works, hand-worked checks, test results
- [INTERFACES_PARTD.md](INTERFACES_PARTD.md): the full signal list between Part D and A, B, C
- [images/](images/): block diagrams (`D_*.svg`) and state diagrams (`D_fsm_*.svg`)
