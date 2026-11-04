# Demo script (under 5 minutes)

Before you start: Pmod OLED on **JC**, wired USB mouse in the top USB port, all switches down, bitstream programmed (or in flash).

| # | Who | Do | Point out |
|---|---|---|---|
| 1 | D | Power on. Click the title, then click **QUICK GAME** (2 clicks). | Mouse menus with hover, 7-seg names the item, fade-in. Quick Game = frames 8–10. |
| 2 | A, B, C | Move the mouse to stand on board ~20, hold left-click, flick straight up, let go. | Trail and live power LEDs while swiping; speed label and 7-seg "16.5"; camera follows; pins scatter; `led[9:0]` show the leave; popup; scorecard after the frame. |
| 3 | A, B | Stand right (board ~10), flick with a curve to the left. | "HOOK L4": the ball skids in the oil and hooks late on the dry lane into the pocket. Strike celebration. |
| 4 | B, C | `sw[2]` up (debug) and `sw[3]` up (slow motion), throw again. `sw[1]` for the minimap. | Velocity vector, contact crosses, pins tinted by state, the path trace on the minimap. |
| 5 | C, D | Hold btnL to leave, then PRACTICE → click the leave chip until **7-10** → SPARE CHALLENGE, throw at the 7. | The pin-setter sets the leave (rake animation); SPLIT detection; made/tries counter. |
| 6 | A | PRACTICE → SWIPE LAB, swipe a curve. | Raw (grey) vs filtered (yellow) path, measured speed, aim and spin: the algorithm made visible. |
| 7 | D | Menu → **RESUME GAME** after reprogramming the FPGA (Vivado → Program Device). | The frame and the score come back from the flash. |

If short on time, skip 6. If something goes wrong: holding btnU + btnD for 2 s soft-resets without losing saves.
