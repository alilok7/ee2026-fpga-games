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

### v3 (2026-11-05)
The team asked the same AI assistant (Claude, in Claude Code) to: make the spin more sensitive to the mouse; make the roll follow the mouse consistently; zoom in to the pins on a click with dotted lines visible; make the game work on a VGA monitor with suitable graphics; and review the physics (ball/floor, ball/pins, pin/pin), the mouse gestures and the UI. The assistant first wrote a plan, the team chose the options (fix the swipe accuracy plus a steer window; aim preview on right-click; a 160 × 120 VGA redesign; the OLED kept as a second screen with the scoreboard and the live top-down pins), approved it, and the assistant then wrote the RTL, tables, testbenches and these documents. The v2 folder and bitstream were copied to `strikeline_v2_backup/` first.
- New / rewritten by the AI: `render_scan.v`, `vga_out.v`, `view_map.v`, `vga_hud.v`; large changes to `gesture_features.v`, `swipe_capture.v`, `mouse_setup.v`, `ball_physics.v`, `pin_physics.v`, `persp_proj.v`, `lane_render.v`, `ball_render.v`, `pin_render.v`, `compositor.v`, `camera.v`, `My_Top_Module.v`, the XDC, `gen_tables.py` (`oil_pattern.mem`, `persp_v.mem`, 16-size `pin_fp.mem`), and the testbenches.
- Bugs found by the AI in v2 while reviewing (now fixed, see A_DESIGN.md / B_DESIGN.md): the lost release packet, the spin measured from the two ends of the swipe, the biased sensitivity shifts, the `wp` race, the asymmetric hook rounding, the slow-motion camera lead.
- The VGA timing (640 × 480 @ 60 Hz, 25.175 MHz nominal, 800 × 525 total) is the standard VESA/IBM mode as given in the Basys3 reference manual; the VGA pin numbers are from the course Basys3_Master.xdc.
- v3.1 (same day): the team asked the assistant to merge the v3 working copy into the GitHub repo and to integrate the zoom with the first-person view; the team chose "zoom from the bowler" (hold the right button). The assistant changed `camera.v` (zoom level, lens constant, back-off), `persp_proj.v` (K as an input, near cull), `lane_render.v` (zoomed row distance, row-based guide dots), `game_fsm.v` (zoom on the held right button), `My_Top_Module.v`, two strings and `tb_screens.v` (zoomed screenshots), and these documents.
- v3.2 / v3.3 (same day): at the team's request the assistant made the VGA 3-D view 320 × 240 (one 9-bit frame buffer, `render_scan`, `vga_out`, `persp_proj`, `lane_render`, `ball_render`, `pin_render`, `gen_tables.py`), made the OLED the scoreboard (`scorecard_render` tall layout), added the automatic top-down replay after every ball with click-to-skip (`turn_fsm`, `replay_buffer`, `game_fsm`), removed the VGA scorecard strip, shrank the panel and added the full-screen replay camera look (`view_map`, `vga_hud`, `compositor`), and updated the testbenches and these documents.
- **Programmed on a Basys3 (JTAG), not yet checked in detail on a monitor**: every student should check the on-board list in `README.md` and be able to explain the v3 parts of their own module (new questions 16-20 in each design file).
