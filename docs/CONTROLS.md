# Controls (exact)

Hardware for both games: Digilent **Basys3** (XC7A35T), **Pmod OLED RGB 96×64 on header JC**, micro-USB to the PC for power and programming.

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
