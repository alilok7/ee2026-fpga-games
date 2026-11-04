# KeyLight interfaces

The frozen contract is `rtl/top/keylight_defs.vh`. This page explains it. To change any signal below, all four owners have to agree.

## Clocks and ticks (`rtl/top/timebase.v`, explained by A)

| Signal | Rate | Notes |
|---|---|---|
| `clk` | 100 MHz | The only clock for logic. |
| `tick_1ms` | 1 kHz | One-cycle pulse: debounce, song clock, timers. |
| `tick_sample` | 48 828.125 Hz | 100 MHz / 2048: DDS and audio output. |
| `tick_frame` | 60 Hz | Pulses at the **end** of each OLED frame's pixel stream. State that renderers read changes on this tick, so it never changes mid-frame. |
| `clk6p25m` | 6.25 MHz | Divide-by-16 counter bit 3. Drives **only** `Oled_Display`. |
| `rst` | — | Synchronous, active high. Held 10 ms at power-on and after the soft reset (U+D for 2 s). `por_rst` resets the OLED at power-on only. |

## Pixel timing (proved by `sim/top/tb_top.v`)

`Oled_Display` changes `pixel_index` on a falling edge of `clk6p25m`. It latches `pixel_data` on the **next** falling edge, while `sample_pixel` is high, which is 16 system clocks later. `pixel_index` then holds for 15 more `clk6p25m` cycles.

The video pipeline at 100 MHz:

| Stage | Register | When |
|---|---|---|
| 1 | `pixel_xy.idx` | Captures `pixel_index`, 1 clock after it changes. |
| 2 | `pixel_xy.px_x/px_y` | Divider-free x/y, 1 clock later. |
| 3 | `mux_video.oled_data` | Captured only when `settle` counts down, 7 clocks after x/y change. |

All renderers are combinational, and the slowest takes about 14 ns. The XDC therefore gives every path into `oled_data` 6 clocks (`set_multicycle_path -setup 6 / -hold 5`). The colour is captured about 9 clocks after `pixel_index` changes, which is 7 clocks before the OLED latches it.

A renderer that reads block RAM must present its address from `px_x`/`px_y`. The read then completes inside the 6-clock window. `tb_top` checks every pixel of a whole frame at the exact latch edge: 6143 pixels, 0 wrong.

Game state can change at any moment, for example when a strike's pop-up timer starts. At worst one pixel of one frame shows the old value. Note positions only change on `tick_frame`, between frames.

## Mode and settings (D to everyone)

| Signal | Width | Values |
|---|---|---|
| `mode` | 4 | 0 TITLE, 1 MENU, 2 SONGSEL, 3 PLAY, 4 RESULTS, 5 NAME, 6 LEARN, 7 FREE, 8 SCORES, 9 SETTINGS, 15 TEST (colour bars: long-press D on the title) |
| `song_id` | 3 | 0 Twinkle, 1 Mary, 2 Ode to Joy, 3 Jingle Bells, 4 MY SONG (only when `rec_exists`) |
| `difficulty` | 2 | 0 Easy, 1 Normal, 2 Hard |
| `settings` | 16 | `[1:0]` instrument, `[4:2]` volume, `[6:5]` note speed, `[7]` LED guides, `[8]` metronome, `[9]` theme, `[11:10]` brightness, `[15:12]` reserved |

The default settings are piano, volume 5, normal speed, guides on, metronome off, dark theme and full brightness.

## Input (B to everyone)

| Signal | Width | Meaning |
|---|---|---|
| `key_strike` | 13 | One-cycle pulse when a key switch flips in **either** direction (5 ms debounce). Chromatic: bit 0 = C4 (`sw[15]`), 1 = C#4 (`sw[7]`), 2 = D4 (`sw[14]`), … 12 = C5 (`sw[8]`). |
| `key_level` | 13 | Debounced switch levels, same order. |
| `ctl_level` | 3 | {octave `sw[2]`, mute `sw[1]`, pause `sw[0]`} |
| `btn_press` / `btn_long` / `btn_repeat` | 5 each | Order {U, D, L, R, C}. Pulses: press; long press at 1 s; repeat from 400 ms, then every 100 ms. |

## Sound bus (to A, chosen by `mux_io`)

| Signal | Width | Meaning |
|---|---|---|
| `ev_valid` / `ev_note` / `ev_vel` | 1 / 7 / 2 | Note-on. MIDI note (C4 = 60). Velocity 1 = soft, 2 = normal, 3 = loud. The note ends through the envelope release. |
| `sfx_valid` / `sfx_id` | 1 / 4 | 1 move, 2 select, 3 back, 4 perfect, 5 miss, 6 combo, 7 record jingle, 8 click, 9 click (downbeat) |
| `scope_sample` | 8 | A to B: the latest output sample, unsigned, 128 = silence. |

The source by mode: Play uses C's hits, Free Play uses B's keys, and Learn uses D. The other modes play D's UI sounds.

## Chart port (C and D read, B serves MY SONG)

Each address holds one 24-bit word. There are 512 words per song, and data arrives one clock after the address.

| Word | Layout |
|---|---|
| 0 (header) | `{step_ms[23:14], event_count[13:5], 5'b0}`, where `step_ms = 15000 / BPM` (ms per 16th note, computed by the script) |
| Event | `{note[23:17], start_step[16:6], len_steps[5:0]}`. Note 0 marks the end. |

ROM songs come from `songs/*.txt` through `tools/song_to_mem.py`, producing `data/songs.mem`. MY SONG is read through `chart_reader.my_addr` / `my_data`, from B's RAM.

## Results (C to D, B)

`res_valid` is a one-cycle pulse. The bundle is `res_score[19:0]`, `res_perfect` / `res_good` / `res_miss` / `res_maxcombo[8:0]`, `res_acc[6:0]` (%) and `res_grade[2:0]` (0 S, 1 A, 2 B, 3 C, 4 D).

## Storage (B, Phase 4)

`hs_rd_song` / `hs_rd_diff` give `hs_score[19:0]` + `hs_initials[14:0]` (3 × 5 bits, 1 = A … 26 = Z). The other signals are `hs_wr_req`, `rec_save_req`, `save_busy`, `rec_exists` and `flash_ok`. They are tied off in the slice: no recording, best score 0.

## Video, LEDs, 7-segment

| Bus | Producers | Meaning |
|---|---|---|
| `px_color` | B, C, D | 16-bit RGB565 from each renderer. |
| `ov_color` + `ov_en` | D | Overlay on top of every mode: hint bar, pause banner, toasts. |
| `led_req` | B, C, D | 16 bits each. `mux_io` picks one by mode, and `led[2:0]` is always {recording, muted, paused}. |
| `seg_glyphs` | B, C, D | 4 × 6-bit glyph codes, leftmost digit in bits `[23:18]`: 0–9 digits, 10–35 A–Z, 36 blank, 37 dash. Also `seg_dp[3:0]` and `seg_blink[3:0]`. |

## Resource log (post-implementation, XC7A35T: 20 800 LUT, 41 600 FF, 50 BRAM36, 90 DSP)

| Date | Milestone | LUT | FF | BRAM36 | DSP | WNS (ns) |
|---|---|---|---|---|---|---|
| 2026-11-02 | Phase 1+2: base build + vertical slice | 3 815 (18.3 %) | 2 471 (5.9 %) | 1.5 (3 %) | 2 (2.2 %) | +0.309 |

Notes on the first build:
- The first build failed timing (WNS −5.5 ns). There were two causes.
  1. **Renderers into `oled_data`:** the combinational renderers take more than 10 ns. Fixed with a capture enable in `mux_video` plus a 6-cycle multicycle constraint (see "Pixel timing").
  2. **`note_table` scans:** selecting one of 24 slots and doing the arithmetic in one clock was too slow. Fixed by splitting each scan into two pipeline stages. The LED guides got a pipeline register before the shared multiplier.
- The 1.5 BRAM36 are the chart ROM (2048 × 24). The 2 DSPs are the loader's step multiplier and the LED-guide square.
- The budget target is ≤ 75 % LUT. About 57 % is left for Phase 3 and 4.
