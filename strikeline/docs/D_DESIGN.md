# Part D: game controller, scoring, UI and save system (Student D)

## Files
| File | What it does |
|---|---|
| `game_fsm.v` | Main FSM: modes, mouse/button menus, settings, game over, initials |
| `turn_fsm.v` | Sub-FSM: one ball at a time, frame rules, 2 players, Quick/Full/Spare, popups, auto-save, resume |
| `score_engine.v` | Ten-pin scoring from the rolls. One 28-bit word per (player, frame) in LUTRAM: {known, total, 3 marks} |
| `save_image.v` | 128-byte image of everything persistent (LUTRAM, 7 read ports) |
| `persist_ctrl.v` | The only writer of the image (roll, header, stats, top-5 insert, settings, defaults) |
| `flash_ctrl.v`, `spi_byte.v`, `crc16.v` | Boot load and saving to the QSPI flash |
| `text_engine.v`, `string_rom.v`, `txt_helpers.vh`, `bcd_fns.vh` | Shared text engine (one string ROM, two fonts) |
| `menu_render.v`, `hud_render.v`, `scorecard_render.v` | D's screens and overlays |
| `compositor.v` | Layer priority, text routing, brightness, fade, capture register |
| `replay_buffer.v` | Instant replay: records 4 s of snapshots in BRAM, plays them back at half speed |
| `seg7_ctrl.v`, `seg7_driver.v` | 7-seg content and multiplexing |
| `input_conditioner.v`, `debounce.v`, `button_events.v`, `reset_gen.v`, `bin2bcd.v` | Inputs, reset |
| tools: `fonts_to_mem.py`, `strings_to_mem.py` | Fonts and strings from `text/*.txt` |
| tests: `sim/d/tb_scoring.v` (23 checks), `sim/d/tb_flash.v` (13 checks, with `flash_model.v`) | |

## Modular FSM (Lecture 4)
```
game_fsm (main)                                     turn_fsm (sub, one ball)
BOOT -> TITLE -> MENU --QUICK/FULL/RESUME--> PLAY ===go_new/go_resume===>  CLEAR/RES -> RACK -> AIM
          ^         |--PRACTICE--> PRACT --LAB-->  LAB                     AIM -grab-> THROW -release-> ROLL
          |         |              \--SPARE--> PLAY (spare kind)           ROLL -deck-> PIN -pit-> SETTLE
          |         |--SCORES / SETTINGS / HELP                            SETTLE -settle_done-> RESULT
          |                                                                RESULT -1.5 s / click-> NEXT
          |  PLAY <===game_over=== ... QUAL -> OVER -> NAME -> SCORES      NEXT -> RACK (next ball / frame) | OVER
```
`game_state` = the mode's code, or turn_fsm's state while a game runs.

## Frame rules (turn_fsm, NEXT)
- Frames 1â€“9: a strike ends the frame. Otherwise sweep the fallen pins and throw ball 2.
- Frame 10: ball 1 strike â†’ full rack, ball 2. Ball 2 after a strike, or a spare â†’ bonus ball (full rack if the deck is clear, else sweep).
- 2 players alternate every frame. Quick Game plays frames 8â€“10, so the 10th-frame rules are always in the demo.
- After every frame the header is written to the image and the flash save starts. At the end of the game the header is cleared (no resume).
- Popups: STRIKE / DOUBLE / TURKEY (strike streak), SPARE, GUTTER (gutter phase seen and 0 pins), SPLIT (first ball of a rack), "n PINS".

## Scoring
The rolls live in the save image, so a resumed game rescores itself. `score_engine` walks each player's rolls: 3 reads + 1 compute clock per frame, about 100 clocks for both players. A frame total is shown only once its bonus balls are known. The 10th frame has its own 3 boxes. Marks are ready-made glyph codes (X / âˆ’ digit). The test covers 300, 299, 150, 0, 90, 190, 10, 24, 20, 30, the classic 167 game with its running totals and marks, an unfinished strike, and a Quick Game.

## Distinct roles for buttons and switches (v2)
- **Switches = live physical settings:** sw11 / sw12 ball 12 / 16 lb (both down = 14), sw13 neon theme, sw14 long oil, sw15 left-handed, sw4 classic view (plus sw0-3: pause, minimap, debug, slow motion). `game_fsm` builds `settings` from them; the Settings menu shows these rows dimmed with an "S" (read-only) and keeps mouse sensitivity, brightness and erase.
- **Buttons = in-game actions the mouse does not have:** btnL / btnR move the stance one board, btnU replay, btnD scorecard, btnC skip, hold btnL quit. Menus keep U / D / C / L navigation.

## Two totals: official and provisional (v2)
- **Official** (`game0/1`, scorecard): only frames whose bonus balls are known, exactly like a paper scorecard.
- **Provisional** (`prov0/1`, 7-seg and HUD): the same walk also adds each frame's pins plus the bonus balls thrown *so far*, so a strike shows +10 at once and the number moves after every ball, like a bowling-alley screen. With a finished game the two are equal (tested: 300, 167). After X X: official 0, provisional 30.
- **7-seg** (`seg7_ctrl.v`): menu word → ball speed for 3 s after a throw → provisional points. In 2-player games the left digit is the player number; at game over it alternates P1 / P2 every 1.5 s; in Spare Challenge it shows made.tries.

## Persistence
- **Image** (`save_image`): settings, lifetime stats, two top-5 tables, the game in progress. Layout in `INTERFACES.md`.
- **One writer** (`persist_ctrl`): each command type has a pending flag and latched arguments; the FSM serves them one at a time. The top-5 insert scans for the first slot the score beats, moves the lower entries down from the bottom up (so nothing is overwritten before it is copied), then writes the new entry.
- **Flash** (`flash_ctrl`, upper FSM over a lower transaction FSM over `spi_byte`):
  - boot: dummy clocks (STARTUPE2 swallows the first USRCCLKO edges) â†’ RDID 0x9F (no answer = play without saves) â†’ RDSR 0x05 (block-protect bits = no saves) â†’ READ 0x03 of both slots, checking magic, version and CRC â†’ load the newer valid slot, or factory defaults
  - save: wait for `persist_ctrl` idle â†’ snapshot the image into a page buffer with a new sequence number and CRC â†’ **older** slot: WREN, 64 KB sector erase 0xD8, RDSR poll, WREN, page program 0x02, RDSR poll, READ back and compare
  - **Why two sectors:** a sector erase is 64 KB, so two slots in one block would both be erased together. Slot A = 0x3E0000 and slot B = 0x3F0000 are in different sectors, far above the 2.2 MB bitstream.
  - **Power loss:** the other slot is never touched, and a half-erased or half-programmed slot fails its CRC, so the newest complete save wins. `tb_flash` cuts the power during erase and during program and checks this.
  - SPI is mode 0 at 12.5 MHz (100/8), far below the flash limit, so the STARTUPE2 clock-path delay doesn't matter.

## Text and screens
One `text_engine`: every text layer sends a text request (string ROM address or a literal glyph, font, cell position, colours). The compositor routes the top-most one to the engine. So there is one string ROM (2048 Ã— 6) and one copy of each font (5Ã—7 and 3Ã—5) for the whole design, which is the TA's "share hardware". Numbers use combinational double dabble (`bcd_fns.vh`). High scores and stats are read straight from the image through two read ports (low and high byte under the pixel).

## Compositor
A cursor > D scorecard > D HUD > D menus > A world > B ball > C pins > B lane > black. Then brightness (shifts), then a fade-in after every screen change (channel Ã— level / 8, about 0.25 s), then the capture register (6-clock multicycle, as in KeyLight).

## How this relates to the lectures
- L3: state register + next-state + outputs in every FSM. L4: game_fsm â†’ turn_fsm (start/done handshake), and flash upper â†’ lower FSM.
- Labs: 7-seg multiplexing (1 ms per digit, active-low anodes), debouncing.
- Beyond the course: SPI flash protocol, CRC, double-buffered saves.

## 15 likely questions
1. **Draw your FSM.** game_fsm (modes) starts turn_fsm (balls), which returns game_over. See the diagram above.
2. **How do strike and spare bonuses work in your engine?** A strike adds the next two rolls and a spare the next one. Totals are shown only when those rolls exist.
3. **What is special about the 10th frame?** Up to 3 balls: a strike or spare earns a bonus ball, and a cleared deck is re-racked in full.
4. **Why are the rolls stored in the save image?** So that a resumed game (even after reprogramming) has everything needed to rescore itself.
5. **Explain the SPI flash sequence for a save.** WREN, SE 0xD8 + address, RDSR until WIP = 0, WREN, PP 0x02 + address + 128 bytes, RDSR, READ back.
6. **Why WREN twice?** The flash clears write-enable after every erase or program.
7. **What is STARTUPE2 for?** After configuration the flash clock pin is driven only through STARTUPE2's USRCCLKO. Its first 3 edges are swallowed, hence the dummy clocks at boot.
8. **How does double-buffering protect the save?** Every save goes to the older slot. The newer one stays intact, so a power cut can only damage the slot being written.
9. **How do you know which slot is newer?** A 16-bit sequence number. B is newer if (seqB âˆ’ seqA) is positive as a signed number, which still works when it wraps.
10. **What does the CRC catch?** Any 1- or 2-bit error and any burst up to 16 bits, so a half-written slot is always rejected.
11. **How do you insert a high score?** Find the first entry it beats, move the entries below it down from the bottom up, write the new one. The test checks the order.
12. **Why one text engine?** One string ROM and one copy of each font for all layers. The compositor passes it the top-most request, which saves LUTs.
13. **What is the compositor's priority?** Cursor > scorecard > HUD > menus > A > ball > pins > lane.
14. **How is the 7-seg multiplexed?** One digit lit at a time, the next every 1 ms (250 Hz per digit), active-low segments and anodes.
15. **What happens if there is no flash or it is protected?** RDID returns 00/FF or RDSR shows protect bits: defaults are loaded, saves are skipped, and the game plays normally.

## Instant replay (stretch, built)
`replay_buffer.v`: every frame during ROLL / PINACTION / SETTLE it stores a 274-bit snapshot (ball x/y/angle/visible, camera, the 10 pins' `pin_vis`) as 8 × 36-bit words in a 2048 × 36 block RAM (2 BRAM36, 256 snapshots = 4.3 s). In RESULT, a middle click or btnD plays it back from the oldest snapshot at half speed, reading 8 words into registers every second frame. The top-level muxes feed those registers to B's and C's renderers. The physics is not touched; the replay is only a picture.
