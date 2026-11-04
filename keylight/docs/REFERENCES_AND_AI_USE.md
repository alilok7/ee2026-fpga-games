# References and AI use

Every external source and every use of AI tools goes in this table **as it happens**. The Sheet B references in the final report are built from it.

## External sources

| # | Source | What we used | Where |
|---|---|---|---|
| 1 | EE2026 course template `Oled_Display.v` | Used unchanged (OLED SPI driver) | `rtl/provided/Oled_Display.v` |
| 2 | EE2026 course `Basys3_Master.xdc` | Pin constraints (uncommented the pins we use) | `constraints/Basys3_Master.xdc` |
| 3 | EE2026 Lab 1/2/4 manuals and lectures L1–L4 | Counter and clock-divider patterns, FSM style, 7-segment multiplexing | Throughout. See each design note. |
| 4 | Digilent Pmod AMP2 reference manual | Pin functions (AIN, GAIN, ~SHUTDOWN) and the PWM input | `rtl/a_sound/audio_out.v` |
| 5 | Twinkle Twinkle, Mary Had a Little Lamb, Ode to Joy (Beethoven), Jingle Bells (Pierpont, 1857) | Public-domain melodies, transcribed by hand | `songs/*.txt` |
| 6 | "Double dabble" binary-to-BCD algorithm (standard technique) | Algorithm idea, implemented ourselves | `rtl/d_ui_learn/bin2bcd.v` |
| 7 | Restoring (shift-subtract) division (standard technique) | Algorithm idea, implemented ourselves | `rtl/c_game/divider_seq.v` |

## AI use

| Date | Tool | Who | What it did | Files | What we changed or checked |
|---|---|---|---|---|---|
| 2026-11-02 | Claude (Anthropic), Claude Code | Team | Wrote first drafts of the base build and the vertical slice: interface contract, timebase, pixel_xy, input conditioner, single-voice DDS, game engine, mode FSM, text engine, screens, testbenches, Python generators, build script | `rtl/**`, `sim/**`, `tools/**`, `docs/INTERFACES.md` | **Each owner must read and rewrite their part until they can explain every line.** All testbenches pass (`bash sim/run_sim.sh all`). Record your own edits here. |
| 2026-11-02 | Claude (Anthropic), Claude Code | Team | Found and fixed timing violations (video capture enable + multicycle path, `note_table` scan pipelining) and a double-load bug that `tb_game` caught | `rtl/top/mux_video.v`, `rtl/c_game/note_table.v`, `rtl/c_game/led_guides.v`, `constraints/Basys3_Master.xdc` | Timing met (WNS +0.309 ns), all testbenches pass |

> Reminder from the TA: roughly 70% of the work must be your own and at most about 30% AI-assisted, and all of it must be explainable in Q&A. Use the AI drafts as a starting point to learn from, not as final code.
