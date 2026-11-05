# References and AI use

Undocumented use is penalised. Keep this file up to date as you change things.

## Provided course files (unchanged)
| File | Source |
|---|---|
| `rtl/provided/Oled_Display.v` | EE2026 template, adapted by the course from github.com/jhol/otl-icoboard-pmodoledrgb-demo (BSD licence, header kept) |
| `rtl/provided/Mouse_Control.vhd` (entity `MouseCtl`), `rtl/provided/Ps2Interface.vhd` | EE2026 template (Digilent reference design) |
| `constraints/Basys3_StrikeLine.xdc` | Pin lines from the course Basys3_Master.xdc |

## Reused from our own KeyLight prototype (same team, same course)
`pixel_xy.v`, `reset_gen.v`, `debounce.v`, `button_events.v`, `bin2bcd.v`, `seg7_driver.v`, the 5×7 font (`text/font5x7.txt`), the capture-enable video timing scheme, and the build/sim script structure.

## External technical references
- Basys3 reference manual (Digilent): QSPI flash pins, USB HID host (PS/2) pins.
- Xilinx UG470 (7 Series Configuration): STARTUPE2, USRCCLKO and the first clock cycles after configuration.
- SPI NOR flash datasheets (Spansion S25FL032P / Micron N25Q032): commands 0x9F, 0x05, 0x06, 0x03, 0x02, 0xD8, status bits WIP/WEL/BP.
- CRC-16-CCITT (polynomial 0x1021, init 0xFFFF): standard definition.
- Real bowling dimensions (USBC specifications): lane 60 ft × 41.5 in, 39 boards, pins 12 in apart, pin and ball sizes, typical oil lengths.
- Ten-pin scoring rules (USBC). The 167-point example game is a standard textbook example.

## AI use
The design, RTL, testbenches, Python generators and these documents were drafted with **Claude (Anthropic), an AI assistant**, working from our team's engineering brief (`Bowling_Engineer_Prompt.md`), with the following process:
- Every module is self-checked in simulation (`sim/*/tb_*.v`), and the AI's mistakes found that way are recorded in the design docs (for example the spin bias in A, the hook tuning in B, the pin radius in C, the flash read-index bug in D).
- **Each student must read, understand and be able to explain every line of their own part before the assessment** (course rule: never claim what you cannot explain). Each `docs/<X>_DESIGN.md` lists 15 likely questions with answers to study.
- Students: record here any change you make yourself, and any later AI help (what was asked, what was used).

## Change log (later AI help and student changes)
| Date | Files | Who | What |
|---|---|---|---|
| 2026-11-05 | `d_game_ui/debounce.v`, `button_events.v`, `seg7_driver.v`, `seg7_ctrl.v`, `score_engine.v` | Claude (AI), asked by Student D | Rewritten in a simpler, lecture-style form so they are easier to study and explain: one always block per output in `button_events`; Lab 4-style digit select in `seg7_driver`; `/` and `%` instead of the double-dabble function in `seg7_ctrl`; `score_engine` as a Lecture 3/4 FSM (state register, next-state block, datapath) that first copies the 21 rolls into an array and then scores one frame per clock. Same ports and behaviour; checked with `tb_scoring` (all checks pass) and the full testbench suite and build. |
