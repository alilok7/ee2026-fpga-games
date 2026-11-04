# KeyLight: engineering brief

*Paste everything below this line to the engineer.*

---

You are the senior engineer on a 4-person university FPGA project. Your job is to design and build **KeyLight**, an interactive piano rhythm game, in Verilog on a Digilent **Basys3** board. The code is split into four parts, one per student (A, B, C, D). Each student is marked on their own part, the team is marked on how well the four parts work as one product, and each student is questioned on their own code. Read the whole brief before writing any code. The marking rules decide many of the design choices below.

## 1. The course and how this project is marked

The course is NUS EE2026 Digital Design, AY2026/27 Semester 1. The project is worth 30% of the course grade:

| Item | Weight | Notes |
|---|---|---|
| Student A / B / C / D component | 9% each, individual | Each part needs a "reasonable amount of Verilog" and "should not have much overlap" with the others |
| Integration of A+B+C+D in ONE bitstream | 9%, group | "How well the different components … are integrated together into one bitstream to create a more complete project" |
| Execution, Q&A, understanding, report and word limits | 9%, individual | A student who can't explain basic things about their own code can get **zero** for Q&A |
| Proposal (already submitted) + peer feedback | 2% + 1% | Not your concern |

**There are exactly four judging criteria:** **Functionality**, **Robustness & reliability**, **User Interface**, **User Experience**. The teaching assistant (TA) added these points:
- Creativity and raw complexity are not marked on their own. **Integration complexity** is: every part must depend on and feed into the others. Four demos behind a mode switch scores very low.
- UX weighs heavily. The A+ project last semester had a very interactive, intuitive UI. A pool game lost marks because its controls weren't intuitive.
- Graders want to see that the students "can program in Verilog quite well". Clean, efficient, well-structured RTL matters.
- **FPGA resources are the real limit.** Optimise: draw shapes with range checks, not pixel-by-pixel tables, and share hardware. Integration often pushes usage over 100% when parts that each fit are combined.
- Graders have seen almost every past project, and any copied code will be recognised. All external or generated code must be cited in the report.

**Official rules that constrain the design** (from the Project Manual):
- Everything must run in **one bitstream**. A demo from a separate bitstream is not accepted.
- **Compulsory hardware:** Basys3 and the Pmod OLED (96×64, 16-bit RGB565). The UI must use the **switches, LEDs and OLED**. Seven-segment display, multiple OLEDs, mouse and keyboard are optional, and *unnecessary devices are discouraged*.
- **Optional lab devices** (no code is provided for them and no extra marks are given): audio input Pmod, **audio output Pmod**, and a VGA-to-HDMI converter. Two OLEDs must **never** go on the same side of the board.
- The report has a hard limit of 500 words for 5 sections (group plus 4 students). Anything shown in the demo but not in the report gets no marks. Anything claimed in the report that doesn't work is penalised.
- The demo lasts 2–5 minutes. The assessor skips features that are slow or fiddly to reach.

**Design consequences, which apply to every decision you make:**
1. Every feature must be explainable line by line by the student who owns it. Prefer clear, simple structures (counters, FSMs, ROM tables, small datapaths) over clever ones. Comment the *why*.
2. Every part must have visible, demonstrable depth **and** be needed by the other parts.
3. Every feature must be reachable within a few button presses from power-on.
4. The product must stay fully usable if the audio Pmod fails. Visuals and LEDs must carry the game on their own.

## 2. The product

**KeyLight** turns the Basys3 into a small piano and rhythm game. The 8 left switches act as piano keys. **Flipping a switch in either direction strikes the note**, so a player never has to reset switches. The LED directly above each switch is a **guide light** that glows brighter as that key's next note approaches. The OLED shows falling notes, menus and an on-screen piano. The audio Pmod plays the notes.

Modes, all in one bitstream:
1. **Play (rhythm game):** notes fall in 8 coloured lanes. Strike the right switch as a note crosses the hit line. Each note is judged Perfect, Good or Miss, and the game tracks score, combo, multiplier, accuracy and a grade.
2. **Learn:** the song waits for you. The next note's LED blinks and its name is shown. The correct key advances the song, and a wrong key shows which key was needed. There is a "Listen first" demo of each phrase.
3. **Free Play:** a 13-key chromatic piano with on-screen keyboard, note names and a live waveform scope. You can **record** a tune with metronome and count-in, play it back, and **save it as "MY SONG"**, which then becomes playable in Play and Learn. This is the main integration loop.
4. **High scores:** best score and initials per song and difficulty, **saved to the on-board flash so they survive power-off and reprogramming**. The saved recording persists the same way.
5. **Settings:** instrument, volume, note speed, LED guides, metronome, display theme and brightness, and erase saves.

### 2.1 Hardware map (Basys3, XC7A35T)

Resource budget: 20,800 LUTs · 41,600 FFs · 50 BRAM36 · 90 DSP48. Target **≤ 75% LUT** and **≤ 40% BRAM** after full integration.

| Hardware | Use |
|---|---|
| `clk` W5, 100 MHz | Single system clock. Everything runs on it with clock enables, except `Oled_Display`. |
| `sw[15:8]` | Note keys / game lanes, left to right: **C4 D4 E4 F4 G4 A4 B4 C5** (`sw[15]` = C4, `sw[8]` = C5) |
| `sw[7:3]` | Black keys, left to right: **C#4 D#4 F#4 G#4 A#4** (Free Play) |
| `sw[2]` | Octave up (+12 semitones, Free Play) |
| `sw[1]` | Mute |
| `sw[0]` | Pause (Play / Learn) |
| `led[15:8]` | Guide lights above the note switches (PWM brightness) |
| `led[7:3]` | Free Play: black-key indicators. Play: combo meter (one LED per 10 combo). |
| `led[2]` / `led[1]` / `led[0]` | Recording (blinks) / muted / paused |
| `btnU`, `btnD` | Navigate. Auto-repeat after 400 ms at 10 Hz. |
| `btnC` | Select / confirm |
| `btnL` | Back. Long press (≥ 1 s) anywhere returns to the main menu. |
| `btnR` | Context action: Free Play record/stop; Results retry |
| `btnU`+`btnD` held 2 s | Soft reset to the title screen. Saved data is untouched. |
| `seg[6:0]`, `dp`, `an[3:0]` | 4-digit status: mode word, combo, note name, grade |
| **JC**[7:0] | Pmod OLED (pin order as in the template) |
| **JA** top row | Audio output Pmod (see Part A) |
| QSPI flash `QspiCSn` K19, `QspiDB[0..3]` D18/D19/G18/F18, CCLK via `STARTUPE2` | Persistent save data (see Part B) |

Optional, stretch only: a second OLED as a dedicated piano view, on a header on a **different side** of the board from the first. No mouse, no keyboard, no VGA.

### 2.2 Musical content

Ship four public-domain songs, all in C major within C4–C5 so they fit the 8 lanes: **Twinkle Twinkle Little Star**, **Mary Had a Little Lamb**, **Ode to Joy**, and **Jingle Bells** (chorus). Slot 4 is **MY SONG**, the saved recording. It appears in song select only once a recording exists.

Songs are **data, not code**. Write them in a readable text format under `songs/`, for example `E4 1, D4 1, C4 2 …` with a BPM header. A Python script in `tools/` converts them into `.mem` files loaded with `$readmemh`. No song may be hardcoded in a `case` statement.

Note colours are one palette shared by every mode and the LEDs' mapping: C red, D orange, E yellow, F green, G cyan, A blue, B violet, C5 pink. Sharps use the lower natural's colour, darkened.

## 3. Architecture

### 3.1 Clocking and timing
- One 100 MHz domain. Make these shared clock enables once in `timebase.v` and reuse them everywhere; don't duplicate counters:
  - `tick_1ms`, a 1 kHz pulse
  - `tick_frame`, a 60 Hz pulse for animations
  - `tick_sample`, the audio sample rate, 100 MHz / 2048 = 48.828 kHz
- `clk6p25m` comes from a divide-by-16 counter, as in the lab exercises, and drives **only** `Oled_Display`.
- Renderers are **combinational** functions of `(px_x, px_y, state)`. Game state that renderers read should change only on `tick_frame` or at slow rates to avoid visible tearing.
- If a renderer reads BRAM (1-cycle latency), read `Oled_Display.v` to find exactly when `pixel_data` is sampled relative to `pixel_index`, then pipeline or look ahead accordingly. Prove it in simulation.
- `px_x = pixel_index % 96` and `px_y = pixel_index / 96` are computed **once** in the top module and broadcast to every renderer.
- Reset: a synchronous, active-high `rst`. It comes from power-on (a counter that holds reset for ~10 ms) OR'd with the soft reset.

### 3.2 Global data flow

```
             +----------------------- settings bus (D) ----------------------------+
             v                                                                     v
 switches/buttons -> [B: input_conditioner] -> key_strike / btn events -> D (mode FSM) -> mode, song_id, difficulty
                                    |                         |
                                    v                         v
                   [B: Free Play + recorder]        [C: game engine]   [D: Learn mode]
                         |      |                     |   ^   |              |  ^
             note events |      | MY SONG chart ------+   |   | results      |  | chart
                         v      v (rec RAM)               |   v              |  |
                     [A: sound engine] <-- note events ---+  [D: results / initials] -> [B: storage <-> flash]
                         |  \__ scope samples -> B's Free Play screen
                         v
                     audio Pmod
 Video: mode-selected renderer (B/C/D) -> overlay layer (D: toasts, pause, help bar) -> global brightness/fade (D) -> Oled_Display
 LEDs / 7-seg: mode-selected requests -> top-level mux -> D's 7-seg driver
```

### 3.3 Shared interface contract: `rtl/top/keylight_defs.vh`
Lock this file before any part is written. Changing it later requires all four owners to agree.

| Signal | Width | Producer → consumer | Meaning |
|---|---|---|---|
| `mode` | 4 | D → all | `TITLE, MENU, SONGSEL, PLAY, RESULTS, NAME, LEARN, FREE, SCORES, SETTINGS` |
| `song_id` / `difficulty` | 3 / 2 | D → B, C | 0–3 ROM songs, 4 = MY SONG / Easy, Normal, Hard |
| `settings` | struct of fields | D → A, C, D | `instrument[1:0]`, `volume[2:0]`, `note_speed[1:0]`, `led_guides_en`, `metronome_en`, `theme`, `brightness[1:0]` |
| `key_strike` | 13 | B → C, D, B | 1-cycle pulse per key strike. Bit 0 = C4 … bit 12 = C5, chromatic order |
| `key_level` | 13 | B → B | Debounced switch levels |
| `btn_press`, `btn_long`, `btn_repeat` | 5 each | B → D, C | Order {U, D, L, R, C}. Pulses only. |
| `ev_valid, ev_note, ev_vel` | 1, 7, 2 | B/C/D → A (top mux by mode) | Note-on event. MIDI numbers (C4 = 60). Note-off comes from the envelope release. |
| `sfx_valid, sfx_id` | 1, 4 | C/D → A | UI and game sound effects |
| `scope_sample` | 8 | A → B | Latest mixed output sample, for the scope |
| Chart port | `chart_addr` 9, `chart_data` 24 | C/D read; B serves MY SONG | Word 0 is the header `{step_ms[23:14], event_count[13:5], 5'b0}`. Each event is `{note[23:17], start_step[16:6], len_steps[5:0]}`; note = 0 means end. `step_ms` = ms per 16th note = 15000 / BPM, precomputed by the script so no divider is needed. |
| Results | `res_valid`, `res_score` 20, `res_perfect/good/miss/maxcombo` 9 each, `res_acc_pct` 7, `res_grade` 3 | C → D, B | Emitted once at song end |
| Storage | `hs_rd_song/diff` → `hs_score` 20 + `hs_initials` 15; `hs_wr_req`; `rec_save_req`; `save_busy`; `rec_exists`; `flash_ok` | B ↔ C, D | High score table and recording persistence |
| Video | `px_color` 16 per renderer; overlay adds `ov_color` 16 + `ov_en` 1 | B, C, D → top | RGB565 |
| LEDs | `led_req` 16 per producer | B, C, D → top mux | |
| 7-seg | `seg_glyph` 4×6 + `seg_dp` 4 + `seg_blink` 4 | B, C, D → D's driver | Glyph codes, not raw segments |

### 3.4 Repository layout (one folder per owner, so ownership is obvious)

```
rtl/top/      My_Top_Module.v, keylight_defs.vh, timebase.v, pixel_xy.v, mux_video.v, mux_io.v
rtl/provided/ Oled_Display.v (unchanged from the course template)
rtl/a_sound/  rtl/b_input_freeplay_storage/  rtl/c_game/  rtl/d_ui_learn/
sim/<a|b|c|d>/  testbenches, one per non-trivial module
songs/ (text)   data/*.mem (generated)   tools/*.py (generators)
constraints/Basys3_Master.xdc
docs/INTERFACES.md  docs/<A|B|C|D>_DESIGN.md  docs/REFERENCES_AND_AI_USE.md  docs/DEMO_SCRIPT.md
```

The shared top-level files are written jointly in an integration session. Each file's header still names the student who explains it in Q&A: `timebase` → A, `pixel_xy` and video mux → D, IO mux → B.

## 4. The four parts

Every part lists its features, how it's built, and how it connects to the others. Each part must also ship testbenches and a design note (see §6).

### Part A: Sound engine and audio output (Student A)

**Features**
1. **4-voice polyphony.** Voice allocator: use a free voice, otherwise steal the oldest. Re-striking a note that is already sounding retriggers that voice.
2. **DDS oscillators.** 24-bit phase accumulators at `tick_sample`. Phase increments come from a generated ROM indexed by MIDI note 36–96 (`tools/gen_note_table.py`, which writes `inc = round(f · 2^24 / 48828.125)`).
3. **Four instruments** (from Settings): Piano (triangle with fast decay), Organ (square, sustained), Chiptune (25% pulse), Bell (sine with long release). The waveforms come from one shared 256-entry sine ROM plus arithmetic-generated square, pulse and triangle.
4. **ADSR envelope per voice**, with parameters set per instrument by a small table. One 8×8 multiplier is **time-shared** across the 4 voices (2048 clock cycles are available per sample). This is a good resource story for the report.
5. **Mixer.** Sum of the voices plus the SFX channel, master volume (8 steps), mute, and **saturation** instead of wrap-around.
6. **SFX generator:** menu move, select, back, Perfect sparkle, Miss thud, combo milestone, new-high-score jingle. Effects are short sequences stored in a ROM, not hardcoded logic.
7. **Metronome click** for Free Play recording and optionally for Play/Learn. Its timing comes from the current `step_ms`.
8. **Output stage behind one adapter module.** First confirm the exact Pmod model at the lab counter.
   - **Pmod AMP2:** 8-bit PWM at 100 MHz/256 ≈ 390 kHz on AIN (JA1), GAIN (JA2) set to a constant, ~SHUTDOWN (JA4) high.
   - **Pmod I2S2:** I2S serializer with an MCLK from the Clocking Wizard.
   - Nothing else in the design may depend on which Pmod it is.
9. **Scope feed:** `scope_sample` for Free Play's live waveform view. This lets the sound engine be seen even without speakers.

**Inputs:** `ev_*`, `sfx_*`, `settings`, `tick_sample`, `step_ms`. **Outputs:** audio pins, `scope_sample`, `voice_active[3:0]` (for the debug LEDs and the Free Play display).

**Q&A depth to prepare:** DDS maths and frequency resolution, why 48.828 kHz, PWM vs DAC, how the time-shared multiplier is scheduled, voice-stealing policy, saturation.

### Part B: Input, Free Play, recorder and persistent storage (Student B)

**Features**
1. **`input_conditioner`**, used by the whole product:
   - 2-flop synchroniser on every switch and button.
   - Switches: 5 ms stable-count debounce, with **toggle-edge detection in both directions** producing `key_strike`.
   - Buttons: 10 ms debounce, then press pulse, long-press (1 s), auto-repeat, and the U+D soft-reset combo.
   - A rhythm game needs fast repeated strikes, so do **not** use a long lockout on switches. Explain in the design note why switches and buttons are debounced differently.
2. **Free Play screen:**
   - On-screen piano with 8 white and 5 black keys in the lower half. A pressed key lights in its note colour and fades out.
   - Large note name and octave, drawn with D's text engine.
   - Live **waveform scope** from A's `scope_sample`, using a 96-sample line buffer.
   - Octave switch, and a recording status bar.
3. **Recorder:**
   - BPM adjustable from 60 to 180 with U/D in Free Play.
   - `btnR` starts a **1-bar count-in** (shown on the 7-seg and LEDs, with A's metronome), then records.
   - Timestamps are **quantised to 16th notes** by a step counter driven by `step_ms`. Round to the nearest step using a half-step offset, so no divider is needed.
   - Up to 255 events in BRAM, stored in the same chart format as the songs. Each note's length is set to the gap until the next note, capped at 63.
4. **Playback:** plays the recording through A with the on-screen keys animating.
5. **"Save as MY SONG":** serves the recording on the chart port, so C's game engine and D's Learn mode play it exactly like a ROM song. Sharps map to the lane of the lower natural but sound as the real sharp.
6. **Persistent storage controller (QSPI flash):**
   - Single-bit SPI: DQ0 = MOSI, DQ1 = MISO, DQ2/WP# and DQ3/HOLD# held high, CCLK via `STARTUPE2.USRCCLKO` at ≤ 12.5 MHz. Handle the documented behaviour that the first few USRCCLKO cycles after configuration don't reach the pin.
   - At boot, read **RDID (0x9F)** to identify the part and confirm its size, its erase command (0x20 4 KB sub-sector or 0xD8 64 KB block) and its page size.
   - Commands: READ 0x03, WREN 0x06, RDSR 0x05 (poll WIP), page program 0x02.
   - Save area: two slots in the **last 64 KB block** (for a 4 MB part, 0x3F0000 onward), well above the bitstream.
   - **Double-buffered with a sequence number and CRC-16.** On boot, load the newer valid slot into a BRAM mirror. If neither is valid, write defaults. A power loss during a write can never corrupt the last good save.
   - Image (≤ 1 KB): magic `"KEYL"`, version, high-score table (5 songs × 3 difficulties × {score 20b, initials 3×5b}), the recording, then the CRC.
   - Saves run in the background with `save_busy` (D shows "SAVING…"). Triggers are a confirmed high score and "Save MY SONG". "Erase saves" comes from Settings.
   - Exposes `flash_ok`. If the flash can't be identified, the game still runs and keeps scores in RAM only.

**Q&A depth to prepare:** metastability and synchronisers, the debounce design, SPI timing and the command sequence, why double-buffering and CRC, how quantisation works without division.

### Part C: Rhythm game engine (Student C)

**Features**
1. **`chart_reader`:** one read interface over the song ROMs and B's MY SONG RAM. D's Learn mode uses it too.
2. **Song clock:** `song_ms` advances on `tick_1ms`. A 2-bar count-in shows "3-2-1-GO". Pause (`sw[0]`) freezes everything. Note `hit_ms = start_step × step_ms`, computed incrementally or with one shared multiplier.
3. **Note scheduler:** a 24-slot active-note table `{lane, hit_ms, len, state}`. Notes are loaded from the chart when they enter the look-ahead window and freed once judged and off-screen.
4. **Judgement:**
   - On `key_strike` for a lane, pick the **earliest pending note in that lane**. |Δ| ≤ 40 ms is Perfect, ≤ 100 ms is Good. Windows scale ×1.5 on Easy and ×0.75 on Hard.
   - A note that passes the hit line beyond the Good window is a Miss.
   - A strike with no note in range is a "stray": it breaks the combo but costs no points.
5. **Scoring:**
   - Perfect 100, Good 50, Miss 0.
   - Combo multiplier ×1 / ×2 (from 10) / ×3 (from 30) / ×4 (from 50).
   - Max combo is tracked.
   - Accuracy % = (2P + G) / (2N) is computed at the end with a **sequential shift-subtract divider**.
   - Grade: S ≥ 95, A ≥ 90, B ≥ 80, C ≥ 70, D otherwise.
6. **Play screen renderer:**
   - 8 lanes × 12 px in note colours. Map x to lane with a comparator chain or ROM, never a divider.
   - Hit line at y = 54.
   - Notes are rounded bars whose height scales with length: `y = 54 − ((hit_ms − song_ms) >> speed_shift)`. `speed_shift` comes from note-speed and difficulty, so there is no division.
   - Per-lane hit flash, a judgement pop-up ("PERFECT", "GOOD", "MISS") for 300 ms, a small burst sprite on Perfect.
   - Score top-left, combo top-right, song progress bar along the top.
   - Visible notes are capped at 4 per lane, so only 32 range checks run per pixel. Document this budget.
7. **LED guide lights:** for each lane, PWM brightness rises from 0 (no note within 1 s) to full as the next note approaches. It blinks inside the Perfect window and flashes white-bright on a hit. It can be turned off in Settings.
8. Sends note events to A when a hit lands, so **the player performs the melody**. A Miss triggers the miss SFX. Every 10 combo triggers a milestone SFX.
9. Emits the results bundle to D and B at song end.

**Q&A depth to prepare:** fixed-window judgement, the active-table design and its limits, why shifts instead of division, the divider FSM, resource cost of the renderer.

### Part D: UI framework, Learn mode and system control (Student D)

**Features**
1. **Mode FSM:** the single owner of `mode`, `song_id`, `difficulty` and `settings`. Defines all transitions, including long-press back and soft reset.
2. **Shared text engine:**
   - 5×7 font ROM (A–Z, 0–9, punctuation, arrows, ♪, ♯) generated from a text file by `tools/font_to_mem.py`.
   - A 16×8 character grid of 6×8 cells, with 2× scaled text for titles.
   - Screens supply characters from string ROMs, not hardcoded comparisons.
   - Large digits use ≤ 3 rectangles each (TA tip).
3. **Screens:**
   - Title: animated "KEYLIGHT" logo with a light sweep over falling notes, and "PRESS C".
   - Main menu: 5 items with icons, a sliding highlight bar and a one-line description.
   - Song select: title, BPM, difficulty selector, and best score with initials from B. MY SONG appears only when `rec_exists`.
   - Settings, a High-score table, and Results: animated score count-up, grade stamp, "NEW RECORD" banner.
   - Arcade-style **initials entry** (A–Z with U/D/C).
4. **On-board guidance (a stated UX criterion):** a bottom hint bar on every screen shows what each button does, e.g. "C:select L:back". There is also a short first-run tip on the Play screen ("Flip the switch under the glowing LED").
5. **Overlay layer:** pause screen, "SAVING…", and toasts such as "Saved!" and "No audio Pmod?".
6. **Global post-processing:** brightness levels and a light/dark theme applied once to the final RGB565 value, plus 200 ms fade transitions between screens. The manual explicitly lists "brightness/mode of the OLED" as a UX enhancement.
7. **Learn mode:**
   - Reads the chart through C's `chart_reader`.
   - Shows the current and next 3 notes as a mini piano-roll with big note names.
   - Blinks the target key's LED. The correct strike plays the note (through A) and advances. A wrong strike shows a red flash and highlights the right key.
   - "Listen first" plays each 4-bar phrase through A with LEDs as a demo.
   - Ends with accuracy and time taken, and 1–3 stars.
8. **7-segment driver:**
   - Multiplexed at ~1 kHz with a glyph table (digits plus the letters needed for PLAY, LErn, FrEE, HI, SEt).
   - Decimal point used as the sharp sign, with blinking.
   - Content by mode: menu word, combo in Play, note name in Free Play, notes left in Learn, grade and accuracy in Results.

**Q&A depth to prepare:** the mode FSM diagram (this is exactly lectures L3/L4 on FSMs and modular FSMs), how the text engine maps a pixel to font bits, 7-seg multiplexing, the post-processing maths on RGB565.

## 5. Why this counts as integration (write the report around this)

- **Your recording becomes a level:** B records and saves to flash, then C plays it as a chart, D's Learn mode teaches it, and A voices it.
- **Every hit is music:** C's judgement creates note events that A plays, with LED guides from C and SFX from A.
- **Persistent progress:** C's results go to D's initials entry, then B's flash save, then D's song select and high-score screens, and they survive reprogramming.
- **One visual language:** a single note-colour palette across lanes, piano keys and the piano-roll, plus one text engine and one post-processing stage, so every screen looks like the same product.

## 6. Engineering standards

- **Build on what the course taught.** Before designing each part, read the course material provided with this brief: the lecture notes (L1 Sequential Circuits, L2 Counters, L3 Intro to FSM, L4 Modular FSMs) and the Lab 1, 2 and 4 manuals, all as Markdown. Note that the lecture diagrams were lost in conversion, so the original PDFs are the reference for figures. Write the code the way the course does wherever that works: the same counter and clock-divider patterns, the same FSM style (state register plus next-state and output logic, as in L3) and the same modular-FSM structure (L4) for the mode controller and the sub-screens. Use the same 7-segment multiplexing and debouncing approaches as the labs and GPT-5 tasks. Only go beyond the course material where a feature needs it (e.g. DDS, SPI flash, the divider). In that case, write a short "how this relates to what we learned" note in that part's design doc. The goal is that each student recognises their own code as an extension of the labs and can defend it in Q&A.
- Verilog-2001, matching the course template. Use non-blocking assignments in sequential logic and blocking in combinational logic. Give every combinational block default assignments, with **zero latches** in synthesis.
- Use one clock and clock enables. Never use a derived clock for logic, apart from `clk6p25m` for `Oled_Display`.
- Use parameters and `localparam` instead of magic numbers. Every module starts with a header giving its owner, purpose, ports and timing.
- Comment the reasoning, not the syntax. Keep modules ≤ ~300 lines and split anything bigger.
- **Testbenches:** at least one self-checking testbench per non-trivial module, e.g. `input_conditioner`, the DDS, the voice allocator, the judgement logic, the divider, the SPI flash FSM against a simple flash model, `chart_reader` and the mode FSM.
- **Resource log:** after every integration build, record post-implementation LUT, FF, BRAM and DSP in `docs/INTERFACES.md`. Keep timing met (WNS ≥ 0) at 100 MHz.
- **Robustness tests:** mash all switches at once, hold buttons for 5 s, change modes mid-song, pause and resume, finish a song with zero hits, record 255+ notes (it must stop cleanly at the limit), power-cycle in the middle of a save, and run with no audio Pmod connected.
- **Citations:** list every external source and any generated code in `docs/REFERENCES_AND_AI_USE.md`, with what was used and where. The report's references sheet is built from this, and undocumented use is penalised.
- Each student's design note (`docs/<X>_DESIGN.md`) covers a block diagram, the FSM diagrams, key design decisions, resource usage and a list of 15 likely assessor questions with answers.

## 7. Build order and acceptance criteria

Order the work like this. Each step must work on the board before the next one starts.

1. **Base, built jointly:** top module, constraints, `timebase`, `pixel_xy`, OLED showing a test pattern, the `keylight_defs.vh` contract, and stub modules for A–D that drive safe defaults.
   - *Accept:* builds clean with stubs, and the OLED shows the colour bars.
2. **Vertical slice:** title, then menu, then Play with one song. Notes fall, switches judge them, a simple square-wave tone sounds, and LEDs guide.
   - *Accept:* a full song can be played start to finish.
3. **Each part to feature-complete in its own folder.** Integrate into the shared top **at least daily**, never only at the end.
4. **Integration loops:** Free Play recording becomes MY SONG and is playable in Play and Learn. Results flow to initials, then the flash save, then reprogramming, and the score is still there.
5. **Polish:** animations, SFX, hint bars, theme and brightness, fade transitions.
6. **Hardening:** the robustness tests above, a resource squeeze if over 75% LUT, and timing closure.
7. **Fresh-user test:** someone who has never seen the game must reach and finish a song with no help. Fix anything they get stuck on.

**Final acceptance:** a single bitstream; every feature in §2 and §4 works on hardware; the robustness tests pass; ≤ 75% LUT; timing met; all docs present.

## 8. Demo script to design for (2–5 minutes)

1. Power on: the animated title appears.
2. Main menu → Play → Twinkle (Normal). The LEDs guide the player, the player performs the melody, and judgements pop up.
3. Results: grade, then NEW RECORD, then initials, then "SAVING…".
4. Free Play: play some chords and show the scope. Record 8 bars with the count-in and play them back. Save as MY SONG.
5. Learn → MY SONG: the game teaches the tune that was just recorded.
6. Reprogram the FPGA: the high score and MY SONG are still there.

Every step must be reachable in ≤ 3 button presses from the previous one.

## 9. Do not

- Add devices beyond the audio output Pmod, or put two OLEDs on the same side.
- Let any one part become a thin wrapper. Each student's part must hold real logic they wrote and can explain.
- Make a separate bitstream for any feature, or claim anything that doesn't work in the final bitstream.
- Copy code from past projects or the internet without citing it. Build anything you can't explain.
- Hardcode songs, fonts, note tables or SFX in logic. They are data files produced by scripts.

Start by producing `keylight_defs.vh`, `docs/INTERFACES.md` and the base build (step 1). Then implement the vertical slice. Report post-implementation resource usage at every milestone.
