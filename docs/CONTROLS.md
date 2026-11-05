# Controls (exact)

Hardware for both games: Digilent **Basys3** (XC7A35T), **Pmod OLED RGB 96×64 on header JC**, micro-USB to the PC for power and programming.

---

## StrikeLine v3 (working copy, not tagged yet) - differences from v2

Extra hardware: a **VGA monitor** on the Basys3 VGA connector (main screen, 640 × 480). During a game the first-person view fills the whole screen (v3.3: no scorecard strip on top); the 3-D lane, ball and pins are drawn at 320 × 240 in 512 colours (v3.2), and a small info panel sits in the top-right corner. The Pmod OLED on JC is the **scoreboard** (v3.3): during a game the whole OLED shows the 10-frame scorecard; in menus it mirrors the menu.

**After every ball (v3.2)** the throw is replayed once, **full-screen and top-down at real speed**, 0.6 s into the result, with a camera look (four corner brackets and a blinking red ● REPLAY). **A click (or btnC) during the replay skips it.** Middle click / btnU still gives the half-speed replay.

### Mouse (v3 changes)
| Action | Effect |
|---|---|
| Move (aiming) | The ball sits under the pointer in the 3-D view (stance board, "BD nn") |
| **Hold right button** (aiming, throwing, rolling, pin action) | **ZOOM** (v3.1): the first-person view zooms in from where you stand, so the ball, the bright dotted aim guide and the pins all stay on screen (the pins grow about 5×). You can grab and flick while holding it; the zoom stays on during the roll. Let go to zoom back out. (Press right first, then grab: a right click *during* a grab still cancels the swipe.) |
| **Wheel while aiming** | Moves the **target** mark (one board per step, "TG nn"); the dotted guide runs from your stance through the target to the pins. It is a guide only: the swipe still decides the throw |
| Hold left + flick forward + release | Throws, as before. **Curving the flick** now gives spin −31..+31 from the shape of the whole curve (31 levels; was 7) |
| **Move sideways right after release** | **Steer window**: for 0.5 s the ball is nudged a little (at most ~3.5 boards) in the direction you move |
| Right click after the throw (result, sweep) | Scorecard on the OLED / in the classic view (btnD at any time) |

### Pause, initials, high scores (v3.4)
| Where | Input | Effect |
|---|---|---|
| Paused (sw0 up) | Click or btnC | **Leave the game** (it is saved at the last frame; RESUME GAME continues it). From Spare Challenge: back to PRACTICE |
| Entering initials | Wheel or btnU / btnD | Change the letter (A..Z) |
| Entering initials | Click or btnC | Confirm the letter, next one; after the 3rd the score is saved |
| Entering initials | **Right click or btnL** | Back to the previous letter |
| HIGH SCORES | — | Top 5 (FULL / QUICK tabs), then lifetime STRIKES and SPARES, GAMES finished and BEST game |

### Settings menu (v3)
Row 1 is now **SPIN** sensitivity: **NORM**, **HIGH** (2×), **MAX** (4×), **SOFT** (½). Mouse sensitivity, brightness and erase saves as before; oil length stays on sw14 only.

### Switches (v3)
| Switch | Effect |
|---|---|
| sw4 | Classic top-down view **on the VGA too** (shown in the framed window); the OLED is always top-down |
| others | as v2 |

### Outputs (v3)
| Output | Shows |
|---|---|
| VGA | Menus: framed window with the STRIKELINE title. Game: full-screen first-person 3-D lane and pins, a half-size panel top right (frame, ball, score, live mph, power, spin, revs, entry board / POCKET, pins). Replay: full-screen top-down with the camera overlay |
| OLED | v3.3: the 10-frame scorecard on the whole screen during a game; menus. (v3: top-down live view) |

---

## StrikeLine v2 (tag `strikeline-v2.0`, current `main`)

Extra hardware: one **wired USB mouse** in the Basys3's full-size USB-A host port (top edge, upper right; labelled USB / J2). Not the micro-USB port.

### Mouse
| Action | Effect |
|---|---|
| Move (menus) | Moves the pointer; the row under it is highlighted |
| Left click (menus) | Chooses the highlighted row; on the main menu, clicking the **1P/2P chip** (right side of QUICK / FULL GAME) toggles 1 or 2 players |
| Move left/right (aiming) | Picks the stance board: the ball sits under the pointer, "BD nn" shows the board (counted from the throwing side) |
| **Hold left button on the lane, flick forward, release** | Throws. Flick speed → ball speed (10-22 mph); flick direction → aim (±6° counts as straight); **curving** the flick → hook (left curve = hook left, spin 1-7) |
| Right click | Cancels a swipe in progress; in a game toggles the scorecard; in menus goes back |
| Middle click (result screen) | Instant replay at half speed |
| Wheel | Changes the letter when entering initials |

### Buttons
| Button | Menus | In a game |
|---|---|---|
| btnC | Choose | Skip the result screen |
| btnU / btnD | Move up / down (initials: change letter) | btnU: **replay**, btnD: **scorecard** |
| btnL | Back | Aiming: **move stance one board left**; **hold 1 s: leave the game** (it is saved) |
| btnR | Main menu: toggle 1P/2P | Aiming: **move stance one board right** |
| btnU + btnD held 2 s | Soft reset (saves are kept) | same |

### Switches
| Switch | Effect |
|---|---|
| sw0 | Pause |
| sw1 | Minimap (whole lane, ball path, view window, pins left) |
| sw2 | Physics debug view (velocity arrow, contact crosses, pins tinted by state) |
| sw3 | Slow motion (physics at 1/4 speed) |
| sw4 | Classic top-down view (default is first person while aiming and rolling) |
| sw11 | 12 lb ball |
| sw12 | 16 lb ball (sw11 and sw12 both down = 14 lb) |
| sw13 | Neon "cosmic bowling" theme |
| sw14 | Long oil (45 ft): the ball hooks later and less |
| sw15 | Left-handed (board numbers counted from the left) |

### Outputs
| Output | Shows |
|---|---|
| OLED | Game (lane 60 px wide on the left, HUD panel on the right) |
| `led[9:0]` | Pins still standing, one LED per pin (led0 = pin 1) |
| `led[15:10]` | Power while swiping; after the throw, hook direction and strength |
| 7-segment | Menu: the item's name. After a throw: ball speed (e.g. `17.2`) for 3 s. Then the **points so far** (a strike counts 10 at once); 2 players: left digit = player. Spare Challenge: made.tries (`03.05`). Game over (2P): P1 and P2 alternate |

### Settings menu (v2)
Mouse sensitivity, brightness, erase saves. Oil, ball, hand and theme are shown dimmed with an "S": they are set by switches.

### Fastest path to play
Power on → click the title → click **QUICK GAME** (frames 8-10) → move the mouse to choose a board → hold left-click on the lane and flick up.

---

## StrikeLine v1 (tag `strikeline-v1.0`) - differences from v2

- **No first-person view** (always top-down); no sw4.
- **Switches:** only sw0-sw3 (pause, minimap, debug, slow motion) and sw15 (left-handed). **Oil, ball weight, hand and theme are in the Settings menu.**
- **Buttons in a game:** btnR / right click = scorecard, btnD / middle click = replay, btnC skip, hold btnL quit. No one-board stance nudges.
- **7-segment:** the official (known-frames) score of the current player, no player digit; Spare Challenge shows 0.
- **Physics:** contains the left-hook contact bug fixed in v2 (a ball moving left could slide through pins) and is more forgiving (almost any hit strikes).

---

## KeyLight (folder `keylight/`, vertical slice)

Optional hardware: Pmod AMP2 + headphones/speaker on **JA, top row (pins 1-6)**. No mouse.

| Input | Effect |
|---|---|
| **sw15 … sw8** | White piano keys C4 D4 E4 F4 G4 A4 B4 C5 (left to right). A key "strike" is a switch flip in **either** direction |
| **sw7 … sw3** | Black keys C#4 D#4 F#4 G#4 A#4 |
| sw2 | Octave up (Free Play) |
| sw1 | Mute (`led[1]` lights) |
| sw0 | Pause (`led[0]` lights, "PAUSED" banner) |
| btnC | Confirm / start |
| btnU / btnD | Menu up / down (the highlight bar slides) |
| btnR | Song select: cycle EASY / NORMAL / HARD; Results: retry |
| btnL | Back; **hold 1 s anywhere: main menu** |
| hold btnD 1 s on the title | Colour-bar self test (7-seg `tESt`) |
| btnU + btnD held 2 s | Soft reset |

Play: title → C → PLAY → C on a song → count-in → flip the switch under the glowing LED as each note reaches the white line (PERFECT / GOOD / MISS). Free Play: flip any switch to play its note. LEDs above the switches guide the next note; `led[7:3]` fill up every 10 combo; the 7-seg shows the menu word, multiplier and combo, then the grade and accuracy.
Not built yet in KeyLight: Learn, High scores, Settings screens, the recorder / MY SONG, flash saves, 4-voice polyphony and instruments (they show "COMING SOON").
