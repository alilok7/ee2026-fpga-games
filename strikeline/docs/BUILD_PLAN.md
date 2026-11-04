# StrikeLine build plan (engineer's working plan)

Spec: `../../prompts/Bowling_Engineer_Prompt.md`. Roadmap: `../../prompts/Bowling_Roadmap_and_Work_Split.md`.
StrikeLine lives in `strikeline/` and is fully separate from KeyLight (repo root).

## Order of work
1. Contract: `rtl/top/strike_defs.vh`, `docs/INTERFACES.md`.
2. Base: `timebase` (tick_phys 1024 Hz, ÷4 slow-mo, pause gate; tick_sample 200 Hz; tick_frame; tick_1ms),
   `reset_gen`, `pixel_xy`, `input_conditioner`, `mouse_setup` (cursor), compositor with capture enable,
   XDC (PS/2 C17/B17 pull-ups, QSPI), `tools/build.tcl`, `sim/run_sim.sh`.
3. Physics chain (vertical slice and then the full version):
   A `swipe_capture` → `gesture_features` → throw event
   B `ball_physics` (SKID/HOOK/ROLL/GUTTER/PIT, ball→pin contact, impulses) + `camera`
   C `pin_physics` (impulses, 45-pair iterator, wobble/topple, walls, pit, rack/rake) + `pin_settle` + `split_detect`
4. D: `game_fsm` (modes + menus), `turn_fsm` (frames/balls/players/rack), `score_engine`, `save_image`,
   `flash_ctrl` + `spi_byte` + `crc16`, `record_keeper` (stats, top-5), renderers (menus, HUD, scorecard, popups),
   `seg7_ctrl`, `replay_buffer`.
5. Renderers: B lane/minimap/ball/debug, C pins/rake, A cursor/trail/meters/labels/Swipe Lab.
6. Testbenches (self-checking): gesture, ball phase FSM, ball–pin + pin–pin (momentum), settle, split,
   scoring (≥10 games), flash FSM vs flash model, top-level pixel timing.
7. Vivado build, resource log in INTERFACES.md, timing at 100 MHz, LUT ≤ 75 %.
8. Docs: A–D design docs (block diagram, FSMs, formats, 15 Q&A each), references/AI use, demo script.
9. Then KeyLight: remaining Phase 3/4 items from `KeyLight_Roadmap_and_Work_Split.md`.

## Key design decisions (deviations from the brief are explained in the design docs)
- Fixed point: ball pos Q10.20 / vel 2^-20 in/tick (24 b); pins pos Q10.12 / vel Q3.16 (20 b);
  interfaces use pos Q10.6 (16 b) and vel Q3.12 (16 b, in/tick).
- Mouse: relative deltas per packet (read on new_event, re-centre with setx/sety) instead of a clamped
  384×256 range, so a long flick never saturates. MouseCtl reports at 40 Hz (SAMPLE_RATE 0x28), so speed is the
  peak 80 ms displacement in the last 120 ms of the swipe, not the last 40 ms.
- Aim has a ±6° dead zone and low gain (a 45° swipe gives a 1.6° launch), so a stranger can throw straight.
- Each tick: B scans the 10 pins first (impulses go to C while C is idle), then C runs its pair iterator.
- Pin sprites: the ROM stores only the N and NE directions × 3 fall stages; the other 6 directions come from flips and
  transposes, which is cheap enough for 10 parallel per-pin renderers (no overlap artefacts).
- Flash: two slots in two different 64 KB sectors (0x3E0000 / 0x3F0000), because one sector erase
  would wipe both slots in a single block. CRC-16-CCITT, sequence number, newest valid slot wins.
- Quick Game = frames 8–10, so the 10th-frame bonus rules appear in every demo.

## Cannot be done without hardware (left for the team)
Feel tuning with 5 new players, mouse re-plug test, power-loss-during-save test, OLED photos.
