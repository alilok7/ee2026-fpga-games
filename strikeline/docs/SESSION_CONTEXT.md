# StrikeLine session context (for any Claude picking this up)

Last updated: 2026-11-05. Read this after the root `CLAUDE.md`, `docs/BUILD_HISTORY.md` and `strikeline/docs/INTERFACES.md`.

This is a summary of a long review-and-rework session with the team member who owns **Part D** (game FSM, scoring, menus, 7-seg, inputs). The member is a Year 2 student who has used Verilog for about 3 months: Labs 1, 2 and 4, the OLED GPT tasks, and lectures L1-L4 (sequential circuits, counters, FSMs, modular FSMs).

## 1. How the team works now (read this first)

- **Code changes** are made by a Claude instance working from this repo (any machine).
- **Builds, simulation and hardware tests** happen on the student's laptop only. It has Vivado 2025.2 at `C:/AMDDesignTools/2025.2/Vivado/bin`, the board and the repo clone at `C:\dev\ee2026-fpga-games`.
- Handoff: push your changes to a branch (currently `v3-dual-oled`). On the laptop, pull, then run:
  ```
  cd strikeline
  bash sim/lint.sh
  bash sim/run_sim.sh all            # 8 testbenches, a few minutes
  vivado -mode batch -source tools/build.tcl   # bitstream + reports in build/ (~15-20 min)
  ```
  Bitstreams are not committed (`build/` is ignored). They are attached to GitHub Releases.
- If you cannot run Vivado, say so and list the exact tests the laptop must run. Never claim that something passed if you didn't see it pass.

## 2. Current state (branch `v3-dual-oled`)

- **v3 = dual OLED.** OLED 1 shows the lane, and OLED 2 (scoreboard or switch page, drawn by C's `screen2`) is now on **JXADC** (see `My_Top_Module.v` header and the XDC). Check that it is on a different side of the board from JC: the course requires the two OLEDs not to be on the same side.
- **Last build (2026-11-05, after the Part D simplification):** 16,238 LUT (78.07 %), 8,447 FF, 3 BRAM tiles, WNS +0.402 ns, WHS +0.028 ns, 0 failing endpoints. The build before the simplification was 16,180 LUT (77.79 %), WNS +0.507. A copy of that bitstream is on the laptop in `strikeline/build/v3_before_simplify/`.
- **Testbenches:** all 8 pass: tb_gesture, tb_carry, tb_physics, tb_flash, tb_scoring (29 checks), tb_resume, tb_screens, tb_top.
- **Hardware:** nothing has been run on the real board yet. That is the biggest risk.
- **The INTERFACES.md resource log stops at build 9 (v2).** Add the v3 numbers above.

## 3. Changes made in this session

Rewritten by Claude at Student D's request, in a simpler lecture style so they are easier to study. Every port and behaviour is unchanged. Logged in `strikeline/docs/REFERENCES_AND_AI_USE.md` (change log table).

| File | What changed |
|---|---|
| `d_game_ui/debounce.v` | Same counter, plain comments; removed stale KeyLight text ("rhythm game", "strikes") |
| `d_game_ui/button_events.v` | One always block per output: prev, press, hold_ms, long_press, repeat |
| `d_game_ui/seg7_driver.v` | Lab 4 style: digit counter → `case (digit)` picks code/dp/anode → glyph table in binary → output registers |
| `d_game_ui/seg7_ctrl.v` | `/` and `%` by constants instead of the `bcd9` double-dabble function |
| `d_game_ui/score_engine.v` | Lecture 3/4 FSM: next-state block + state register + combinational frame scorer + datapath. States IDLE → COUNT → LOAD (copy 21 rolls into `roll[]`) → BLANK (frames before `start_frame`) → FRAME (one frame per clock) → NEXT (player 2) → done. `fr_mem` keeps its name because `tb_scoring` reads it by hierarchy. |

## 4. Review findings still open

1. **The top module says "wiring only" (`My_Top_Module.v:11`) but has logic:** frame_cnt, plot_sel, the state decodes (in_lab, throw_go, in_play, fp), the replay muxes, the LED mux. Either change the comment to "wiring plus glue" or move the logic into owned modules. Someone must be able to explain each line.
2. **Duplication:** the brightness case and the 6-clock capture register are in both `compositor.v` and `c_pins/screen2.v`. A shared `oled_out.v` would fix it.
3. **Dead code:** `d_game_ui/bin2bcd.v` is never instantiated; delete it and its mention in REFERENCES.
4. **Stale docs:** `C_DESIGN.md` says the topple threshold is 1300, but the code has `TOPPLE_P = 2200` (`pin_physics.v:41`). `seg7_driver` no longer mentions the "sharp sign" (fixed).
5. **Part C has no testbench of its own** (there is no `sim/c/`).
6. **The student-name block** in `My_Top_Module.v` lines 4-8 is empty.
7. **Part D is much larger than A, B and C** (~2,700 lines vs ~1,000-1,200). Proposed rebalance, not yet done (it needs the whole team to agree, and the `Owner:` lines plus `docs/TEAM.md` updated):
   - `flash_ctrl`, `spi_byte`, `crc16` → **A** ("external interfaces: PS/2 + SPI")
   - `compositor`, `text_engine`, `string_rom`, `strings_map.vh`, `txt_helpers.vh`, `bcd_fns.vh`, `replay_buffer` → **B** ("ball + video pipeline")
   - `hud_render`, `scorecard_render` → **C**
   - D keeps game_fsm, turn_fsm, score_engine, persist_ctrl, save_image, menu_render, seg7_ctrl, seg7_driver, input_conditioner, debounce, button_events

## 5. Rules for whoever continues (agreed in this session)

- **Keep `REFERENCES_AND_AI_USE.md` truthful.** Every AI change goes in its change-log table with the date, files and what was done. The course gives full penalties for undocumented AI use, and the TA's guideline is about 30 % AI. The repo already says the code is AI-generated (`BUILD_HISTORY.md`, `TEAM.md`), so the honest log is the student's protection.
- **Don't disguise authorship.** The student asked twice for changes meant to make AI code "look student-written" (splitting styles to look like four authors, adding inefficiencies). Claude declined those and instead offered simpler, easier-to-explain rewrites that are logged as AI work. Keep to that: making code **simpler to understand** is fine; making it look like someone else wrote it is not.
- **The best way to raise genuine ownership** is for the student to type their own versions of small modules (debounce, button_events, seg7_driver), with Claude reviewing and the existing testbenches checking them, and to log those as student changes.
- **Resources:** the hard limit is 100 % of the XC7A35T (Project Manual "FPGA resource limitations"). In practice this design failed timing at 80.2 % once (build 7), so keep new logic pipelined. Up to about 85 % LUT is acceptable if timing still closes.
- Verilog-2001 only. Every file starts with a `// name.v - purpose` header. Use tick enables, not new clocks.

## 6. Recommended next steps (in order)

1. **Hardware bring-up** with `strikeline/README.md`'s checklist: OLED 1 on JC, OLED 2 on JXADC, mouse in the USB host port. Take the real OLED photos for the report.
2. Optionally simplify `game_fsm.v` and then `turn_fsm.v` into the 2-always lecture style. Do one at a time, and run tb_top, tb_resume and tb_screens after each.
3. Fix review items 1-6 above.
4. Report (Sheet A ≤ 500 words, optional devices in bold, real photos; Sheet B lists references plus the full AI log).

Q&A prep for Part D (the questions an assessor is likely to ask) is in `strikeline/docs/D_DESIGN.md`. Add these: how the 1 ms tick is made (100,000 counts), why tick enables instead of slow clocks, the 2-flop synchroniser, 7-seg refresh (1 ms per digit, 250 Hz), the LED assignment in `My_Top_Module.v` (LED mux near the end), strike / spare / 10th-frame scoring, official vs provisional totals, and why the design fits at 78 % (resource log in INTERFACES.md: the first build was 90.6 %; LUTRAM, a two-port pin file, shared multipliers and text engines brought it down).

## 7. Deadlines (check Canvas for the exact dates)

Around 7, 9 and 11 Nov 2026 (archive, report, peer feedback), with the demo and Q&A in week 13. Any code change must be in the bitstream before the archive is submitted.
