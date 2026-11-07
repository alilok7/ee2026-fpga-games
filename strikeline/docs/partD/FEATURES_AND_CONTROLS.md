# 09. My features: what they are, how to use them, why, and where the code is

These are the features of Part D (game flow, menus and saves) in the team game. For each one: **what** it is, the **controls**, **how to use it**, **why** it is built this way, and **where** the code is. In the controls, the mouse comes first and the buttons are the second way to do everything. Button names: btnU / btnD / btnL / btnR / btnC.

Quick map of my files: `game_fsm` = screens and menus; `menu_render` = how the screens look on the OLED; `vga_hud` = the VGA panel and pop-ups; `compositor` = joins every layer into one picture; `persist_ctrl` + `save_image` + `flash_ctrl` (+ `spi_byte`, `crc16`) = saving.

---

## A. Getting around

### 1. Title screen and main menu
- **What:** the title (STRIKELINE, a little animated lane, a blinking "CLICK TO PLAY"), then the main menu: RESUME GAME, QUICK GAME, FULL GAME, HIGH SCORES, SETTINGS, HELP. The highlighted row has a bar, and a hint line on top says what it does.
- **Controls:** move the mouse over a row to highlight it, click to choose. Buttons: U / D move, C chooses, L goes back to the title.
- **How to use:** power on → click the title → click QUICK GAME. **Two clicks from power-on to playing.**
- **Why:** the demo must be quick for the assessor (2-5 minutes for the whole team), and the highlight that follows the mouse makes the menu feel like a real game. The buttons are there so it still works with no mouse.
- **Code:** menu logic [game_fsm.v:250](../../rtl/d_game_ui/game_fsm.v#L250) (next state [game_fsm.v:142](../../rtl/d_game_ui/game_fsm.v#L142)); hover from the pointer `row_at` [game_fsm.v:111](../../rtl/d_game_ui/game_fsm.v#L111); how it looks: title [menu_render.v:136](../../rtl/d_game_ui/menu_render.v#L136), menu [menu_render.v:162](../../rtl/d_game_ui/menu_render.v#L162).

### 2. 1 or 2 players
- **What:** the "1P / 2P" chip next to QUICK and FULL GAME.
- **Controls:** click the chip, or btnR on the main menu.
- **Why:** hot-seat 2-player games are part of C's scoring; the chip sets the mode before the game starts, so there's no extra screen.
- **Code:** [game_fsm.v:252](../../rtl/d_game_ui/game_fsm.v#L252); the game kind sent to C (`kind_out`) [game_fsm.v:250](../../rtl/d_game_ui/game_fsm.v#L250); the chip drawing [menu_render.v:162](../../rtl/d_game_ui/menu_render.v#L162).

### 3. Quick Game and Full Game
- **What:** Quick = frames 8-10 (so the 10th-frame rules are always shown in a short demo); Full = 10 frames.
- **Controls:** click QUICK GAME / FULL GAME (or highlight + btnC).
- **Why:** a Full game is too long for a demo; Quick shows strikes, spares and the 10th frame in about a minute.
- **Code:** `go_new` + `kind_out` to C's turn_fsm [game_fsm.v:250](../../rtl/d_game_ui/game_fsm.v#L250).

### 4. Help screen
- **What:** 8 lines explaining how to bowl and what the switches do.
- **Controls:** HELP in the menu; any click / btnC / btnL / right click goes back.
- **Code:** [menu_render.v:262](../../rtl/d_game_ui/menu_render.v#L262); back [game_fsm.v:355](../../rtl/d_game_ui/game_fsm.v#L355).

---

## B. During a game (game_fsm passes these on to A, B and C)

| Control | When | Effect | Code |
|---|---|---|---|
| **Hold right mouse button** | aiming → pin action | zoom the 3-D view down the lane (B's camera) | [game_fsm.v:266](../../rtl/d_game_ui/game_fsm.v#L266) |
| **btnL / btnR** | aiming | move the stance one board left / right (A) | [game_fsm.v:269](../../rtl/d_game_ui/game_fsm.v#L269) |
| **btnD**, or right click after the throw | any time / result | show or hide the scorecard | [game_fsm.v:264](../../rtl/d_game_ui/game_fsm.v#L264) |
| **Middle click / btnU** | result | half-speed replay | [game_fsm.v:273](../../rtl/d_game_ui/game_fsm.v#L273) |
| **Click / btnC** | result or replay | skip it | [game_fsm.v:261](../../rtl/d_game_ui/game_fsm.v#L261) |
| **sw0 up, then click / btnC** | paused | leave the game (it stays saved, RESUME continues it) | [game_fsm.v:277](../../rtl/d_game_ui/game_fsm.v#L277) |
| **Hold btnL 1 s** | any time | leave the game (saved) | [game_fsm.v:154](../../rtl/d_game_ui/game_fsm.v#L154) |

- **Why:** one place (game_fsm) decides what each input means in each state, so a click never does two things at once. For example, a right click only toggles the scorecard *after* the throw, because while aiming it means zoom.
- **While playing**, `game_state` = C's turn_fsm state. This makes game_fsm the main machine and turn_fsm its submachine: I start it (`go_new` / `go_resume`), it tells me when the game is over (`t_game_over`).

---

## C. End of a game and high scores

### 5. Game over and the top-5 check
- **What:** GAME OVER with the score (2 players: both scores and "P1 WINS!" or "TIE GAME"). If the score made the top 5, it says "NEW HIGH SCORE!".
- **How it decides:** it counts the game in the lifetime stats, then reads place 5 of the right table (Quick or Full). If the score beats it, or place 5 is empty, that player made the top 5. In a 2-player game, each player is checked.
- **Controls:** click / btnC to continue.
- **Code:** check [game_fsm.v:281](../../rtl/d_game_ui/game_fsm.v#L281); screen [menu_render.v:276](../../rtl/d_game_ui/menu_render.v#L276).

### 6. Initials entry
- **What:** 3 big letters, the current one blinking and underlined, like an arcade machine.
- **Controls:** **mouse wheel or btnU / btnD** change the letter (A..Z, wraps round); **click / btnC** confirms it and moves to the next; **right click / btnL** goes back one letter. After the 3rd letter, the score is saved. In a 2-player game P1 enters first, then P2.
- **Why:** the wheel is the fastest way to pick a letter; stepping back fixes a mistake without starting again.
- **Code:** [game_fsm.v:304](../../rtl/d_game_ui/game_fsm.v#L304) (letter step [game_fsm.v:208](../../rtl/d_game_ui/game_fsm.v#L208), save [game_fsm.v:316](../../rtl/d_game_ui/game_fsm.v#L316)); screen [menu_render.v:306](../../rtl/d_game_ui/menu_render.v#L306); the sorted insert into the table [persist_ctrl.v:241](../../rtl/d_game_ui/persist_ctrl.v#L241).

### 7. High scores
- **What:** the top 5 with initials, with **FULL / QUICK tabs**; under them the lifetime STRIKES, SPARES, GAMES and BEST (the best game of the tab shown).
- **Controls:** click the tab (top right) or btnU / btnD to switch tabs; btnL / right click to go back.
- **Why:** Quick and Full scores can't be compared (3 frames vs 10), so they have separate tables. Lifetime stats give a reason to keep playing.
- **Code:** tabs [game_fsm.v:350](../../rtl/d_game_ui/game_fsm.v#L350); screen (reads the table straight from the save image) [menu_render.v:221](../../rtl/d_game_ui/menu_render.v#L221).

---

## D. Settings

### 8. Settings menu
| Row | Set by | Values | Saved? |
|---|---|---|---|
| SPIN (sensitivity) | menu | NORM, HIGH, MAX, SOFT | yes |
| BALL | **sw11 / sw12** | 12 / 14 / 16 lb | (switch) |
| HAND | **sw15** | right / left | (switch) |
| MOUSE (sensitivity) | menu | 1..4 | yes |
| THEME | **sw13** | wood / neon | (switch) |
| BRIGHT | menu | 1..4 | yes |
| ERASE SAVES | menu, **2 clicks** | SAVES → SURE? (red) → DONE | resets everything |
| (oil length) | **sw14** | short / long | (switch) |

- **Controls:** highlight a row, click / btnC to change it; btnL / right click to leave (the settings are saved to flash as you leave, only if something changed).
- **Why:** the physical choices (ball, hand, theme, oil) are on switches, so they are visible on the board and can be changed mid-game. Those rows are greyed out with an "S". Erasing needs two clicks so it can't happen by accident.
- **Bug fixed from v3.5:** changing a setting and then clicking a greyed row made v3.5 forget the change. Mine remembers it ([game_fsm.v:333](../../rtl/d_game_ui/game_fsm.v#L333)).
- **Code:** [game_fsm.v:326](../../rtl/d_game_ui/game_fsm.v#L326); switches into `settings` [game_fsm.v:196](../../rtl/d_game_ui/game_fsm.v#L196); erase [game_fsm.v:341](../../rtl/d_game_ui/game_fsm.v#L341); screen [menu_render.v:186](../../rtl/d_game_ui/menu_render.v#L186).

### 9. Brightness and fade-in
- **What:** 4 brightness levels for the whole picture (OLED and VGA); every screen change fades in from black in about 0.25 s.
- **Why:** brightness is a user-experience option; the fade makes screen changes smooth instead of a hard cut. The ball states (aim → roll → result) don't fade, so the game itself never flickers.
- **Code:** [compositor.v:150](../../rtl/d_game_ui/compositor.v#L150) (fade), [compositor.v:175](../../rtl/d_game_ui/compositor.v#L175) (brightness).

---

## E. Saves that survive a power cut (my main feature)

### 10. What is saved, and when
- **Saved:** settings, lifetime stats, both top-5 tables with initials, and the **game in progress** (every roll of both players, frame, player, kind). All of it is 128 bytes ([save_image.v](../../rtl/d_game_ui/save_image.v)).
- **When:** after every frame (C's turn_fsm asks), when you leave Settings with a change, after entering initials, and after Erase. The VGA hint row shows "SAVING" while a save runs.
- **Code:** saving steps [flash_ctrl.v:319](../../rtl/d_game_ui/flash_ctrl.v#L319) onwards; the one writer of the image [persist_ctrl.v](../../rtl/d_game_ui/persist_ctrl.v).

### 11. RESUME after a power cut or a reprogram
- **What:** turn the board off (or reprogram it), turn it on → RESUME GAME is no longer grey → click it → the game continues at the same frame with the same scorecard.
- **How it works:** at power-on, flash_ctrl loads the newest good save into the image. game_fsm sees "a game is saved" and enables RESUME ([game_fsm.v:230](../../rtl/d_game_ui/game_fsm.v#L230)). C reads the saved rolls back and rescores them.
- **This is the demo moment for Part D.**

### 12. Why a power cut can't lose the last save
- **Two slots** (0x3E0000 and 0x3F0000, at the top of the flash, far from the bitstream), each in its own 64 KB erase block. Every save goes into the **older** slot, so the newest good save is never touched.
- **A sequence number** in each save says which slot is newer ([flash_ctrl.v:195](../../rtl/d_game_ui/flash_ctrl.v#L195)).
- **A CRC-16** over each slot ([crc16.v](../../rtl/d_game_ui/crc16.v)): a slot cut off half-way fails it and is ignored at the next power-on ([flash_ctrl.v:293](../../rtl/d_game_ui/flash_ctrl.v#L293)).
- **Read-back check** after programming ([flash_ctrl.v:345](../../rtl/d_game_ui/flash_ctrl.v#L345)), and a **4 s timeout** while waiting for the flash ([flash_ctrl.v:341](../../rtl/d_game_ui/flash_ctrl.v#L341)), so it can never hang.
- **Blank flash** → factory defaults ([flash_ctrl.v:308](../../rtl/d_game_ui/flash_ctrl.v#L308)). **No flash or a protected flash** → the game plays normally without saving.
- **Why:** robustness is one of the four marked criteria and most teams leave it thin. This is the "not straightforward" part of my component.

### 13. One writer for the save image
- **What:** every change to the save image goes through persist_ctrl as a 1-clock command (save a roll, the header, a strike, a spare, game end, a new high score, settings, defaults). Each command waits its turn, so none are lost, even if several arrive together.
- **Why:** if C and I wrote the image at the same time, they would collide; and a save must never copy a half-updated image (`busy` makes flash_ctrl wait).
- **Code:** commands accepted [persist_ctrl.v:278](../../rtl/d_game_ui/persist_ctrl.v#L278); which job runs next [persist_ctrl.v:131](../../rtl/d_game_ui/persist_ctrl.v#L131); `busy` [persist_ctrl.v:102](../../rtl/d_game_ui/persist_ctrl.v#L102).

---

## F. What the VGA screen shows (vga_hud)

### 14. Info panel (top right during a game)
- **What:** FRAME and BALL (and P1 / P2), SCORE (2P: both), **live SPEED in mph** (falls as the ball slows), a POWER bar (live while the ball is held), SPIN value and bar (left / right), a REVS bar, then after the hit the **ENTRY board** with "POCKET" when it is a pocket hit, and a pin diagram of the standing pins.
- **Why:** these numbers show what the player's swipe actually did, which connects A's swipe, B's ball and C's pins on one panel (part of the integration mark).
- **Code:** panel [vga_hud.v:188](../../rtl/d_game_ui/vga_hud.v#L188); the last throw [vga_hud.v:115](../../rtl/d_game_ui/vga_hud.v#L115); entry board [vga_hud.v:134](../../rtl/d_game_ui/vga_hud.v#L134).

### 15. Pop-ups and hints over the 3-D view
- **What:** STRIKE! / SPARE! / DOUBLE! / TURKEY! / GUTTER / SPLIT / "n PINS" in big letters; a FRAME n banner; PAUSED with "CLICK: QUIT GAME"; ZOOM; "BD nn  TG nn" (board / target) while aiming; a hint row (what to do now, swipe errors such as "SWIPE FASTER", or SAVING); the STRIKELINE sign on the back wall.
- **Code:** [vga_hud.v:318](../../rtl/d_game_ui/vga_hud.v#L318) (boxes [vga_hud.v:361](../../rtl/d_game_ui/vga_hud.v#L361), sign [vga_hud.v:386](../../rtl/d_game_ui/vga_hud.v#L386), hint row [vga_hud.v:406](../../rtl/d_game_ui/vga_hud.v#L406)).

### 16. Replay look and menu backdrop
- **What:** during the replay: corner brackets, a blinking red dot and "REPLAY", like a camera. In the menus the VGA shows the menu in a framed window on a gradient backdrop with the STRIKELINE title and a little lane.
- **Code:** replay [vga_hud.v:424](../../rtl/d_game_ui/vga_hud.v#L424); backdrop [vga_hud.v:449](../../rtl/d_game_ui/vga_hud.v#L449).

---

## G. Putting the picture together (compositor)

### 17. Layers and the shared text engine
- **What:** every part draws its own layer; the compositor picks the front-most one for every pixel (pointer > HUD / scorecard > menus > trail > ball / pins > lane), and in 3-D the nearer of a pin and the ball covers the other. All text on both screens goes through **one** text engine.
- **Why:** one text engine = one string ROM and one copy of each font for the whole game, which saves a lot of the chip (it is 94 % full).
- **Code:** [compositor.v:81](../../rtl/d_game_ui/compositor.v#L81) (text), [compositor.v:112](../../rtl/d_game_ui/compositor.v#L112) (layer order).

---

## H. On the board (not in a menu)

| Output | Shows | Code |
|---|---|---|
| `led[9:0]` | blink while the save is loading at power-on, then the standing pins in a game | [My_Top_Module.v:508](../../rtl/top/My_Top_Module.v#L508) (shared top) |
| Flash pins | my flash_ctrl drives them; the clock goes through STARTUPE2 | [My_Top_Module.v:287](../../rtl/top/My_Top_Module.v#L287), [:294](../../rtl/top/My_Top_Module.v#L294) |

---

## Short version for the report (Sheet A, Student D)

> **Student D: Game flow, menus and crash-safe saves**
> - **Crash-safe flash saves:** a 128-byte save image in the on-board QSPI flash over SPI (through STARTUPE2); two alternating slots with sequence numbers and a CRC-16, so a power cut mid-save never loses the last good save.
> - **Resume after reprogramming:** the unfinished game, top-5 tables with initials and lifetime stats survive power-off.
> - Title, Quick / Full games, 1-2 players, settings, help, high scores; mouse-hover menus with a full button fallback.
> - VGA info panel: live speed, spin, revs and entry board; layered picture with brightness and fade.

Claim only what works on the final team board.
